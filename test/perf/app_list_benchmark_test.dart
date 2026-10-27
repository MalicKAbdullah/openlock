// Benchmarks for the app list on the UI isolate, 200 installed apps.
// Run: flutter test test/perf/app_list_benchmark_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/features/apps/providers/apps_providers.dart';
import 'package:openlock/src/features/apps/screens/app_picker_screen.dart';
import 'package:openlock/src/features/apps/services/app_list_filter.dart';

import '../helpers/fakes.dart';

const _appCount = 200;
const _codec = StandardMethodCodec();

/// Package/label pairs shaped like a real phone's launcher apps.
List<(String, String)> _apps(Random random) {
  const words = [
    'mail',
    'chat',
    'maps',
    'music',
    'photos',
    'bank',
    'notes',
    'camera',
    'news',
    'weather',
    'video',
    'shop',
    'fit',
    'drive',
    'calendar',
    'games',
  ];
  return [
    for (var i = 0; i < _appCount; i++)
      (
        'com.${words[random.nextInt(words.length)]}$i.android',
        '${random.nextBool() ? 'My' : 'the'} '
            '${words[random.nextInt(words.length)]} ${i * 7919 % 1000}',
      ),
  ];
}

/// Incompressible bytes the size of a 96px launcher-icon PNG (6–10 KB).
Uint8List _pngSizedBytes(Random random) =>
    Uint8List.fromList(List.generate(6000 + random.nextInt(4000), (_) {
      return random.nextInt(256);
    }));

/// The reply the old native `getInstalledApps` sent: every icon inline as
/// base64, as one channel envelope.
ByteData _oldReply(List<(String, String)> apps, Random random) =>
    _codec.encodeSuccessEnvelope([
      for (final (pkg, label) in apps)
        {
          'packageName': pkg,
          'label': label,
          'icon': base64Encode(_pngSizedBytes(random)),
        },
    ]);

ByteData _newReply(List<(String, String)> apps) =>
    _codec.encodeSuccessEnvelope([
      for (final (pkg, label) in apps)
        {'packageName': pkg, 'label': label, 'versionCode': 1000 + pkg.length},
    ]);

/// The old Dart side: decode the envelope, then base64-decode every icon.
List<(String, String, Uint8List?)> _decodeOld(ByteData reply) {
  final raw = (_codec.decodeEnvelope(reply) as List).cast<Map>();
  return [
    for (final m in raw)
      (
        m['packageName'] as String,
        m['label'] as String,
        base64Decode(m['icon'] as String),
      ),
  ];
}

List<InstalledApp> _decodeNew(ByteData reply) {
  final raw = (_codec.decodeEnvelope(reply) as List).cast<Map>();
  return [
    for (final m in raw)
      InstalledApp(
        packageName: m['packageName'] as String,
        label: m['label'] as String,
        versionCode: m['versionCode'] as int,
      ),
  ];
}

/// The filter as it was: lower-cases both labels inside every comparison.
List<InstalledApp> _naiveFilter(
  List<InstalledApp> apps,
  Set<String> locked,
  String query,
) {
  final q = query.trim().toLowerCase();
  final filtered = q.isEmpty
      ? List<InstalledApp>.of(apps)
      : apps
          .where((a) =>
              a.label.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q))
          .toList();
  filtered.sort((a, b) {
    final aLocked = locked.contains(a.packageName);
    final bLocked = locked.contains(b.packageName);
    if (aLocked != bLocked) return aLocked ? -1 : 1;
    final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    if (byLabel != 0) return byLabel;
    return a.packageName.compareTo(b.packageName);
  });
  return filtered;
}

/// Mean microseconds per run of [body] after a warm-up.
double _time(void Function() body, {int runs = 50}) {
  for (var i = 0; i < 5; i++) {
    body();
  }
  final watch = Stopwatch()..start();
  for (var i = 0; i < runs; i++) {
    body();
  }
  return watch.elapsedMicroseconds / runs;
}

String _ms(double micros) => '${(micros / 1000).toStringAsFixed(2)} ms';

void main() {
  final random = Random(7);
  final pairs = _apps(random);

  test('installed apps reply: base64 icons vs metadata only', () {
    final oldReply = _oldReply(pairs, random);
    final newReply = _newReply(pairs);
    final oldMicros = _time(() => _decodeOld(oldReply), runs: 20);
    final newMicros = _time(() => _decodeNew(newReply));
    // ignore: avoid_print
    print('installed apps ($_appCount): reply '
        '${(oldReply.lengthInBytes / 1024).round()} KiB → '
        '${(newReply.lengthInBytes / 1024).round()} KiB; UI-isolate decode '
        '${_ms(oldMicros)} → ${_ms(newMicros)}');
    expect(newMicros, lessThanOrEqualTo(oldMicros));
  });

  test('filter: matches the naive version and is no slower', () async {
    final apps = _decodeNew(_newReply(pairs));
    final locked = {
      for (final (pkg, _) in pairs)
        if (random.nextInt(5) == 0) pkg,
    };
    for (final query in ['', 'MAIL', 'my ', 'android', '1', 'zzz']) {
      expect(
        AppListFilter.apply(apps: apps, lockedPackages: locked, query: query),
        _naiveFilter(apps, locked, query),
        reason: 'query "$query"',
      );
    }
    final oldMicros = _time(() => _naiveFilter(apps, locked, ''), runs: 200);
    final newMicros = _time(
      () => AppListFilter.apply(apps: apps, lockedPackages: locked),
      runs: 200,
    );

    final container = ProviderContainer(
      overrides: [
        enforcementBridgeProvider.overrideWithValue(
          FakeEnforcementBridge(apps: apps),
        ),
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(installedAppsProvider.future);
    final first = container.read(appListProvider);
    final memoMicros = _time(() => container.read(appListProvider), runs: 200);
    expect(identical(container.read(appListProvider), first), isTrue);
    // ignore: avoid_print
    print('filter + sort ($_appCount): per-comparison lower-casing '
        '${_ms(oldMicros)} → precomputed keys ${_ms(newMicros)}; '
        'memoized re-read ${_ms(memoMicros)}');
    expect(newMicros, lessThanOrEqualTo(oldMicros * 1.2));
  });

  testWidgets('home first frame with 200 apps', (tester) async {
    final apps = _decodeNew(_newReply(pairs));
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    Future<int> firstFrameMicros(FakeEnforcementBridge bridge) async {
      final container = ProviderContainer(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(bridge),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
        ],
      );
      addTearDown(container.dispose);
      // Data loaded while the unlock prompt was up.
      await tester.runAsync(() async {
        if (bridge.holdApps == null) {
          await container.read(installedAppsProvider.future);
        }
      });
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme:
                AppTheme.build(Brightness.light, accent: AppAccents.openlock),
            home: const AppPickerScreen(),
          ),
        ),
      );
      final micros = watch.elapsedMicroseconds;
      await tester.pumpWidget(const SizedBox());
      return micros;
    }

    // Warm up the widget code paths.
    await firstFrameMicros(FakeEnforcementBridge(apps: apps));
    final ready = await firstFrameMicros(FakeEnforcementBridge(apps: apps));
    final pending = await firstFrameMicros(
      FakeEnforcementBridge(apps: apps)..holdApps = Completer<void>(),
    );
    // ignore: avoid_print
    print('home first frame ($_appCount apps, 1080x2400 @3x): '
        'apps ready ${_ms(ready.toDouble())}, '
        'apps still loading ${_ms(pending.toDouble())}');
    expect(ready, greaterThan(0));
  });
}
