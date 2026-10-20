import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Static app identity constants.
abstract final class AppInfo {
  static const String name = 'OpenLock';
}

/// Installed app version from the platform (pubspec `version`), read once.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);
