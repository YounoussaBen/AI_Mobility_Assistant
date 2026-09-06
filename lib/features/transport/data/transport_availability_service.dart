import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../journey/domain/accra_operating_area.dart';
import '../../journey/domain/route_option.dart';

final transportAvailabilityServiceProvider =
    Provider<TransportAvailabilityService>(
      (ref) => TransportAvailabilityService(),
    );

/// Selects actual routed transport options. Routing does not book a vehicle or
/// establish live dispatch availability, fares, or pickup waiting times.
class TransportAvailabilityService {
  Future<List<JourneyRouteOption>> search({
    required LatLng origin,
    required LatLng destination,
    required List<JourneyRouteOption> baseRoutes,
  }) async {
    if (!AccraOperatingArea.contains(origin) ||
        !AccraOperatingArea.contains(destination)) {
      return const [];
    }
    return baseRoutes
        .where(
          (route) =>
              !route.isSimulated &&
              route.availability != RouteAvailability.unavailable &&
              route.path.isNotEmpty &&
              AccraOperatingArea.containsRoute(route.path) &&
              (route.mode == JourneyTravelMode.transit ||
                  route.mode == JourneyTravelMode.driving),
        )
        .toList();
  }
}
