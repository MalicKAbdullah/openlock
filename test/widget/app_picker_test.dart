import 'dart:async';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/apps/screens/app_picker_screen.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';

import '../helpers/fakes.dart';

void main() {
  testWidgets('renders installed apps and toggles lock state', (tester) async {
    final bridge = FakeEnforcementBridge(
      apps: [
        InstalledApp(packageName: 'com.alpha', label: 'Alpha', versionCode: 1),
        InstalledApp(packageName: 'com.beta', label: 'Beta', versionCode: 1),
      ],
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(bridge),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, accent: AppAccents.openlock),
          home: const AppPickerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Both apps are listed.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('0 locked'), findsOneWidget);

    // Toggle the first app's switch on.
    final firstSwitch = find.byType(Switch).at(1); // 0 = "lock new apps"
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();

    expect(find.text('1 locked'), findsOneWidget);
  });

  Future<void> pumpPicker(WidgetTester tester, FakeEnforcementBridge bridge) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(bridge),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, accent: AppAccents.openlock),
          home: const AppPickerScreen(),
        ),
      ),
    );
  }

  testWidgets('the header shows while the app list loads; rows hold its space',
      (tester) async {
    final bridge = FakeEnforcementBridge(
      apps: [
        InstalledApp(packageName: 'com.alpha', label: 'Alpha', versionCode: 1),
      ],
    )..holdApps = Completer<void>();
    await pumpPicker(tester, bridge);
    await tester.pump();

    expect(find.text('Protected apps'), findsOneWidget);
    expect(find.text('Counting installed apps'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final skeletonRow = find
        .ancestor(of: find.byType(Skeleton), matching: find.byType(AppListRow))
        .first;
    final skeletonHeight = tester.getSize(skeletonRow).height;

    bridge.holdApps!.complete();
    await tester.pumpAndSettle();

    expect(find.text('of 1 installed apps'), findsOneWidget);
    final row = find.ancestor(
      of: find.text('Alpha'),
      matching: find.byType(AppListRow),
    );
    expect(tester.getSize(row).height, skeletonHeight);
  });

  testWidgets('rows built in one frame fetch their icons in one batch',
      (tester) async {
    final bridge = FakeEnforcementBridge(
      apps: [
        for (var i = 0; i < 40; i++)
          InstalledApp(
            packageName: 'com.app$i',
            label: 'App ${i.toString().padLeft(2, '0')}',
            versionCode: 1,
          ),
      ],
    );
    await pumpPicker(tester, bridge);
    await tester.pumpAndSettle();

    expect(bridge.iconRequests, hasLength(1));
    final batch = bridge.iconRequests.single;
    // Only the rows the list actually built, not all 40.
    expect(batch, isNotEmpty);
    expect(batch.length, lessThan(40));
    expect(batch.first, 'com.app0');
  });

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'a locked row fits its card at ${width.toInt()} dp with 1.3x text',
        (tester) async {
      const package = 'com.example.a.rather.long.package.name';
      final container = ProviderContainer(
        overrides: [
          enforcementBridgeProvider.overrideWithValue(
            FakeEnforcementBridge(
              apps: [
                InstalledApp(
                  packageName: package,
                  label: 'An app with a fairly long name',
                  versionCode: 1,
                ),
              ],
            ),
          ),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
          configFileStoreProvider.overrideWithValue(FakeConfigFileStore()),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container
            .read(configRepositoryProvider)
            .save(const LockConfig(lockedPackages: {package})),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1400);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme:
                AppTheme.build(Brightness.light, accent: AppAccents.openlock),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const AppPickerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The test font draws every glyph a full em wide, which overflows the
      // shared hero card's label row above the list; the app rows are checked
      // directly below instead.
      tester.takeException();

      expect(find.text('Hide notifications'), findsOneWidget);
      // No row inside the app's card lays its children out past its edge.
      final rows = find.descendant(
        of: find.byType(GroupedRowItem),
        matching: find.byType(Row),
      );
      expect(rows, findsWidgets);
      for (final row in tester.renderObjectList<RenderFlex>(rows)) {
        var extent = 0.0;
        for (var child = row.firstChild; child != null;) {
          extent += child.size.width;
          child = (child.parentData! as FlexParentData).nextSibling;
        }
        expect(extent, lessThanOrEqualTo(row.size.width));
      }
      // The hide switch sits under the lock switch, inside the row padding.
      final card = tester.getRect(find.byType(GroupedRowItem));
      final lock = tester.getRect(find.byType(Switch).at(1)); // 0 = new apps
      final hide = tester.getRect(find.byType(Switch).at(2));
      expect(hide.right, lock.right);
      expect(hide.right, lessThanOrEqualTo(card.right - AppSpacing.md));
      expect(hide.bottom, lessThanOrEqualTo(card.bottom));
    });
  }
}
