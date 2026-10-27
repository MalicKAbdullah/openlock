import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeEnforcementBridge bridge;
  late FakeSecureStorage storage;
  late ProviderContainer container;

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(bridge),
          secureStorageProvider.overrideWithValue(storage),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
          clockProvider.overrideWithValue(FakeClock(DateTime(2026, 7, 9))),
          biometricAuthProvider
              .overrideWithValue(FakeBiometricAuth(available: false)),
        ],
      );

  setUp(() async {
    bridge = FakeEnforcementBridge();
    storage = FakeSecureStorage();
    container = makeContainer();
    // A PIN must exist before config pushes reach native.
    await container.read(pinAuthServiceProvider).setupPin('135790');
    await container.read(configControllerProvider.future);
  });

  tearDown(() => container.dispose());

  ConfigController controller() =>
      container.read(configControllerProvider.notifier);

  test('setHideNotifications persists and pushes the flag to native', () async {
    await controller().setHideNotifications(true);

    expect(
      container.read(configControllerProvider).valueOrNull!.hideNotifications,
      isTrue,
    );
    expect(bridge.lastPushedConfig!['hideNotifications'], true);
  });

  test('setNotificationOverride stores and clears per-app overrides', () async {
    await controller().toggleApp('com.social');
    await controller().setNotificationOverride('com.social', true);

    var config = container.read(configControllerProvider).valueOrNull!;
    expect(config.notificationOverrides, {'com.social': true});
    expect(config.hidesNotificationsFor('com.social'), isTrue);
    expect(bridge.lastPushedConfig!['notificationOverrides'],
        {'com.social': true});

    // Passing null removes the override so the app follows the global default.
    await controller().setNotificationOverride('com.social', null);
    config = container.read(configControllerProvider).valueOrNull!;
    expect(config.notificationOverrides, isEmpty);
    expect(config.hidesNotificationsFor('com.social'), isFalse);
  });

  test('a per-app override opts an app in while the global flag is off',
      () async {
    await controller().toggleApp('com.social');
    await controller().toggleApp('com.game');
    await controller().setNotificationOverride('com.game', true);

    final config = container.read(configControllerProvider).valueOrNull!;
    expect(config.hideNotifications, isFalse);
    expect(config.hidesNotificationsFor('com.game'), isTrue);
    expect(config.hidesNotificationsFor('com.social'), isFalse);
  });
}
