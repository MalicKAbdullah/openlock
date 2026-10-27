package dev.abdullah.openlock

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [UninstallGuard.isAboutOwnApp] against flattened window trees
 * modelled on Pixel (AOSP) and Samsung (One UI) Settings / package-installer
 * screens — OpenLock's own screens must match, other apps' and list screens
 * must not.
 */
class UninstallGuardMatchingTest {

    private val label = "OpenLock"
    private val pkg = "dev.abdullah.openlock"

    private fun about(windowPkg: String, cls: String?, vararg nodes: Pair<String?, String?>) =
        UninstallGuard.isAboutOwnApp(
            windowPackage = windowPkg,
            windowClass = cls,
            nodes = nodes.map { ScreenNode(it.first, it.second) },
            ownLabel = label,
            ownPackage = pkg,
        )

    private val settings = UninstallGuard.SETTINGS_PACKAGE
    private val subSettings = "com.android.settings.SubSettings"

    // --- App info -------------------------------------------------------------

    private fun pixelAppInfo(appLabel: String) = arrayOf(
        "com.android.settings:id/action_bar" to null,
        null to "App info",
        "com.android.settings:id/entity_header_title" to appLabel,
        "com.android.settings:id/entity_header_summary" to "Installed",
        "com.android.settings:id/button1" to "Open",
        "com.android.settings:id/button2" to "Uninstall",
        "com.android.settings:id/button3" to "Force stop",
        "android:id/title" to "Notifications",
        "android:id/title" to "Permissions",
        "android:id/title" to "Storage & cache",
    )

    private fun samsungAppInfo(appLabel: String) = arrayOf(
        "com.android.settings:id/collapsing_toolbar" to null,
        null to "App info",
        "com.android.settings:id/entity_header_title" to appLabel,
        "com.android.settings:id/entity_header_summary" to "Version 1.7.0",
        "android:id/title" to "Mobile data",
        "android:id/title" to "Battery",
        "android:id/title" to "Storage",
        "com.android.settings:id/button1" to "Open",
        "com.android.settings:id/button2" to "Uninstall",
        "com.android.settings:id/button3" to "Force stop",
    )

    @Test
    fun guardsOwnAppInfoOnPixelAndSamsung() {
        assertTrue(about(settings, subSettings, *pixelAppInfo("OpenLock")))
        assertTrue(about(settings, "com.android.settings.applications.InstalledAppDetailsTop", *samsungAppInfo("OpenLock")))
    }

    @Test
    fun doesNotGuardOtherAppsInfo() {
        assertFalse(about(settings, subSettings, *pixelAppInfo("Chrome")))
        assertFalse(about(settings, "com.android.settings.applications.InstalledAppDetailsTop", *samsungAppInfo("WhatsApp")))
        // A label that merely starts with ours is another app.
        assertFalse(about(settings, subSettings, *pixelAppInfo("OpenLock Pro")))
    }

    @Test
    fun guardsOwnAppInfoSubPages() {
        // Storage & cache: clearing storage would wipe the PIN.
        assertTrue(
            about(
                settings,
                subSettings,
                null to "Storage & cache",
                "com.android.settings:id/entity_header_title" to "OpenLock",
                "com.android.settings:id/button1" to "Clear storage",
            ),
        )
    }

    // --- Lists that merely contain OpenLock's row -----------------------------

    @Test
    fun doesNotGuardAppsListOrSearchResults() {
        // Pixel Settings → Apps → See all apps.
        assertFalse(
            about(
                settings,
                subSettings,
                null to "All apps",
                "android:id/title" to "Calculator",
                "android:id/title" to "Chrome",
                "android:id/title" to "OpenLock",
                "android:id/summary" to "24 MB",
            ),
        )
        // Samsung Settings → Apps.
        assertFalse(
            about(
                settings,
                "com.android.settings.Settings\$ManageApplicationsActivity",
                null to "Apps",
                "com.android.settings:id/app_name" to "OpenLock",
                "com.android.settings:id/app_name" to "Samsung Notes",
            ),
        )
        // Settings search results (Pixel hosts search in a separate package).
        assertFalse(
            about(
                "com.google.android.settings.intelligence",
                "com.android.settings.intelligence.search.SearchActivity",
                "android:id/title" to "OpenLock",
                "android:id/summary" to "Apps",
            ),
        )
        // In-Settings search (Samsung) results page.
        assertFalse(
            about(
                settings,
                "com.samsung.android.settings.search.SearchActivity",
                "com.android.settings:id/title" to "OpenLock",
                "com.android.settings:id/summary" to "Apps",
            ),
        )
    }

    // --- Device admin ---------------------------------------------------------

    @Test
    fun guardsOwnDeviceAdminDeactivation() {
        // Pixel: DeviceAdminAdd with the AOSP header id.
        assertTrue(
            about(
                settings,
                "com.android.settings.DeviceAdminAdd",
                "com.android.settings:id/admin_name" to "OpenLock",
                "com.android.settings:id/admin_warning" to
                    "This admin app is active and allows the app OpenLock to perform the following operations:",
                "com.android.settings:id/action_button" to "Deactivate this device admin app",
            ),
        )
        // Samsung: DeviceAdminAdd whose layout lacks admin_name; body names us.
        assertTrue(
            about(
                settings,
                "com.android.settings.DeviceAdminAdd",
                null to "Device admin app",
                "com.android.settings:id/sec_admin_title" to "OpenLock",
                null to "Deactivate",
            ),
        )
    }

    @Test
    fun doesNotGuardOtherDeviceAdminsOrTheList() {
        assertFalse(
            about(
                settings,
                "com.android.settings.DeviceAdminAdd",
                "com.android.settings:id/admin_name" to "Find My Device",
                "com.android.settings:id/admin_warning" to
                    "This admin app is active and allows the app Find My Device to perform the following operations:",
                "com.android.settings:id/action_button" to "Deactivate this device admin app",
            ),
        )
        // The device-admin list shows OpenLock as one row among others.
        assertFalse(
            about(
                settings,
                "com.android.settings.Settings\$DeviceAdminSettingsActivity",
                "android:id/title" to "Find My Device",
                "android:id/title" to "OpenLock",
            ),
        )
    }

    // --- Package installer ----------------------------------------------------

    @Test
    fun guardsOwnUninstallDialog() {
        // Pixel: label in the dialog title.
        assertTrue(
            about(
                "com.google.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
                "android:id/alertTitle" to "OpenLock",
                "android:id/message" to "Do you want to uninstall this app?",
                "android:id/button1" to "OK",
            ),
        )
        // Samsung: label inside the message.
        assertTrue(
            about(
                "com.samsung.android.packageinstaller",
                null,
                "com.samsung.android.packageinstaller:id/message" to "Uninstall OpenLock?",
                "android:id/button1" to "Uninstall",
            ),
        )
        // Package name exposed instead of the label.
        assertTrue(
            about(
                "com.android.packageinstaller",
                null,
                "android:id/message" to "dev.abdullah.openlock will be uninstalled.",
            ),
        )
    }

    @Test
    fun doesNotGuardOtherAppsUninstallDialog() {
        assertFalse(
            about(
                "com.google.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
                "android:id/alertTitle" to "Chrome",
                "android:id/message" to "Do you want to uninstall this app?",
            ),
        )
        assertFalse(
            about(
                "com.samsung.android.packageinstaller",
                null,
                "com.samsung.android.packageinstaller:id/message" to "Uninstall OpenLockPro?",
            ),
        )
    }

    @Test
    fun ignoresOtherPackagesEvenWhenTheyNameUs() {
        assertFalse(
            about(
                "com.android.chrome",
                null,
                "com.android.chrome:id/title" to "Uninstall OpenLock?",
            ),
        )
        assertFalse(about(settings, "com.android.settings.wifi.WifiSettings"))
    }
}
