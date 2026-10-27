import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/app_info.dart';
import 'package:openlock/src/core/widgets/screen_header.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SuiteColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: PageList(
          children: [
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Column(
                children: [
                  const SuiteAppIcon(app: SuiteApp.openlock, size: 88),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppInfo.name,
                    style: AppTextStyles.h1.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    'Version ${ref.watch(appVersionProvider).valueOrNull ?? ''}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.smd),
                  const SuiteEndorsement(),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            VaultCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_rounded, color: c.accent, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Private by design',
                        style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'OpenLock runs entirely on your device. Your lock settings '
                    'and any intruder photos are encrypted and never leave '
                    'your phone. No account, no ads, no tracking.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            VaultCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.app_blocking_outlined,
                          color: c.accent, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Removing OpenLock',
                        style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'With uninstall protection on, OpenLock is a device '
                    'administrator, so Android blocks uninstalling it directly. '
                    'To remove it yourself: open Settings in OpenLock, turn '
                    'off "Prevent uninstall" (confirm your PIN or fingerprint), '
                    'then uninstall the app normally. While protection is on, '
                    'OpenLock also guards the system app-info and device-admin '
                    'screens with the lock so no one can disable it without '
                    'your PIN.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
