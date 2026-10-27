package dev.abdullah.openlock

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [LockLogic.shouldGuardUninstall] — the package/activity
 * matcher that decides when to throw the lock over the OS screens used to
 * remove OpenLock. Covers Pixel (AOSP) and Samsung (OneUI) activity names.
 */
class UninstallGuardMatchingTest {

    private fun guard(pkg: String, cls: String?) =
        LockLogic.shouldGuardUninstall(preventUninstall = true, pkg = pkg, className = cls)

    @Test
    fun neverGuardsWhenProtectionIsOff() {
        assertFalse(
            LockLogic.shouldGuardUninstall(
                preventUninstall = false,
                pkg = "com.android.settings",
                className = "com.android.settings.DeviceAdminAdd",
            ),
        )
        assertFalse(
            LockLogic.shouldGuardUninstall(
                preventUninstall = false,
                pkg = "com.android.packageinstaller",
                className = "com.android.packageinstaller.UninstallerActivity",
            ),
        )
    }

    @Test
    fun guardsDeviceAdminScreens() {
        // Pixel / AOSP
        assertTrue(guard("com.android.settings", "com.android.settings.DeviceAdminAdd"))
        assertTrue(guard("com.android.settings", "com.android.settings.DeviceAdminSettings"))
        // Samsung OneUI (sub-activity alias, still under com.android.settings)
        assertTrue(
            guard(
                "com.android.settings",
                "com.android.settings.Settings\$DeviceAdminSettingsActivity",
            ),
        )
    }

    @Test
    fun guardsAppInfoScreens() {
        // Pixel: classic + dashboard app-info
        assertTrue(
            guard(
                "com.android.settings",
                "com.android.settings.applications.InstalledAppDetails",
            ),
        )
        assertTrue(
            guard(
                "com.android.settings",
                "com.android.settings.applications.appinfo.AppInfoDashboardFragment",
            ),
        )
        // Samsung OneUI app-info entry activity
        assertTrue(
            guard(
                "com.android.settings",
                "com.android.settings.applications.InstalledAppDetailsTop",
            ),
        )
    }

    @Test
    fun guardsUninstallerDialogsAcrossOems() {
        assertTrue(
            guard(
                "com.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
            ),
        )
        assertTrue(
            guard(
                "com.google.android.packageinstaller",
                "com.android.packageinstaller.UninstallerActivity",
            ),
        )
        // Samsung ships its own package installer flavour.
        assertTrue(guard("com.samsung.android.packageinstaller", null))
    }

    @Test
    fun doesNotGuardUnrelatedSettingsScreens() {
        assertFalse(guard("com.android.settings", "com.android.settings.wifi.WifiSettings"))
        assertFalse(
            guard(
                "com.android.settings",
                "com.android.settings.Settings\$WifiSettingsActivity",
            ),
        )
        // Settings home with no class info should not trip the guard.
        assertFalse(guard("com.android.settings", null))
    }

    @Test
    fun doesNotGuardUnrelatedApps() {
        assertFalse(guard("com.whatsapp", "com.whatsapp.HomeActivity"))
        assertFalse(guard("com.android.chrome", null))
    }
}
