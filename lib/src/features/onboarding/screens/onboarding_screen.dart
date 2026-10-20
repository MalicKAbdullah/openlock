import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/features/auth/providers/auth_providers.dart';

/// Three-page welcome shown once, before PIN setup.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage(this.icon, this.title, this.message);

  final IconData icon;
  final String title;
  final String message;
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      Icons.shield_rounded,
      'Lock the apps that matter',
      'Pick any apps on your phone and OpenLock keeps them behind your PIN '
          'or fingerprint.',
    ),
    _OnboardingPage(
      Icons.schedule_rounded,
      'Focus on your schedule',
      'Lock social apps during work hours, games during study time — set '
          'windows and OpenLock enforces them automatically.',
    ),
    _OnboardingPage(
      Icons.phonelink_lock_rounded,
      'Private by design',
      'Everything stays on this device, encrypted. No account, no cloud, '
          'no tracking.',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() =>
      ref.read(sessionProvider.notifier).completeOnboarding();

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final isLast = _index == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.gutter + AppSpacing.sm,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.sizeOf(context).height * 0.5,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (index == 0)
                                const SuiteAppIcon(
                                  app: SuiteApp.openlock,
                                  size: 88,
                                )
                              else
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.accentContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusXl,
                                    ),
                                  ),
                                  child: SizedBox(
                                    width: 88,
                                    height: 88,
                                    child: Icon(
                                      page.icon,
                                      size: 40,
                                      color: c.accent,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.xl),
                              Text(
                                '${index + 1} of ${_pages.length}',
                                style: AppTextStyles.overline.copyWith(
                                  color: c.accent,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Semantics(
                                header: true,
                                child: Text(
                                  page.title,
                                  style: AppTextStyles.display.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                page.message,
                                style: AppTextStyles.body.copyWith(
                                  color: c.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: AppMotion.fast,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? c.accent : c.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.gutter),
                  child: VaultButton(
                    label: isLast ? 'Set up my PIN' : 'Next',
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
