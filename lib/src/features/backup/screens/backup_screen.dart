import 'dart:io';

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/di.dart';
import 'package:openlock/src/features/backup/services/backup_codec.dart';
import 'package:openlock/src/features/enforcement/models/lock_config.dart';
import 'package:openlock/src/features/enforcement/providers/config_providers.dart';
import 'package:path_provider/path_provider.dart';

/// Minimal, dependency-light backup: export writes an encrypted `.olbackup`
/// file into app storage and reports the path; import reads that file back with
/// the passphrase. (A share-sheet / file-picker flow can be layered on later.)
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _passphraseController = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  Future<File> _backupFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/openlock_backup.olbackup');
  }

  Future<void> _export() async {
    final passphrase = _passphraseController.text;
    if (passphrase.length < BackupCodec.minPassphraseLength) {
      setState(() => _status = 'Use a passphrase of at least 8 characters');
      return;
    }
    setState(() => _busy = true);
    final config =
        ref.read(configControllerProvider).valueOrNull ?? LockConfig.empty;
    final raw = await ref
        .read(backupCodecProvider)
        .export(config: config, passphrase: passphrase);
    final file = await _backupFile();
    await file.writeAsString(raw, flush: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = 'Exported to ${file.path}';
    });
  }

  Future<void> _import() async {
    final passphrase = _passphraseController.text;
    setState(() => _busy = true);
    try {
      final file = await _backupFile();
      if (!file.existsSync()) {
        setState(() {
          _busy = false;
          _status = 'No backup file found to import';
        });
        return;
      }
      final raw = await file.readAsString();
      final config = await ref
          .read(backupCodecProvider)
          .decode(raw: raw, passphrase: passphrase);
      await ref.read(configControllerProvider.notifier).replace(config);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Backup restored';
      });
    } on BackupException catch (e) {
      final message = switch (e.error) {
        BackupError.wrongPassphrase => 'Wrong passphrase',
        BackupError.unsupportedVersion => 'Backup from a newer version',
        BackupError.invalidFormat => 'That file is not a valid backup',
      };
      setState(() {
        _busy = false;
        _status = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your backup is encrypted with a passphrase you choose — '
                'separate from your unlock PIN. Keep it safe: without it the '
                'backup cannot be restored.',
                style:
                    AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Backup passphrase',
                controller: _passphraseController,
                obscureText: true,
              ),
              const SizedBox(height: AppSpacing.mdl),
              VaultButton(
                label: 'Export encrypted backup',
                isLoading: _busy,
                onPressed: _export,
              ),
              const SizedBox(height: AppSpacing.sm),
              VaultButton(
                label: 'Restore from backup',
                variant: VaultButtonVariant.secondary,
                onPressed: _busy ? null : _import,
              ),
              if (_status != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppBanner(title: _status!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
