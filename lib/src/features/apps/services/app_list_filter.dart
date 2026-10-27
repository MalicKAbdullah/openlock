import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';

/// Pure search / sort helpers for the app picker, kept out of the widget so
/// they can be tested directly.
abstract final class AppListFilter {
  /// Filters [apps] by a case-insensitive [query] over label and package
  /// name, then sorts them: locked apps first, then alphabetically by label
  /// (case-insensitive), with package name as a stable tiebreaker.
  static List<InstalledApp> apply({
    required List<InstalledApp> apps,
    required Set<String> lockedPackages,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<InstalledApp>.of(apps)
        : apps
            .where((a) => a.labelKey.contains(q) || a.packageKey.contains(q))
            .toList();

    filtered.sort((a, b) {
      final aLocked = lockedPackages.contains(a.packageName);
      final bLocked = lockedPackages.contains(b.packageName);
      if (aLocked != bLocked) return aLocked ? -1 : 1;
      final byLabel = a.labelKey.compareTo(b.labelKey);
      if (byLabel != 0) return byLabel;
      return a.packageName.compareTo(b.packageName);
    });
    return filtered;
  }

  /// How many of [apps] are currently locked.
  static int lockedCount({
    required List<InstalledApp> apps,
    required Set<String> lockedPackages,
  }) =>
      apps.where((a) => lockedPackages.contains(a.packageName)).length;
}
