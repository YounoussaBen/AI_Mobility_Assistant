import 'package:ai_mobility_assistant/app/storage/app_storage.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:ai_mobility_assistant/features/transport/data/transport_availability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test(
    'prototype provider options and requests are unmistakably simulated',
    () async {
      final service = SimulatedTransportAvailabilityService(MemoryAppStorage());
      final routes = await service.search(
        origin: const LatLng(5.60, -0.18),
        destination: const LatLng(5.64, -0.15),
        baseRoutes: const [],
      );

      expect(
        routes.where((route) => route.mode == JourneyTravelMode.onDemand),
        hasLength(2),
      );
      expect(
        routes.every(
          (route) => route.source == JourneyEvidenceSource.simulated,
        ),
        isTrue,
      );
      expect(routes.every((route) => route.fareMinorUnits != null), isTrue);
      expect(routes.every((route) => route.waitingTime != null), isTrue);

      final request = await service.request(routes.first);
      expect(request.simulated, isTrue);
      expect(request.message, contains('No real vehicle'));
    },
  );
}
