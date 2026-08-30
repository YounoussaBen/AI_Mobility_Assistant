import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/storage/app_storage.dart';
import '../../journey/domain/accra_operating_area.dart';
import '../../journey/domain/route_option.dart';
import '../domain/transport_request.dart';

final transportAvailabilityServiceProvider =
    Provider<TransportAvailabilityService>((ref) {
      return SimulatedTransportAvailabilityService(
        ref.watch(appStorageProvider),
      );
    });

abstract interface class TransportAvailabilityService {
  Future<List<JourneyRouteOption>> search({
    required LatLng origin,
    required LatLng destination,
    required List<JourneyRouteOption> baseRoutes,
  });

  Future<TransportRequest> request(JourneyRouteOption route);
}

/// Controlled provider scenarios for the research prototype.
///
/// Every result carries [JourneyEvidenceSource.simulated], so the UI and the
/// model can never describe these values as a live commercial service.
class SimulatedTransportAvailabilityService
    implements TransportAvailabilityService {
  SimulatedTransportAvailabilityService(this._storage);

  static const _requestsKey = 'companion.transport_requests.v1';
  final AppStorage _storage;

  @override
  Future<List<JourneyRouteOption>> search({
    required LatLng origin,
    required LatLng destination,
    required List<JourneyRouteOption> baseRoutes,
  }) async {
    if (!AccraOperatingArea.contains(origin) ||
        !AccraOperatingArea.contains(destination)) {
      return const [];
    }
    final driving = baseRoutes
        .where((route) => route.mode == JourneyTravelMode.driving)
        .firstOrNull;
    final transit = baseRoutes
        .where((route) => route.mode == JourneyTravelMode.transit)
        .firstOrNull;
    final direct = driving ?? _directRoute(origin, destination);
    final seed =
        ((origin.latitude.abs() * 10000).round() +
            (destination.longitude.abs() * 10000).round()) %
        7;
    final now = DateTime.now();
    final options = <JourneyRouteOption>[];

    if (transit != null) {
      final wait = Duration(minutes: 6 + seed);
      options.add(
        transit.copyWith(
          providerRouteId: 'sim-bus-${transit.routeKey}',
          routeLabel: 'Walk + bus or trotro + walk',
          providerName: 'Accra pilot transit feed',
          duration: transit.duration + wait,
          fareMinorUnits: 650,
          currencyCode: 'GHS',
          waitingTime: wait,
          serviceStatus: 'Operating normally in this simulated Accra scenario',
          source: JourneyEvidenceSource.simulated,
          availability: RouteAvailability.available,
          lastUpdated: now,
        ),
      );
    }

    final sharedWait = Duration(minutes: 3 + seed);
    options.add(
      _onDemandRoute(
        direct,
        id: 'sim-shared-${direct.routeKey}',
        label: 'Shared taxi',
        provider: 'Accra pilot dispatch',
        wait: sharedWait,
        fareMinorUnits: 600 + (direct.distanceMeters * 250 ~/ 1000),
        status: 'Vehicles available in this simulated Accra scenario',
        availability: RouteAvailability.available,
        now: now,
      ),
    );
    options.add(
      _onDemandRoute(
        direct,
        id: 'sim-accessible-${direct.routeKey}',
        label: 'Wheelchair-accessible taxi',
        provider: 'Accra pilot accessible dispatch',
        wait: sharedWait + const Duration(minutes: 5),
        fareMinorUnits: 1100 + (direct.distanceMeters * 300 ~/ 1000),
        status: 'One vehicle in this simulated Accra scenario',
        availability: RouteAvailability.limited,
        now: now,
      ),
    );
    return options;
  }

  JourneyRouteOption _onDemandRoute(
    JourneyRouteOption base, {
    required String id,
    required String label,
    required String provider,
    required Duration wait,
    required int fareMinorUnits,
    required String status,
    required RouteAvailability availability,
    required DateTime now,
  }) {
    const pickupWalk = JourneyStep(
      instruction: 'Walk to the confirmed pickup point',
      distanceMeters: 80,
      duration: Duration(minutes: 2),
      travelMode: JourneyTravelMode.walking,
    );
    const finalWalk = JourneyStep(
      instruction: 'Continue from drop-off to the destination',
      distanceMeters: 30,
      duration: Duration(minutes: 1),
      travelMode: JourneyTravelMode.walking,
    );
    return base.copyWith(
      mode: JourneyTravelMode.onDemand,
      providerRouteId: id,
      routeLabel: 'Walk + $label + walk',
      providerName: provider,
      duration: base.duration + wait + const Duration(minutes: 3),
      steps: [pickupWalk, ...base.steps, finalWalk],
      walkingDistanceMeters: 110,
      transfers: 0,
      fareMinorUnits: fareMinorUnits,
      currencyCode: 'GHS',
      waitingTime: wait,
      serviceStatus: status,
      source: JourneyEvidenceSource.simulated,
      availability: availability,
      lastUpdated: now,
    );
  }

  JourneyRouteOption _directRoute(LatLng origin, LatLng destination) {
    final distance = _distanceMeters(origin, destination).round();
    final duration = Duration(minutes: math.max(4, (distance / 350).round()));
    return JourneyRouteOption(
      mode: JourneyTravelMode.driving,
      duration: duration,
      distanceMeters: distance,
      path: [origin, destination],
      steps: [
        JourneyStep(
          instruction: 'Continue to the destination',
          distanceMeters: distance,
          duration: duration,
          travelMode: JourneyTravelMode.driving,
          endLocation: destination,
        ),
      ],
      providerRouteId: 'sim-direct-$distance',
      providerName: 'Prototype route estimate',
      source: JourneyEvidenceSource.simulated,
    );
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const radius = 6371000.0;
    double radians(double value) => value * math.pi / 180;
    final lat1 = radians(a.latitude);
    final lat2 = radians(b.latitude);
    final deltaLat = lat2 - lat1;
    final deltaLon = radians(b.longitude - a.longitude);
    final h =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  @override
  Future<TransportRequest> request(JourneyRouteOption route) async {
    final now = DateTime.now();
    final request = TransportRequest(
      id: 'SIM-${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      route: route,
      status: TransportRequestStatus.confirmed,
      createdAt: now,
      message:
          'Simulated request confirmed for evaluation. No real vehicle was dispatched.',
      simulated: true,
    );
    List<dynamic> existing = [];
    final raw = _storage.readString(_requestsKey);
    if (raw != null) {
      try {
        existing = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        existing = [];
      }
    }
    await _storage.writeString(
      _requestsKey,
      jsonEncode([request.toJson(), ...existing].take(50).toList()),
    );
    return request;
  }
}
