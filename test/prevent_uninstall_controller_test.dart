import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/settings/providers/settings_providers.dart';

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

  setUp(() {
    bridge = FakeEnforcementBridge();
    storage = FakeSecureStorage();
    container = makeContainer();
  });

  tearDown(() => container.dispose());

  test('build reflects the live device-admin state', () async {
    bridge.deviceAdminActive = true;
    final active =
        await container.read(preventUninstallControllerProvider.future);
    expect(active, isTrue);
  });

  test('requestEnable requests device admin and marks the config flag',
      () async {
    await container.read(configControllerProvider.future);
    await container.read(preventUninstallControllerProvider.future);

    await container
        .read(preventUninstallControllerProvider.notifier)
        .requestEnable();

    expect(bridge.deviceAdminRequested, isTrue);
    expect(
      container.read(configControllerProvider).valueOrNull!.preventUninstall,
      isTrue,
    );
  });

  test('disableWithAuth does NOT deactivate when auth fails', () async {
    bridge.deviceAdminActive = true;
    await container.read(configControllerProvider.future);
    await container.read(preventUninstallControllerProvider.future);

    final lifted = await container
        .read(preventUninstallControllerProvider.notifier)
        .disableWithAuth(() async => false);

    expect(lifted, isFalse);
    expect(bridge.deviceAdminDeactivated, isFalse);
    expect(bridge.deviceAdminActive, isTrue);
  });

  test('disableWithAuth deactivates and clears the flag when auth succeeds',
      () async {
    bridge.deviceAdminActive = true;
    await container.read(configControllerProvider.future);
    await container
        .read(configControllerProvider.notifier)
        .setPreventUninstall(true);
    await container.read(preventUninstallControllerProvider.future);

    final lifted = await container
        .read(preventUninstallControllerProvider.notifier)
        .disableWithAuth(() async => true);

    expect(lifted, isTrue);
    expect(bridge.deviceAdminDeactivated, isTrue);
    expect(container.read(preventUninstallControllerProvider).valueOrNull,
        isFalse);
    expect(
      container.read(configControllerProvider).valueOrNull!.preventUninstall,
      isFalse,
    );
  });

  test('preventUninstall flag is pushed to native once a PIN exists', () async {
    await container.read(pinAuthServiceProvider).setupPin('135790');
    await container.read(configControllerProvider.future);

    await container
        .read(configControllerProvider.notifier)
        .setPreventUninstall(true);

    expect(bridge.lastPushedConfig, isNotNull);
    expect(bridge.lastPushedConfig!['preventUninstall'], true);
  });
}
