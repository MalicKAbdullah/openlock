import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/features/onboarding/screens/onboarding_screen.dart';
import 'package:openlock/src/features/onboarding/screens/permissions_screen.dart';

import '../helpers/fakes.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.build(Brightness.light, accent: AppAccents.openlock),
      home: child,
    ),
  );
}

void main() {
  testWidgets('onboarding renders the first intro page', (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingScreen()));
    expect(find.text('Lock the apps that matter'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('permissions checklist renders each item + status banner',
      (tester) async {
    final bridge = FakeEnforcementBridge(
      permissions: const PermissionStates(
        usageAccess: false,
        overlay: false,
        notifications: false,
        batteryExempt: false,
        serviceRunning: false,
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const PermissionsScreen(),
        overrides: [enforcementBridgeProvider.overrideWithValue(bridge)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Protection not active yet'), findsOneWidget);
    expect(find.text('Usage access'), findsOneWidget);
    expect(find.text('Display over other apps'), findsOneWidget);
    expect(find.text('Ignore battery optimization'), findsOneWidget);
    // Two required permissions ungranted → two "Grant" buttons at least.
    expect(find.text('Grant'), findsWidgets);
  });

  testWidgets('permissions banner shows active when everything is granted',
      (tester) async {
    final bridge = FakeEnforcementBridge(); // all-granted defaults
    await tester.pumpWidget(
      _wrap(
        const PermissionsScreen(),
        overrides: [enforcementBridgeProvider.overrideWithValue(bridge)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protection active'), findsOneWidget);
  });
}
