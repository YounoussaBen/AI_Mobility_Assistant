import 'package:ai_mobility_assistant/app/theme/app_theme.dart';
import 'package:ai_mobility_assistant/app/integrations/native_map_configuration.dart';
import 'package:ai_mobility_assistant/features/auth/data/auth_repository.dart';
import 'package:ai_mobility_assistant/features/journey/application/journey_session_controller.dart';
import 'package:ai_mobility_assistant/features/journey/domain/accra_operating_area.dart';
import 'package:ai_mobility_assistant/features/journey/domain/place.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:ai_mobility_assistant/features/journey/presentation/active_journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async {
            if (call.method == 'isLocationServiceEnabled') return false;
            if (call.method == 'checkPermission') return 3;
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  testWidgets('active guidance keeps conversation inside the journey', (
    tester,
  ) async {
    final container = _activeJourneyContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ActiveJourneyScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Test destination'), findsOneWidget);
    expect(find.text('Ask Mobility'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.cameraTargetBounds.bounds, AccraOperatingArea.bounds);

    await tester.tap(find.byKey(const Key('journey_companion_capsule')));
    await tester.pumpAndSettle();

    expect(find.text('Guidance continues while we talk'), findsOneWidget);
    expect(find.text('Why this route?'), findsOneWidget);
    expect(
      container.read(journeySessionControllerProvider).destination?.name,
      'Test destination',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('active guidance remains usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = _activeJourneyContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ActiveJourneyScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('journey_companion_capsule')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active guidance does not construct an unavailable native map', (
    tester,
  ) async {
    final container = _activeJourneyContainer(mapAvailable: false);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ActiveJourneyScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GoogleMap), findsNothing);
    expect(find.text('Guidance is still active'), findsOneWidget);
    expect(find.text('Test destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _activeJourneyContainer({bool mapAvailable = true}) {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_JourneyTestAuth()),
      nativeMapAvailableProvider.overrideWithValue(mapAvailable),
    ],
  );
  final controller = container.read(journeySessionControllerProvider.notifier);
  const destination = JourneyPlace(
    placeId: 'destination',
    name: 'Test destination',
    address: 'Test address',
    location: LatLng(5.61, -0.18),
  );
  const route = JourneyRouteOption(
    mode: JourneyTravelMode.walking,
    duration: Duration(minutes: 12),
    distanceMeters: 900,
    path: [LatLng(5.60, -0.19), LatLng(5.61, -0.18)],
    steps: [
      JourneyStep(
        instruction: 'Continue straight toward the junction',
        distanceMeters: 250,
        duration: Duration(minutes: 4),
        travelMode: JourneyTravelMode.walking,
      ),
      JourneyStep(
        instruction: 'Turn left at the junction',
        distanceMeters: 650,
        duration: Duration(minutes: 8),
        travelMode: JourneyTravelMode.walking,
        maneuver: 'turn_left',
      ),
    ],
  );
  controller.destinationConfirmed(destination);
  controller.routesReady(const [route]);
  controller.startJourney();
  return container;
}

class _JourneyTestAuth implements AuthRepository {
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
