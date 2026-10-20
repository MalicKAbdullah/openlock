import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openlock/src/core/router/app_router.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/schedules/models/lock_schedule.dart';
import 'package:openlock/src/features/schedules/widgets/schedule_format.dart';

class SchedulesScreen extends ConsumerWidget {
  const SchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config =
        ref.watch(configControllerProvider).valueOrNull ?? LockConfig.empty;
    final schedules = config.schedules;

    final active = schedules.where((s) => s.enabled).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newSchedule),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: SafeArea(
        bottom: false,
        child: PageList(
          bottomPadding: 96,
          children: [
            ScreenHeader(
              eyebrow: schedules.isEmpty
                  ? 'Lock by the clock'
                  : '$active of ${schedules.length} on',
              title: 'Schedules',
            ),
            if (schedules.isEmpty)
              const AppEmptyState(
                icon: Icons.schedule_rounded,
                title: 'No schedules yet',
                message: 'Lock chosen apps during set hours, like social apps '
                    '9-5 on weekdays.',
              )
            else
              RowGroup(
                children: [
                  for (final schedule in schedules)
                    _ScheduleCard(
                      schedule: schedule,
                      onTap: () => context.push(
                        '${AppRoutes.editSchedule}/${schedule.id}',
                      ),
                      onToggle: (value) => ref
                          .read(configControllerProvider.notifier)
                          .upsertSchedule(schedule.copyWith(enabled: value)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onTap,
    required this.onToggle,
  });

  final LockSchedule schedule;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final count = schedule.packages.length;
    return DetailRow(
      onTap: onTap,
      leading: const IconBadge(icon: Icons.schedule_rounded),
      title: schedule.name,
      detail: '${ScheduleFormat.summary(schedule)}\n'
          '$count ${count == 1 ? 'app' : 'apps'}',
      trailing: Switch(value: schedule.enabled, onChanged: onToggle),
    );
  }
}
