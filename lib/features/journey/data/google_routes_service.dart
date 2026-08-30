import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/accra_operating_area.dart';
import '../domain/route_option.dart';
import 'route_cache_repository.dart';

class GoogleRoutesService {
  GoogleRoutesService({
    required String apiKey,
    String backendUrl = '',
    Future<String?> Function()? accessToken,
    RouteCacheRepository? cacheRepository,
    Dio? dio,
  }) : _apiKey = apiKey,
       _usesBackend = backendUrl.isNotEmpty,
       _accessToken = accessToken,
       _cacheRepository = cacheRepository,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: backendUrl.isNotEmpty
                   ? backendUrl.replaceFirst(RegExp(r'/$'), '')
                   : 'https://routes.googleapis.com',
             ),
           );

  final String _apiKey;
  final bool _usesBackend;
  final Future<String?> Function()? _accessToken;
  final RouteCacheRepository? _cacheRepository;
  final Dio _dio;

  static const _googleModes = [
    JourneyTravelMode.walking,
    JourneyTravelMode.transit,
    JourneyTravelMode.driving,
    JourneyTravelMode.bicycling,
    JourneyTravelMode.twoWheeled,
  ];

  Future<List<JourneyRouteOption>> routes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (!AccraOperatingArea.contains(origin) ||
        !AccraOperatingArea.contains(destination)) {
      throw const OutsideAccraOperatingArea(
        'Routes are available only when both points are inside the Accra pilot area.',
      );
    }
    final results = await Future.wait(
      _googleModes.map(
        (mode) => _routesForMode(
          origin: origin,
          destination: destination,
          mode: mode,
        ).catchError((_) => const <JourneyRouteOption>[]),
      ),
    );
    final routes = results
        .expand((items) => items)
        .where(
          (route) =>
              route.path.isNotEmpty &&
              AccraOperatingArea.containsRoute(route.path),
        )
        .toList(growable: false);
    if (routes.isNotEmpty) {
      await _cacheRepository?.save(origin, destination, routes);
      return routes;
    }
    final cached = _cacheRepository?.load(origin, destination) ?? const [];
    return cached
        .where(
          (route) =>
              route.path.isNotEmpty &&
              AccraOperatingArea.containsRoute(route.path),
        )
        .toList(growable: false);
  }

  Future<List<JourneyRouteOption>> _routesForMode({
    required LatLng origin,
    required LatLng destination,
    required JourneyTravelMode mode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _usesBackend ? '/v1/maps/routes:compute' : '/directions/v2:computeRoutes',
      data: {
        'origin': _waypoint(origin),
        'destination': _waypoint(destination),
        'travelMode': mode.apiValue,
        if (mode == JourneyTravelMode.driving)
          'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': true,
        'languageCode': AccraOperatingArea.languageCode,
        'units': 'METRIC',
      },
      options: _usesBackend
          ? await _authenticatedOptions()
          : Options(
              headers: {
                'X-Goog-Api-Key': _apiKey,
                'X-Goog-FieldMask':
                    'routes.duration,routes.distanceMeters,'
                    'routes.polyline.encodedPolyline,'
                    'routes.legs.steps.distanceMeters,'
                    'routes.legs.steps.staticDuration,'
                    'routes.legs.steps.travelMode,'
                    'routes.legs.steps.endLocation.latLng,'
                    'routes.legs.steps.navigationInstruction.instructions,'
                    'routes.legs.steps.navigationInstruction.maneuver',
              },
            ),
    );

    final routes = response.data?['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) return const [];
    final parsed = <JourneyRouteOption>[];
    for (var index = 0; index < routes.length; index++) {
      final route = routes[index] as Map<String, dynamic>;
      final option = _parseRoute(route, mode: mode, alternativeIndex: index);
      if (option != null) parsed.add(option);
    }
    return parsed;
  }

  JourneyRouteOption? _parseRoute(
    Map<String, dynamic> route, {
    required JourneyTravelMode mode,
    required int alternativeIndex,
  }) {
    final encoded =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    if (encoded == null) return null;

    final steps = _parseSteps(route, fallbackMode: mode);
    final walkingDistance = mode == JourneyTravelMode.walking
        ? route['distanceMeters'] as int? ?? 0
        : steps
              .where((step) => step.travelMode == JourneyTravelMode.walking)
              .fold<int>(0, (total, step) => total + step.distanceMeters);
    final transitSteps = steps
        .where((step) => step.travelMode == JourneyTravelMode.transit)
        .length;

    return JourneyRouteOption(
      mode: mode,
      duration: _parseDuration(route['duration'] as String? ?? '0s'),
      distanceMeters: route['distanceMeters'] as int? ?? 0,
      path: _decodePolyline(encoded),
      steps: steps,
      walkingDistanceMeters: walkingDistance,
      transfers: mode == JourneyTravelMode.transit
          ? (transitSteps - 1).clamp(0, 99)
          : 0,
      providerRouteId:
          'google-${mode.name}-$alternativeIndex-${encoded.hashCode}',
      routeLabel: alternativeIndex == 0
          ? null
          : '${mode.label} alternative ${alternativeIndex + 1}',
      providerName: 'Google Routes',
      source: JourneyEvidenceSource.live,
      availability: RouteAvailability.available,
      lastUpdated: DateTime.now(),
    );
  }

  List<JourneyStep> _parseSteps(
    Map<String, dynamic> route, {
    required JourneyTravelMode fallbackMode,
  }) {
    final legs = route['legs'] as List<dynamic>? ?? const [];
    final steps = <JourneyStep>[];
    for (final rawLeg in legs.whereType<Map<String, dynamic>>()) {
      final rawSteps = rawLeg['steps'] as List<dynamic>? ?? const [];
      for (final rawStep in rawSteps.whereType<Map<String, dynamic>>()) {
        final navigation =
            rawStep['navigationInstruction'] as Map<String, dynamic>?;
        final instruction = navigation?['instructions'] as String?;
        final distance = rawStep['distanceMeters'] as int? ?? 0;
        if ((instruction == null || instruction.trim().isEmpty) &&
            distance == 0) {
          continue;
        }
        steps.add(
          JourneyStep(
            instruction: instruction?.trim().isNotEmpty == true
                ? instruction!.trim()
                : 'Continue on the route',
            distanceMeters: distance,
            duration: _parseDuration(
              rawStep['staticDuration'] as String? ?? '0s',
            ),
            travelMode: _parseTravelMode(
              rawStep['travelMode'] as String?,
              fallbackMode,
            ),
            maneuver: navigation?['maneuver'] as String?,
            endLocation: _parseLocation(
              rawStep['endLocation'] as Map<String, dynamic>?,
            ),
          ),
        );
      }
    }
    return steps;
  }

  JourneyTravelMode _parseTravelMode(
    String? value,
    JourneyTravelMode fallback,
  ) {
    return switch (value) {
      'WALK' => JourneyTravelMode.walking,
      'TRANSIT' => JourneyTravelMode.transit,
      'DRIVE' => JourneyTravelMode.driving,
      'BICYCLE' => JourneyTravelMode.bicycling,
      'TWO_WHEELER' => JourneyTravelMode.twoWheeled,
      _ => fallback,
    };
  }

  LatLng? _parseLocation(Map<String, dynamic>? raw) {
    final latLng = raw?['latLng'] as Map<String, dynamic>?;
    final latitude = latLng?['latitude'] as num?;
    final longitude = latLng?['longitude'] as num?;
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  Map<String, Object> _waypoint(LatLng point) => {
    'location': {
      'latLng': {'latitude': point.latitude, 'longitude': point.longitude},
    },
  };

  Duration _parseDuration(String value) {
    final seconds = double.tryParse(value.replaceAll('s', '')) ?? 0;
    return Duration(seconds: seconds.round());
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      final lat = _decodeValue(encoded, index);
      index = lat.nextIndex;
      latitude += lat.value;
      final lng = _decodeValue(encoded, index);
      index = lng.nextIndex;
      longitude += lng.value;
      points.add(LatLng(latitude / 1e5, longitude / 1e5));
    }
    return points;
  }

  ({int value, int nextIndex}) _decodeValue(String encoded, int start) {
    var result = 0;
    var shift = 0;
    var index = start;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    final value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    return (value: value, nextIndex: index);
  }

  Future<Options?> _authenticatedOptions() async {
    final token = await _accessToken?.call();
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }
}
