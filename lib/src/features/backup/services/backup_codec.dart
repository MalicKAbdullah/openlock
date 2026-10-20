import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:openlock/src/core/clock.dart';
import 'package:openlock/src/core/interfaces/key_derivation.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';

/// Why a backup could not be read.
enum BackupError { invalidFormat, unsupportedVersion, wrongPassphrase }

final class BackupException implements Exception {
  const BackupException(this.error);

  final BackupError error;

  @override
  String toString() => 'BackupException($error)';
}

/// Encrypted `.olbackup` export/import of the OpenLock [LockConfig].
///
/// The file is a JSON envelope `{formatVersion, app, appVersion, createdAt,
/// salt, nonce, ciphertext}` where the ciphertext is the config JSON encrypted
/// with AES-256-GCM under an Argon2id key derived from a user-chosen backup
/// passphrase (independent of the unlock PIN). The passphrase alone restores
/// everything; the file is useless to anyone else.
final class BackupCodec {
  const BackupCodec({
    required IKeyDerivation keyDerivation,
    required CipherService cipher,
    required Future<String> Function() appVersion,
    required Clock clock,
  })  : _kdf = keyDerivation,
        _cipher = cipher,
        _appVersion = appVersion,
        _clock = clock;

  final IKeyDerivation _kdf;
  final CipherService _cipher;
  final Future<String> Function() _appVersion;
  final Clock _clock;

  static const int formatVersion = 1;
  static const String fileExtension = 'olbackup';
  static const int minPassphraseLength = 8;

  Future<String> export({
    required LockConfig config,
    required String passphrase,
  }) async {
    final salt = await _cipher.generateSalt();
    final key = await _kdf.deriveKey(passphrase: passphrase, salt: salt);
    final plaintext = jsonEncode(config.toJson());
    final payload = await _cipher.encrypt(
      plaintext: plaintext,
      keyBytes: key,
      salt: salt,
    );
    key.fillRange(0, key.length, 0);
    return jsonEncode({
      'formatVersion': formatVersion,
      'app': 'openlock',
      'appVersion': await _appVersion(),
      'createdAt': _clock.now().toIso8601String(),
      'salt': base64Encode(salt),
      'nonce': base64Encode(payload.nonce),
      'ciphertext': base64Encode(payload.ciphertext),
    });
  }

  Future<LockConfig> decode({
    required String raw,
    required String passphrase,
  }) async {
    final Uint8List salt;
    final Uint8List nonce;
    final Uint8List ciphertext;
    final int? version;
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      version = envelope['formatVersion'] as int?;
      salt = base64Decode(envelope['salt'] as String);
      nonce = base64Decode(envelope['nonce'] as String);
      ciphertext = base64Decode(envelope['ciphertext'] as String);
    } catch (_) {
      throw const BackupException(BackupError.invalidFormat);
    }
    if (version == null || version > formatVersion) {
      throw const BackupException(BackupError.unsupportedVersion);
    }

    final key = await _kdf.deriveKey(passphrase: passphrase, salt: salt);
    final String plaintext;
    try {
      plaintext = await _cipher.decrypt(
        payload: EncryptedPayload(
          ciphertext: ciphertext,
          nonce: nonce,
          salt: salt,
        ),
        keyBytes: key,
      );
    } catch (_) {
      throw const BackupException(BackupError.wrongPassphrase);
    } finally {
      key.fillRange(0, key.length, 0);
    }

    try {
      return LockConfig.fromJson(jsonDecode(plaintext) as Map<String, dynamic>);
    } catch (_) {
      throw const BackupException(BackupError.invalidFormat);
    }
  }

  static String suggestedFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'openlock-${now.year}-${two(now.month)}-${two(now.day)}'
        '.$fileExtension';
  }
}
