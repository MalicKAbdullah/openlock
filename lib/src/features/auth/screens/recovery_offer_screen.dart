import 'package:core_lock/core_lock.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';

/// Shown by the router while a [RecoveryOffer] is pending: a new recovery key
/// to save (after setup), or the one-time offer to create one.
class RecoveryOfferScreen extends ConsumerStatefulWidget {
  const RecoveryOfferScreen({super.key});

  @override
  ConsumerState<RecoveryOfferScreen> createState() =>
      _RecoveryOfferScreenState();
}

class _RecoveryOfferScreenState extends ConsumerState<RecoveryOfferScreen> {
  String? _created;
  bool _busy = false;

  Future<void> _finish() async {
    final offer = ref.read(recoveryOfferProvider);
    await ref.read(pinAuthServiceProvider).markRecoveryOffered();
    ref.read(recoveryOfferProvider.notifier).state = null;
    if (mounted && offer != null) context.go(offer.then);
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final key = await ref.read(pinAuthServiceProvider).createRecoveryKey();
    if (mounted) setState(() => _created = key);
  }

  @override
  Widget build(BuildContext context) {
    final key = _created ?? ref.watch(recoveryOfferProvider)?.key;
    if (key != null) {
      return PopScope(
        canPop: false,
        child: RecoveryKeyView(
          recoveryKey: key,
          appName: 'OpenLock',
          onDone: _finish,
        ),
      );
    }
    final c = SuiteColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.key_rounded, size: 40, color: c.accent),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Set up a recovery key',
                style: AppTextStyles.h2.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A recovery key lets you reset your OpenLock PIN if you forget '
                'it and your fingerprint is not working. Without one, a '
                'forgotten PIN cannot be reset.',
                style: AppTextStyles.body.copyWith(color: c.textSecondary),
              ),
              const Spacer(),
              VaultButton(
                label: 'Create recovery key',
                isLoading: _busy,
                onPressed: _busy ? null : _create,
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _finish,
                  child: const Text('Not now — I can do this in Settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
