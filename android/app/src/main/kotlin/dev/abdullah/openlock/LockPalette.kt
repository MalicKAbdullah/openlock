package dev.abdullah.openlock

import android.content.Context
import android.content.res.Configuration
import androidx.core.graphics.ColorUtils

/**
 * The suite colour tokens the native lock overlay draws with, in the same
 * values as core_theme's SuiteColors so the overlay matches the Flutter lock.
 */
data class LockPalette(
    val isDark: Boolean,
    val background: Int,
    val surface: Int,
    val hairline: Int,
    val textPrimary: Int,
    val textSecondary: Int,
    val accent: Int,
    val onAccent: Int,
    val error: Int,
) {
    /** The tonal fill behind the fingerprint glyph: the accent at ~12% over the background. */
    val accentContainer: Int =
        ColorUtils.compositeColors(ColorUtils.setAlphaComponent(accent, 31), background)

    companion object {
        private val LIGHT = LockPalette(
            isDark = false,
            background = 0xFFF6F7F9.toInt(),
            surface = 0xFFFFFFFF.toInt(),
            hairline = 0xFFE8EBEF.toInt(),
            textPrimary = 0xFF0E1116.toInt(),
            textSecondary = 0xFF5B6371.toInt(),
            accent = 0xFF007E9C.toInt(),
            onAccent = 0xFFFFFFFF.toInt(),
            error = 0xFFDC3B42.toInt(),
        )

        private val DARK = LockPalette(
            isDark = true,
            background = 0xFF0A0C10.toInt(),
            surface = 0xFF12151A.toInt(),
            hairline = 0xFF1F232B.toInt(),
            textPrimary = 0xFFEDEFF3.toInt(),
            textSecondary = 0xFF9BA3B1.toInt(),
            accent = 0xFF3FD0EE.toInt(),
            onAccent = 0xFF0A0C10.toInt(),
            error = 0xFFFF6B70.toInt(),
        )

        /**
         * The palette for the user's Appearance choice, which Flutter's
         * AppearanceController saves in `FlutterSharedPreferences` as
         * `system`, `light` or `dark`; `system` follows the device night mode.
         */
        fun resolve(context: Context): LockPalette {
            val mode = context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString(THEME_MODE_KEY, "system")
            return when (mode) {
                "light" -> LIGHT
                "dark" -> DARK
                else -> {
                    val night = context.resources.configuration.uiMode and
                        Configuration.UI_MODE_NIGHT_MASK
                    if (night == Configuration.UI_MODE_NIGHT_YES) DARK else LIGHT
                }
            }
        }

        private const val THEME_MODE_KEY = "flutter.offlyne_theme_mode"
    }
}
