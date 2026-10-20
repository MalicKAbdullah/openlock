import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/router/app_router.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';

/// First-run PIN creation: enter a 6+ digit PIN, confirm it, see a strength
/// hint, then move on to the permissions checklist.
class SetupPinScreen extends ConsumerStatefulWidget {
  const SetupPinScreen({super.key});

  @override
  ConsumerState<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends ConsumerState<SetupPinScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  ({String label, double value, Color color}) _strength(
    BuildContext context,
    String pin,
  ) {
    if (pin.length < PinAuthService.minPinLength) {
      return (
        label: 'Too short',
        value: 0.2,
        color: SuiteColors.of(context).negative
      );
    }
    final unique = pin.split('').toSet().length;
    final sequential = _isSequential(pin);
    if (pin.length >= 8 && unique >= 5 && !sequential) {
      return (
        label: 'Strong',
        value: 1,
        color: SuiteColors.of(context).positive
      );
    }
    if (pin.length >= 6 && unique >= 3 && !sequential) {
      return (
        label: 'Good',
        value: 0.66,
        color: SuiteColors.of(context).warning
      );
    }
    return (label: 'Weak', value: 0.4, color: SuiteColors.of(context).negative);
  }

  bool _isSequential(String pin) {
    if (pin.length < 3) return false;
    var ascending = true;
    var descending = true;
    for (var i = 1; i < pin.length; i++) {
      final diff = pin.codeUnitAt(i) - pin.codeUnitAt(i - 1);
      if (diff != 1) ascending = false;
      if (diff != -1) descending = false;
    }
    return ascending || descending;
  }

  Future<void> _submit() async {
    final pin = _pinController.text;
    final confirm = _confirmController.text;
    if (pin.length < PinAuthService.minPinLength) {
      setState(() => _error = 'Use at least 6 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await ref
        .read(sessionProvider.notifier)
        .completeSetup(pin, then: AppRoutes.permissions);
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pinController.text;
    final strength = _strength(context, pin);
    return Scaffold(
      appBar: AppBar(title: const Text('Create your PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This PIN unlocks OpenLock and every app you lock. Choose '
                'something only you know.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: SuiteColors.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                label: 'PIN',
                monospace: true,
                clearable: false,
                controller: _pinController,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppProgressBar(value: strength.value, color: strength.color),
              const SizedBox(height: AppSpacing.xs),
              Text(
                strength.label,
                style: AppTextStyles.caption.copyWith(
                  color: SuiteColors.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Confirm PIN',
                monospace: true,
                clearable: false,
                controller: _confirmController,
                obscureText: _obscure,
                keyboardType: TextInputType.number,
                errorText: _error,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.xl),
              VaultButton(
                label: 'Continue',
                isLoading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
