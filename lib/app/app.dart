import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/preferences/application/mobility_preferences_controller.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class MobilityAiApp extends ConsumerWidget {
  const MobilityAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final preferences = ref.watch(mobilityPreferencesControllerProvider);
    final useLargerText = preferences.value?.largerText ?? false;

    ThemeData scale(ThemeData theme) => useLargerText
        ? theme.copyWith(textTheme: theme.textTheme.apply(fontSizeFactor: 1.12))
        : theme;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Mobility AI',
      theme: scale(AppTheme.light),
      darkTheme: scale(AppTheme.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
