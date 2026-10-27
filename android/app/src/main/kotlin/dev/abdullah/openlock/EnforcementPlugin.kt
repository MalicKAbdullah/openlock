package dev.abdullah.openlock

import android.app.Activity
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Handles the `openlock/enforcement` MethodChannel: config push, installed-app
 * enumeration, permission checks/requests, service control, and the intruder
 * log. Everything here is local to the device.
 */
class EnforcementPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private val store = ConfigStore(activity)

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pushConfig" -> {
                val config = call.argument<String>("config")
                if (config != null) store.saveConfig(config)
                result.success(null)
            }
            "getInstalledApps" -> result.success(installedApps())
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
            "requestScreenGuardAccess" -> {
                launch(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
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
            "getIntruderRecords" -> result.success(store.intruderRecords())
            "deleteIntruderRecord" -> {
                call.argument<String>("id")?.let { store.deleteIntruder(it) }
                result.success(null)
            }
            "clearIntruderRecords" -> {
                store.clearIntruders()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // --- Installed apps -----------------------------------------------------

    private fun installedApps(): List<Map<String, Any?>> {
        val pm = activity.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolveInfos = pm.queryIntentActivities(intent, 0)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>()
        for (info in resolveInfos) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == activity.packageName) continue
            if (!seen.add(pkg)) continue
            val label = info.loadLabel(pm)?.toString() ?: pkg
            val icon = runCatching { drawableToBase64(info.loadIcon(pm)) }.getOrNull()
            apps.add(mapOf("packageName" to pkg, "label" to label, "icon" to icon))
        }
        apps.sortWith(compareBy { (it["label"] as? String)?.lowercase() ?: "" })
        return apps
    }

    private fun drawableToBase64(drawable: Drawable?): String? {
        if (drawable == null) return null
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
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }

    // --- Permissions --------------------------------------------------------

    private fun permissionStates(): Map<String, Any?> = mapOf(
        "usageAccess" to hasUsageAccess(),
        "overlay" to hasOverlay(),
        "notifications" to hasNotifications(),
        "notificationAccess" to hasNotificationAccess(),
        "screenGuardAccess" to hasScreenGuardAccess(),
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

    /** Whether OpenLock's uninstall-guard accessibility service is enabled
     *  (required for the guard to recognise OpenLock's own screens). */
    private fun hasScreenGuardAccess(): Boolean {
        val flat = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val me = ComponentName(activity, OpenLockGuardAccessibilityService::class.java)
        return flat.split(':').any { ComponentName.unflattenFromString(it) == me }
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
        private const val ICON_SIZE_PX = 96
        private const val REQ_NOTIFICATIONS = 9021
    }
}
