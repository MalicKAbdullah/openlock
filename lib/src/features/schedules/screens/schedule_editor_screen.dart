import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/apps/providers/apps_providers.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/schedules/models/lock_schedule.dart';
import 'package:openlock/src/features/schedules/widgets/schedule_format.dart';

class ScheduleEditorScreen extends ConsumerStatefulWidget {
  const ScheduleEditorScreen({this.scheduleId, super.key});

  final String? scheduleId;

  @override
  ConsumerState<ScheduleEditorScreen> createState() =>
      _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends ConsumerState<ScheduleEditorScreen> {
  final _nameController = TextEditingController(text: 'Focus time');
  Set<int> _weekdays = {1, 2, 3, 4, 5};
  int _start = 9 * 60;
  int _end = 17 * 60;
  Set<String> _packages = {};
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _hydrate(LockConfig config) {
    if (_initialized || widget.scheduleId == null) return;
    LockSchedule? existing;
    for (final s in config.schedules) {
      if (s.id == widget.scheduleId) {
        existing = s;
        break;
      }
    }
    if (existing != null) {
      _nameController.text = existing.name;
      _weekdays = Set.of(existing.weekdays);
      _start = existing.startMinutes;
      _end = existing.endMinutes;
      _packages = Set.of(existing.packages);
    }
    _initialized = true;
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        _start = minutes;
      } else {
        _end = minutes;
      }
    });
  }

  Future<void> _save() async {
    final schedule = LockSchedule(
      id: widget.scheduleId,
      name: _nameController.text.trim().isEmpty
          ? 'Schedule'
          : _nameController.text.trim(),
      packages: _packages,
      weekdays: _weekdays,
      startMinutes: _start,
      endMinutes: _end,
    );
    await ref.read(configControllerProvider.notifier).upsertSchedule(schedule);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (widget.scheduleId != null) {
      await ref
          .read(configControllerProvider.notifier)
          .deleteSchedule(widget.scheduleId!);
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final config =
        ref.watch(configControllerProvider).valueOrNull ?? LockConfig.empty;
    _hydrate(config);
    final appsAsync = ref.watch(installedAppsProvider);
    final isEditing = widget.scheduleId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit schedule' : 'New schedule'),
        actions: [
          if (isEditing)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: PageList(
          children: [
            AppTextField(label: 'Name', controller: _nameController),
            const _FieldLabel('Active days'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var day = 1; day <= 7; day++)
                  AppChip(
                    label: ScheduleFormat.weekdayLabels[day - 1],
                    selected: _weekdays.contains(day),
                    onTap: () => setState(() {
                      if (!_weekdays.add(day)) _weekdays.remove(day);
                    }),
                  ),
              ],
            ),
            const _FieldLabel('Hours'),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Start',
                    value: ScheduleFormat.time(_start),
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: AppSpacing.smd),
                Expanded(
                  child: _TimeField(
                    label: 'End',
                    value: ScheduleFormat.time(_end),
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            if (_end < _start)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Overnight window — ends the next morning.',
                  style: AppTextStyles.caption.copyWith(
                    color: SuiteColors.of(context).textSecondary,
                  ),
                ),
              ),
            _FieldLabel(
              'Apps to lock',
              trailing: '${_packages.length} selected',
            ),
            appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const AppEmptyState(
                compact: true,
                icon: Icons.error_outline_rounded,
                title: 'Could not load apps',
              ),
              data: (apps) {
                final sorted = [...apps]..sort((a, b) =>
                    a.label.toLowerCase().compareTo(b.label.toLowerCase()));
                void toggle(String pkg) => setState(() {
                      if (!_packages.add(pkg)) _packages.remove(pkg);
                    });
                return RowGroup(
                  separatorIndent: AppSpacing.md,
                  children: [
                    for (final app in sorted)
                      AppListRow(
                        dense: true,
                        title: app.label,
                        onTap: () => toggle(app.packageName),
                        trailing: Checkbox(
                          value: _packages.contains(app.packageName),
                          onChanged: (_) => toggle(app.packageName),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            VaultButton(label: 'Save schedule', onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.labelStrong.copyWith(color: c.textPrimary),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: AppTextStyles.label.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Semantics(
      button: true,
      label: '$label time, $value',
      child: ExcludeSemantics(
        child: VaultCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: AppTextStyles.numberMedium.copyWith(
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
