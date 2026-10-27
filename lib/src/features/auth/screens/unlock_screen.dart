import 'dart:async';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/router/app_router.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/auth/widgets/pin_entry_panel.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

/// Unlock gate for opening OpenLock itself. PIN, optional fingerprint, and an
/// escalating cooldown after repeated wrong attempts. "Forgot PIN?" resets the
/// PIN with the recovery key under the same cooldown.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _panelKey = GlobalKey<PinEntryPanelState>();
  String? _message;
  Duration _cooldown = Duration.zero;
  Timer? _ticker;
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCooldown();
      _tryBiometric();
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

  Future<void> _tryBiometric() async {
    final session = ref.read(sessionProvider.notifier);
    if (!session.biometricEnabled) return;
    if (await ref.read(biometricServiceProvider).authenticate()) {
      session.markUnlocked(UnlockMethod.biometric, then: AppRoutes.apps);
    }
  }

  Future<void> _submit(String pin) async {
    final result = await ref.read(pinAuthServiceProvider).unlock(pin);
    if (!mounted) return;
    switch (result) {
      case UnlockSuccess():
        // Re-push config in case anything changed while locked.
        unawaited(ref.read(configControllerProvider.notifier).pushToNative());
        ref
            .read(sessionProvider.notifier)
            .markUnlocked(UnlockMethod.pin, then: AppRoutes.apps);
      case UnlockWrongPin(:final cooldown):
        _panelKey.currentState
          ?..shake()
          ..clear();
        setState(() => _message = 'Wrong PIN');
        if (cooldown != null) await _syncCooldown();
      case UnlockCoolingDown():
        _panelKey.currentState?.clear();
        await _syncCooldown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final coolingDown = _cooldown > Duration.zero;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SuiteAppIcon(app: SuiteApp.openlock, size: 72),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'OpenLock',
                        style: AppTextStyles.h1.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Enter your PIN to unlock',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        height: 20,
                        child: Text(
                          coolingDown
                              ? 'Too many attempts. Try again in '
                                  '${_cooldown.inSeconds}s'
                              : (_message ?? ''),
                          style: AppTextStyles.caption.copyWith(
                            color: c.negative,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_recovering)
                        _RecoveryForm(
                          enabled: !coolingDown,
                          onCooldown: _syncCooldown,
                          onBack: () => setState(() => _recovering = false),
                        )
                      else ...[
                        PinEntryPanel(
                          key: _panelKey,
                          enabled: !coolingDown,
                          onSubmit: _submit,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: coolingDown ? null : _tryBiometric,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Use fingerprint'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _message = null;
                            _recovering = true;
                          }),
                          child: const Text('Forgot PIN?'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: SuiteEndorsement(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recovery key + new PIN. A match sets the PIN, pushes it to native and
/// unlocks (the session notifier handles all three).
class _RecoveryForm extends ConsumerStatefulWidget {
  const _RecoveryForm({
    required this.enabled,
    required this.onCooldown,
    required this.onBack,
  });

  final bool enabled;
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
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(sessionProvider.notifier).recover(
          recoveryKey: _key.text,
          newPin: _pin.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case UnlockSuccess():
        break;
      case UnlockWrongPin(:final cooldown):
        setState(() => _error = 'That recovery key is not right');
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
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _key,
                label: 'Recovery key',
                hint: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                monospace: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.smd),
              AppTextField(
                controller: _pin,
                label: 'New PIN',
                obscureText: true,
                monospace: true,
                clearable: false,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.smd),
              AppTextField(
                controller: _confirm,
                label: 'Confirm new PIN',
                obscureText: true,
                monospace: true,
                clearable: false,
                keyboardType: TextInputType.number,
                errorText: _error,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.md),
              VaultButton(
                label: 'Reset PIN and unlock',
                isLoading: _busy,
                onPressed: widget.enabled && !_busy ? _submit : null,
              ),
            ],
            TextButton(
              onPressed: _busy ? null : widget.onBack,
              child: const Text('Back to PIN'),
            ),
          ],
        );
      },
    );
  }
}
