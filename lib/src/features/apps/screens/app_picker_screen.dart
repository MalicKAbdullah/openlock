import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/apps/providers/apps_providers.dart';
import 'package:openlock/src/features/apps/services/app_list_filter.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/models/relock_policy.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/intruder/providers/intruder_providers.dart';

class AppPickerScreen extends ConsumerWidget {
  const AppPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(installedAppsProvider);
    final configAsync = ref.watch(configControllerProvider);
    final query = ref.watch(appSearchQueryProvider);
    final config = configAsync.valueOrNull ?? LockConfig.empty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: appsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const AppEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load apps',
            message: 'The list of installed apps is unavailable right now.',
          ),
          data: (apps) {
            final visible = AppListFilter.apply(
              apps: apps,
              lockedPackages: config.lockedPackages,
              query: query,
            );
            final lockedCount = AppListFilter.lockedCount(
              apps: apps,
              lockedPackages: config.lockedPackages,
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    AppSpacing.xl,
                  ),
                  // Header blocks first, then one lazily built row per app.
                  itemCount:
                      _headerCount + (visible.isEmpty ? 1 : visible.length),
                  itemBuilder: (context, index) {
                    if (index < _headerCount) {
                      return _header(
                        context,
                        ref,
                        index,
                        config: config,
                        total: apps.length,
                        lockedCount: lockedCount,
                        shown: visible.length,
                      );
                    }
                    if (visible.isEmpty) {
                      return const AppEmptyState(
                        compact: true,
                        icon: Icons.search_off_rounded,
                        title: 'No apps match',
                        message: 'Try a different name.',
                      );
                    }
                    final i = index - _headerCount;
                    final app = visible[i];
                    return GroupedRowItem(
                      isFirst: i == 0,
                      isLast: i == visible.length - 1,
                      child: _AppTile(
                        app: app,
                        locked: config.lockedPackages.contains(app.packageName),
                        onToggle: () => ref
                            .read(configControllerProvider.notifier)
                            .toggleApp(app.packageName),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static const _headerCount = 5;

  Widget _header(
    BuildContext context,
    WidgetRef ref,
    int index, {
    required LockConfig config,
    required int total,
    required int lockedCount,
    required int shown,
  }) {
    switch (index) {
      case 0:
        return const ScreenHeader(eyebrow: 'Protection', title: 'OpenLock');
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _UpdateBannerCard(),
            _ProtectionHero(
              config: config,
              lockedCount: lockedCount,
              total: total,
            ),
          ],
        );
      case 2:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.smd),
          child: _LockNewAppsTile(config: config),
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLead('Apps'),
            AppSearchField(
              hint: 'Search apps',
              onChanged: (value) =>
                  ref.read(appSearchQueryProvider.notifier).state = value,
            ),
          ],
        );
      default:
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Text(
            '$lockedCount locked',
            style: AppTextStyles.label.copyWith(
              color: SuiteColors.of(context).textSecondary,
            ),
          ),
        );
    }
  }
}

/// The dashboard hero: how many apps are guarded, with schedules, intruder
/// events and the relock rule that explain the protection beneath it.
class _ProtectionHero extends ConsumerWidget {
  const _ProtectionHero({
    required this.config,
    required this.lockedCount,
    required this.total,
  });

  final LockConfig config;
  final int lockedCount;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    final intruders = ref.watch(intruderControllerProvider).valueOrNull;
    final activeSchedules = config.schedules.where((s) => s.enabled).length;
    final guarded = lockedCount > 0;
    return HeroMetricCard(
      label: 'Protected apps',
      trailing: _GuardPill(guarded: guarded),
      value: ValueText(
        '$lockedCount',
        style: AppTextStyles.hero.copyWith(color: c.textPrimary),
      ),
      deltaCaption: 'of $total installed apps',
      footer: [
        StatTile(label: 'Schedules', value: '$activeSchedules on'),
        StatTile(
          label: 'Intruders',
          value: intruders == null ? '-' : '${intruders.length}',
          valueColor: (intruders?.isNotEmpty ?? false) ? c.negative : null,
        ),
        StatTile(
          label: 'Relock',
          value: switch (config.relock.mode) {
            RelockMode.immediately => 'On exit',
            RelockMode.onScreenOff => 'Screen off',
            RelockMode.afterTimeout => '${config.relock.timeout.inMinutes} min',
          },
        ),
      ],
    );
  }
}

class _GuardPill extends StatelessWidget {
  const _GuardPill({required this.guarded});
  final bool guarded;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final color = guarded ? c.positive : c.textSecondary;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: guarded ? c.positiveContainer : c.surfaceAlt,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              guarded ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              guarded ? 'Guarding' : 'Nothing locked',
              style: AppTextStyles.labelStrong.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockNewAppsTile extends ConsumerWidget {
  const _LockNewAppsTile({required this.config});

  final LockConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void set(bool value) =>
        ref.read(configControllerProvider.notifier).setLockNewApps(value);
    return RowGroup(
      children: [
        AppListRow(
          leading: const IconBadge(icon: Icons.new_releases_outlined),
          title: 'Lock newly installed apps',
          subtitle: 'Guard apps you install later',
          trailing: Switch(value: config.lockNewApps, onChanged: set),
          onTap: () => set(!config.lockNewApps),
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.locked,
    required this.onToggle,
  });

  final InstalledApp app;
  final bool locked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return AppListRow(
      onTap: onToggle,
      leading: SizedBox(
        width: 40,
        height: 40,
        child: app.icon != null
            ? Image.memory(
                app.icon!,
                gaplessPlayback: true,
                // Icons arrive as 96px PNGs; decode at that size (not full
                // resolution) to keep the scrolling list light.
                cacheWidth: 96,
                cacheHeight: 96,
              )
            : Icon(Icons.android, color: c.textSecondary),
      ),
      title: app.label,
      subtitle: app.packageName,
      trailing: Switch(value: locked, onChanged: (_) => onToggle()),
    );
  }
}

/// "Update available" card, shown when a newer GitHub release exists and the
/// user hasn't dismissed it this session.
class _UpdateBannerCard extends ConsumerWidget {
  const _UpdateBannerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateCheckProvider).valueOrNull;
    final dismissed = ref.watch(updateDismissedProvider);
    if (info == null || dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smd),
      child: UpdateBanner(
        info: info,
        onUpdate: () => ref.read(updateServiceProvider).openDownload(info),
        onDismiss: () =>
            ref.read(updateDismissedProvider.notifier).state = true,
      ),
    );
  }
}
