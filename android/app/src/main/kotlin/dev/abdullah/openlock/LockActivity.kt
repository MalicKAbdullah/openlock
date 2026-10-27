package dev.abdullah.openlock

import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.core.content.res.ResourcesCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.FragmentActivity
import java.security.SecureRandom

/**
 * The on-top lock screen shown over a locked app. Native (not Flutter) so it
 * can appear reliably from the background. Verifies the entered PIN against the
 * pushed verifier hash entirely offline, offers a fingerprint prompt, escalates
 * a cooldown after repeated failures, and optionally captures an intruder photo.
 */
class LockActivity : FragmentActivity() {

    private lateinit var store: ConfigStore
    private var lockedPackage: String = ""
    private var pin = StringBuilder()
    private var failedAttempts = 0
    private var locked = false

    /** The real PIN screen (not the decoy) is showing → biometrics apply. */
    private var realLockShown = false

    /** A BiometricPrompt is currently up; guards against double-prompting. */
    private var biometricInFlight = false

    private lateinit var palette: LockPalette
    private lateinit var regular: Typeface
    private lateinit var medium: Typeface
    private lateinit var semiBold: Typeface
    private lateinit var dotsRow: LinearLayout
    private lateinit var messageView: TextView
    private lateinit var backspaceKey: View
    private lateinit var checkKey: View
    private lateinit var keypad: View

    /** Every keypad key, for sizing and for dimming during a cooldown. */
    private val keys = mutableListOf<View>()
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }

        store = ConfigStore.get(this)
        lockedPackage = intent.getStringExtra(EXTRA_PACKAGE).orEmpty()

        // LockTheme's window background follows the device night mode; a
        // forced Light/Dark appearance can differ, so the window takes the
        // resolved palette before any content is set and the first frame
        // never shows the other mode's background.
        palette = LockPalette.resolve(this)
        applyWindowColors()

        if (store.fakeCoverEnabled()) {
            setContentView(buildDecoyView())
        } else {
            showRealLock()
        }
    }

    override fun onResume() {
        super.onResume()
        // Auto-trigger the biometric prompt once every time the real lock
        // screen appears (deterministic; the in-flight guard prevents the
        // onCreate + onResume pair from stacking two prompts).
        if (realLockShown) triggerBiometric()
    }

    /** Swaps in the real PIN screen and kicks off the biometric prompt. */
    private fun showRealLock() {
        regular = ResourcesCompat.getFont(this, R.font.mona_sans_regular)!!
        medium = ResourcesCompat.getFont(this, R.font.mona_sans_medium)!!
        semiBold = ResourcesCompat.getFont(this, R.font.mona_sans_semibold)!!
        setContentView(buildLockView())
        realLockShown = true
        triggerBiometric()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        lockedPackage = intent.getStringExtra(EXTRA_PACKAGE) ?: lockedPackage
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Never reveal the locked app via Back — send the user home instead.
        goHome()
    }

    // --- UI construction ----------------------------------------------------

    /**
     * The suite lock layout, matching the Flutter unlock screen: on the flat
     * background a centred column a little above the middle (2 parts of the
     * free space above, 3 below) with the locked app's icon and name, "Locked
     * by OpenLock", the PIN dots, the error line and the keypad; low on the
     * screen the fingerprint button (when enabled), then "by Offlyne".
     */
    private fun buildLockView(): View {
        val p = palette
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(p.background)
        }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        // The keys are sized from the real height so the keypad always fits.
        root.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop) {
                val width = right - left - root.paddingLeft - root.paddingRight
                val height = bottom - top - root.paddingTop - root.paddingBottom
                root.post { sizeKeypad(width, height) }
            }
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
        }
        column.addView(
            ImageView(this).apply { setImageBitmap(appIcon(lockedPackage, dp(MARK_DP))) },
            LinearLayout.LayoutParams(dp(MARK_DP), dp(MARK_DP)),
        )
        column.addView(
            text(appLabel(lockedPackage), TITLE_SP, semiBold, p.textPrimary).apply {
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            },
            wrapWidth(top = 16),
        )
        column.addView(
            text("Locked by OpenLock", SUBTITLE_SP, regular, p.textSecondary),
            wrapWidth(top = 4),
        )

        dotsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        column.addView(dotsRow, wrapWidth(top = 32))

        messageView = text("", 12f, medium, p.error).apply {
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
        }
        column.addView(
            messageView,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(ERROR_DP)).apply {
                topMargin = dp(DOT_GAP_DP)
            },
        )
        keypad = buildKeypad()
        column.addView(
            keypad,
            LinearLayout.LayoutParams(dp(KEYPAD_MAX_WIDTH_DP), ViewGroup.LayoutParams.WRAP_CONTENT)
                .apply { topMargin = dp(ERROR_GAP_DP) },
        )

        root.addView(View(this), LinearLayout.LayoutParams(0, 0, 2f))
        root.addView(
            column,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        root.addView(View(this), LinearLayout.LayoutParams(0, 0, 3f))

        // If the user enabled biometrics, always show the fingerprint button
        // immediately — no async capability probe hiding it. Tapping re-triggers
        // the prompt; the PIN pad above stays available as the fallback.
        if (store.biometricEnabled()) {
            root.addView(
                fingerprintButton(),
                LinearLayout.LayoutParams(dp(FINGERPRINT_DP), dp(FINGERPRINT_DP)).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    bottomMargin = dp(32)
                },
            )
        }
        root.addView(
            endorsement(),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(20)
            },
        )

        updateDots()
        return root
    }

    private fun buildKeypad(): View {
        val digits = (0..9).map { it.toString() }.toMutableList()
        if (store.randomizeKeypad()) digits.shuffle(SecureRandom())

        val grid = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        fun row(cells: List<View>, last: Boolean) {
            val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            cells.forEachIndexed { i, key ->
                line.addView(
                    key,
                    LinearLayout.LayoutParams(0, dp(KEY_MAX_DP), 1f).apply {
                        if (i > 0) marginStart = dp(12)
                    },
                )
            }
            grid.addView(
                line,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { if (!last) bottomMargin = dp(ROW_GAP_DP) },
            )
        }

        keys.clear()
        // Three rows of three digits.
        for (r in 0 until 3) {
            row((0 until 3).map { c -> digitKey(digits[r * 3 + c]) }, last = false)
        }
        // Bottom row: backspace, last digit, check.
        backspaceKey = iconKey(R.drawable.ic_lock_backspace, "Delete digit", emphasized = false) {
            onBackspace()
        }
        checkKey = iconKey(R.drawable.ic_lock_check, "Unlock", emphasized = true) { onSubmit() }
        row(listOf(backspaceKey, digitKey(digits[9]), checkKey), last = true)
        keys += backspaceKey
        keys += checkKey
        return grid
    }

    /** A digit key: the surface with a hairline edge, like the Flutter keypad. */
    private fun digitKey(digit: String): View = TextView(this).apply {
        text = digit
        textSize = 24f
        typeface = medium
        gravity = Gravity.CENTER
        setTextColor(palette.textPrimary)
        background = keyBackground(emphasized = false)
        setOnClickListener { onDigit(digit) }
    }.also { keys += it }

    private fun iconKey(
        icon: Int,
        label: String,
        emphasized: Boolean,
        onTap: () -> Unit,
    ): ImageView = ImageView(this).apply {
        val glyph = ContextCompat.getDrawable(this@LockActivity, icon)!!.mutate()
        glyph.setTint(if (emphasized) palette.onAccent else palette.textPrimary)
        setImageDrawable(glyph)
        scaleType = ImageView.ScaleType.CENTER
        contentDescription = label
        background = keyBackground(emphasized)
        setOnClickListener { onTap() }
    }

    private fun keyBackground(emphasized: Boolean): Drawable {
        val p = palette
        fun shape() = GradientDrawable().apply { cornerRadius = dp(KEY_RADIUS_DP).toFloat() }
        val fill = shape().apply {
            if (emphasized) {
                setColor(p.accent)
            } else {
                setColor(p.surface)
                setStroke(dp(1), p.hairline)
            }
        }
        val ripple = ColorUtils.setAlphaComponent(
            if (emphasized) p.onAccent else p.textPrimary,
            31,
        )
        return RippleDrawable(ColorStateList.valueOf(ripple), fill, shape().apply { setColor(Color.WHITE) })
    }

    /** The round tonal fingerprint button (56 dp), as core_lock's LockBiometricButton. */
    private fun fingerprintButton(): View = ImageView(this).apply {
        val glyph = ContextCompat.getDrawable(this@LockActivity, R.drawable.ic_lock_fingerprint)!!
            .mutate()
        glyph.setTint(palette.accent)
        setImageDrawable(glyph)
        scaleType = ImageView.ScaleType.CENTER
        contentDescription = "Unlock with fingerprint"
        val circle = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(palette.accentContainer)
        }
        background = RippleDrawable(
            ColorStateList.valueOf(ColorUtils.setAlphaComponent(palette.accent, 31)),
            circle,
            null,
        )
        setOnClickListener { triggerBiometric() }
    }

    /** The small "by Offlyne" endorsement at the bottom of every suite lock. */
    private fun endorsement(): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        addView(text("by ", ENDORSEMENT_SP, regular, palette.textSecondary))
        addView(text("Offlyne", ENDORSEMENT_SP, semiBold, palette.textSecondary))
    }

    private fun text(value: String, sp: Float, face: Typeface, color: Int) = TextView(this).apply {
        text = value
        textSize = sp
        typeface = face
        gravity = Gravity.CENTER
        setTextColor(color)
        includeFontPadding = false
    }

    private fun wrapWidth(top: Int) = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = dp(top) }

    /**
     * Fits the keypad into the [availableWidthPx] × [availableHeightPx] the
     * root leaves inside the system bars: at most the suite's 380 dp content
     * width, and keys between the tap target and 64 dp tall next to
     * everything else on the screen — the same rule as the Flutter keypad.
     */
    private fun sizeKeypad(availableWidthPx: Int, availableHeightPx: Int) {
        val width = minOf(availableWidthPx - dp(48), dp(KEYPAD_MAX_WIDTH_DP))
        keypad.layoutParams = keypad.layoutParams.apply { this.width = width }

        val fixedDp = 24 + 24 + MARK_DP + 16 + 4 + 32 + DOT_DP + DOT_GAP_DP + ERROR_DP +
            ERROR_GAP_DP + ROW_GAP_DP * 3 + 20 +
            (if (store.biometricEnabled()) FINGERPRINT_DP + 32 else 0)
        val textLines = sp((TITLE_SP + SUBTITLE_SP + ENDORSEMENT_SP) * LINE_HEIGHT)
        val key = ((availableHeightPx - dp(fixedDp) - textLines) / 4)
            .coerceIn(dp(KEY_MIN_DP), dp(KEY_MAX_DP))
        for (k in keys) {
            k.layoutParams = k.layoutParams.apply { height = key }
        }
    }

    /**
     * The locked app's launcher icon at [sizePx], clipped to the suite tile
     * shape (a rounded rect with corners of 0.3 × size). Adaptive icons are
     * drawn from their layers so the device's own icon mask does not show.
     */
    private fun appIcon(pkg: String, sizePx: Int): Bitmap {
        val icon = try {
            packageManager.getApplicationIcon(pkg)
        } catch (e: PackageManager.NameNotFoundException) {
            // The app was uninstalled while its lock was up.
            packageManager.defaultActivityIcon
        }
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val radius = sizePx * TILE_CORNER_FRACTION
        canvas.clipPath(
            Path().apply {
                addRoundRect(
                    RectF(0f, 0f, sizePx.toFloat(), sizePx.toFloat()),
                    radius,
                    radius,
                    Path.Direction.CW,
                )
            },
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && icon is AdaptiveIconDrawable) {
            // Layers are 108 dp with the visible 72 dp in the middle, so they
            // overflow the tile by a quarter of its size on each side.
            val bleed = sizePx / 4
            for (layer in listOfNotNull(icon.background, icon.foreground)) {
                layer.setBounds(-bleed, -bleed, sizePx + bleed, sizePx + bleed)
                layer.draw(canvas)
            }
        } else {
            icon.setBounds(0, 0, sizePx, sizePx)
            icon.draw(canvas)
        }
        return bitmap
    }

    /** Colours the status and navigation bars like the lock background. */
    private fun applyWindowColors() {
        val p = palette
        window.setBackgroundDrawable(ColorDrawable(p.background))
        WindowCompat.setDecorFitsSystemWindows(window, false)
        @Suppress("DEPRECATION")
        window.statusBarColor = p.background
        @Suppress("DEPRECATION")
        window.navigationBarColor = p.background
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = !p.isDark
            isAppearanceLightNavigationBars = !p.isDark
        }
    }

    private fun buildDecoyView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#B0000000"))
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(color(R.color.lockSurface))
            setPadding(dp(24), dp(24), dp(24), dp(16))
        }
        card.addView(TextView(this).apply {
            text = "${appLabel(lockedPackage)} keeps stopping"
            setTextColor(color(R.color.lockTextPrimary))
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
        })
        card.addView(TextView(this).apply {
            text = "Close app"
            setTextColor(color(R.color.lockAccent))
            textSize = 15f
            gravity = Gravity.END
            setPadding(0, dp(24), 0, 0)
            setOnClickListener { goHome() }
        })
        // Hidden gesture: long-press the card reveals the real lock screen.
        card.setOnLongClickListener {
            showRealLock()
            true
        }
        root.addView(card)
        return root
    }

    // --- Input handling -----------------------------------------------------

    private fun onDigit(digit: String) {
        if (locked || pin.length >= 12) return
        pin.append(digit)
        updateDots()
    }

    private fun onBackspace() {
        if (locked || pin.isEmpty()) return
        pin.deleteCharAt(pin.length - 1)
        updateDots()
    }

    private fun onSubmit() {
        if (locked || pin.length < MIN_PIN) return
        val hash = store.pinHash()
        val salt = store.pinSalt()
        if (hash == null || salt == null) {
            unlockAndFinish()
            return
        }
        if (PinVerifier.verify(pin.toString(), salt, hash, store.pinIterations())) {
            unlockAndFinish()
        } else {
            onWrongPin()
        }
    }

    private fun onWrongPin() {
        failedAttempts++
        pin = StringBuilder()
        updateDots()
        messageView.text = "Wrong PIN"

        if (store.intruderCaptureEnabled() && failedAttempts == store.intruderThreshold()) {
            IntruderCapture.record(this, store, lockedPackage, attemptPhoto = true)
        }
        if (failedAttempts >= MAX_FREE_ATTEMPTS) {
            startCooldown(cooldownSeconds(failedAttempts))
        }
    }

    private fun startCooldown(seconds: Int) {
        locked = true
        updateDots()
        var remaining = seconds
        val runnable = object : Runnable {
            override fun run() {
                if (remaining <= 0) {
                    locked = false
                    messageView.text = ""
                    updateDots()
                    return
                }
                messageView.text = "Too many attempts. Try again in ${countdown(remaining)}."
                remaining--
                handler.postDelayed(this, 1000)
            }
        }
        handler.post(runnable)
    }

    private fun unlockAndFinish() {
        LockSession.markUnlocked(lockedPackage)
        finish()
    }

    /** Redraws the PIN dots (filled accent / 1.5 dp outline) and dims the keys that cannot act. */
    private fun updateDots() {
        val shown = maxOf(pin.length, MIN_PIN)
        dotsRow.removeAllViews()
        for (i in 0 until shown) {
            val dot = View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    if (i < pin.length) {
                        setColor(palette.accent)
                    } else {
                        setStroke((1.5f * resources.displayMetrics.density).toInt(), palette.textSecondary)
                    }
                }
            }
            dotsRow.addView(
                dot,
                LinearLayout.LayoutParams(dp(DOT_DP), dp(DOT_DP)).apply {
                    marginStart = dp(6)
                    marginEnd = dp(6)
                },
            )
        }
        for (key in keys) key.alpha = if (locked) DISABLED_ALPHA else 1f
        if (!locked) {
            backspaceKey.alpha = if (pin.isEmpty()) DISABLED_ALPHA else 1f
            checkKey.alpha = if (pin.length < MIN_PIN) DISABLED_ALPHA else 1f
        }
    }

    // --- Biometric ----------------------------------------------------------

    /**
     * Shows the biometric prompt when the user has enabled biometrics. Called
     * on every appearance of the real lock screen and on tapping the button.
     * Idempotent while a prompt is up. If hardware is unavailable, it leaves a
     * note and the PIN pad remains the fallback.
     */
    private fun triggerBiometric() {
        if (biometricInFlight) return
        if (!store.biometricEnabled()) return

        val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        val canAuth = BiometricManager.from(this).canAuthenticate(authenticators)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            messageView.text = "Fingerprint unavailable — enter your PIN"
            return
        }

        biometricInFlight = true
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult,
                ) {
                    biometricInFlight = false
                    unlockAndFinish()
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    // Cancel / "Use PIN" / lockout — drop back to the PIN pad;
                    // do not auto-re-prompt until the screen reappears.
                    biometricInFlight = false
                }

                override fun onAuthenticationFailed() {
                    // A single non-matching finger; the prompt stays up.
                }
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock ${appLabel(lockedPackage)}")
            .setSubtitle("Use your fingerprint or enter your PIN")
            .setNegativeButtonText("Use PIN")
            .setAllowedAuthenticators(authenticators)
            .build()
        runCatching { prompt.authenticate(info) }.onFailure {
            biometricInFlight = false
        }
    }

    // --- Helpers ------------------------------------------------------------

    private fun goHome() {
        val home = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        runCatching { startActivity(home) }
        finish()
    }

    private fun appLabel(pkg: String): String {
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            "this app"
        }
    }

    private fun color(id: Int): Int = ContextCompat.getColor(this, id)

    private fun sp(value: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value, resources.displayMetrics).toInt()

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    companion object {
        const val EXTRA_PACKAGE = "package"

        // Layout sizes (dp) shared with the Flutter lock (core_lock LockLayout
        // and OpenLock's PinEntryPanel).
        private const val MARK_DP = 64
        private const val TILE_CORNER_FRACTION = 0.3f
        private const val DOT_DP = 14
        private const val DOT_GAP_DP = 6
        private const val ERROR_DP = 16
        private const val ERROR_GAP_DP = 8
        private const val ROW_GAP_DP = 8
        private const val KEY_MIN_DP = 48
        private const val KEY_MAX_DP = 64
        private const val KEY_RADIUS_DP = 14
        private const val KEYPAD_MAX_WIDTH_DP = 332
        private const val FINGERPRINT_DP = 56
        private const val TITLE_SP = 24f
        private const val SUBTITLE_SP = 14f
        private const val ENDORSEMENT_SP = 13f
        private const val LINE_HEIGHT = 1.25f
        private const val DISABLED_ALPHA = 0.4f

        /** A cooldown as a countdown clock, "0:28" or "4:05", as formatLockCountdown. */
        private fun countdown(seconds: Int): String = "%d:%02d".format(seconds / 60, seconds % 60)
        private const val MIN_PIN = 6
        private const val MAX_FREE_ATTEMPTS = 5

        /** Mirror of the Dart escalating cooldown: 30s at the 5th failure,
         *  doubling, capped at 15 minutes. */
        private fun cooldownSeconds(attempts: Int): Int {
            if (attempts < MAX_FREE_ATTEMPTS) return 0
            var seconds = 30
            repeat(attempts - MAX_FREE_ATTEMPTS) {
                seconds *= 2
                if (seconds >= 900) return 900
            }
            return seconds
        }
    }
}
