package dev.abdullah.openlock

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Reads the active window of Settings and the package installer so the
 * uninstall guard can tell *which app* a screen is about — information
 * UsageStats does not expose. It only publishes [GuardedScreen]; the monitor
 * service decides whether to lock. Window content is inspected in memory and
 * never stored or sent anywhere.
 */
class OpenLockGuardAccessibilityService : AccessibilityService() {

    private var windowPackage: String? = null
    private var windowClass: String? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val type = event.eventType
        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            windowPackage = event.packageName?.toString()
            windowClass = event.className?.toString()
        } else if (type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            return
        }
        val eventPkg = event.packageName?.toString()
        if (type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            (eventPkg == null || !UninstallGuard.isCandidatePackage(eventPkg))
        ) {
            return
        }

        val root = rootInActiveWindow
        val rootPkg = root?.packageName?.toString()
        if (root == null || rootPkg == null || !UninstallGuard.isCandidatePackage(rootPkg)) {
            GuardedScreen.clear()
            return
        }
        val about = UninstallGuard.isAboutOwnApp(
            windowPackage = rootPkg,
            windowClass = if (windowPackage == rootPkg) windowClass else null,
            nodes = flatten(root),
            ownLabel = applicationInfo.loadLabel(packageManager).toString(),
            ownPackage = packageName,
        )
        if (about) GuardedScreen.set(rootPkg) else GuardedScreen.clear()
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        GuardedScreen.clear()
        super.onDestroy()
    }

    private fun flatten(root: AccessibilityNodeInfo): List<ScreenNode> {
        val out = ArrayList<ScreenNode>()
        val stack = ArrayDeque<AccessibilityNodeInfo>()
        stack.addLast(root)
        while (stack.isNotEmpty() && out.size < MAX_NODES) {
            val node = stack.removeLast()
            val text = node.text?.toString() ?: node.contentDescription?.toString()
            out.add(ScreenNode(node.viewIdResourceName, text))
            for (i in node.childCount - 1 downTo 0) {
                node.getChild(i)?.let { stack.addLast(it) }
            }
        }
        return out
    }

    private companion object {
        /** Settings and installer screens are far smaller; the cap bounds the
         *  walk on a pathological tree. */
        const val MAX_NODES = 600
    }
}

/**
 * The candidate window (Settings / package installer) currently showing a
 * screen about OpenLock, as last seen by [OpenLockGuardAccessibilityService].
 * Same process as [OpenLockMonitorService], which reads it every poll.
 */
object GuardedScreen {
    @Volatile private var pkg: String? = null

    fun set(windowPackage: String) {
        pkg = windowPackage
    }

    fun clear() {
        pkg = null
    }

    fun isShowing(windowPackage: String): Boolean = pkg == windowPackage
}
