import 'package:ai_mobility_assistant/features/companion/domain/companion_models.dart';
import 'package:ai_mobility_assistant/features/journey/application/journey_session_controller.dart';
import 'package:ai_mobility_assistant/features/journey/domain/place.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('a companion command does not erase an active journey', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      journeySessionControllerProvider.notifier,
    );

    const destination = JourneyPlace(
      placeId: 'place',
      name: 'Test destination',
      address: 'Test address',
      location: LatLng(5.60, -0.18),
    );
    const route = JourneyRouteOption(
      mode: JourneyTravelMode.walking,
      duration: Duration(minutes: 8),
      distanceMeters: 500,
      path: [LatLng(5.60, -0.18), LatLng(5.61, -0.17)],
      steps: [
        JourneyStep(
          instruction: 'Continue straight',
          distanceMeters: 100,
          duration: Duration(minutes: 2),
          travelMode: JourneyTravelMode.walking,
        ),
      ],
    );

    controller.destinationConfirmed(destination);
    controller.routesReady(const [route]);
    controller.startJourney();
    controller.beginRequest('Repeat the last instruction');

    final state = container.read(journeySessionControllerProvider);
    expect(state.phase, CompanionPhase.guiding);
    expect(state.destination, destination);
    expect(state.selectedRoute, route);
    expect(state.lastInstruction, 'Continue straight');
  });
}
