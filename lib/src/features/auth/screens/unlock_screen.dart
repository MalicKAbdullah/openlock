import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_lock/core_lock.dart'
    show
        LockBiometricButton,
        LockLayout,
        LockShake,
        LockTextLink,
        formatLockCountdown;
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/router/app_router.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/auth/widgets/pin_entry_panel.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

/// Unlock gate for opening OpenLock itself, on the suite's [LockLayout]: PIN
/// dots and keypad, an optional fingerprint button low on the screen, and an
/// escalating cooldown after repeated wrong attempts. "Forgot PIN?" resets
/// the PIN with the recovery key under the same cooldown.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  /// Key height bounds. The keypad is sized from the screen height so it fits
  /// a 360 × 640 phone without scrolling; keys never drop below the tap
  /// target.
  static const double minKeyHeight = AppSpacing.tapTarget;
  static const double maxKeyHeight = 64;

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _panelKey = GlobalKey<PinEntryPanelState>();
  String? _message;
  Duration _cooldown = Duration.zero;
  Timer? _ticker;
  bool _recovering = false;
  bool _biometric = false;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCooldown();
      _startBiometric();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _syncCooldown() async {
    final remaining =
        await ref.read(pinAuthServiceProvider).cooldownRemaining();
    if (!mounted) return;
    setState(() => _cooldown = remaining);
    _ticker?.cancel();
    if (remaining > Duration.zero) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _cooldown -= const Duration(seconds: 1);
          if (_cooldown <= Duration.zero) {
            _cooldown = Duration.zero;
            _ticker?.cancel();
          }
        });
      });
    }
  }

  /// Shows the fingerprint button when biometric unlock is on and starts the
  /// system prompt once; the button brings the prompt back.
  Future<void> _startBiometric() async {
    if (!await ref.read(biometricServiceProvider).isEnabled()) return;
    if (!mounted) return;
    setState(() => _biometric = true);
    await _tryBiometric();
  }

  /// The system prompt shows its own mismatch and cancel feedback, so a
  /// failed or dismissed prompt adds nothing here.
  Future<void> _tryBiometric() async {
    final biometric = ref.read(biometricServiceProvider);
    if (!await biometric.isEnabled()) return;
    if (await biometric.authenticate()) {
      await ref
          .read(sessionProvider.notifier)
          .markUnlocked(UnlockMethod.biometric, then: AppRoutes.apps);
    }
  }

  Future<void> _submit(String pin) async {
    final result = await ref.read(pinAuthServiceProvider).unlock(pin);
    if (!mounted) return;
    switch (result) {
      case UnlockSuccess():
        // Re-push config in case anything changed while locked.
        unawaited(ref.read(configControllerProvider.notifier).pushToNative());
        await ref
            .read(sessionProvider.notifier)
            .markUnlocked(UnlockMethod.pin, then: AppRoutes.apps);
      case UnlockWrongPin(:final cooldown):
        _panelKey.currentState?.clear();
        setState(() {
          _failures++;
          _message = 'Wrong PIN';
        });
        if (cooldown != null) await _syncCooldown();
      case UnlockCoolingDown():
        _panelKey.currentState?.clear();
        await _syncCooldown();
    }
  }

  /// The key height that fits the keypad into [height] (the screen without
  /// system bars) next to everything else [LockLayout] stacks around it.
  double _keyHeight(double height) {
    const column = AppSpacing.lg * 2 + // LockLayout's vertical padding
        LockLayout.markSize +
        AppSpacing.md +
        28 + // the h2 app name
        AppSpacing.xl +
        AppSpacing.tapTarget; // "Forgot PIN?"
    const endorsement = 20 + AppSpacing.mdl;
    final biometric =
        _biometric ? LockBiometricButton.size + AppSpacing.xl : 0.0;
    final keys =
        height - column - endorsement - biometric - PinEntryPanel.heightFor(0);
    return (keys / 4).clamp(
      UnlockScreen.minKeyHeight,
      UnlockScreen.maxKeyHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final coolingDown = _cooldown > Duration.zero;
    final error = coolingDown
        ? 'Too many attempts. Try again in ${formatLockCountdown(_cooldown)}.'
        : _message;
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight - MediaQuery.paddingOf(context).vertical;
        return LockLayout(
          mark: const SuiteAppIcon(app: SuiteApp.openlock, size: 64),
          title: 'OpenLock',
          message: _recovering ? 'Reset your PIN' : null,
          bottom: _biometric
              ? LockBiometricButton(
                  onPressed: coolingDown ? null : _tryBiometric,
                )
              : null,
          children: _recovering
              ? [
                  _RecoveryForm(
                    enabled: !coolingDown,
                    error: coolingDown ? error : null,
                    onCooldown: _syncCooldown,
                    onBack: () => setState(() => _recovering = false),
                  ),
                ]
              : [
                  PinEntryPanel(
                    key: _panelKey,
                    enabled: !coolingDown,
                    error: error,
                    failures: _failures,
                    keyHeight: _keyHeight(height),
                    onSubmit: _submit,
                  ),
                  LockTextLink(
                    label: 'Forgot PIN?',
                    onPressed: () => setState(() {
                      _message = null;
                      _recovering = true;
                    }),
                  ),
                ],
        );
      },
    );
  }
}

/// Recovery key + new PIN. A match sets the PIN, pushes it to native and
/// unlocks (the session notifier handles all three).
class _RecoveryForm extends ConsumerStatefulWidget {
  const _RecoveryForm({
    required this.enabled,
    required this.error,
    required this.onCooldown,
    required this.onBack,
  });

  final bool enabled;

  /// The cooldown line, shown in place of the form's own error.
  final String? error;
  final Future<void> Function() onCooldown;
  final VoidCallback onBack;

  @override
  ConsumerState<_RecoveryForm> createState() => _RecoveryFormState();
}

class _RecoveryFormState extends ConsumerState<_RecoveryForm> {
  final _key = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  late final Future<bool> _hasKey =
      ref.read(pinAuthServiceProvider).hasRecoveryKey();
  bool _busy = false;
  String? _error;
  int _failures = 0;

  @override
  void dispose() {
    _key.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String? problem;
    if (RecoveryKey.normalize(_key.text) == null) {
      problem = 'A recovery key has ${RecoveryKey.length} letters and numbers';
    } else if (_pin.text.length < PinAuthService.minPinLength) {
      problem = 'New PIN must be at least 6 digits';
    } else if (_pin.text != _confirm.text) {
      problem = 'New PINs do not match';
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() {
        _error = problem;
        _failures++;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).recover(
          recoveryKey: _key.text,
          newPin: _pin.text,
          then: AppRoutes.apps,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case UnlockSuccess():
        break;
      case UnlockWrongPin(:final cooldown):
        setState(() {
          _error = 'That recovery key is not right';
          _failures++;
        });
        if (cooldown != null) await widget.onCooldown();
      case UnlockCoolingDown():
        await widget.onCooldown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return FutureBuilder<bool>(
      future: _hasKey,
      builder: (context, snapshot) {
        final hasKey = snapshot.data;
        if (hasKey == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasKey
                  ? 'Enter the recovery key you saved when you set up '
                      'OpenLock, then choose a new PIN.'
                  : 'No recovery key was set up, so a forgotten PIN cannot '
                      'be reset. Unlock with your fingerprint, then create a '
                      'recovery key in Settings.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
            ),
            if (hasKey) ...[
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                controller: _key,
                label: 'Recovery key',
                hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                monospace: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: LockLayout.gap),
              AppTextField(
                controller: _pin,
                label: 'New PIN',
                obscureText: true,
                monospace: true,
                clearable: false,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: LockLayout.gap),
              LockShake(
                trigger: _failures,
                child: AppTextField(
                  controller: _confirm,
                  label: 'Confirm new PIN',
                  obscureText: true,
                  monospace: true,
                  clearable: false,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  errorText: widget.error ?? _error,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: LockLayout.gap),
              VaultButton(
                label: 'Reset and unlock',
                isLoading: _busy,
                onPressed: widget.enabled && !_busy ? _submit : null,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            LockTextLink(
              label: 'Back to unlock',
              onPressed: _busy ? null : widget.onBack,
            ),
          ],
        );
      },
    );
  }
}
