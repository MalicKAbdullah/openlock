package dev.abdullah.openlock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.ConcurrentHashMap

/**
 * Replaces the notifications of locked apps (for which "hide notification
 * content" is on) with OpenLock's own redacted notice: "<App> · N new
 * notifications", the app icon, and no sender or body. Tapping it opens the
 * app, which the monitor then gates behind the lock screen.
 *
 * Privacy invariant: this service never reads, logs, or stores a notification's
 * title, text, or any extra. It inspects only flags, category, the posting
 * package, and — to redraw the icon — the small icon. The redacted replacement
 * is built purely from the app's label and a per-app count held in memory.
 *
 * The decision of *whether* to redact lives in [NotificationRedaction] (pure,
 * unit-tested). The config is read live from [ConfigStore] on every post, so a
 * settings change takes effect without restarting the service.
 */
class OpenLockNotificationListenerService : NotificationListenerService() {

    private lateinit var store: ConfigStore

    /** Per-package set of original notification keys we have hidden. Size is the
     *  count shown in the redacted notice. Keys only — never content. */
    private val hiddenKeys = ConcurrentHashMap<String, MutableSet<String>>()

    override fun onCreate() {
        super.onCreate()
        store = ConfigStore(this)
        instance = this
        ensureChannel()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val pkg = sbn.packageName ?: return
        // Never touch our own redacted notifications.
        if (pkg == packageName) return
        if (!store.shouldHideNotificationsFor(pkg)) return

        val notification = sbn.notification ?: return
        val flags = notification.flags
        val redact = NotificationRedaction.shouldRedact(
            hideEnabledForApp = true,
            isOngoing = flags and Notification.FLAG_ONGOING_EVENT != 0,
            isForegroundService = flags and Notification.FLAG_FOREGROUND_SERVICE != 0,
            isGroupSummary = flags and Notification.FLAG_GROUP_SUMMARY != 0,
            isMediaSession = hasMediaSession(notification),
            category = notification.category,
        )
        if (!redact) return

        // Record the key, drop the original, and (re)post the redacted notice.
        val keys = hiddenKeys.getOrPut(pkg) { java.util.Collections.synchronizedSet(HashSet()) }
        keys.add(sbn.key)
        runCatching { cancelNotification(sbn.key) }
        postRedacted(pkg, keys.size)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        // We drive clearing from app-open (see [onAppForegrounded]); removals of
        // originals are caused by our own cancel and need no bookkeeping here.
    }

    /**
     * Called by [OpenLockMonitorService] when a package comes to the foreground.
     * Once the user is in the app (having passed the lock), its hidden backlog
     * is meaningless, so clear the redacted notice and the tracked keys.
     */
    private fun clearPackage(pkg: String) {
        hiddenKeys.remove(pkg)
        runCatching {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(NotificationRedaction.notificationId(pkg))
        }
    }

    private fun postRedacted(pkg: String, count: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val label = appLabel(pkg)

        val launch = packageManager.getLaunchIntentForPackage(pkg)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val contentIntent = launch?.let {
            PendingIntent.getActivity(
                this,
                NotificationRedaction.notificationId(pkg),
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(label)
            .setContentText(NotificationRedaction.summaryText(label, count))
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setGroup(NotificationRedaction.groupKey(pkg))
        // Re-use the app's own small icon as the large icon so the notice is
        // recognisable; falls back silently if unavailable.
        appIconBitmap(pkg)?.let { builder.setLargeIcon(it) }

        manager.notify(NotificationRedaction.notificationId(pkg), builder.build())
    }

    private fun hasMediaSession(notification: Notification): Boolean {
        val extras = notification.extras ?: return false
        return extras.containsKey(Notification.EXTRA_MEDIA_SESSION)
    }

    private fun appLabel(pkg: String): String = runCatching {
        val info = packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    }.getOrDefault(pkg)

    private fun appIconBitmap(pkg: String): Bitmap? = runCatching {
        drawableToBitmap(packageManager.getApplicationIcon(pkg))
    }.getOrNull()

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) return drawable.bitmap
        val size = ICON_SIZE_PX
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bmp
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hidden app notifications",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Redacted stand-ins for notifications from locked apps."
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "openlock_hidden_notifications"
        private const val ICON_SIZE_PX = 96

        /** The live instance, used by [OpenLockMonitorService] to clear a
         *  package's redacted notice once the user opens the app. */
        @Volatile
        private var instance: OpenLockNotificationListenerService? = null

        fun onAppForegrounded(pkg: String) {
            instance?.clearPackage(pkg)
        }
    }
}
