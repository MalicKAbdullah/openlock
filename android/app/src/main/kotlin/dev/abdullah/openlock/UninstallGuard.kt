package dev.abdullah.openlock

/** One node of the active window's accessibility tree: its resource id (e.g.
 *  `com.android.settings:id/entity_header_title`) and its visible text or
 *  content description. */
data class ScreenNode(val viewId: String?, val text: String?)

/**
 * Decides whether the active window is an OS screen *about OpenLock itself*
 * that could remove it: its App info page (and sub-pages), its uninstall
 * confirmation, or the device-admin deactivation screen naming it. Mirror of
 * the Dart `UninstallGuard`.
 *
 * Screens are identified by what they show, never by activity class alone:
 * the same Settings activities and installer dialogs serve every app, and
 * lists that merely contain OpenLock's row (Apps list, Settings search
 * results, the device-admin list) must not match.
 */
object UninstallGuard {

    const val SETTINGS_PACKAGE = "com.android.settings"

    /** Resource-id suffixes of the single-app header in Settings: the App info
     *  header (SettingsLib EntityHeaderController, used by AOSP and One UI) and
     *  the device-admin activate/deactivate screen's app name. */
    private val HEADER_ID_SUFFIXES = listOf(
        ":id/entity_header_title",
        ":id/admin_name",
    )

    private const val DEVICE_ADMIN_ADD_CLASS = "deviceadminadd"

    /** Packages whose windows can host a screen that removes OpenLock. */
    fun isCandidatePackage(pkg: String): Boolean =
        pkg == SETTINGS_PACKAGE || isPackageInstaller(pkg)

    fun isPackageInstaller(pkg: String): Boolean =
        pkg == "com.android.packageinstaller" ||
            pkg == "com.google.android.packageinstaller" ||
            pkg.endsWith(".packageinstaller")

    /**
     * [windowPackage]/[windowClass] come from the latest window-state change;
     * [nodes] is the active window's flattened tree; [ownLabel] is OpenLock's
     * label from PackageManager in the current locale (the same string the OS
     * screens render) and [ownPackage] its package name.
     */
    fun isAboutOwnApp(
        windowPackage: String,
        windowClass: String?,
        nodes: List<ScreenNode>,
        ownLabel: String,
        ownPackage: String,
    ): Boolean {
        // The uninstaller dialog only ever concerns one app; it names it in the
        // title (AOSP) or message (One UI).
        if (isPackageInstaller(windowPackage)) {
            return nodes.any { mentions(it.text, ownLabel, ownPackage) }
        }
        if (windowPackage != SETTINGS_PACKAGE) return false

        val headerNamesUs = nodes.any { node ->
            val id = node.viewId ?: return@any false
            HEADER_ID_SUFFIXES.any { id.endsWith(it) } &&
                node.text != null &&
                (sameText(node.text, ownLabel) || node.text.trim() == ownPackage)
        }
        if (headerNamesUs) return true

        // DeviceAdminAdd is a single-app screen; its body text names the admin
        // app even where the OEM layout lacks the AOSP header id.
        val isDeviceAdminAdd =
            windowClass?.lowercase()?.contains(DEVICE_ADMIN_ADD_CLASS) == true
        return isDeviceAdminAdd && nodes.any { mentions(it.text, ownLabel, ownPackage) }
    }

    private fun sameText(text: String, label: String): Boolean =
        text.trim().equals(label.trim(), ignoreCase = true)

    /** [text] names the app: its package name, or its label as a whole word
     *  ("OpenLock" in "Uninstall OpenLock?" but not in "OpenLockPro"). */
    private fun mentions(text: String?, label: String, pkg: String): Boolean {
        if (text.isNullOrEmpty()) return false
        if (text.contains(pkg)) return true
        val needle = label.trim()
        if (needle.isEmpty()) return false
        var from = 0
        while (true) {
            val i = text.indexOf(needle, from, ignoreCase = true)
            if (i < 0) return false
            val end = i + needle.length
            val before = if (i == 0) null else text[i - 1]
            val after = if (end >= text.length) null else text[end]
            if ((before == null || !before.isLetterOrDigit()) &&
                (after == null || !after.isLetterOrDigit())
            ) {
                return true
            }
            from = i + 1
        }
    }
}
