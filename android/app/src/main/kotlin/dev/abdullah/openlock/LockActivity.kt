package dev.abdullah.openlock

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

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

    private lateinit var dotsView: TextView
    private lateinit var messageView: TextView
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

    private fun buildLockView(): View {
        val bg = color(R.color.lockBackground)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(bg)
            setPadding(dp(24), dp(48), dp(24), dp(48))
        }

        root.addView(TextView(this).apply {
            text = "🔒"
            textSize = 40f
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = "Enter your PIN"
            setTextColor(color(R.color.lockTextPrimary))
            textSize = 22f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(4))
        })
        root.addView(TextView(this).apply {
            text = appLabel(lockedPackage)
            setTextColor(color(R.color.lockTextSecondary))
            textSize = 14f
            gravity = Gravity.CENTER
        })

        dotsView = TextView(this).apply {
            setTextColor(color(R.color.lockAccent))
            textSize = 28f
            gravity = Gravity.CENTER
            setPadding(0, dp(20), 0, dp(8))
            letterSpacing = 0.3f
        }
        root.addView(dotsView)

        messageView = TextView(this).apply {
            setTextColor(color(R.color.lockError))
            textSize = 13f
            gravity = Gravity.CENTER
            minHeight = dp(20)
        }
        root.addView(messageView)

        root.addView(buildKeypad())

        // If the user enabled biometrics, always show the fingerprint button
        // immediately — no async capability probe hiding it. Tapping re-triggers
        // the prompt; the PIN pad above stays available as the fallback.
        if (store.biometricEnabled()) {
            root.addView(TextView(this).apply {
                text = "Use fingerprint"
                setTextColor(color(R.color.lockAccent))
                textSize = 16f
                gravity = Gravity.CENTER
                setPadding(0, dp(16), 0, 0)
                setOnClickListener { triggerBiometric() }
            })
        }

        updateDots()
        return root
    }

    private fun buildKeypad(): View {
        val digits = (0..9).map { it.toString() }.toMutableList()
        if (store.randomizeKeypad()) digits.shuffle()

        val grid = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, 0)
        }

        var index = 0
        // Three rows of three digits.
        for (row in 0 until 3) {
            grid.addView(LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                for (col in 0 until 3) {
                    addView(digitButton(digits[index]))
                    index++
                }
            })
        }
        // Bottom row: backspace, last digit, check.
        grid.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(actionButton("⌫") { onBackspace() })
            addView(digitButton(digits[9]))
            addView(actionButton("✓") { onSubmit() })
        })
        return grid
    }

    private fun digitButton(digit: String): Button = Button(this).apply {
        text = digit
        textSize = 22f
        setTextColor(color(R.color.lockTextPrimary))
        setBackgroundColor(Color.TRANSPARENT)
        layoutParams = LinearLayout.LayoutParams(dp(88), dp(72)).apply {
            setMargins(dp(6), dp(6), dp(6), dp(6))
        }
        setOnClickListener { onDigit(digit) }
    }

    private fun actionButton(label: String, onTap: () -> Unit): Button = Button(this).apply {
        text = label
        textSize = 22f
        setTextColor(color(R.color.lockAccent))
        setBackgroundColor(Color.TRANSPARENT)
        layoutParams = LinearLayout.LayoutParams(dp(88), dp(72)).apply {
            setMargins(dp(6), dp(6), dp(6), dp(6))
        }
        setOnClickListener { onTap() }
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
        var remaining = seconds
        val runnable = object : Runnable {
            override fun run() {
                if (remaining <= 0) {
                    locked = false
                    messageView.text = ""
                    return
                }
                messageView.text = "Too many attempts. Try again in ${remaining}s"
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

    private fun updateDots() {
        val shown = if (pin.isEmpty()) MIN_PIN else pin.length
        val filled = "●".repeat(pin.length)
        val empty = "○".repeat((shown - pin.length).coerceAtLeast(0))
        dotsView.text = filled + empty
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

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    companion object {
        const val EXTRA_PACKAGE = "package"
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
