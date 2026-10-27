import 'dart:async';

import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';

/// Resolves launcher-icon file paths on demand.
///
/// Rows ask for their icon as they are built; every request made before the
/// current task ends (one frame's worth of rows) goes to native as a single
/// batch. Each app version is requested at most once per session.
final class AppIconLoader {
  AppIconLoader(this._bridge);

  final IEnforcementBridge _bridge;
  final Map<String, Future<String?>> _requests = {};
  final Map<String, String?> _resolved = {};
  final List<(InstalledApp, Completer<String?>)> _batch = [];

  static String _key(InstalledApp app) =>
      '${app.packageName}@${app.versionCode}';

  /// Whether [app]'s path is already known, so a rebuilt row can paint the
  /// icon on its first frame instead of a placeholder.
  bool isResolved(InstalledApp app) => _resolved.containsKey(_key(app));

  /// The known path for [app]; only valid when [isResolved].
  String? resolvedPath(InstalledApp app) {
    assert(isResolved(app), 'resolvedPath called before the icon resolved');
    return _resolved[_key(app)];
  }

  /// The icon PNG path for [app], or null when it has no icon.
  Future<String?> pathFor(InstalledApp app) =>
      _requests.putIfAbsent(_key(app), () {
        final completer = Completer<String?>();
        if (_batch.isEmpty) scheduleMicrotask(_flush);
        _batch.add((app, completer));
        return completer.future;
      });

  Future<void> _flush() async {
    final batch = List.of(_batch);
    _batch.clear();
    try {
      final paths =
          await _bridge.getAppIcons([for (final (app, _) in batch) app]);
      for (final (app, completer) in batch) {
        final path = paths[app.packageName];
        _resolved[_key(app)] = path;
        completer.complete(path);
      }
    } catch (error, stack) {
      for (final (_, completer) in batch) {
        completer.completeError(error, stack);
      }
    }
  }
}
