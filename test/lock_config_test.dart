import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/models/relock_policy.dart';
import 'package:openlock/src/features/schedules/models/lock_schedule.dart';

void main() {
  LockConfig sample() => LockConfig(
        lockedPackages: {'com.social', 'com.game'},
        lockNewApps: true,
        relock: const RelockPolicy(
          mode: RelockMode.afterTimeout,
          timeout: Duration(minutes: 15),
        ),
        randomizeKeypad: true,
        intruderCaptureEnabled: true,
        intruderThreshold: 4,
        fakeCoverEnabled: true,
        preventUninstall: true,
        hideNotifications: true,
        notificationOverrides: const {'com.game': false},
        schedules: [
          LockSchedule(
            id: 's1',
            name: 'Work',
            packages: {'com.social'},
            weekdays: {1, 2, 3, 4, 5},
            startMinutes: 540,
            endMinutes: 1020,
          ),
        ],
      );

  test('JSON round-trip preserves every field', () {
    final original = sample();
    final restored = LockConfig.fromJson(original.toJson());

    expect(restored.lockedPackages, original.lockedPackages);
    expect(restored.lockNewApps, isTrue);
    expect(restored.relock.mode, RelockMode.afterTimeout);
    expect(restored.relock.timeout, const Duration(minutes: 15));
    expect(restored.randomizeKeypad, isTrue);
    expect(restored.intruderCaptureEnabled, isTrue);
    expect(restored.intruderThreshold, 4);
    expect(restored.fakeCoverEnabled, isTrue);
    expect(restored.preventUninstall, isTrue);
    expect(restored.hideNotifications, isTrue);
    expect(restored.notificationOverrides, {'com.game': false});
    expect(restored.schedules.length, 1);
    expect(restored.schedules.first.name, 'Work');
    expect(restored.schedules.first.weekdays, {1, 2, 3, 4, 5});
  });

  test('empty JSON yields sensible defaults', () {
    final config = LockConfig.fromJson(const {});
    expect(config.lockedPackages, isEmpty);
    expect(config.relock.mode, RelockMode.immediately);
    expect(config.intruderThreshold, 3);
    expect(config.preventUninstall, isFalse);
    expect(config.hideNotifications, isFalse);
    expect(config.notificationOverrides, isEmpty);
  });

  test('hidesNotificationsFor honours lock state, global flag, and override',
      () {
    const base = LockConfig(
      lockedPackages: {'com.social', 'com.game'},
      hideNotifications: true,
      notificationOverrides: {'com.game': false},
    );
    // Locked + global on → hidden.
    expect(base.hidesNotificationsFor('com.social'), isTrue);
    // Locked but explicit override off → not hidden.
    expect(base.hidesNotificationsFor('com.game'), isFalse);
    // Not locked → never hidden even with global on.
    expect(base.hidesNotificationsFor('com.other'), isFalse);

    // Global off, but a per-app override opts one app in.
    const optIn = LockConfig(
      lockedPackages: {'com.social'},
      notificationOverrides: {'com.social': true},
    );
    expect(optIn.hidesNotificationsFor('com.social'), isTrue);
  });

  test('toNativeMap contains exactly the enforcement subset + verifier', () {
    final map = sample().toNativeMap(
      pinHash: 'HASH',
      pinSalt: 'SALT',
      biometricEnabled: true,
    );

    expect(map['lockedPackages'], ['com.game', 'com.social']); // sorted
    expect(map['relockMode'], 'afterTimeout');
    expect(map['relockTimeoutMinutes'], 15);
    expect(map['randomizeKeypad'], true);
    expect(map['intruderCaptureEnabled'], true);
    expect(map['intruderThreshold'], 4);
    expect(map['fakeCoverEnabled'], true);
    expect(map['preventUninstall'], true);
    expect(map['hideNotifications'], true);
    expect(map['notificationOverrides'], {'com.game': false});
    expect(map['biometricEnabled'], true);
    expect(map['pinHash'], 'HASH');
    expect(map['pinSalt'], 'SALT');
    expect(map['pinIterations'], 120000);
    expect((map['schedules'] as List).length, 1);
    // The native map must not leak the source-of-truth-only lockNewApps flag.
    expect(map.containsKey('lockNewApps'), isFalse);
  });

  test('toNativeMap defaults biometricEnabled to false', () {
    final map = const LockConfig().toNativeMap(pinHash: 'H', pinSalt: 'S');
    expect(map['biometricEnabled'], false);
    expect(map['preventUninstall'], false);
  });

  test('IntruderRecord.fromMap round-trips the channel payload', () {
    final record = IntruderRecord.fromMap({
      'id': 'abc',
      'package': 'com.social',
      'timestamp': 1700000000000,
      'photoPath': '/data/x.jpg',
    });
    expect(record.id, 'abc');
    expect(record.packageName, 'com.social');
    expect(record.timestamp.millisecondsSinceEpoch, 1700000000000);
    expect(record.photoPath, '/data/x.jpg');
  });

  test('LockSchedule JSON round-trip', () {
    final s = LockSchedule(
      id: 'x',
      name: 'Night',
      packages: {'com.b', 'com.a'},
      weekdays: {6, 7},
      startMinutes: 1320,
      endMinutes: 360,
    );
    final restored = LockSchedule.fromJson(s.toJson());
    expect(restored.id, 'x');
    expect(restored.packages, {'com.a', 'com.b'});
    expect(restored.weekdays, {6, 7});
    expect(restored.startMinutes, 1320);
    expect(restored.endMinutes, 360);
    expect(restored.isOvernight, isTrue);
  });
}
