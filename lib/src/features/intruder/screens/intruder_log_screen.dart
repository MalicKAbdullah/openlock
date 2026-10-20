import 'dart:io';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/intruder/providers/intruder_providers.dart';

class IntruderLogScreen extends ConsumerWidget {
  const IntruderLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(intruderControllerProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const AppEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load the log',
          ),
          data: (records) => PageList(
            children: [
              ScreenHeader(
                eyebrow: 'Failed unlocks',
                title: 'Intruders',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => ref
                          .read(intruderControllerProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    if (records.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear all',
                        onPressed: () => ref
                            .read(intruderControllerProvider.notifier)
                            .clearAll(),
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                  ],
                ),
              ),
              if (records.isEmpty)
                const AppEmptyState(
                  icon: Icons.verified_user_outlined,
                  title: 'No intruder events',
                  message: 'If someone fails your PIN too many times, a '
                      'snapshot appears here.',
                )
              else
                RowGroup(
                  separatorIndent: 84,
                  children: [
                    for (final record in records)
                      _IntruderRow(
                        record: record,
                        onDelete: () => ref
                            .read(intruderControllerProvider.notifier)
                            .delete(record.id),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntruderRow extends StatelessWidget {
  const _IntruderRow({required this.record, required this.onDelete});

  final IntruderRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final when = DateFormat.yMMMd().add_jm().format(record.timestamp);
    final photo = record.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();
    return AppListRow(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: SizedBox(
          width: 52,
          height: 52,
          child: hasPhoto
              ? Image.file(File(photo), fit: BoxFit.cover)
              : ColoredBox(
                  color: c.surfaceAlt,
                  child: Icon(
                    Icons.no_photography_outlined,
                    color: c.textSecondary,
                  ),
                ),
        ),
      ),
      title: record.packageName,
      subtitle: when,
      trailing: IconButton(
        tooltip: 'Delete',
        onPressed: onDelete,
        icon: const Icon(Icons.close_rounded),
      ),
    );
  }
}
