import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Launch and unlock timing lines (`openlock.startup`) in debug and profile
/// builds, measured from the start of `main()`.
abstract final class PerfLog {
  static final Stopwatch _sinceLaunch = Stopwatch()..start();

  static void mark(String event) {
    if (kReleaseMode) return;
    developer.log(
      '$event ${_sinceLaunch.elapsedMilliseconds} ms',
      name: 'openlock.startup',
    );
  }
}
