import 'dart:async';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/auth/widgets/pin_entry_panel.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

/// Unlock gate for opening OpenLock itself. PIN, optional fingerprint, and an
/// escalating cooldown after repeated wrong attempts.
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
    final biometric = ref.read(biometricServiceProvider);
    if (!await biometric.isEnabled()) return;
    if (await biometric.authenticate()) {
      ref.read(sessionProvider.notifier).markUnlocked();
    }
  }

  Future<void> _submit(String pin) async {
    final result = await ref.read(pinAuthServiceProvider).unlock(pin);
    if (!mounted) return;
    switch (result) {
      case UnlockSuccess():
        // Re-push config in case anything changed while locked.
        unawaited(ref.read(configControllerProvider.notifier).pushToNative());
        ref.read(sessionProvider.notifier).markUnlocked();
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
