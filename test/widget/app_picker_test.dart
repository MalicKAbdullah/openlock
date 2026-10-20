import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/features/apps/screens/app_picker_screen.dart';

import '../helpers/fakes.dart';

void main() {
  testWidgets('renders installed apps and toggles lock state', (tester) async {
    final bridge = FakeEnforcementBridge(
      apps: const [
        InstalledApp(packageName: 'com.alpha', label: 'Alpha'),
        InstalledApp(packageName: 'com.beta', label: 'Beta'),
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
}
