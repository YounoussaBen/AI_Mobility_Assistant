import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:ai_mobility_assistant/features/transport/data/transport_availability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const origin = LatLng(5.60, -0.18);
  const destination = LatLng(5.64, -0.15);
  final service = TransportAvailabilityService();
  test(
    'missing transport evidence produces no invented vehicles or routes',
    () async {
      expect(
        await service.search(
          origin: origin,
          destination: destination,
          baseRoutes: [],
        ),
        isEmpty,
      );
    },
  );
  test(
    'returns only actual car/transit routes without invented price or wait',
    () async {
      const car = JourneyRouteOption(
        mode: JourneyTravelMode.driving,
        duration: Duration(minutes: 12),
        distanceMeters: 5000,
        path: [origin, destination],
      );
      final result = await service.search(
        origin: origin,
        destination: destination,
        baseRoutes: [
          car,
          car.copyWith(source: JourneyEvidenceSource.simulated),
          car.copyWith(mode: JourneyTravelMode.walking),
          car.copyWith(availability: RouteAvailability.unavailable),
        ],
      );
      expect(result, [car]);
      expect(result.single.fareMinorUnits, isNull);
      expect(result.single.waitingTime, isNull);
      expect(result.single.isRequestable, isFalse);
    },
  );
}
