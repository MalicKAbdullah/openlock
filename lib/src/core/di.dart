import 'package:core_crypto/core_crypto.dart';
import 'package:core_storage/core_storage.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openlock/src/core/app_info.dart';
import 'package:openlock/src/core/clock.dart';
import 'package:openlock/src/core/interfaces/biometric_auth.dart';
import 'package:openlock/src/core/interfaces/config_file_store.dart';
import 'package:openlock/src/core/interfaces/enforcement_bridge.dart';
import 'package:openlock/src/core/interfaces/key_derivation.dart';
import 'package:openlock/src/core/services/method_channel_enforcement_bridge.dart';
import 'package:openlock/src/features/auth/services/biometric_service.dart';
import 'package:openlock/src/features/auth/services/pin_auth_service.dart';
import 'package:openlock/src/features/auth/services/pin_hasher.dart';
import 'package:openlock/src/features/backup/services/backup_codec.dart';
import 'package:openlock/src/features/enforcement/services/config_repository.dart';

/// Composition root. Tests override the leaf providers (storage, file store,
/// clock, biometrics, enforcement bridge) with in-memory fakes — no platform
/// channels.
final clockProvider = Provider<Clock>((_) => const SystemClock());

final secureStorageProvider = Provider<ISecureStorage>(
  (_) => const SecureStorageImpl(FlutterSecureStorage()),
);

final cipherServiceProvider = Provider<CipherService>(
  (_) => const CipherService(),
);

final keyDerivationProvider = Provider<IKeyDerivation>(
  (_) => const Argon2KeyDerivation(KeyDerivationService()),
);

final pinHasherProvider = Provider<PinHasher>((_) => const PinHasher());

final configFileStoreProvider = Provider<IConfigFileStore>(
  (_) => const DocumentsConfigFileStore(),
);

final enforcementBridgeProvider = Provider<IEnforcementBridge>(
  (_) => const MethodChannelEnforcementBridge(),
);

final biometricAuthProvider = Provider<IBiometricAuth>(
  (_) => LocalAuthBiometric(),
);

final pinAuthServiceProvider = Provider<PinAuthService>(
  (ref) => PinAuthService(
    storage: ref.watch(secureStorageProvider),
    hasher: ref.watch(pinHasherProvider),
    keyDerivation: ref.watch(keyDerivationProvider),
    clock: ref.watch(clockProvider),
  ),
);

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(
    storage: ref.watch(secureStorageProvider),
    biometric: ref.watch(biometricAuthProvider),
  ),
);

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    storage: ref.watch(secureStorageProvider),
    cipher: ref.watch(cipherServiceProvider),
    fileStore: ref.watch(configFileStoreProvider),
  ),
);

final backupCodecProvider = Provider<BackupCodec>(
  (ref) => BackupCodec(
    keyDerivation: ref.watch(keyDerivationProvider),
    cipher: ref.watch(cipherServiceProvider),
    appVersion: () => ref.read(appVersionProvider.future),
    clock: ref.watch(clockProvider),
  ),
);

// -- In-app update (core_update) ------------------------------------------

/// Secure-storage key for the auto-check preference.
const String updateAutoCheckKey = 'openlock_update_autocheck';

final updateServiceProvider = Provider<IUpdateService>(
  (_) => GithubUpdateService(owner: 'MalicKAbdullah', repo: 'openlock'),
);

/// Auto-check preference (persisted; on by default). Toggle in Settings.
final updateAutoCheckProvider = FutureProvider<bool>(
  (ref) async =>
      await ref.watch(secureStorageProvider).read(key: updateAutoCheckKey) !=
      'false',
);

/// The pending update (null when disabled, up to date, or offline).
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (!await ref.watch(updateAutoCheckProvider.future)) return null;
  return ref.watch(updateServiceProvider).check();
});

/// Session-only dismissal of the update banner.
final updateDismissedProvider = StateProvider<bool>((_) => false);
