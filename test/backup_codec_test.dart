import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlock/src/features/backup/services/backup_codec.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/models/relock_policy.dart';
import 'package:openlock/src/features/schedules/models/lock_schedule.dart';

import 'helpers/fakes.dart';

void main() {
  late BackupCodec codec;

  setUp(() {
    codec = BackupCodec(
      keyDerivation: const FakeKeyDerivation(),
      cipher: const CipherService(),
      appVersion: () async => '9.9.9',
      clock: FakeClock(DateTime(2026, 7, 8)),
    );
  });

  LockConfig config() => LockConfig(
        lockedPackages: {'com.social'},
        relock: const RelockPolicy(mode: RelockMode.onScreenOff),
        randomizeKeypad: true,
        schedules: [
          LockSchedule(
            id: 's1',
            name: 'Work',
            packages: {'com.social'},
            weekdays: {1, 2, 3},
            startMinutes: 540,
            endMinutes: 1020,
          ),
        ],
      );

  test('export then decode with the right passphrase round-trips', () async {
    final raw =
        await codec.export(config: config(), passphrase: 'correct horse');
    final restored = await codec.decode(raw: raw, passphrase: 'correct horse');

    expect(restored.lockedPackages, {'com.social'});
    expect(restored.relock.mode, RelockMode.onScreenOff);
    expect(restored.randomizeKeypad, isTrue);
    expect(restored.schedules.single.name, 'Work');
  });

  test('wrong passphrase throws wrongPassphrase', () async {
    final raw = await codec.export(config: config(), passphrase: 'right-one');
    expect(
      () => codec.decode(raw: raw, passphrase: 'WRONG'),
      throwsA(
        isA<BackupException>()
            .having((e) => e.error, 'error', BackupError.wrongPassphrase),
      ),
    );
  });

  test('garbage input throws invalidFormat', () async {
    expect(
      () => codec.decode(raw: 'not json', passphrase: 'x'),
      throwsA(
        isA<BackupException>()
            .having((e) => e.error, 'error', BackupError.invalidFormat),
      ),
    );
  });

  test('a newer format version is rejected', () async {
    const envelope =
        '{"formatVersion":99,"salt":"AAAA","nonce":"AAAA","ciphertext":"AAAA"}';
    expect(
      () => codec.decode(raw: envelope, passphrase: 'x'),
      throwsA(
        isA<BackupException>()
            .having((e) => e.error, 'error', BackupError.unsupportedVersion),
      ),
    );
  });

  test('suggestedFileName uses the .olbackup extension', () {
    final name = BackupCodec.suggestedFileName(DateTime(2026, 7, 8));
    expect(name, 'openlock-2026-07-08.olbackup');
  });
}
