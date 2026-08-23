import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/route_option.dart';

class GoogleRoutesService {
  GoogleRoutesService({required String apiKey, Dio? dio})
    : _apiKey = apiKey,
      _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://routes.googleapis.com'));

  final String _apiKey;
  final Dio _dio;

  Future<List<JourneyRouteOption>> routes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final results = await Future.wait(
      JourneyTravelMode.values.map(
        (mode) => _routeForMode(
          origin: origin,
          destination: destination,
          mode: mode,
        ).catchError((_) => null),
      ),
    );
    return results.whereType<JourneyRouteOption>().toList(growable: false);
  }

  Future<JourneyRouteOption?> _routeForMode({
    required LatLng origin,
    required LatLng destination,
    required JourneyTravelMode mode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/directions/v2:computeRoutes',
      data: {
        'origin': _waypoint(origin),
        'destination': _waypoint(destination),
        'travelMode': mode.apiValue,
        if (mode == JourneyTravelMode.driving)
          'routingPreference': 'TRAFFIC_AWARE',
        'computeAlternativeRoutes': false,
        'languageCode': 'en-US',
        'units': 'METRIC',
      },
      options: Options(
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'routes.duration,routes.distanceMeters,'
              'routes.polyline.encodedPolyline',
        },
      ),
    );

    final routes = response.data?['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final encoded =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    if (encoded == null) return null;

    return JourneyRouteOption(
      mode: mode,
      duration: _parseDuration(route['duration'] as String? ?? '0s'),
      distanceMeters: route['distanceMeters'] as int? ?? 0,
      path: _decodePolyline(encoded),
    );
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
}
