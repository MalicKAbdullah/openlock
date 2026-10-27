package dev.abdullah.openlock

/**
 * Pure, side-effect-free decisions for notification hiding, kept separate from
 * [OpenLockNotificationListenerService] so they can be unit-tested without the
 * Android framework. Nothing here ever receives or returns notification text:
 * the redacted summary is built from the app label and a count only.
 */
object NotificationRedaction {

    /**
     * System [android.app.Notification] categories that must never be swallowed:
     * calls, alarms, incoming messages the system treats as time-critical, and
     * ongoing media/navigation transport controls. OpenLock leaves these posted
     * as-is so a locked app can still ring, alarm, or show playback controls.
     */
    val leaveAloneCategories: Set<String> = setOf(
        "call", // Notification.CATEGORY_CALL
        "alarm", // Notification.CATEGORY_ALARM
        "transport", // Notification.CATEGORY_TRANSPORT (media playback)
        "event", // Notification.CATEGORY_EVENT (calendar/time-critical)
        "reminder", // Notification.CATEGORY_REMINDER
    )

    /**
     * Whether OpenLock should replace this posted notification with a redacted
     * one. It replaces only genuinely user-facing content notifications from an
     * app the user chose to hide; everything structural or time-critical is
     * left untouched.
     *
     * @param hideEnabledForApp the app is locked AND hiding is on for it
     * @param isOngoing         FLAG_ONGOING_EVENT set (persistent status item)
     * @param isForegroundService FLAG_FOREGROUND_SERVICE set
     * @param isGroupSummary    FLAG_GROUP_SUMMARY set (the bundle header, not a
     *                          real message — redacting children is enough)
     * @param isMediaSession    carries an active MediaSession token
     * @param category          Notification.category, or null
     */
    fun shouldRedact(
        hideEnabledForApp: Boolean,
        isOngoing: Boolean,
        isForegroundService: Boolean,
        isGroupSummary: Boolean,
        isMediaSession: Boolean,
        category: String?,
    ): Boolean {
        if (!hideEnabledForApp) return false
        if (isForegroundService || isOngoing) return false
        if (isGroupSummary) return false
        if (isMediaSession) return false
        if (category != null && leaveAloneCategories.contains(category.lowercase())) {
            return false
        }
        return true
    }

    /**
     * The redacted replacement text, e.g. "WhatsApp · 2 new notifications".
     * Carries only the app's own label and how many of its notifications are
     * currently hidden — never a sender, title, or message body.
     */
    fun summaryText(appLabel: String, count: Int): String {
        val safeCount = if (count < 1) 1 else count
        val noun = if (safeCount == 1) "new notification" else "new notifications"
        return "$appLabel · $safeCount $noun"
    }

    /** Stable per-app grouping key so one app's hidden notifications collapse
     *  into a single OpenLock entry. */
    fun groupKey(packageName: String): String = "openlock.hidden.$packageName"

    /** Stable per-app notification id for the redacted replacement. */
    fun notificationId(packageName: String): Int = packageName.hashCode()
}
