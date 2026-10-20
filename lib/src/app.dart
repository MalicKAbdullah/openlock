import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/core/router/app_router.dart';

class OpenLockApp extends ConsumerWidget {
  const OpenLockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'OpenLock',
      theme: AppTheme.build(Brightness.light, accent: AppAccents.openlock),
      darkTheme: AppTheme.build(Brightness.dark, accent: AppAccents.openlock),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
