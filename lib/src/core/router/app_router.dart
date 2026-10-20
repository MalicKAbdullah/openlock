import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openlock/src/core/shell/home_shell.dart';
import 'package:openlock/src/features/apps/screens/app_picker_screen.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/screens/recovery_offer_screen.dart';
import 'package:openlock/src/features/auth/screens/setup_pin_screen.dart';
import 'package:openlock/src/features/auth/screens/unlock_screen.dart';
import 'package:openlock/src/features/backup/screens/backup_screen.dart';
import 'package:openlock/src/features/intruder/screens/intruder_log_screen.dart';
import 'package:openlock/src/features/onboarding/screens/onboarding_screen.dart';
import 'package:openlock/src/features/onboarding/screens/permissions_screen.dart';
import 'package:openlock/src/features/schedules/screens/schedule_editor_screen.dart';
import 'package:openlock/src/features/schedules/screens/schedules_screen.dart';
import 'package:openlock/src/features/settings/screens/about_screen.dart';
import 'package:openlock/src/features/settings/screens/change_pin_screen.dart';
import 'package:openlock/src/features/settings/screens/relock_settings_screen.dart';
import 'package:openlock/src/features/settings/screens/settings_screen.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String setup = '/setup';
  static const String unlock = '/unlock';
  static const String recoveryOffer = '/recovery-key';
  static const String permissions = '/permissions';
  static const String apps = '/apps';
  static const String schedules = '/schedules';
  static const String intruder = '/intruder';
  static const String settings = '/settings';
  static const String newSchedule = '/schedule/new';
  static const String editSchedule = '/schedule/edit';
  static const String changePin = '/change-pin';
  static const String relock = '/relock';
  static const String about = '/about';
  static const String backup = '/backup';
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen(sessionProvider, (_, __) => refresh.value++)
    ..listen(onboardingSeenProvider, (_, __) => refresh.value++)
    ..listen(recoveryOfferProvider, (_, __) => refresh.value++);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(sessionProvider);
      final location = state.matchedLocation;
      switch (status) {
        case AuthStatus.unknown:
          return AppRoutes.splash;
        case AuthStatus.needsSetup:
          final seen = ref.read(onboardingSeenProvider).valueOrNull;
          if (seen == null) return AppRoutes.splash;
          final target = seen ? AppRoutes.setup : AppRoutes.onboarding;
          return location == target ? null : target;
        case AuthStatus.locked:
          return location == AppRoutes.unlock ? null : AppRoutes.unlock;
        case AuthStatus.unlocked:
          if (ref.read(recoveryOfferProvider) != null) {
            return location == AppRoutes.recoveryOffer
                ? null
                : AppRoutes.recoveryOffer;
          }
          const gates = {
            AppRoutes.recoveryOffer,
            AppRoutes.splash,
            AppRoutes.onboarding,
            AppRoutes.setup,
            AppRoutes.unlock,
          };
          return gates.contains(location) ? AppRoutes.apps : null;
      }
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (_, __) => const SetupPinScreen(),
      ),
      GoRoute(
        path: AppRoutes.unlock,
        builder: (_, __) => const UnlockScreen(),
      ),
      GoRoute(
        path: AppRoutes.recoveryOffer,
        builder: (_, __) => const RecoveryOfferScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissions,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const PermissionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.newSchedule,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ScheduleEditorScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.editSchedule}/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            ScheduleEditorScreen(scheduleId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.changePin,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ChangePinScreen(),
      ),
      GoRoute(
        path: AppRoutes.relock,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const RelockSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.backup,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const BackupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.apps,
                builder: (_, __) => const AppPickerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.schedules,
                builder: (_, __) => const SchedulesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.intruder,
                builder: (_, __) => const IntruderLogScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (_, __) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
