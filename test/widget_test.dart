import 'package:ai_mobility_assistant/app/app.dart';
import 'package:ai_mobility_assistant/features/auth/data/auth_repository.dart';
import 'package:ai_mobility_assistant/features/preferences/data/mobility_preferences_repository.dart';
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

    expect(find.text('Good to go'), findsOneWidget);
    expect((await repository.load()).reducedWalking, isTrue);
    expect(repository.hasCompletedIntro, isTrue);
    expect(repository.isProfileComplete, isTrue);
    expect(auth.currentUser?.isGuest, isTrue);
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
}
