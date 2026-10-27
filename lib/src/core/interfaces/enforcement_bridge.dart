/// A launchable app installed on the device, as reported by the native
/// PackageManager query. Metadata only: the icon is fetched separately, per
/// visible row, through [IEnforcementBridge.getAppIcons].
final class InstalledApp {
  InstalledApp({
    required this.packageName,
    required this.label,
    required this.versionCode,
  })  : labelKey = label.toLowerCase(),
        packageKey = packageName.toLowerCase();

  final String packageName;
  final String label;

  /// The installed build; it keys the cached icon, so an update re-renders it.
  final int versionCode;

  /// [label] and [packageName] lower-cased once, for case-insensitive sorting
  /// and search without lower-casing inside every comparison.
  final String labelKey;
  final String packageKey;
}

/// Snapshot of the special-access permissions the enforcement service needs.
final class PermissionStates {
  const PermissionStates({
    required this.usageAccess,
    required this.overlay,
    required this.notifications,
    required this.notificationAccess,
    required this.screenGuardAccess,
    required this.batteryExempt,
    required this.serviceRunning,
  });

  const PermissionStates.unknown()
      : usageAccess = false,
        overlay = false,
        notifications = false,
        notificationAccess = false,
        screenGuardAccess = false,
        batteryExempt = false,
        serviceRunning = false;

  final bool usageAccess;
  final bool overlay;
  final bool notifications;

  /// Notification-listener access, required to hide locked apps' notification
  /// content. Separate from [notifications] (the POST_NOTIFICATIONS runtime
  /// grant for OpenLock's own notices).
  final bool notificationAccess;

  /// OpenLock's uninstall-guard accessibility service is enabled, letting the
  /// "Prevent uninstall" guard recognise OpenLock's own App info, uninstall,
  /// and device-admin screens.
  final bool screenGuardAccess;
  final bool batteryExempt;
  final bool serviceRunning;

  /// The two permissions without which cross-app locking cannot work at all.
  bool get canEnforce => usageAccess && overlay;

  /// Everything granted and the monitor actually running.
  bool get protectionActive => canEnforce && serviceRunning;

  PermissionStates copyWith({
    bool? usageAccess,
    bool? overlay,
    bool? notifications,
    bool? notificationAccess,
    bool? screenGuardAccess,
    bool? batteryExempt,
    bool? serviceRunning,
  }) =>
      PermissionStates(
        usageAccess: usageAccess ?? this.usageAccess,
        overlay: overlay ?? this.overlay,
        notifications: notifications ?? this.notifications,
        notificationAccess: notificationAccess ?? this.notificationAccess,
        screenGuardAccess: screenGuardAccess ?? this.screenGuardAccess,
        batteryExempt: batteryExempt ?? this.batteryExempt,
        serviceRunning: serviceRunning ?? this.serviceRunning,
      );
}

/// A recorded intruder event: a failed-unlock burst against a locked app,
/// optionally with a silently captured front-camera photo.
final class IntruderRecord {
  const IntruderRecord({
    required this.id,
    required this.packageName,
    required this.timestamp,
    this.photoPath,
  });

  factory IntruderRecord.fromMap(Map<Object?, Object?> map) => IntruderRecord(
        id: map['id'] as String? ?? '',
        packageName: map['package'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? 0,
        ),
        photoPath: map['photoPath'] as String?,
      );

  final String id;
  final String packageName;
  final DateTime timestamp;
  final String? photoPath;
}

/// The bridge to the native enforcement layer (`openlock/enforcement`
/// MethodChannel). Every platform interaction goes through this interface so
/// the whole Flutter app is testable with an in-memory fake — no platform
/// channels in tests.
abstract interface class IEnforcementBridge {
  /// Writes the enforcement subset of the config into the native
  /// EncryptedSharedPreferences the monitor service reads.
  Future<void> pushConfig(Map<String, dynamic> config);

  /// The list of launchable apps (excluding OpenLock and launcher-less system
  /// apps) for the app picker, without icons.
  Future<List<InstalledApp>> getInstalledApps();

  /// Paths of launcher-icon PNGs for [apps], keyed by package name; null for
  /// a package that has no loadable icon. Native renders an icon into its
  /// disk cache the first time a version is requested.
  Future<Map<String, String?>> getAppIcons(List<InstalledApp> apps);

  Future<PermissionStates> getPermissionStates();

  Future<void> requestUsageAccess();
  Future<void> requestOverlayPermission();
  Future<void> requestBatteryExemption();
  Future<void> requestNotificationPermission();

  /// Opens the system "Notification access" screen so the user can grant
  /// OpenLock's NotificationListenerService (needed to hide locked apps'
  /// notification content). The grant is read back via [getPermissionStates].
  Future<void> requestNotificationAccess();

  /// Opens the system Accessibility settings so the user can enable OpenLock's
  /// uninstall-guard service. The grant is read back via
  /// [getPermissionStates].
  Future<void> requestScreenGuardAccess();

  Future<bool> isServiceRunning();
  Future<void> startService();
  Future<void> stopService();

  /// Whether OpenLock is currently an active device administrator. While it is,
  /// Android blocks the app from being uninstalled until admin is deactivated.
  Future<bool> isDeviceAdminActive();

  /// Launches the system "activate device admin" dialog. The user must confirm;
  /// the resulting state is read back via [isDeviceAdminActive].
  Future<void> requestDeviceAdmin();

  /// Programmatically deactivates device admin (lifting uninstall protection).
  /// Callers MUST have re-authenticated the user in-app first.
  Future<void> deactivateDeviceAdmin();

  Future<List<IntruderRecord>> getIntruderRecords();
  Future<void> deleteIntruderRecord(String id);
  Future<void> clearIntruderRecords();
}
