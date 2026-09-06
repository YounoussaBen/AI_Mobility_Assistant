import 'package:ai_mobility_assistant/app/storage/app_storage.dart';
import 'package:ai_mobility_assistant/features/journey/data/route_cache_repository.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test(
    'old simulated cache evidence cannot become an offline real route',
    () async {
      final repository = RouteCacheRepository(MemoryAppStorage());
      const origin = LatLng(5.60, -0.18);
      const destination = LatLng(5.61, -0.17);
      await repository.save(origin, destination, const [
        JourneyRouteOption(
          mode: JourneyTravelMode.driving,
          duration: Duration(minutes: 5),
          distanceMeters: 1000,
          path: [origin, destination],
          source: JourneyEvidenceSource.simulated,
        ),
      ]);
      expect(repository.load(origin, destination), isEmpty);
    },
  );
  test(
    'route cache restores evidence with an explicit cached source',
    () async {
      final repository = RouteCacheRepository(MemoryAppStorage());
      const origin = LatLng(5.60, -0.18);
      const destination = LatLng(5.61, -0.17);
      const route = JourneyRouteOption(
        mode: JourneyTravelMode.walking,
        duration: Duration(minutes: 8),
        distanceMeters: 600,
        path: [origin, destination],
        providerRouteId: 'cached-route',
      );

      await repository.save(origin, destination, const [route]);
      final restored = repository.load(origin, destination);

      expect(restored, hasLength(1));
      expect(restored.single.source, JourneyEvidenceSource.cached);
      expect(restored.single.serviceStatus, contains('Saved route'));
    },
  );
}
