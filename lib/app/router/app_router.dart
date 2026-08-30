import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/journey/presentation/journey_planner_screen.dart';
import '../../features/journey/presentation/active_journey_screen.dart';
import '../../features/perception/presentation/look_ahead_screen.dart';
import '../../features/voice/presentation/voice_guidance_screen.dart';
import '../../features/home/presentation/menu_screen.dart';
import '../../features/home/presentation/profile_screen.dart';
import '../../features/home/presentation/safety_privacy_screen.dart';
import '../../features/home/presentation/settings_screen.dart';
import '../../features/home/presentation/travel_history_screen.dart';
import '../../features/home/presentation/support_screen.dart';
import '../../features/saved_places/presentation/saved_places_screen.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/preferences/presentation/mobility_preferences_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/companion/domain/companion_models.dart';
import '../../features/journey/application/journey_session_controller.dart';
import '../integrations/system_shortcut_service.dart';

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
        pageBuilder: (context, state) => _appPage(
          state: state,
          child: AuthScreen(
            startInCreateMode: state.uri.queryParameters['mode'] == 'create',
            isGuestUpgrade: state.uri.queryParameters['upgrade'] == 'true',
          ),
        ),
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
        pageBuilder: (context, state) => _appPage(
          state: state,
          child: HomeScreen(
            startWithVoice: state.uri.queryParameters['voice'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/plan',
        pageBuilder: (context, state) => _appPage(
          state: state,
          child: JourneyPlannerScreen(
            startWithVoice: state.uri.queryParameters['voice'] == 'true',
            initialPrompt: state.uri.queryParameters['prompt'],
            resumeDestination:
                state.uri.queryParameters['resumeDestination'] == 'true',
            reroute: state.uri.queryParameters['reroute'] == 'true',
            transportOnly: state.uri.queryParameters['transport'] == 'true',
          ),
        ),
      ),
      GoRoute(
        path: '/guidance',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const ActiveJourneyScreen()),
      ),
      GoRoute(
        path: '/look-ahead',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const LookAheadScreen()),
      ),
      GoRoute(
        path: '/voice-guidance',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const VoiceGuidanceScreen()),
      ),
      GoRoute(
        path: '/menu',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const MenuScreen()),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const ProfileScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const SettingsScreen()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const TravelHistoryScreen()),
      ),
      GoRoute(
        path: '/saved-places',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const SavedPlacesScreen()),
      ),
      GoRoute(
        path: '/support',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const SupportScreen()),
      ),
      GoRoute(
        path: '/safety-privacy',
        pageBuilder: (context, state) =>
            _appPage(state: state, child: const SafetyPrivacyScreen()),
      ),
    ],
  );

  final shortcuts = ref.watch(systemShortcutServiceProvider);
  final shortcutSubscription = shortcuts.actions.listen((action) {
    final session = ref.read(journeySessionControllerProvider);
    switch (action) {
      case SystemShortcutAction.talk:
        router.go('/home?voice=true');
      case SystemShortcutAction.guidance:
        router.go(session.hasActiveJourney ? '/guidance' : '/home');
      case SystemShortcutAction.lens:
        if (session.hasActiveJourney) {
          ref
              .read(journeySessionControllerProvider.notifier)
              .setGuidanceView(GuidanceView.lookAhead);
          router.go('/guidance');
        } else {
          router.go('/look-ahead');
        }
    }
  });
  unawaited(shortcuts.initialize());

  ref.onDispose(shortcutSubscription.cancel);
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
