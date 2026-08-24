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

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Mobility AI',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) {
        if (!useLargerText || child == null) return child ?? const SizedBox();
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(minScaleFactor: 1.30),
          ),
          child: child,
        );
      },
    );
  }
}
