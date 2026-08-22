import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/preferences/presentation/mobility_preferences_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const OnboardingScreen()),
      ),
      GoRoute(
        path: '/auth',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const AuthScreen()),
      ),
      GoRoute(
        path: '/preferences',
        pageBuilder: (context, state) => _appPage(
          state: state,
          child: MobilityPreferencesScreen(
            isEditing: state.uri.queryParameters['edit'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const HomeScreen()),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

CustomTransitionPage<void> _appPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;

      final entering = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic));
      final leaving = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.10, 0),
      ).chain(CurveTween(curve: Curves.easeOutCubic));

      return SlideTransition(
        position: secondaryAnimation.drive(leaving),
        child: SlideTransition(
          position: animation.drive(entering),
          child: child,
        ),
      );
    },
  );
}
