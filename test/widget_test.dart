import 'package:ai_mobility_assistant/app/app.dart';
import 'package:ai_mobility_assistant/features/auth/data/auth_repository.dart';
import 'package:ai_mobility_assistant/features/preferences/data/mobility_preferences_repository.dart';
import 'package:ai_mobility_assistant/features/voice/data/voice_preferences_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('fresh install can onboard and continue as a guest', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = MobilityPreferencesRepository(
      await SharedPreferences.getInstance(),
    );
    final auth = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobilityPreferencesRepositoryProvider.overrideWithValue(repository),
          voicePreferencesRepositoryProvider.overrideWithValue(
            VoicePreferencesRepository(await SharedPreferences.getInstance()),
          ),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const MobilityAiApp(),
      ),
    );

    expect(find.text('Mobility AI'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text('Move with more confidence'), findsOneWidget);

    await tester.tap(find.byKey(const Key('skip_onboarding_button')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    final guestButton = find.byKey(const Key('continue_as_guest_button'));
    await tester.ensureVisible(guestButton);
    await tester.tap(guestButton);
    await tester.pumpAndSettle();
    expect(find.text('What matters most?').hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile_setup_continue_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('What makes travel easier?').hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.text('Shorter walking').hitTestable());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile_setup_continue_button')));
    await tester.pumpAndSettle();
    expect(find.text('Choose your signals').hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile_setup_back_button')));
    await tester.pumpAndSettle();
    expect(
      find.text('What makes travel easier?').hitTestable(),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('profile_setup_continue_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile_setup_continue_button')));
    await tester.pumpAndSettle();
    expect(find.text('Ready to go').hitTestable(), findsOneWidget);

    final saveButton = find.byKey(const Key('save_preferences_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('How can I help you move?'), findsOneWidget);
    expect(find.text('Talk to Mobility AI'), findsOneWidget);
    expect(
      find.byKey(const Key('companion_microphone_button')),
      findsOneWidget,
    );
    expect((await repository.load()).reducedWalking, isTrue);
    expect(repository.hasCompletedIntro, isTrue);
    expect(repository.isProfileComplete, isTrue);
    expect(auth.currentUser?.isGuest, isTrue);

    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Guest traveler'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Travel history'), findsOneWidget);
    expect(find.text('No journeys yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Travel profile'));
    await tester.pumpAndSettle();
    expect(find.text('Route priority'), findsOneWidget);
    expect(find.text('Mobility'), findsOneWidget);
    expect(find.text('Guidance'), findsOneWidget);
    expect(
      find.byKey(const Key('profile_setup_continue_button')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('profile_setup_back_button')));
    await tester.pumpAndSettle();

    final safetyLink = find.text('Safety and privacy');
    await tester.scrollUntilVisible(safetyLink, 120);
    await tester.pumpAndSettle();
    await tester.tap(safetyLink);
    await tester.pumpAndSettle();
    expect(find.text('Safety and privacy'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    final settingsLink = find.text('Settings');
    await tester.scrollUntilVisible(settingsLink, -120);
    await tester.pumpAndSettle();
    await tester.tap(settingsLink);
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsNothing);
    expect(find.text('Clear map cache'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guest traveler'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('continue_as_guest_button')), findsNothing);
  });
}

class _FakeAuthRepository implements AuthRepository {
  AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_user);

  @override
  Future<AppUser> continueAsGuest() async {
    return _user = const AppUser(id: 'guest', isGuest: true);
  }

  @override
  Future<AppUser> createAccount({
    required String email,
    required String password,
  }) async {
    return _user = AppUser(id: 'account', isGuest: false, email: email);
  }

  @override
  Future<AppUser> upgradeGuest({
    required String email,
    required String password,
  }) async {
    return _user = AppUser(id: 'account', isGuest: false, email: email);
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return _user = AppUser(id: 'account', isGuest: false, email: email);
  }

  @override
  Future<void> signOut() async {
    _user = null;
  }

  @override
  Future<String?> idToken() async => _user == null ? null : 'test-token';
}
