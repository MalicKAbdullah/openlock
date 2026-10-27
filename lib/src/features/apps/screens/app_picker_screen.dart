import 'dart:io';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';
import 'package:openlock/src/features/apps/providers/apps_providers.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/models/relock_policy.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/intruder/providers/intruder_providers.dart';

class AppPickerScreen extends ConsumerWidget {
  const AppPickerScreen({super.key});

  /// Rows shown while the installed apps load; enough to fill the screen
  /// below the header.
  static const _skeletonRows = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(appListProvider);
    final config =
        ref.watch(configControllerProvider).valueOrNull ?? LockConfig.empty;
    final view = list.valueOrNull;
    final rowCount = switch (list) {
      AsyncData(:final value) =>
        value.visible.isEmpty ? 1 : value.visible.length,
      AsyncError() => 1,
      _ => _skeletonRows,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                AppSpacing.xl,
              ),
              // Header blocks first, then one lazily built row per app. The
              // header never waits for the app list; only the rows do.
              itemCount: _headerCount + rowCount,
              itemBuilder: (context, index) {
                if (index < _headerCount) {
                  return _header(
                    context,
                    ref,
                    index,
                    config: config,
                    total: view?.total,
                    lockedCount: view?.lockedCount,
                  );
                }
                final i = index - _headerCount;
                if (list.hasError) {
                  return const AppEmptyState(
                    compact: true,
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load apps',
                    message:
                        'The list of installed apps is unavailable right now.',
                  );
                }
                if (view == null) {
                  return GroupedRowItem(
                    isFirst: i == 0,
                    isLast: i == rowCount - 1,
                    child: const _AppTileSkeleton(),
                  );
                }
                if (view.visible.isEmpty) {
                  return const AppEmptyState(
                    compact: true,
                    icon: Icons.search_off_rounded,
                    title: 'No apps match',
                    message: 'Try a different name.',
                  );
                }
                final app = view.visible[i];
                return GroupedRowItem(
                  isFirst: i == 0,
                  isLast: i == view.visible.length - 1,
                  child: _AppTile(
                    app: app,
                    config: config,
                    onToggle: () => ref
                        .read(configControllerProvider.notifier)
                        .toggleApp(app.packageName),
                  ),
                );
              },
            ),
          ),
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
    required int? total,
    required int? lockedCount,
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
            lockedCount == null ? '' : '$lockedCount locked',
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

  /// Null until the installed apps have loaded.
  final int? lockedCount;
  final int? total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    final intruders = ref.watch(intruderControllerProvider).valueOrNull;
    final activeSchedules = config.schedules.where((s) => s.enabled).length;
    // Until the app list arrives, the configured set is the best answer.
    final guarded = (lockedCount ?? config.lockedPackages.length) > 0;
    return HeroMetricCard(
      label: 'Protected apps',
      trailing: _GuardPill(guarded: guarded),
      value: ValueText(
        lockedCount == null ? '-' : '$lockedCount',
        style: AppTextStyles.hero.copyWith(color: c.textPrimary),
      ),
      deltaCaption: total == null
          ? 'Counting installed apps'
          : 'of $total installed apps',
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

class _AppTile extends ConsumerWidget {
  const _AppTile({
    required this.app,
    required this.config,
    required this.onToggle,
  });

  final InstalledApp app;
  final LockConfig config;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    final locked = config.lockedPackages.contains(app.packageName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListRow(
          onTap: onToggle,
          leading: _AppIcon(app: app),
          title: app.label,
          subtitle: app.packageName,
          trailing: Switch(value: locked, onChanged: (_) => onToggle()),
        ),
        // Per-app notification-hiding override, only meaningful once the app is
        // locked. Reflects the effective choice (override, else the global
        // default) and writes an explicit per-app override. Inset like
        // AppListRow, so it starts under the app's name, its switch lines up
        // under the lock switch, and the label wraps rather than pushing the
        // switch out of the card.
        if (locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md + _iconSize + AppSpacing.smd + 2,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 18,
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Hide notifications',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.smd),
                Switch(
                  value: config.hidesNotificationsFor(app.packageName),
                  onChanged: (value) => ref
                      .read(configControllerProvider.notifier)
                      .setNotificationOverride(app.packageName, value),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// An [_AppTile] while the installed apps load: built from the same row so
/// it has exactly the same height, with the text left blank.
class _AppTileSkeleton extends StatelessWidget {
  const _AppTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppListRow(
      leading: Skeleton(width: _iconSize, height: _iconSize, radius: 12),
      title: '',
      subtitle: '',
      trailing: Visibility(
        visible: false,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: Switch(value: false, onChanged: null),
      ),
    );
  }
}

const double _iconSize = 40;

/// A row's launcher icon, loaded from native's disk cache once the row is
/// built. A same-size placeholder holds the space until it is decoded.
class _AppIcon extends ConsumerWidget {
  const _AppIcon({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(appIconLoaderProvider);
    if (loader.isResolved(app)) return _icon(context, loader.resolvedPath(app));
    return FutureBuilder<String?>(
      future: loader.pathFor(app),
      builder: (context, snapshot) => switch (snapshot) {
        AsyncSnapshot(hasError: true) => _icon(context, null),
        AsyncSnapshot(connectionState: ConnectionState.done) =>
          _icon(context, snapshot.data),
        _ => const _IconPlaceholder(),
      },
    );
  }

  Widget _icon(BuildContext context, String? path) {
    if (path == null) {
      return SizedBox.square(
        dimension: _iconSize,
        child:
            Icon(Icons.android, color: SuiteColors.of(context).textSecondary),
      );
    }
    // Decode straight to the drawn size; decoding runs off the UI thread.
    final px = (_iconSize * MediaQuery.devicePixelRatioOf(context)).round();
    return Image.file(
      File(path),
      width: _iconSize,
      height: _iconSize,
      cacheWidth: px,
      cacheHeight: px,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) =>
          sync || frame != null ? child : const _IconPlaceholder(),
      // The OS may clear the cache directory while the app is running.
      errorBuilder: (context, _, __) => _icon(context, null),
    );
  }
}

class _IconPlaceholder extends StatelessWidget {
  const _IconPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _iconSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SuiteColors.of(context).surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
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
