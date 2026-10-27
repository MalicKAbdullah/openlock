package dev.abdullah.openlock

import android.app.Activity
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Handles the `openlock/enforcement` MethodChannel: config push, installed-app
 * enumeration, permission checks/requests, service control, and the intruder
 * log. Everything here is local to the device.
 *
 * PackageManager queries, icon rendering and the encrypted store run off the
 * main thread so they never hold up a Flutter frame; replies are posted back
 * to the main thread, where MethodChannel results must be delivered.
 */
class EnforcementPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private val store: ConfigStore by lazy { ConfigStore.get(activity) }
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Serial, so config pushes and intruder-log edits apply in call order. */
    private val storeExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    /** App list and icon rendering; independent requests, so two workers. */
    private val appsExecutor: ExecutorService = Executors.newFixedThreadPool(2)

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        storeExecutor.shutdown()
        appsExecutor.shutdown()
    }

    /** Runs [work] on [executor] and delivers its value (or error) on the main thread. */
    private fun <T> replyFrom(
        executor: ExecutorService,
        result: MethodChannel.Result,
        work: () -> T,
    ) {
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("native_error", e.message, null) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pushConfig" -> {
                val config = call.argument<String>("config")
                replyFrom(storeExecutor, result) {
                    if (config != null) store.saveConfig(config)
                    null
                }
            }
            "getInstalledApps" -> replyFrom(appsExecutor, result) { installedApps() }
            "getAppIcons" -> {
                val apps = call.argument<List<Map<String, Any?>>>("apps").orEmpty()
                replyFrom(appsExecutor, result) { appIcons(apps) }
            }
            "getPermissionStates" -> result.success(permissionStates())
            "requestUsageAccess" -> {
                launch(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(null)
            }
            "requestOverlayPermission" -> {
                launch(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                result.success(null)
            }
            "requestBatteryExemption" -> {
                requestBatteryExemption()
                result.success(null)
            }
            "requestNotificationPermission" -> {
                requestNotifications()
                result.success(null)
            }
            "requestNotificationAccess" -> {
                launch(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                result.success(null)
            }
            "isServiceRunning" -> result.success(OpenLockMonitorService.isRunning)
            "startService" -> {
                startService()
                result.success(null)
            }
            "stopService" -> {
                stopService()
                result.success(null)
            }
            "isDeviceAdminActive" -> result.success(isDeviceAdminActive())
            "requestDeviceAdmin" -> {
                requestDeviceAdmin()
                result.success(null)
            }
            "deactivateDeviceAdmin" -> {
                deactivateDeviceAdmin()
                result.success(null)
            }
            "getIntruderRecords" ->
                replyFrom(storeExecutor, result) { store.intruderRecords() }
            "deleteIntruderRecord" -> {
                val id = call.argument<String>("id")
                replyFrom(storeExecutor, result) {
                    id?.let { store.deleteIntruder(it) }
                    null
                }
            }
            "clearIntruderRecords" -> replyFrom(storeExecutor, result) {
                store.clearIntruders()
                null
            }
            else -> result.notImplemented()
        }
    }

    // --- Installed apps -----------------------------------------------------

    /**
     * Launchable apps as metadata only (no icons), sorted by label. The
     * version code keys each app's icon in the disk cache.
     */
    private fun installedApps(): List<Map<String, Any?>> {
        val started = SystemClock.elapsedRealtime()
        val pm = activity.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolveInfos = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>()
        for (info in resolveInfos) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == activity.packageName) continue
            if (!seen.add(pkg)) continue
            // Uninstalled since the launcher query: not an installed app.
            val packageInfo = try {
                pm.getPackageInfo(pkg, 0)
            } catch (e: PackageManager.NameNotFoundException) {
                continue
            }
            val label = info.loadLabel(pm)?.toString() ?: pkg
            apps.add(
                mapOf(
                    "packageName" to pkg,
                    "label" to label,
                    "versionCode" to PackageInfoCompat.getLongVersionCode(packageInfo),
                ),
            )
        }
        apps.sortWith(compareBy { (it["label"] as? String)?.lowercase() ?: "" })
        if (BuildConfig.DEBUG) {
            Log.d(
                TAG,
                "installedApps: ${apps.size} apps in " +
                    "${SystemClock.elapsedRealtime() - started} ms",
            )
        }
        return apps
    }

    /**
     * Icon PNG paths for [apps] (`packageName`, `versionCode`), rendering any
     * not yet in the disk cache. A package without a loadable icon maps to
     * null. Older cached versions of a re-rendered package are deleted.
     */
    private fun appIcons(apps: List<Map<String, Any?>>): Map<String, String?> {
        val started = SystemClock.elapsedRealtime()
        val dir = File(activity.cacheDir, ICON_DIR).apply { mkdirs() }
        val cached = dir.list()?.toHashSet() ?: HashSet()
        val pm = activity.packageManager
        val paths = HashMap<String, String?>(apps.size)
        var misses = 0
        for (app in apps) {
            val pkg = app["packageName"] as String
            val version = (app["versionCode"] as Number).toLong()
            val name = "$pkg@$version.png"
            val file = File(dir, name)
            if (name in cached) {
                paths[pkg] = file.path
                continue
            }
            misses++
            paths[pkg] = runCatching {
                renderIcon(pm.getApplicationIcon(pkg), file)
                // Package names never contain '@', so the prefix matches only
                // this package's earlier versions.
                cached.filter { it.startsWith("$pkg@") }
                    .forEach { File(dir, it).delete() }
                file.path
            }.getOrNull()
        }
        if (BuildConfig.DEBUG) {
            Log.d(
                TAG,
                "appIcons: ${apps.size} requested, ${apps.size - misses} cached, " +
                    "$misses rendered in ${SystemClock.elapsedRealtime() - started} ms",
            )
        }
        return paths
    }

    /** Draws [drawable] at [ICON_SIZE_PX] and writes it to [target] atomically. */
    private fun renderIcon(drawable: Drawable, target: File) {
        val size = ICON_SIZE_PX
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            bmp
        }
        // A reader must never see a half-written PNG under the final name.
        val partial = File(target.parentFile, "${target.name}.part")
        FileOutputStream(partial).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        if (!partial.renameTo(target)) {
            partial.delete()
            error("could not move icon into place for ${target.name}")
        }
    }

    // --- Permissions --------------------------------------------------------

    private fun permissionStates(): Map<String, Any?> = mapOf(
        "usageAccess" to hasUsageAccess(),
        "overlay" to hasOverlay(),
        "notifications" to hasNotifications(),
        "notificationAccess" to hasNotificationAccess(),
        "batteryExempt" to isBatteryExempt(),
        "serviceRunning" to OpenLockMonitorService.isRunning,
    )

    /** Whether OpenLock holds notification-listener access (required to hide
     *  locked apps' notification content). */
    private fun hasNotificationAccess(): Boolean {
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val me = activity.packageName
        return flat.split(':').any { it.startsWith("$me/") }
    }

    private fun hasUsageAccess(): Boolean {
        return try {
            val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    activity.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    activity.packageName,
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun hasOverlay(): Boolean = Settings.canDrawOverlays(activity)

    private fun hasNotifications(): Boolean =
        NotificationManagerCompat.from(activity).areNotificationsEnabled()

    private fun isBatteryExempt(): Boolean {
        return try {
            val pm = activity.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
            pm.isIgnoringBatteryOptimizations(activity.packageName)
        } catch (e: Exception) {
            false
        }
    }

    private fun requestBatteryExemption() {
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${activity.packageName}"),
        )
        launch(intent)
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFICATIONS,
            )
        } else {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            launch(intent)
        }
    }

    // --- Service control ----------------------------------------------------

    private fun startService() {
        val intent = Intent(activity, OpenLockMonitorService::class.java)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
        }
    }

    private fun stopService() {
        runCatching {
            activity.stopService(Intent(activity, OpenLockMonitorService::class.java))
        }
        LockSession.clearAll()
    }

    // --- Device admin (uninstall protection) --------------------------------

    private fun adminComponent(): ComponentName =
        ComponentName(activity, OpenLockDeviceAdminReceiver::class.java)

    private fun devicePolicyManager(): DevicePolicyManager =
        activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private fun isDeviceAdminActive(): Boolean =
        runCatching { devicePolicyManager().isAdminActive(adminComponent()) }
            .getOrDefault(false)

    private fun requestDeviceAdmin() {
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent())
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "OpenLock uses device administrator access only to block itself " +
                    "from being uninstalled while protection is on. It never " +
                    "manages, locks, or wipes your device.",
            )
        }
        launch(intent)
    }

    private fun deactivateDeviceAdmin() {
        runCatching { devicePolicyManager().removeActiveAdmin(adminComponent()) }
    }

    private fun launch(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { activity.startActivity(intent) }
    }

    companion object {
        private const val CHANNEL = "openlock/enforcement"
        private const val TAG = "OpenLockPerf"
        private const val ICON_DIR = "app_icons"

        /** 40 dp at up to ~3.6x density, the largest the app list draws. */
        private const val ICON_SIZE_PX = 144
        private const val REQ_NOTIFICATIONS = 9021
    }
}
