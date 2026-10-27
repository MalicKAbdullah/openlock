import 'dart:io';
import 'dart:ui' as ui;

import 'package:core_theme/core_theme.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/storage_keys.dart';
import 'package:openlock/src/features/apps/screens/app_picker_screen.dart';
import 'package:openlock/src/features/auth/screens/setup_pin_screen.dart';
import 'package:openlock/src/features/auth/screens/unlock_screen.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/intruder/screens/intruder_log_screen.dart';
import 'package:openlock/src/features/onboarding/screens/onboarding_screen.dart';
import 'package:openlock/src/features/onboarding/screens/permissions_screen.dart';
import 'package:openlock/src/features/schedules/models/lock_schedule.dart';
import 'package:openlock/src/features/schedules/screens/schedule_editor_screen.dart';
import 'package:openlock/src/features/schedules/screens/schedules_screen.dart';
import 'package:openlock/src/features/settings/screens/about_screen.dart';
import 'package:openlock/src/features/settings/screens/relock_settings_screen.dart';
import 'package:openlock/src/features/settings/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

/// Writes light and dark PNGs of each main screen and each lock state into
/// `$GALLERY` when it is set (with `CORE_FONTS` pointing at core_theme/fonts).
/// The mode comes from the saved appearance choice, as in the app. Used for
/// design review only; it asserts nothing.
final String? _gallery = Platform.environment['GALLERY'];

/// A 96px launcher-style icon (colored squircle with a white disc), matching
/// the PNGs the native side sends, so previews show what real icons look like.
Future<Uint8List> _fakeIcon(Color color) async {
  const size = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas
    ..drawRRect(
      RRect.fromRectXY(const Rect.fromLTWH(0, 0, size, size), 22, 22),
      Paint()..color = color,
    )
    ..drawCircle(
      const Offset(size / 2, size / 2),
      22,
      Paint()..color = const Color(0xE6FFFFFF),
    );
  final image = await recorder.endRecording().toImage(96, 96);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  final fonts = Platform.environment['CORE_FONTS']!;
  await family(AppTextStyles.fontFamily, [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      '$fonts/MonaSans-$w.ttf',
  ]);
  await family(AppTextStyles.displayFamily, [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      '$fonts/MonaSansDisplay-$w.ttf',
  ]);
  await family(AppTextStyles.monoFamily, [
    for (final w in ['Regular', 'Medium', 'SemiBold'])
      '$fonts/MonaSansMono-$w.ttf',
  ]);
  final root = Platform.environment['FLUTTER_ROOT'] ??
      '/Users/abdullah/development/flutter';
  await family('MaterialIcons', [
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

class _NoUpdates implements IUpdateService {
  @override
  Future<UpdateInfo?> check() async => null;
  @override
  Future<bool> openDownload(UpdateInfo info) async => true;
}

void main() {
  testWidgets('renders previews', (tester) async {
    if (_gallery == null) return;
    await tester.runAsync(_loadFonts);

    final icons = await tester.runAsync(() async => {
          'com.instagram.android': await _fakeIcon(const Color(0xFFD62976)),
          'com.whatsapp': await _fakeIcon(const Color(0xFF25D366)),
          'com.google.android.gm': await _fakeIcon(const Color(0xFFEA4335)),
          'com.netflix.mediaclient': await _fakeIcon(const Color(0xFF141414)),
          'org.telegram.messenger': await _fakeIcon(const Color(0xFF2AABEE)),
          'com.spotify.music': await _fakeIcon(const Color(0xFF1DB954)),
          'com.android.chrome': await _fakeIcon(const Color(0xFF4285F4)),
        });
    InstalledApp app(String pkg, String label) =>
        InstalledApp(packageName: pkg, label: label, icon: icons![pkg]);

    final bridge = FakeEnforcementBridge(
      apps: [
        app('com.instagram.android', 'Instagram'),
        app('com.whatsapp', 'WhatsApp'),
        app('com.google.android.gm', 'Gmail'),
        app('com.netflix.mediaclient', 'Netflix'),
        app('org.telegram.messenger', 'Telegram'),
        app('com.spotify.music', 'Spotify'),
        app('com.android.chrome', 'Chrome'),
      ],
      permissions: const PermissionStates(
        usageAccess: true,
        overlay: false,
        notifications: true,
        batteryExempt: false,
        serviceRunning: false,
      ),
    )..records.addAll([
        IntruderRecord(
          id: '1',
          packageName: 'com.whatsapp',
          timestamp: DateTime(2026, 10, 19, 22, 41),
        ),
        IntruderRecord(
          id: '2',
          packageName: 'com.instagram.android',
          timestamp: DateTime(2026, 10, 18, 8, 5),
        ),
      ]);

    Future<ProviderContainer> container(
      IEnforcementBridge b, {
      bool seed = true,
    }) async {
      final c = ProviderContainer(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(b),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
          biometricAuthProvider.overrideWithValue(FakeBiometricAuth()),
          updateServiceProvider.overrideWithValue(_NoUpdates()),
          keyDerivationProvider.overrideWithValue(const FakeKeyDerivation()),
        ],
      );
      await c.read(configControllerProvider.future);
      if (seed) {
        final ctl = c.read(configControllerProvider.notifier);
        await ctl.toggleApp('com.instagram.android');
        await ctl.toggleApp('com.whatsapp');
        await ctl.toggleApp('com.netflix.mediaclient');
        await ctl.setLockNewApps(true);
        await ctl.upsertSchedule(
          LockSchedule(
            name: 'Work hours',
            packages: {'com.instagram.android', 'com.whatsapp'},
            weekdays: {1, 2, 3, 4, 5},
            startMinutes: 9 * 60,
            endMinutes: 17 * 60,
          ),
        );
        await ctl.upsertSchedule(
          LockSchedule(
            name: 'Wind down',
            packages: {'com.netflix.mediaclient'},
            weekdays: {1, 2, 3, 4, 5, 6, 7},
            startMinutes: 22 * 60,
            endMinutes: 6 * 60,
            enabled: false,
          ),
        );
      }
      return c;
    }

    /// A lock-screen container: a PIN and a recovery key set up, a failing
    /// fingerprint prompt (so the screen stays put), and [storage] seeded by
    /// [prepare].
    Future<ProviderContainer> lock({
      bool biometric = false,
      bool cooldown = false,
    }) async {
      final storage = FakeSecureStorage();
      final c = ProviderContainer(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(FakeEnforcementBridge()),
          secureStorageProvider.overrideWithValue(storage),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
          biometricAuthProvider
              .overrideWithValue(FakeBiometricAuth(willSucceed: false)),
          keyDerivationProvider.overrideWithValue(const FakeKeyDerivation()),
        ],
      );
      final auth = c.read(pinAuthServiceProvider);
      await auth.setupPin('123456');
      await auth.createRecoveryKey();
      if (biometric) {
        await storage.write(key: OpenLockKeys.biometricEnabled, value: 'true');
      }
      if (cooldown) {
        await storage.write(
          key: OpenLockKeys.lockoutUntil,
          value: DateTime.now()
              .add(const Duration(seconds: 28, milliseconds: 500))
              .millisecondsSinceEpoch
              .toString(),
        );
      }
      return c;
    }

    final seeded = await tester.runAsync(() => container(bridge));
    final empty = await tester.runAsync(
      () => container(FakeEnforcementBridge(), seed: false),
    );

    final lockBio = await tester.runAsync(() => lock(biometric: true));
    final lockPin = await tester.runAsync(lock);
    final lockCool = await tester.runAsync(() => lock(cooldown: true));

    Future<void> enterWrongPin() async {
      for (final d in '000000'.split('')) {
        await tester.tap(find.text(d).last);
      }
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> openRecovery() async {
      await tester.tap(find.text('Forgot PIN?'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    // name, screen, container, logical size, light/dark, then-action.
    final locks = <(
      String,
      ProviderContainer,
      Size,
      List<Brightness>,
      Future<void> Function()?,
    )>[
      ('lock-biometric', lockBio!, _phone, Brightness.values, null),
      ('lock-pin', lockPin!, _phone, Brightness.values, null),
      ('lock-error', lockPin, _phone, Brightness.values, enterWrongPin),
      ('lock-cooldown', lockCool!, _phone, Brightness.values, null),
      ('lock-recovery', lockBio, _phone, Brightness.values, openRecovery),
      (
        'lock-small-360x640',
        lockBio,
        const Size(360, 640),
        [Brightness.light],
        null,
      ),
    ];

    for (final (name, c, size, modes, action) in locks) {
      for (final b in modes) {
        await _shoot(
          tester,
          name: name,
          size: size,
          mode: b,
          container: c,
          screen: const UnlockScreen(),
          then: action,
        );
        // Unmount so each state starts from a fresh UnlockScreen.
        await tester.pumpWidget(const SizedBox());
      }
    }

    final boards = <(String, Widget, ProviderContainer, double)>[
      ('apps', const AppPickerScreen(), seeded!, 1100),
      ('schedules', const SchedulesScreen(), seeded, 700),
      ('schedules-empty', const SchedulesScreen(), empty!, 700),
      ('intruders', const IntruderLogScreen(), seeded, 700),
      ('intruders-empty', const IntruderLogScreen(), empty, 700),
      ('settings', const SettingsScreen(), seeded, 1500),
      ('onboarding', const OnboardingScreen(), seeded, 800),
      ('setup-pin', const SetupPinScreen(), seeded, 700),
      ('permissions', const PermissionsScreen(), seeded, 800),
      ('editor', const ScheduleEditorScreen(scheduleId: null), seeded, 1300),
      ('relock', const RelockSettingsScreen(), seeded, 600),
      ('about', const AboutScreen(), seeded, 700),
    ];

    for (final (name, screen, c, height) in boards) {
      for (final b in Brightness.values) {
        await _shoot(
          tester,
          name: name,
          size: Size(390, height),
          mode: b,
          container: c,
          screen: screen,
        );
      }
    }
  });
}

const _phone = Size(390, 844);

/// Renders [screen] at [size] @2x with the theme picked by a saved
/// appearance choice of [mode], runs [then], and writes `<name>-<mode>.png`.
Future<void> _shoot(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Brightness mode,
  required ProviderContainer container,
  required Widget screen,
  Future<void> Function()? then,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    AppearanceController.storageKey: mode.name,
  });
  final appearance = (await tester.runAsync(AppearanceController.load))!;
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: UncontrolledProviderScope(
        container: container,
        child: ProviderScope(
          overrides: [appearanceProvider.overrideWithValue(appearance)],
          child: ListenableBuilder(
            listenable: appearance,
            builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(
                Brightness.light,
                accent: AppAccents.openlock,
              ),
              darkTheme: AppTheme.build(
                Brightness.dark,
                accent: AppAccents.openlock,
              ),
              themeMode: appearance.mode,
              home: screen,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  if (then != null) {
    await then();
    // A second frame lets animations started by the action settle.
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_gallery!).createSync(recursive: true);
    File('$_gallery/$name-${mode.name}.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}
