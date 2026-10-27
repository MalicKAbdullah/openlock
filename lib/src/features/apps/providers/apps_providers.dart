import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/perf_log.dart';
import 'package:openlock/src/features/apps/services/app_icon_loader.dart';
import 'package:openlock/src/features/apps/services/app_list_filter.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';

/// The launchable apps installed on the device, loaded once from native.
final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  final apps = await ref.watch(enforcementBridgeProvider).getInstalledApps();
  PerfLog.mark('installed apps (${apps.length}) loaded');
  return apps;
});

/// The current search query in the app picker.
final appSearchQueryProvider = StateProvider<String>((_) => '');

/// Launcher icons, fetched per visible row and cached for the session.
final appIconLoaderProvider = Provider<AppIconLoader>(
  (ref) => AppIconLoader(ref.watch(enforcementBridgeProvider)),
);

/// What the app picker shows: the filtered, sorted rows and the counts in
/// its header.
final class AppListView {
  const AppListView({
    required this.visible,
    required this.lockedCount,
    required this.total,
  });

  final List<InstalledApp> visible;
  final int lockedCount;
  final int total;
}

/// [AppListView] for the current apps, locked set and query. Recomputed only
/// when one of those changes, not on every rebuild of the picker.
final appListProvider = Provider<AsyncValue<AppListView>>((ref) {
  final apps = ref.watch(installedAppsProvider);
  final lockedPackages = ref.watch(
    configControllerProvider.select(
      (config) => (config.valueOrNull ?? LockConfig.empty).lockedPackages,
    ),
  );
  final query = ref.watch(appSearchQueryProvider);
  return apps.whenData(
    (apps) => AppListView(
      visible: AppListFilter.apply(
        apps: apps,
        lockedPackages: lockedPackages,
        query: query,
      ),
      lockedCount: AppListFilter.lockedCount(
        apps: apps,
        lockedPackages: lockedPackages,
      ),
      total: apps.length,
    ),
  );
});
