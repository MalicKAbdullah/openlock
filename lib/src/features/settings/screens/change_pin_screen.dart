import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPin = _newController.text;
    if (newPin.length < PinAuthService.minPinLength) {
      setState(() => _error = 'New PIN must be at least 6 digits');
      return;
    }
    if (newPin != _confirmController.text) {
      setState(() => _error = 'New PINs do not match');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref.read(pinAuthServiceProvider).changePin(
          oldPin: _oldController.text,
          newPin: newPin,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case UnlockSuccess():
        // Push the new verifier hash down to the native enforcement layer.
        await ref.read(configControllerProvider.notifier).pushToNative();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN changed')),
          );
          context.pop();
        }
      case UnlockWrongPin():
        setState(() => _error = 'Current PIN is incorrect');
      case UnlockCoolingDown(:final remaining):
        setState(
          () => _error = 'Too many attempts. Wait ${remaining.inSeconds}s',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                label: 'Current PIN',
                controller: _oldController,
                obscureText: true,
                monospace: true,
                clearable: false,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'New PIN',
                controller: _newController,
                obscureText: true,
                monospace: true,
                clearable: false,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Confirm new PIN',
                controller: _confirmController,
                obscureText: true,
                monospace: true,
                clearable: false,
                keyboardType: TextInputType.number,
                errorText: _error,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.xl),
              VaultButton(
                label: 'Change PIN',
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
