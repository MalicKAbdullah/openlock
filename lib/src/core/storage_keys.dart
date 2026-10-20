/// Secure-storage keys used by OpenLock. Namespaced to avoid clashing with
/// sibling apps that share the core packages.
abstract final class OpenLockKeys {
  /// Random AES key that encrypts the app's config file at rest.
  static const String configKey = 'openlock_config_key';

  /// PIN verifier (PBKDF2 hash, base64) and its salt (base64). Mirrored into
  /// the native EncryptedSharedPreferences so LockActivity can verify offline.
  static const String pinHash = 'openlock_pin_hash';
  static const String pinSalt = 'openlock_pin_salt';

  static const String failedAttempts = 'openlock_failed_attempts';
  static const String lockoutUntil = 'openlock_lockout_until';

  /// Argon2id verifier of the recovery key (`base64(salt):base64(hash)`) and
  /// whether its one-time offer to existing users has been shown.
  static const String recoveryVerifier = 'openlock_recovery_verifier';
  static const String recoveryOffered = 'openlock_recovery_offered';

  static const String biometricEnabled = 'openlock_biometric_enabled';
  static const String onboardingSeen = 'openlock_onboarding_seen';

  static const List<String> all = [
    configKey,
    pinHash,
    pinSalt,
    failedAttempts,
    lockoutUntil,
    recoveryVerifier,
    recoveryOffered,
    biometricEnabled,
    onboardingSeen,
  ];
}
