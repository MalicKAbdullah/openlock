/// One node of the active window's accessibility tree: its resource id (e.g.
/// `com.android.settings:id/entity_header_title`) and its visible text or
/// content description.
typedef ScreenNode = ({String? viewId, String? text});

/// Pure decision for the uninstall-protection screen guard, mirrored exactly by
/// the Kotlin `UninstallGuard`. Decides whether the active window is an OS
/// screen *about OpenLock itself* that could remove it: its App info page (and
/// sub-pages), its uninstall confirmation, or the device-admin deactivation
/// screen naming it.
///
/// Screens are identified by what they show (read by OpenLock's accessibility
/// service), never by activity class alone: the same Settings activities and
/// installer dialogs serve every app, and lists that merely contain OpenLock's
/// row (Apps list, Settings search results, the device-admin list) must not
/// match.
abstract final class UninstallGuard {
  const UninstallGuard._();

  static const String settingsPackage = 'com.android.settings';

  /// Resource-id suffixes of the single-app header in Settings: the App info
  /// header (SettingsLib EntityHeaderController, used by AOSP and One UI) and
  /// the device-admin activate/deactivate screen's app name.
  static const List<String> headerIdSuffixes = [
    ':id/entity_header_title',
    ':id/admin_name',
  ];

  static const String _deviceAdminAddClass = 'deviceadminadd';

  /// Packages whose windows can host a screen that removes OpenLock.
  static bool isCandidatePackage(String package) =>
      package == settingsPackage || isPackageInstaller(package);

  static bool isPackageInstaller(String package) =>
      package == 'com.android.packageinstaller' ||
      package == 'com.google.android.packageinstaller' ||
      package.endsWith('.packageinstaller');

  /// [windowPackage]/[windowClass] come from the latest window-state change;
  /// [nodes] is the active window's flattened tree; [ownLabel] is OpenLock's
  /// label in the current locale and [ownPackage] its package name.
  static bool isAboutOwnApp({
    required String windowPackage,
    String? windowClass,
    required List<ScreenNode> nodes,
    required String ownLabel,
    required String ownPackage,
  }) {
    // The uninstaller dialog only ever concerns one app; it names it in the
    // title (AOSP) or message (One UI).
    if (isPackageInstaller(windowPackage)) {
      return nodes.any((n) => _mentions(n.text, ownLabel, ownPackage));
    }
    if (windowPackage != settingsPackage) return false;

    final headerNamesUs = nodes.any((n) {
      final id = n.viewId;
      final text = n.text;
      if (id == null || text == null) return false;
      return headerIdSuffixes.any(id.endsWith) &&
          (_sameText(text, ownLabel) || text.trim() == ownPackage);
    });
    if (headerNamesUs) return true;

    // DeviceAdminAdd is a single-app screen; its body text names the admin
    // app even where the OEM layout lacks the AOSP header id.
    final isDeviceAdminAdd =
        windowClass?.toLowerCase().contains(_deviceAdminAddClass) ?? false;
    return isDeviceAdminAdd &&
        nodes.any((n) => _mentions(n.text, ownLabel, ownPackage));
  }

  static bool _sameText(String text, String label) =>
      text.trim().toLowerCase() == label.trim().toLowerCase();

  /// [text] names the app: its package name, or its label as a whole word
  /// ("OpenLock" in "Uninstall OpenLock?" but not in "OpenLockPro").
  static bool _mentions(String? text, String label, String package) {
    if (text == null || text.isEmpty) return false;
    if (text.contains(package)) return true;
    final needle = label.trim().toLowerCase();
    if (needle.isEmpty) return false;
    final haystack = text.toLowerCase();
    var from = 0;
    while (true) {
      final i = haystack.indexOf(needle, from);
      if (i < 0) return false;
      final end = i + needle.length;
      final beforeOk = i == 0 || !_isWordChar(haystack[i - 1]);
      final afterOk = end >= haystack.length || !_isWordChar(haystack[end]);
      if (beforeOk && afterOk) return true;
      from = i + 1;
    }
  }

  static final RegExp _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isWordChar(String c) => _word.hasMatch(c);
}
