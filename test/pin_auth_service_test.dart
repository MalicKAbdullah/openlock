import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/auth/services/pin_hasher.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late FakeClock clock;
  late PinAuthService service;

  setUp(() {
    storage = FakeSecureStorage();
    clock = FakeClock(DateTime(2026, 7, 8, 12));
    service = PinAuthService(
      storage: storage,
      hasher: const PinHasher(),
      keyDerivation: const FakeKeyDerivation(),
      clock: clock,
    );
  });

  test('setup then correct PIN unlocks', () async {
    await service.setupPin('123456');
    expect(await service.hasPin(), isTrue);
    expect(await service.unlock('123456'), isA<UnlockSuccess>());
  });

  test('wrong PIN reports increasing attempt counts', () async {
    await service.setupPin('123456');
    final r1 = await service.unlock('000000');
    final r2 = await service.unlock('111111');
    expect((r1 as UnlockWrongPin).failedAttempts, 1);
    expect((r2 as UnlockWrongPin).failedAttempts, 2);
    expect(r2.cooldown, isNull);
  });

  test('verifier exposes stored hash + salt for the native push', () async {
    await service.setupPin('123456');
    final v = await service.verifier();
    expect(v, isNotNull);
    expect(v!.hash, isNotEmpty);
    expect(v.salt, isNotEmpty);
  });

  test('fifth failure triggers a cooldown and blocks further attempts',
      () async {
    await service.setupPin('123456');
    for (var i = 0; i < 4; i++) {
      await service.unlock('000000');
    }
    final fifth = await service.unlock('000000');
    expect(fifth, isA<UnlockWrongPin>());
    expect((fifth as UnlockWrongPin).cooldown, isNotNull);

    // Even the correct PIN is refused while cooling down.
    final duringCooldown = await service.unlock('123456');
    expect(duringCooldown, isA<UnlockCoolingDown>());
  });

  test('cooldown clears after the clock advances past it', () async {
    await service.setupPin('123456');
    for (var i = 0; i < 5; i++) {
      await service.unlock('000000');
    }
    expect(await service.cooldownRemaining(), greaterThan(Duration.zero));

    clock.advance(const Duration(minutes: 20));
    expect(await service.cooldownRemaining(), Duration.zero);
    expect(await service.unlock('123456'), isA<UnlockSuccess>());
  });

  test('successful unlock resets the attempt counter', () async {
    await service.setupPin('123456');
    await service.unlock('000000');
    await service.unlock('123456'); // success resets
    final next = await service.unlock('000000');
    expect((next as UnlockWrongPin).failedAttempts, 1);
  });

  test('changePin requires the old PIN and then accepts the new one', () async {
    await service.setupPin('123456');
    final bad = await service.changePin(oldPin: '999999', newPin: '654321');
    expect(bad, isA<UnlockWrongPin>());

    final ok = await service.changePin(oldPin: '123456', newPin: '654321');
    expect(ok, isA<UnlockSuccess>());
    expect(await service.unlock('654321'), isA<UnlockSuccess>());
    expect(await service.unlock('123456'), isA<UnlockWrongPin>());
  });

  group('cooldownFor', () {
    test('no cooldown before the fifth failure', () {
      expect(PinAuthService.cooldownFor(4), Duration.zero);
    });

    test('30s at the fifth failure, doubling after', () {
      expect(PinAuthService.cooldownFor(5), const Duration(seconds: 30));
      expect(PinAuthService.cooldownFor(6), const Duration(seconds: 60));
      expect(PinAuthService.cooldownFor(7), const Duration(seconds: 120));
    });

    test('caps at 15 minutes', () {
      expect(PinAuthService.cooldownFor(20), const Duration(minutes: 15));
    });
  });
}
