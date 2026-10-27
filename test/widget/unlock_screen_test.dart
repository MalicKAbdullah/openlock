import 'package:core_lock/core_lock.dart' show LockBiometricButton;
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/storage_keys.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/screens/unlock_screen.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late FakeClock clock;
  late FakeConfigFileStore configFiles;

  setUp(() {
    storage = FakeSecureStorage();
    configFiles = FakeConfigFileStore();
    clock = FakeClock(DateTime(2026, 10, 27, 9));
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool biometric = false,
    bool randomizeKeypad = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    if (biometric) {
      await storage.write(key: OpenLockKeys.biometricEnabled, value: 'true');
    }
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        clockProvider.overrideWithValue(clock),
        biometricAuthProvider
            .overrideWithValue(FakeBiometricAuth(willSucceed: false)),
        keyDerivationProvider.overrideWithValue(const FakeKeyDerivation()),
        enforcementBridgeProvider.overrideWithValue(FakeEnforcementBridge()),
        configFileStoreProvider.overrideWithValue(configFiles),
      ],
    );
    addTearDown(container.dispose);
    if (randomizeKeypad) {
      await container
          .read(configRepositoryProvider)
          .save(const LockConfig(randomizeKeypad: true));
    }
    // As in main: the unlock flags are read before the first frame.
    await container.read(sessionProvider.notifier).resolved;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, accent: AppAccents.openlock),
          home: const UnlockScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The digit keys' labels in reading order (row by row, left to right).
  List<String> keypadOrder(WidgetTester tester) {
    final digits = [for (var i = 0; i < 10; i++) '$i'];
    final centers = {
      for (final d in digits) d: tester.getCenter(find.text(d)),
    };
    return digits
      ..sort((a, b) {
        final dy = centers[a]!.dy.compareTo(centers[b]!.dy);
        return dy != 0 ? dy : centers[a]!.dx.compareTo(centers[b]!.dx);
      });
  }

  const phoneOrder = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

  /// Unmounts the screen so its cooldown ticker is cancelled.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('the keypad fits a 360 x 640 phone with fingerprint on',
      (tester) async {
    await pump(tester, size: const Size(360, 640), biometric: true);

    expect(find.byType(LockBiometricButton), findsOneWidget);
    expect(find.text('Use fingerprint'), findsNothing);
    expect(find.text('Forgot PIN?'), findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0);
    final key = tester.getSize(
      find.ancestor(of: find.text('5'), matching: find.byType(InkWell)),
    );
    expect(key.height, inInclusiveRange(52, UnlockScreen.maxKeyHeight));
  });

  testWidgets('without fingerprint there is no fingerprint button',
      (tester) async {
    await pump(tester);
    expect(find.byType(LockBiometricButton), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
  });

  testWidgets('a cooldown counts down under the dots and disables the keys',
      (tester) async {
    await storage.write(
      key: OpenLockKeys.lockoutUntil,
      value: clock
          .now()
          .add(const Duration(seconds: 28))
          .millisecondsSinceEpoch
          .toString(),
    );
    await pump(tester);

    expect(find.text('Too many attempts. Try again in 0:28.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Too many attempts. Try again in 0:27.'), findsOneWidget);
    final five = tester.widget<InkWell>(
      find.ancestor(of: find.text('5'), matching: find.byType(InkWell)),
    );
    expect(five.onTap, isNull);
    await unmount(tester);
  });

  testWidgets('Forgot PIN? opens the reset form', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset your PIN'), findsOneWidget);
    expect(find.text('Back to unlock'), findsOneWidget);
    await tester.tap(find.text('Back to unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot PIN?'), findsOneWidget);
  });

  testWidgets('the keypad keeps phone order when Randomize keypad is off',
      (tester) async {
    await pump(tester);
    expect(keypadOrder(tester), phoneOrder);
  });

  testWidgets('Randomize keypad shuffles the digits on every show',
      (tester) async {
    await pump(tester, randomizeKeypad: true);
    final first = keypadOrder(tester);
    await unmount(tester);
    await pump(tester, randomizeKeypad: true);
    final second = keypadOrder(tester);

    // Each order is a permutation of all ten digits; two secure shuffles
    // (or a shuffle and phone order) coincide with probability 1/10!.
    expect(first.toSet(), phoneOrder.toSet());
    expect(second.toSet(), phoneOrder.toSet());
    expect(first, isNot(phoneOrder));
    expect(first, isNot(second));
  });
}
