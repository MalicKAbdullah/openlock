import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlock/src/app.dart';
import 'package:openlock/src/core/di.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appearance = await AppearanceController.load();
  runApp(
    ProviderScope(
      overrides: [appearanceProvider.overrideWithValue(appearance)],
      child: const OpenLockApp(),
    ),
  );
}
