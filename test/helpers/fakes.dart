import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:openlock/src/core/clock.dart';
import 'package:openlock/src/core/interfaces/biometric_auth.dart';
import 'package:openlock/src/core/interfaces/config_file_store.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/interfaces/key_derivation.dart';

/// In-memory secure storage.
final class FakeSecureStorage implements ISecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String value}) async =>
      _data[key] = value;

  @override
  Future<String?> read({required String key}) async => _data[key];

  @override
  Future<void> delete({required String key}) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<Map<String, String>> readAll() async => Map.of(_data);
}

/// A controllable clock.
final class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  void setTime(DateTime value) => _now = value;

  void advance(Duration by) => _now = _now.add(by);

  @override
  DateTime now() => _now;
}

/// Deterministic, passphrase-sensitive key derivation — fast enough for tests
/// (no Argon2id) while still failing loudly on the wrong passphrase.
final class FakeKeyDerivation implements IKeyDerivation {
  const FakeKeyDerivation();

  @override
  Future<Uint8List> deriveKey({
    required String passphrase,
    required Uint8List salt,
  }) async {
    final combined = <int>[...passphrase.codeUnits, ...salt];
    final key = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      key[i] = (combined[i % combined.length] ^ (i * 7)) & 0xff;
    }
    return key;
  }
}

/// In-memory config file store.
final class FakeConfigFileStore implements IConfigFileStore {
  Uint8List? _bytes;

  @override
  Future<Uint8List?> read() async => _bytes;

  @override
  Future<void> write(Uint8List bytes) async => _bytes = bytes;

  @override
  Future<void> delete() async => _bytes = null;
}

/// Configurable biometric authenticator.
final class FakeBiometricAuth implements IBiometricAuth {
  FakeBiometricAuth({this.available = true, this.willSucceed = true});

  bool available;
  bool willSucceed;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async => willSucceed;
}

/// In-memory enforcement bridge capturing pushed configs.
final class FakeEnforcementBridge implements IEnforcementBridge {
  FakeEnforcementBridge({this.apps = const [], PermissionStates? permissions})
      : permissions = permissions ??
            const PermissionStates(
              usageAccess: true,
              overlay: true,
              notifications: true,
              notificationAccess: true,
              screenGuardAccess: true,
              batteryExempt: true,
              serviceRunning: true,
            );

  List<InstalledApp> apps;
  PermissionStates permissions;
  Map<String, dynamic>? lastPushedConfig;
  final List<IntruderRecord> records = [];
  bool serviceRunning = false;
  bool deviceAdminActive = false;
  bool deviceAdminRequested = false;
  bool deviceAdminDeactivated = false;

  @override
  Future<void> pushConfig(Map<String, dynamic> config) async =>
      lastPushedConfig = config;

  @override
  Future<List<InstalledApp>> getInstalledApps() async => apps;

  @override
  Future<PermissionStates> getPermissionStates() async => permissions;

  @override
  Future<void> requestUsageAccess() async {}

  @override
  Future<void> requestOverlayPermission() async {}

  @override
  Future<void> requestBatteryExemption() async {}

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<void> requestNotificationAccess() async {}

  @override
  Future<void> requestScreenGuardAccess() async {}

  @override
  Future<bool> isServiceRunning() async => serviceRunning;

  @override
  Future<void> startService() async => serviceRunning = true;

  @override
  Future<void> stopService() async => serviceRunning = false;

  @override
  Future<bool> isDeviceAdminActive() async => deviceAdminActive;

  @override
  Future<void> requestDeviceAdmin() async => deviceAdminRequested = true;

  @override
  Future<void> deactivateDeviceAdmin() async {
    deviceAdminDeactivated = true;
    deviceAdminActive = false;
  }

  @override
  Future<List<IntruderRecord>> getIntruderRecords() async => records;

  @override
  Future<void> deleteIntruderRecord(String id) async =>
      records.removeWhere((r) => r.id == id);

  @override
  Future<void> clearIntruderRecords() async => records.clear();
}
