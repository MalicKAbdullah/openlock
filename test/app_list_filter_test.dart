import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/features/apps/services/app_list_filter.dart';

void main() {
  final apps = [
    InstalledApp(packageName: 'com.zeta.chat', label: 'Zeta', versionCode: 1),
    InstalledApp(packageName: 'com.alpha.mail', label: 'Alpha', versionCode: 1),
    InstalledApp(packageName: 'com.beta.game', label: 'beta', versionCode: 1),
  ];

  test('sorts locked apps first, then case-insensitively by label', () {
    final result = AppListFilter.apply(
      apps: apps,
      lockedPackages: {'com.zeta.chat'},
    );
    expect(result.map((a) => a.label), ['Zeta', 'Alpha', 'beta']);
  });

  test('unlocked apps sort alphabetically ignoring case', () {
    final result = AppListFilter.apply(apps: apps, lockedPackages: {});
    expect(result.map((a) => a.label), ['Alpha', 'beta', 'Zeta']);
  });

  test('search matches label case-insensitively', () {
    final result = AppListFilter.apply(
      apps: apps,
      lockedPackages: {},
      query: 'ALPH',
    );
    expect(result.single.label, 'Alpha');
  });

  test('search matches package name', () {
    final result = AppListFilter.apply(
      apps: apps,
      lockedPackages: {},
      query: 'game',
    );
    expect(result.single.packageName, 'com.beta.game');
  });

  test('lockedCount counts only locked installed apps', () {
    expect(
      AppListFilter.lockedCount(
        apps: apps,
        lockedPackages: {'com.zeta.chat', 'com.not.installed'},
      ),
      1,
    );
  });

  test('empty query returns all apps', () {
    final result = AppListFilter.apply(apps: apps, lockedPackages: {});
    expect(result.length, 3);
  });
}
