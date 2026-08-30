import 'package:ai_mobility_assistant/app/storage/app_storage.dart';
import 'package:ai_mobility_assistant/features/companion/domain/companion_models.dart';
import 'package:ai_mobility_assistant/features/history/application/journey_history_controller.dart';
import 'package:ai_mobility_assistant/features/journey/application/journey_session_controller.dart';
import 'package:ai_mobility_assistant/features/journey/domain/place.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const destination = JourneyPlace(
    placeId: 'memory-place',
    name: 'Memory destination',
    address: 'Accra',
    location: LatLng(5.6, -0.18),
  );
  const route = JourneyRouteOption(
    mode: JourneyTravelMode.walking,
    duration: Duration(minutes: 5),
    distanceMeters: 300,
    path: [LatLng(5.6, -0.18), LatLng(5.61, -0.17)],
    providerRouteId: 'route-memory',
    steps: [
      JourneyStep(
        instruction: 'Continue to the destination',
        distanceMeters: 300,
        duration: Duration(minutes: 5),
        travelMode: JourneyTravelMode.walking,
      ),
    ],
  );

  test(
    'conversation and active journey restore from on-device memory',
    () async {
      final storage = MemoryAppStorage();
      final first = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(storage)],
      );
      final controller = first.read(journeySessionControllerProvider.notifier);
      controller.beginRequest('Take me to my saved place');
      controller.addTurn(AssistantSpeaker.companion, 'I remember the context.');
      controller.destinationConfirmed(destination);
      controller.routesReady(const [route]);
      controller.startJourney();
      await Future<void>.delayed(Duration.zero);
      first.dispose();

      final restored = ProviderContainer(
        overrides: [appStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(restored.dispose);
      final state = restored.read(journeySessionControllerProvider);

      expect(state.destination?.placeId, destination.placeId);
      expect(state.selectedRoute?.routeKey, route.routeKey);
      expect(state.phase, CompanionPhase.guiding);
      expect(
        state.turns.map((turn) => turn.text),
        contains('I remember the context.'),
      );
    },
  );

  test('arrival records a completed journey once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      journeySessionControllerProvider.notifier,
    );
    controller.destinationConfirmed(destination);
    controller.routesReady(const [route]);
    controller.startJourney();

    controller.advanceStep();
    controller.advanceStep();

    final history = container.read(journeyHistoryControllerProvider);
    expect(history, hasLength(1));
    expect(history.single.destination, destination);
  });

  test('history privacy setting prevents journey recording', () {
    final storage = MemoryAppStorage({
      'companion.journey_history.enabled': false,
    });
    final container = ProviderContainer(
      overrides: [appStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      journeySessionControllerProvider.notifier,
    );
    controller.destinationConfirmed(destination);
    controller.routesReady(const [route]);
    controller.startJourney();

    controller.advanceStep();

    expect(container.read(journeyHistoryControllerProvider), isEmpty);
  });
}
