import 'package:ai_mobility_assistant/features/auth/data/auth_repository.dart';
import 'package:ai_mobility_assistant/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text composer closes without using a disposed controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AccessibilityTestAuth()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    final typeButton = find.widgetWithText(TextButton, 'Type');
    await tester.ensureVisible(typeButton);
    await tester.tap(typeButton);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Pause journey');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Companion home remains usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_AccessibilityTestAuth()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('companion_microphone_button')),
      findsOneWidget,
    );
    expect(find.text('Talk to Mobility AI'), findsOneWidget);

    final mic = tester.getSize(
      find.byKey(const Key('companion_microphone_button')),
    );
    expect(mic.width, greaterThanOrEqualTo(44));
    expect(mic.height, greaterThanOrEqualTo(44));
  });
}

class _AccessibilityTestAuth implements AuthRepository {
  @override
  AppUser? get currentUser => const AppUser(id: 'test', isGuest: true);

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<AppUser> continueAsGuest() async => currentUser!;

  @override
  Future<AppUser> createAccount({
    required String email,
    required String password,
  }) async => currentUser!;

  @override
  Future<String?> idToken() async => 'test-token';

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async => currentUser!;

  @override
  Future<void> signOut() async {}

  @override
  Future<AppUser> upgradeGuest({
    required String email,
    required String password,
  }) async => currentUser!;
}
