import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_storage/core_storage.dart';
import 'package:openlock/src/core/clock.dart';
import 'package:openlock/src/core/interfaces/key_derivation.dart';
import 'package:openlock/src/core/storage_keys.dart';
import 'package:openlock/src/features/auth/services/pin_hasher.dart';

/// Result of a PIN unlock attempt against the app itself (opening OpenLock).
sealed class UnlockResult {
  const UnlockResult();
}

final class UnlockSuccess extends UnlockResult {
  const UnlockSuccess();
}

final class UnlockWrongPin extends UnlockResult {
  const UnlockWrongPin({required this.failedAttempts, this.cooldown});

  final int failedAttempts;

  /// Non-null when this failure triggered a lockout.
  final Duration? cooldown;
}

final class UnlockCoolingDown extends UnlockResult {
  const UnlockCoolingDown({required this.remaining});

  final Duration remaining;
}

/// Owns the unlock PIN for the OpenLock app itself: setup, verification,
/// change, and an escalating wrong-attempt cooldown. The same verifier hash it
/// stores is pushed to the native layer so the on-top LockActivity checks the
/// identical PIN.
///
/// A recovery key resets a forgotten PIN: only an Argon2id verifier of its
/// canonical form is stored, and recovery attempts share the PIN cooldown.
final class PinAuthService {
  PinAuthService({
    required ISecureStorage storage,
    required PinHasher hasher,
    required IKeyDerivation keyDerivation,
    required Clock clock,
  })  : _storage = storage,
        _hasher = hasher,
        _kdf = keyDerivation,
        _clock = clock;

  final ISecureStorage _storage;
  final PinHasher _hasher;
  final IKeyDerivation _kdf;
  final Clock _clock;

  static const int minPinLength = 6;
  static const int maxFreeAttempts = 5;
  static const Duration baseCooldown = Duration(seconds: 30);
  static const Duration maxCooldown = Duration(minutes: 15);

  Future<bool> hasPin() async =>
      await _storage.read(key: OpenLockKeys.pinHash) != null;

  /// The stored verifier hash and salt (base64), or null before setup. Used
  /// when assembling the native config map.
  Future<({String hash, String salt})?> verifier() async {
    final hash = await _storage.read(key: OpenLockKeys.pinHash);
    final salt = await _storage.read(key: OpenLockKeys.pinSalt);
    if (hash == null || salt == null) return null;
    return (hash: hash, salt: salt);
  }

  /// Creates the PIN on first run.
  Future<void> setupPin(String pin) async {
    assert(pin.length >= minPinLength, 'PIN must be at least 6 digits');
    final salt = _hasher.newSalt();
    final hash = await _hasher.hash(pin: pin, salt: salt);
    await _storage.write(key: OpenLockKeys.pinHash, value: hash);
    await _storage.write(key: OpenLockKeys.pinSalt, value: base64Encode(salt));
    await _resetAttempts();
  }

  /// Attempts to unlock with [pin], enforcing the escalating cooldown.
  Future<UnlockResult> unlock(String pin) async {
    final v = await verifier();
    if (v == null) throw StateError('No PIN configured');
    final salt = Uint8List.fromList(base64Decode(v.salt));
    return _attempt(
      () => _hasher.verify(pin: pin, salt: salt, expectedHash: v.hash),
    );
  }

  Future<bool> hasRecoveryKey() async =>
      await _storage.read(key: OpenLockKeys.recoveryVerifier) != null;

  /// Creates a recovery key, replacing any earlier one (which stops working),
  /// and returns it in display form. It is never stored — show it now.
  Future<String> createRecoveryKey() async {
    final key = RecoveryKey.generate();
    final salt = _hasher.newSalt();
    final hash = await _kdf.deriveKey(
      passphrase: RecoveryKey.normalize(key)!,
      salt: salt,
    );
    await _storage.write(
      key: OpenLockKeys.recoveryVerifier,
      value: '${base64Encode(salt)}:${base64Encode(hash)}',
    );
    return key;
  }

  /// Whether existing users should get the one-time recovery-key offer: no
  /// key yet and never offered.
  Future<bool> recoveryOfferDue() async =>
      !await hasRecoveryKey() &&
      await _storage.read(key: OpenLockKeys.recoveryOffered) != 'true';

  Future<void> markRecoveryOffered() =>
      _storage.write(key: OpenLockKeys.recoveryOffered, value: 'true');

  /// Forgotten PIN: when [recoveryKey] matches, stores [newPin] (fresh salt
  /// and hash; push the config to native afterwards). Shares the cooldown.
  Future<UnlockResult> resetWithRecoveryKey({
    required String recoveryKey,
    required String newPin,
  }) async {
    assert(newPin.length >= minPinLength, 'PIN must be at least 6 digits');
    final result = await _attempt(() async {
      final stored = await _storage.read(key: OpenLockKeys.recoveryVerifier);
      final normalized = RecoveryKey.normalize(recoveryKey);
      if (stored == null || normalized == null) return false;
      final parts = stored.split(':');
      final actual = await _kdf.deriveKey(
        passphrase: normalized,
        salt: Uint8List.fromList(base64Decode(parts[0])),
      );
      return _constantTimeEquals(actual, base64Decode(parts[1]));
    });
    if (result is UnlockSuccess) await setupPin(newPin);
    return result;
  }

  Future<UnlockResult> _attempt(Future<bool> Function() check) async {
    final remaining = await cooldownRemaining();
    if (remaining > Duration.zero) {
      return UnlockCoolingDown(remaining: remaining);
    }
    if (await check()) {
      await _resetAttempts();
      return const UnlockSuccess();
    }

    final attempts = await _failedAttempts() + 1;
    await _storage.write(
      key: OpenLockKeys.failedAttempts,
      value: attempts.toString(),
    );

    Duration? cooldown;
    if (attempts >= maxFreeAttempts) {
      cooldown = cooldownFor(attempts);
      final until = _clock.now().add(cooldown);
      await _storage.write(
        key: OpenLockKeys.lockoutUntil,
        value: until.millisecondsSinceEpoch.toString(),
      );
    }
    return UnlockWrongPin(failedAttempts: attempts, cooldown: cooldown);
  }

  /// Escalating cooldown: 30s at the 5th failure, doubling per extra failure,
  /// capped at 15 minutes.
  static Duration cooldownFor(int failedAttempts) {
    if (failedAttempts < maxFreeAttempts) return Duration.zero;
    final exponent = failedAttempts - maxFreeAttempts;
    var seconds = baseCooldown.inSeconds;
    for (var i = 0; i < exponent; i++) {
      seconds *= 2;
      if (seconds >= maxCooldown.inSeconds) return maxCooldown;
    }
    return Duration(seconds: seconds);
  }

  Future<Duration> cooldownRemaining() async {
    final raw = await _storage.read(key: OpenLockKeys.lockoutUntil);
    if (raw == null) return Duration.zero;
    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
    final diff = until.difference(_clock.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Verifies [pin] against the stored verifier WITHOUT touching the
  /// wrong-attempt cooldown. Used by in-app re-auth gates (e.g. confirming
  /// deactivation of uninstall protection), where the app-open lockout should
  /// not be affected.
  Future<bool> verifyPin(String pin) async {
    final v = await verifier();
    if (v == null) return false;
    final salt = Uint8List.fromList(base64Decode(v.salt));
    return _hasher.verify(pin: pin, salt: salt, expectedHash: v.hash);
  }

  /// Changes the PIN: verifies [oldPin], then stores a fresh salt + hash.
  Future<UnlockResult> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    final result = await unlock(oldPin);
    if (result is! UnlockSuccess) return result;
    await setupPin(newPin);
    return const UnlockSuccess();
  }

  Future<void> eraseAll() async {
    for (final key in OpenLockKeys.all) {
      await _storage.delete(key: key);
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<int> _failedAttempts() async {
    final raw = await _storage.read(key: OpenLockKeys.failedAttempts);
    return raw == null ? 0 : int.parse(raw);
  }

  Future<void> _resetAttempts() async {
    await _storage.delete(key: OpenLockKeys.failedAttempts);
    await _storage.delete(key: OpenLockKeys.lockoutUntil);
  }
}
