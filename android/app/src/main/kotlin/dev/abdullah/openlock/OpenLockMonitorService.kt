package dev.abdullah.openlock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.util.Calendar
import java.util.concurrent.ConcurrentHashMap

/**
 * Persistent foreground service that detects the current foreground app via
 * [UsageStatsManager] and throws up [LockActivity] over any locked app that is
 * not currently in an unlocked session (per relock policy + schedules).
 */
class OpenLockMonitorService : Service() {

    private lateinit var store: ConfigStore
    private lateinit var usageStatsManager: UsageStatsManager
    private val handler = Handler(Looper.getMainLooper())

    private val leftAppAt = ConcurrentHashMap<String, Long>()
    @Volatile private var screenOffAt: Long = 0L
    private var lastForegroundPkg: String? = null
    private var lastLaunchedPkg: String? = null
    private var lastLaunchAt: Long = 0L

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> screenOffAt = System.currentTimeMillis()
            }
        }
    }

    private val poller = object : Runnable {
        override fun run() {
            try {
                tick()
            } catch (_: Exception) {
                // Never let a transient failure kill the loop.
            }
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        store = ConfigStore.get(this)
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        registerReceiver(screenReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
        handler.removeCallbacks(poller)
        handler.post(poller)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(poller)
        runCatching { unregisterReceiver(screenReceiver) }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun tick() {
        val foreground = foregroundApp() ?: return
        val current = foreground.first
        val currentClass = foreground.second
        val now = System.currentTimeMillis()

        // Track departures from the foreground for the relock policy.
        val previous = lastForegroundPkg
        if (previous != null && previous != current) {
            leftAppAt[previous] = now
        }
        lastForegroundPkg = current

        // Once the user is in an app, its hidden-notification backlog is stale —
        // clear OpenLock's redacted notice for it. (No-op when the listener is
        // off or nothing was hidden.)
        OpenLockNotificationListenerService.onAppForegrounded(current)

        // Never lock ourselves.
        if (current == packageName) return

        // Uninstall protection: guard the OS deactivate-admin / app-info /
        // uninstall screens (best-effort; see LockLogic + README). Runs before
        // the normal locked-app check because Settings is not in the locked set.
        if (store.pinHash() != null &&
            LockLogic.shouldGuardUninstall(store.preventUninstall(), current, currentClass)
        ) {
            // Respect an in-session unlock so the user can actually reach the
            // deactivate screen after authenticating; re-lock once the screen
            // has turned off since.
            val unlockedAt = LockSession.unlockedAt(current)
            val stillUnlocked = unlockedAt != 0L && screenOffAt <= unlockedAt
            if (!stillUnlocked &&
                !(current == lastLaunchedPkg && now - lastLaunchAt < RELAUNCH_GUARD_MS)
            ) {
                lastLaunchedPkg = current
                lastLaunchAt = now
                launchLock(current)
            }
            return
        }

        val locked = HashSet(store.lockedPackages())
        locked.addAll(LockLogic.scheduledLockedPackages(store.schedules(), Calendar.getInstance()))
        if (!locked.contains(current)) return

        // No PIN configured yet → nothing to enforce.
        if (store.pinHash() == null) return

        val shouldLock = LockLogic.isLocked(
            mode = store.relockMode(),
            timeoutMinutes = store.relockTimeoutMinutes(),
            unlockedAt = LockSession.unlockedAt(current),
            leftAppAt = leftAppAt[current] ?: 0L,
            screenOffAt = screenOffAt,
            now = now,
        )
        if (!shouldLock) return

        // Debounce so we don't stack multiple lock screens for the same app.
        if (current == lastLaunchedPkg && now - lastLaunchAt < RELAUNCH_GUARD_MS) return
        lastLaunchedPkg = current
        lastLaunchAt = now
        launchLock(current)
    }

    private fun launchLock(packageName: String) {
        val intent = Intent(this, LockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            putExtra(LockActivity.EXTRA_PACKAGE, packageName)
        }
        runCatching { startActivity(intent) }
    }

    /** The latest foreground (package, activityClass). Class name powers the
     *  best-effort uninstall-screen guard; it may be null on some devices. */
    private fun foregroundApp(): Pair<String, String?>? {
        val end = System.currentTimeMillis()
        val begin = end - LOOKBACK_MS
        val events = usageStatsManager.queryEvents(begin, end)
        var pkg: String? = null
        var cls: String? = null
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                pkg = event.packageName
                cls = event.className
            }
        }
        return pkg?.let { Pair(it, cls) }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App lock protection",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while OpenLock is guarding your apps."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pending = openIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
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
        return builder
            .setContentTitle("OpenLock is protecting your apps")
            .setContentText("Locked apps stay behind your PIN.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(pending)
            .build()
    }

    companion object {
        @Volatile
        var isRunning: Boolean = false
            private set

        private const val CHANNEL_ID = "openlock_monitor"
        private const val NOTIFICATION_ID = 4711
        private const val POLL_INTERVAL_MS = 300L
        private const val LOOKBACK_MS = 10_000L
        private const val RELAUNCH_GUARD_MS = 1_500L
    }
}
