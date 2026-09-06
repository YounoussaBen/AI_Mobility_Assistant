import 'package:ai_mobility_assistant/features/journey/data/google_routes_service.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const origin = LatLng(5.5600, -0.2050);
  const destination = LatLng(5.5700, -0.1950);

  test(
    'uses transit evidence for instructions and the mixed route label',
    () async {
      String? fieldMask;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            fieldMask = request.headers['X-Goog-FieldMask'] as String?;
            final mode = (request.data as Map<String, dynamic>)['travelMode'];
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: request,
                data: mode == 'TRANSIT'
                    ? {
                        'routes': [
                          _route(
                            path: [origin, destination],
                            steps: [
                              _step(
                                'WALK',
                                origin,
                                const LatLng(5.561, -0.204),
                              ),
                              _step(
                                'TRANSIT',
                                const LatLng(5.561, -0.204),
                                const LatLng(5.569, -0.196),
                                transitDetails: const {
                                  'headsign': 'Osu Oxford Street',
                                  'stopDetails': {
                                    'departureStop': {'name': '37 Station'},
                                    'arrivalStop': {'name': 'Koala'},
                                  },
                                  'transitLine': {
                                    'vehicle': {
                                      'name': {
                                        'text': 'City bus',
                                        'languageCode': 'en',
                                      },
                                      'type': 'BUS',
                                    },
                                  },
                                },
                              ),
                              _step(
                                'WALK',
                                const LatLng(5.569, -0.196),
                                destination,
                              ),
                            ],
                          ),
                        ],
                      }
                    : const {'routes': <Object>[]},
              ),
            );
          },
        ),
      );

      final routes = await GoogleRoutesService(
        apiKey: 'test',
        dio: dio,
      ).routes(origin: origin, destination: destination);

      final transit = routes.single;
      expect(transit.routeLabel, 'Walk + City bus + Walk');
      expect(
        transit.steps[1].instruction,
        'Board City bus toward Osu Oxford Street at 37 Station; alight at Koala',
      );
      expect(
        transit.steps[1].instruction.toLowerCase(),
        isNot(contains('trotro')),
      );
      expect(fieldMask, contains('routes.legs.steps.startLocation.latLng'));
      expect(
        fieldMask,
        contains('routes.legs.steps.transitDetails.transitLine'),
      );
      expect(fieldMask, contains('routes.legs.steps.transitDetails.headsign'));
    },
  );

  test(
    'joins returned walking evidence to a road-snapped driving route',
    () async {
      const roadStart = LatLng(5.5610, -0.2050);
      const roadEnd = LatLng(5.5690, -0.1950);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final body = request.data as Map<String, dynamic>;
            final mode = body['travelMode'];
            final from = _point(body['origin']);
            final to = _point(body['destination']);
            Map<String, dynamic> data = const {'routes': <Object>[]};
            if (mode == 'DRIVE') {
              data = {
                'routes': [
                  _route(
                    path: [roadStart, roadEnd],
                    distance: 900,
                    duration: '300s',
                    steps: [_step('DRIVE', roadStart, roadEnd, distance: 900)],
                  ),
                ],
              };
            } else if (mode == 'WALK' && from == origin && to == roadStart) {
              data = {
                'routes': [
                  _route(
                    path: [origin, roadStart],
                    distance: 120,
                    duration: '90s',
                    steps: [_step('WALK', origin, roadStart, distance: 120)],
                  ),
                ],
              };
            } else if (mode == 'WALK' && from == roadEnd && to == destination) {
              data = {
                'routes': [
                  _route(
                    path: [roadEnd, destination],
                    distance: 130,
                    duration: '100s',
                    steps: [_step('WALK', roadEnd, destination, distance: 130)],
                  ),
                ],
              };
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: request,
                data: data,
              ),
            );
          },
        ),
      );

      final routes = await GoogleRoutesService(
        apiKey: 'test',
        dio: dio,
      ).routes(origin: origin, destination: destination);

      final driving = routes.single;
      expect(driving.mode, JourneyTravelMode.driving);
      expect(driving.routeLabel, 'Walk + Drive + Walk');
      expect(driving.walkingDistanceMeters, 250);
      expect(driving.distanceMeters, 1150);
      expect(driving.duration, const Duration(seconds: 490));
      expect(driving.steps.map((step) => step.travelMode), [
        JourneyTravelMode.walking,
        JourneyTravelMode.driving,
        JourneyTravelMode.walking,
      ]);
      expect(driving.path.first, origin);
      expect(driving.path.last, destination);
    },
  );

  test('discards a snapped car route when a walking connector fails', () async {
    const roadStart = LatLng(5.5610, -0.2050);
    const roadEnd = LatLng(5.5690, -0.1950);
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          final body = request.data as Map<String, dynamic>;
          final mode = body['travelMode'];
          final from = _point(body['origin']);
          final to = _point(body['destination']);
          if (mode == 'WALK' && from == origin && to == roadStart) {
            handler.reject(DioException(requestOptions: request));
            return;
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              data: mode == 'DRIVE'
                  ? {
                      'routes': [
                        _route(
                          path: [roadStart, roadEnd],
                          steps: [_step('DRIVE', roadStart, roadEnd)],
                        ),
                      ],
                    }
                  : const {'routes': <Object>[]},
            ),
          );
        },
      ),
    );

    final routes = await GoogleRoutesService(
      apiKey: 'test',
      dio: dio,
    ).routes(origin: origin, destination: destination);

    expect(routes, isEmpty);
  });

  test(
    'discards a walking connector that does not reach the snapped road',
    () async {
      const roadStart = LatLng(5.5610, -0.2050);
      const roadEnd = LatLng(5.5699, -0.1950);
      const unrelatedStart = LatLng(5.5650, -0.2010);
      const unrelatedEnd = LatLng(5.5660, -0.2000);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final body = request.data as Map<String, dynamic>;
            final mode = body['travelMode'];
            final from = _point(body['origin']);
            final to = _point(body['destination']);
            Map<String, dynamic> data = const {'routes': <Object>[]};
            if (mode == 'DRIVE') {
              data = {
                'routes': [
                  _route(
                    path: [roadStart, roadEnd],
                    steps: [_step('DRIVE', roadStart, roadEnd)],
                  ),
                ],
              };
            } else if (mode == 'WALK' && from == origin && to == roadStart) {
              data = {
                'routes': [
                  _route(
                    path: [unrelatedStart, unrelatedEnd],
                    steps: [_step('WALK', unrelatedStart, unrelatedEnd)],
                  ),
                ],
              };
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: request,
                data: data,
              ),
            );
          },
        ),
      );

      final routes = await GoogleRoutesService(
        apiKey: 'test',
        dio: dio,
      ).routes(origin: origin, destination: destination);

      expect(routes, isEmpty);
    },
  );

  test(
    'keeps walking distance unknown when driving endpoints are absent',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final mode = (request.data as Map<String, dynamic>)['travelMode'];
            final step = _step('DRIVE', origin, destination)
              ..remove('startLocation')
              ..remove('endLocation');
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: request,
                data: mode == 'DRIVE'
                    ? {
                        'routes': [
                          _route(path: [origin, destination], steps: [step]),
                        ],
                      }
                    : const {'routes': <Object>[]},
              ),
            );
          },
        ),
      );

      final routes = await GoogleRoutesService(
        apiKey: 'test',
        dio: dio,
      ).routes(origin: origin, destination: destination);

      expect(routes.single.walkingDistanceMeters, isNull);
    },
  );
}

Map<String, dynamic> _route({
  required List<LatLng> path,
  required List<Map<String, dynamic>> steps,
  int distance = 1000,
  String duration = '600s',
}) => {
  'duration': duration,
  'distanceMeters': distance,
  'polyline': {'encodedPolyline': _encode(path)},
  'legs': [
    {'steps': steps},
  ],
};

Map<String, dynamic> _step(
  String mode,
  LatLng start,
  LatLng end, {
  int distance = 100,
  Map<String, dynamic>? transitDetails,
}) => {
  'travelMode': mode,
  'distanceMeters': distance,
  'staticDuration': '60s',
  'startLocation': {'latLng': _latLng(start)},
  'endLocation': {'latLng': _latLng(end)},
  'navigationInstruction': {'instructions': 'Provider instruction'},
  'transitDetails': ?transitDetails,
};

LatLng _point(Object? waypoint) {
  final location = (waypoint as Map<String, dynamic>)['location'];
  final latLng = (location as Map<String, dynamic>)['latLng'];
  return LatLng(
    (latLng['latitude'] as num).toDouble(),
    (latLng['longitude'] as num).toDouble(),
  );
}

Map<String, double> _latLng(LatLng point) => {
  'latitude': point.latitude,
  'longitude': point.longitude,
};

String _encode(List<LatLng> points) {
  final encoded = StringBuffer();
  var previousLatitude = 0;
  var previousLongitude = 0;
  for (final point in points) {
    final latitude = (point.latitude * 1e5).round();
    final longitude = (point.longitude * 1e5).round();
    _encodeValue(latitude - previousLatitude, encoded);
    _encodeValue(longitude - previousLongitude, encoded);
    previousLatitude = latitude;
    previousLongitude = longitude;
  }
  return encoded.toString();
}

void _encodeValue(int value, StringBuffer output) {
  var shifted = value < 0 ? ~(value << 1) : value << 1;
  while (shifted >= 0x20) {
    output.writeCharCode((0x20 | (shifted & 0x1f)) + 63);
    shifted >>= 5;
  }
  output.writeCharCode(shifted + 63);
}
