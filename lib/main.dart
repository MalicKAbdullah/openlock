import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openlock/src/app.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/core/perf_log.dart';
import 'package:openlock/src/features/apps/providers/apps_providers.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:openlock/src/features/intruder/providers/intruder_providers.dart';

Future<void> main() async {
  PerfLog.mark('main');
  WidgetsFlutterBinding.ensureInitialized();

  // One bulk secure-storage read serves every later read (PIN verifier,
  // flags, cooldown, config key). OpenLock is the only writer of its
  // flutter_secure_storage keys (the native ConfigStore keeps its own prefs
  // file), and no value waits for a user gesture: the fingerprint only gates
  // entry, and the config key is random, not derived from the PIN.
  final storage = await CachedSecureStorage.load(
    const SecureStorageImpl(FlutterSecureStorage()),
  );
  final container = ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(storage)],
  );
  // The first frame is already the right gate (unlock, setup or intro), and
  // the unlock screen knows whether to prompt for a fingerprint.
  await container.read(sessionProvider.notifier).resolved;
  PerfLog.mark('secure storage ready');

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OpenLockApp(),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => PerfLog.mark('first frame'),
  );

  // Home's data loads while the unlock prompt is up, so it is ready the
  // moment the user is in.
  container
    ..read(installedAppsProvider)
    ..read(configControllerProvider)
    ..read(intruderControllerProvider);
}
