import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';

/// Production [IEnforcementBridge] backed by the `openlock/enforcement`
/// MethodChannel. Native side lives in the Kotlin `EnforcementPlugin`.
final class MethodChannelEnforcementBridge implements IEnforcementBridge {
  const MethodChannelEnforcementBridge();

  static const MethodChannel _channel = MethodChannel('openlock/enforcement');

  @override
  Future<void> pushConfig(Map<String, dynamic> config) async {
    await _channel.invokeMethod<void>('pushConfig', {
      'config': jsonEncode(config),
    });
  }

  @override
  Future<List<InstalledApp>> getInstalledApps() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'getInstalledApps',
    );
    return [
      for (final m in raw!)
        InstalledApp(
          packageName: m['packageName']! as String,
          label: m['label']! as String,
          versionCode: m['versionCode']! as int,
        ),
    ];
  }

  @override
  Future<Map<String, String?>> getAppIcons(List<InstalledApp> apps) async {
    final raw = await _channel.invokeMapMethod<String, String?>(
      'getAppIcons',
      {
        'apps': [
          for (final app in apps)
            {'packageName': app.packageName, 'versionCode': app.versionCode},
        ],
      },
    );
    return raw!;
  }

  @override
  Future<PermissionStates> getPermissionStates() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getPermissionStates',
    );
    if (raw == null) return const PermissionStates.unknown();
    return PermissionStates(
      usageAccess: raw['usageAccess'] == true,
      overlay: raw['overlay'] == true,
      notifications: raw['notifications'] == true,
      notificationAccess: raw['notificationAccess'] == true,
      batteryExempt: raw['batteryExempt'] == true,
      serviceRunning: raw['serviceRunning'] == true,
    );
  }

  @override
  Future<void> requestUsageAccess() =>
      _channel.invokeMethod<void>('requestUsageAccess');

  @override
  Future<void> requestOverlayPermission() =>
      _channel.invokeMethod<void>('requestOverlayPermission');

  @override
  Future<void> requestBatteryExemption() =>
      _channel.invokeMethod<void>('requestBatteryExemption');

  @override
  Future<void> requestNotificationPermission() =>
      _channel.invokeMethod<void>('requestNotificationPermission');

  @override
  Future<void> requestNotificationAccess() =>
      _channel.invokeMethod<void>('requestNotificationAccess');

  @override
  Future<bool> isServiceRunning() async =>
      await _channel.invokeMethod<bool>('isServiceRunning') ?? false;

  @override
  Future<void> startService() => _channel.invokeMethod<void>('startService');

  @override
  Future<void> stopService() => _channel.invokeMethod<void>('stopService');

  @override
  Future<bool> isDeviceAdminActive() async =>
      await _channel.invokeMethod<bool>('isDeviceAdminActive') ?? false;

  @override
  Future<void> requestDeviceAdmin() =>
      _channel.invokeMethod<void>('requestDeviceAdmin');

  @override
  Future<void> deactivateDeviceAdmin() =>
      _channel.invokeMethod<void>('deactivateDeviceAdmin');

  @override
  Future<List<IntruderRecord>> getIntruderRecords() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'getIntruderRecords',
    );
    if (raw == null) return const [];
    return raw.map(IntruderRecord.fromMap).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<void> deleteIntruderRecord(String id) =>
      _channel.invokeMethod<void>('deleteIntruderRecord', {'id': id});

  @override
  Future<void> clearIntruderRecords() =>
      _channel.invokeMethod<void>('clearIntruderRecords');
}
