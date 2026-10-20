import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/models/relock_policy.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

class RelockSettingsScreen extends ConsumerWidget {
  const RelockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config =
        ref.watch(configControllerProvider).valueOrNull ?? LockConfig.empty;
    final controller = ref.read(configControllerProvider.notifier);
    final policy = config.relock;

    return Scaffold(
      appBar: AppBar(title: const Text('Relock behavior')),
      body: SafeArea(
        child: RadioGroup<RelockMode>(
          groupValue: policy.mode,
          onChanged: (mode) {
            if (mode != null) controller.setRelock(policy.copyWith(mode: mode));
          },
          child: PageList(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(
                  'When should a locked app relock after you unlock it?',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: SuiteColors.of(context).textSecondary,
                  ),
                ),
              ),
              RowGroup(
                separatorIndent: AppSpacing.md,
                children: [
                  _ModeRow(
                    mode: RelockMode.immediately,
                    title: 'When you leave the app',
                    subtitle: 'Relocks the instant you switch away',
                    onSelect: () => controller.setRelock(
                        policy.copyWith(mode: RelockMode.immediately)),
                  ),
                  _ModeRow(
                    mode: RelockMode.afterTimeout,
                    title: 'After a timeout',
                    subtitle: 'Stays open briefly if you come back',
                    onSelect: () => controller.setRelock(
                      policy.copyWith(mode: RelockMode.afterTimeout),
                    ),
                  ),
                  _ModeRow(
                    mode: RelockMode.onScreenOff,
                    title: 'When the screen turns off',
                    subtitle: 'Stays open across app switches',
                    onSelect: () => controller.setRelock(
                      policy.copyWith(mode: RelockMode.onScreenOff),
                    ),
                  ),
                ],
              ),
              if (policy.mode == RelockMode.afterTimeout) ...[
                const SectionLead('Timeout'),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final choice in RelockPolicy.timeoutChoices)
                      AppChip(
                        label: '${choice.inMinutes} min',
                        selected: policy.timeout == choice,
                        onTap: () => controller
                            .setRelock(policy.copyWith(timeout: choice)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.onSelect,
  });

  final RelockMode mode;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      title: title,
      subtitle: subtitle,
      onTap: onSelect,
      trailing: Radio<RelockMode>(value: mode),
    );
  }
}
