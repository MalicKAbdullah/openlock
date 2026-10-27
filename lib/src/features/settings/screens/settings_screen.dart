import 'package:core_lock/core_lock.dart' show RecoveryKeyView;
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/router/app_router.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/models/relock_policy.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/onboarding/providers/permissions_providers.dart';
import 'package:openlock/src/features/settings/providers/settings_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read live state after returning from a system screen: device-admin
    // activation, and notification-access grant.
    if (state == AppLifecycleState.resumed) {
      ref.read(preventUninstallControllerProvider.notifier).refresh();
      ref.read(permissionsControllerProvider.notifier).refresh();
    }
  }

  String _relockLabel(RelockPolicy policy) {
    switch (policy.mode) {
      case RelockMode.immediately:
        return 'When you leave the app';
      case RelockMode.onScreenOff:
        return 'When the screen turns off';
      case RelockMode.afterTimeout:
        return 'After ${policy.timeout.inMinutes} min';
    }
  }

  /// In-app re-auth required before device admin can be deactivated. Tries
  /// biometrics first (if enabled), then falls back to a PIN prompt. Returns
  /// true only on a successful check.
  Future<bool> _authenticateForDisable() =>
      _reauthenticate('Enter your PIN to turn off uninstall protection.');

  /// Re-auth, confirm replacing any existing key, then show a new recovery
  /// key until the user confirms saving it.
  Future<void> _recoveryKey() async {
    if (!await _reauthenticate('Enter your PIN to create a recovery key.')) {
      return;
    }
    final auth = ref.read(pinAuthServiceProvider);
    if (await auth.hasRecoveryKey() && mounted) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace your recovery key?'),
          content: const Text(
            'Your current recovery key will stop working. Recovery keys are '
            'never stored, so the current one cannot be shown again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create new key'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    final key = await auth.createRecoveryKey();
    await auth.markRecoveryOffered();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => PopScope(
          canPop: false,
          child: RecoveryKeyView(
            recoveryKey: key,
            appName: 'OpenLock',
            onDone: () => Navigator.pop(routeContext),
          ),
        ),
      ),
    );
  }

  Future<bool> _reauthenticate(String pinPrompt) async {
    final biometric = ref.read(biometricServiceProvider);
    if (await biometric.isEnabled() && await biometric.authenticate()) {
      return true;
    }
    if (!mounted) return false;
    return _promptPin(pinPrompt);
  }

  Future<bool> _promptPin(String prompt) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var error = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Confirm your PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(prompt),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: controller,
                  label: 'PIN',
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  errorText: error ? 'Wrong PIN' : null,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final ok = await ref
                      .read(pinAuthServiceProvider)
                      .verifyPin(controller.text);
                  if (ok) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } else {
                    setDialogState(() => error = true);
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final config =
        ref.watch(configControllerProvider).valueOrNull ?? LockConfig.empty;
    final controller = ref.read(configControllerProvider.notifier);
    final biometricSupported =
        ref.watch(biometricSupportedProvider).valueOrNull ?? false;
    final biometricEnabled =
        ref.watch(biometricEnabledProvider).valueOrNull ?? false;
    final preventUninstall =
        ref.watch(preventUninstallControllerProvider).valueOrNull ?? false;
    final notificationAccess = ref
            .watch(permissionsControllerProvider)
            .valueOrNull
            ?.notificationAccess ??
        false;

    Widget toggle({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) =>
        SettingsTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          showChevron: false,
          trailing: Switch(value: value, onChanged: onChanged),
          onTap: onChanged == null ? null : () => onChanged(!value),
        );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageList(
          children: [
            const ScreenHeader(eyebrow: 'OpenLock', title: 'Settings'),
            const SectionLead('Protection'),
            RowGroup(
              children: [
                SettingsTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Permissions & status',
                  subtitle: 'Usage access, overlay, monitor service',
                  onTap: () => context.push(AppRoutes.permissions),
                ),
                SettingsTile(
                  icon: Icons.timer_outlined,
                  title: 'Relock behavior',
                  subtitle: _relockLabel(config.relock),
                  onTap: () => context.push(AppRoutes.relock),
                ),
              ],
            ),
            const SectionLead('Notifications'),
            RowGroup(
              children: [
                toggle(
                  icon: Icons.notifications_off_outlined,
                  title: 'Hide notification content',
                  subtitle: config.hideNotifications
                      ? 'Locked apps show a redacted notice'
                      : 'Replace locked apps\' notifications with a count',
                  value: config.hideNotifications,
                  onChanged: (value) async {
                    final messenger = ScaffoldMessenger.of(context);
                    await controller.setHideNotifications(value);
                    if (value && !notificationAccess) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Grant Notification access so OpenLock can hide '
                            'notification content.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                SettingsTile(
                  icon: notificationAccess
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  title: 'Notification access',
                  subtitle: notificationAccess
                      ? 'Granted'
                      : 'Required to hide notification content',
                  showChevron: false,
                  trailing: notificationAccess
                      ? null
                      : TextButton(
                          onPressed: () => ref
                              .read(permissionsControllerProvider.notifier)
                              .requestNotificationAccess(),
                          child: const Text('Grant'),
                        ),
                  onTap: notificationAccess
                      ? null
                      : () => ref
                          .read(permissionsControllerProvider.notifier)
                          .requestNotificationAccess(),
                ),
              ],
            ),
            const SectionLead('Security'),
            RowGroup(
              children: [
                SettingsTile(
                  icon: Icons.pin_outlined,
                  title: 'Change PIN',
                  onTap: () => context.push(AppRoutes.changePin),
                ),
                SettingsTile(
                  icon: Icons.key_outlined,
                  title: 'Recovery key',
                  subtitle: 'Resets your PIN if you forget it',
                  onTap: _recoveryKey,
                ),
                toggle(
                  icon: Icons.fingerprint,
                  title: 'Fingerprint unlock',
                  subtitle: biometricSupported
                      ? 'Unlock with your fingerprint'
                      : 'Not available on this device',
                  value: biometricEnabled,
                  onChanged: biometricSupported
                      ? (value) async {
                          final service = ref.read(biometricServiceProvider);
                          if (value) {
                            await service.enable();
                          } else {
                            await service.disable();
                          }
                          ref.invalidate(biometricEnabledProvider);
                          // Keep the native lock screen in sync with the choice.
                          await controller.pushToNative();
                        }
                      : null,
                ),
                toggle(
                  icon: Icons.app_blocking_outlined,
                  title: 'Prevent uninstall',
                  subtitle: preventUninstall
                      ? 'Uninstall needs your PIN'
                      : 'Require your PIN to uninstall',
                  value: preventUninstall,
                  onChanged: (value) async {
                    final security =
                        ref.read(preventUninstallControllerProvider.notifier);
                    if (value) {
                      await security.requestEnable();
                    } else {
                      final messenger = ScaffoldMessenger.of(context);
                      final lifted = await security
                          .disableWithAuth(_authenticateForDisable);
                      if (!lifted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'PIN or fingerprint required to turn off '
                              'uninstall protection.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
                toggle(
                  icon: Icons.shuffle,
                  title: 'Randomize keypad',
                  subtitle: 'Shuffle digits on the keypad',
                  value: config.randomizeKeypad,
                  onChanged: controller.setRandomizeKeypad,
                ),
              ],
            ),
            const SectionLead('Intruder detection'),
            RowGroup(
              children: [
                toggle(
                  icon: Icons.photo_camera_outlined,
                  title: 'Capture intruder photos',
                  subtitle:
                      'Photo after ${config.intruderThreshold} failed attempts',
                  value: config.intruderCaptureEnabled,
                  onChanged: (value) =>
                      controller.setIntruderCapture(enabled: value),
                ),
                SettingsTile(
                  icon: Icons.list_alt_outlined,
                  title: 'View intruder log',
                  onTap: () => context.go(AppRoutes.intruder),
                ),
              ],
            ),
            const SectionLead('Advanced'),
            RowGroup(
              children: [
                toggle(
                  icon: Icons.warning_amber_outlined,
                  title: 'Decoy cover',
                  subtitle: 'Fake "app stopped" dialog',
                  value: config.fakeCoverEnabled,
                  onChanged: controller.setFakeCover,
                ),
                SettingsTile(
                  icon: Icons.backup_outlined,
                  title: 'Backup & restore',
                  onTap: () => context.push(AppRoutes.backup),
                ),
              ],
            ),
            const SectionLead('Updates'),
            RowGroup(
              children: [
                const _UpdateTiles(),
                SettingsTile(
                  icon: Icons.info_outline,
                  title: 'About',
                  onTap: () => context.push(AppRoutes.about),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Check for updates on open" toggle + a manual "Check now", backed by
/// core_update. On by default; the only network call the app makes.
class _UpdateTiles extends ConsumerStatefulWidget {
  const _UpdateTiles();

  @override
  ConsumerState<_UpdateTiles> createState() => _UpdateTilesState();
}

class _UpdateTilesState extends ConsumerState<_UpdateTiles> {
  bool _checking = false;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final info = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _checking = false);
    final messenger = ScaffoldMessenger.of(context);
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Update available · v${info.version}'),
          action: SnackBarAction(
            label: 'Update',
            onPressed: () => ref.read(updateServiceProvider).openDownload(info),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoCheck = ref.watch(updateAutoCheckProvider).valueOrNull ?? true;
    Future<void> setAuto(bool v) async {
      await ref.read(secureStorageProvider).write(
            key: updateAutoCheckKey,
            value: v ? 'true' : 'false',
          );
      ref.invalidate(updateAutoCheckProvider);
      ref.invalidate(updateCheckProvider);
    }

    return Column(
      children: [
        SettingsTile(
          icon: Icons.system_update_alt,
          title: 'Auto-check for updates',
          subtitle: 'Checks GitHub, uploads nothing',
          showChevron: false,
          trailing: Switch(value: autoCheck, onChanged: setAuto),
          onTap: () => setAuto(!autoCheck),
        ),
        const Divider(height: 1, indent: 68),
        SettingsTile(
          icon: Icons.refresh,
          title: 'Check now',
          showChevron: false,
          trailing: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _checking ? null : _checkNow,
        ),
      ],
    );
  }
}
