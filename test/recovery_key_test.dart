import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/storage_keys.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/auth/services/pin_hasher.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late FakeClock clock;
  late PinAuthService service;

  setUp(() {
    storage = FakeSecureStorage();
    clock = FakeClock(DateTime(2026, 10, 20, 12));
    service = PinAuthService(
      storage: storage,
      hasher: const PinHasher(),
      keyDerivation: const FakeKeyDerivation(),
      clock: clock,
    );
  });

  group('PinAuthService recovery key', () {
    test('resets a forgotten PIN; the old PIN stops working', () async {
      await service.setupPin('123456');
      final key = await service.createRecoveryKey();

      final result = await service.resetWithRecoveryKey(
        recoveryKey: key.toLowerCase().replaceAll('-', ' '),
        newPin: '654321',
      );
      expect(result, isA<UnlockSuccess>());
      expect(await service.verifyPin('654321'), isTrue);
      expect(await service.verifyPin('123456'), isFalse);
    });

    test('stores only a verifier, never the key', () async {
      await service.setupPin('123456');
      final key = await service.createRecoveryKey();
      final canonical = RecoveryKey.normalize(key)!;
      for (final value in (await storage.readAll()).values) {
        expect(value, isNot(contains(key)));
        expect(value, isNot(contains(canonical)));
      }
    });

    test('a wrong key is rejected and counts toward the PIN cooldown',
        () async {
      await service.setupPin('123456');
      await service.createRecoveryKey();
      for (var i = 0; i < 4; i++) {
        final r = await service.resetWithRecoveryKey(
          recoveryKey: RecoveryKey.generate(),
          newPin: '654321',
        );
        expect(r, isA<UnlockWrongPin>());
      }
      final fifth = await service.resetWithRecoveryKey(
        recoveryKey: 'not a key',
        newPin: '654321',
      );
      expect((fifth as UnlockWrongPin).cooldown, isNotNull);
      expect(await service.unlock('123456'), isA<UnlockCoolingDown>());
      expect(await service.verifyPin('123456'), isTrue);
    });

    test('regenerating invalidates the previous key', () async {
      await service.setupPin('123456');
      final first = await service.createRecoveryKey();
      final second = await service.createRecoveryKey();
      expect(
        await service.resetWithRecoveryKey(
            recoveryKey: first, newPin: '111111'),
        isA<UnlockWrongPin>(),
      );
      expect(
        await service.resetWithRecoveryKey(
          recoveryKey: second,
          newPin: '111111',
        ),
        isA<UnlockSuccess>(),
      );
    });

    test('no recovery key means no reset', () async {
      await service.setupPin('123456');
      expect(
        await service.resetWithRecoveryKey(
          recoveryKey: RecoveryKey.generate(),
          newPin: '111111',
        ),
        isA<UnlockWrongPin>(),
      );
    });

    test('the one-time offer is due until marked, and never with a key',
        () async {
      await service.setupPin('123456');
      expect(await service.recoveryOfferDue(), isTrue);
      await service.markRecoveryOffered();
      expect(await service.recoveryOfferDue(), isFalse);

      await storage.delete(key: OpenLockKeys.recoveryOffered);
      await service.createRecoveryKey();
      expect(await service.recoveryOfferDue(), isFalse);
    });

    test('eraseAll removes the recovery verifier', () async {
      await service.setupPin('123456');
      await service.createRecoveryKey();
      await service.eraseAll();
      expect(await service.hasRecoveryKey(), isFalse);
    });
  });

  group('SessionNotifier', () {
    late FakeBiometricAuth biometric;
    late FakeEnforcementBridge bridge;
    late ProviderContainer container;

    setUp(() async {
      biometric = FakeBiometricAuth();
      bridge = FakeEnforcementBridge();
      container = ProviderContainer(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(bridge),
          secureStorageProvider.overrideWithValue(storage),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
          clockProvider.overrideWithValue(clock),
          biometricAuthProvider.overrideWithValue(biometric),
          keyDerivationProvider.overrideWithValue(const FakeKeyDerivation()),
        ],
      );
      await storage.write(key: OpenLockKeys.biometricEnabled, value: 'true');
      await container.read(pinAuthServiceProvider).setupPin('123456');
      await container.read(configControllerProvider.future);
    });

    tearDown(() => container.dispose());

    SessionNotifier session() => container.read(sessionProvider.notifier);

    test('a fingerprint session changes the PIN after a fresh fingerprint',
        () async {
      await session().markUnlocked(UnlockMethod.biometric, then: '/apps');
      expect(session().canChangePinWithBiometric, isTrue);

      biometric.willSucceed = false;
      expect(
        await session().changePin(oldPin: null, newPin: '222222'),
        isA<UnlockWrongPin>(),
      );
      biometric.willSucceed = true;
      expect(
        await session().changePin(oldPin: null, newPin: '222222'),
        isA<UnlockSuccess>(),
      );
      final auth = container.read(pinAuthServiceProvider);
      expect(await auth.verifyPin('222222'), isTrue);
      expect(bridge.lastPushedConfig, isNotNull);
    });

    test('a PIN session must give the current PIN', () async {
      await session().markUnlocked(UnlockMethod.pin, then: '/apps');
      expect(session().canChangePinWithBiometric, isFalse);
      expect(
        await session().changePin(oldPin: null, newPin: '222222'),
        isA<UnlockWrongPin>(),
      );
      expect(
        await session().changePin(oldPin: '000000', newPin: '222222'),
        isA<UnlockWrongPin>(),
      );
      expect(
        await session().changePin(oldPin: '123456', newPin: '222222'),
        isA<UnlockSuccess>(),
      );
    });

    test('recover unlocks, pushes the new verifier, and offers nothing',
        () async {
      final auth = container.read(pinAuthServiceProvider);
      final key = await auth.createRecoveryKey();
      final result = await session().recover(
        recoveryKey: key,
        newPin: '333333',
        then: '/apps',
      );
      expect(result, isA<UnlockSuccess>());
      expect(container.read(sessionProvider), AuthStatus.unlocked);
      expect(session().unlockedWith, UnlockMethod.recoveryKey);
      expect(bridge.lastPushedConfig, isNotNull);
      expect(container.read(recoveryOfferProvider), isNull);
    });

    test('an unlock without a key queues the one-time offer', () async {
      await session().markUnlocked(UnlockMethod.pin, then: '/apps');
      final offer = container.read(recoveryOfferProvider);
      expect(offer, isNotNull);
      expect(offer!.key, isNull);
    });
  });
}
