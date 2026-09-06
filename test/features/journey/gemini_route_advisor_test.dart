import 'package:ai_mobility_assistant/features/journey/data/gemini_route_advisor.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:ai_mobility_assistant/features/preferences/domain/mobility_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const origin = LatLng(5.60, -0.18);
  const destination = LatLng(5.64, -0.15);
  const walk = JourneyRouteOption(
    mode: JourneyTravelMode.walking,
    providerRouteId: 'walk',
    duration: Duration(minutes: 12),
    distanceMeters: 900,
    walkingDistanceMeters: 900,
    path: [origin, destination],
  );
  const transit = JourneyRouteOption(
    mode: JourneyTravelMode.transit,
    providerRouteId: 'transit',
    duration: Duration(minutes: 18),
    distanceMeters: 5000,
    walkingDistanceMeters: 300,
    path: [origin, destination],
    steps: [
      JourneyStep(
        instruction: 'Walk to the stop',
        distanceMeters: 200,
        duration: Duration(minutes: 3),
        travelMode: JourneyTravelMode.walking,
      ),
      JourneyStep(
        instruction: 'Board the named service',
        distanceMeters: 4700,
        duration: Duration(minutes: 13),
        travelMode: JourneyTravelMode.transit,
      ),
      JourneyStep(
        instruction: 'Walk to the destination',
        distanceMeters: 100,
        duration: Duration(minutes: 2),
        travelMode: JourneyTravelMode.walking,
      ),
    ],
  );
  Future<RouteAdvice> compare(
    Object response, {
    String? token = 'token',
    MobilityPreferences preferences = const MobilityPreferences(),
  }) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.headers['Authorization'], 'Bearer token');
          final data = request.data as Map;
          final routes = data['routes'] as List;
          expect(routes.last['firstWalkMeters'], 200);
          expect(routes.last['lastWalkMeters'], 100);
          expect(routes.last['fareMinorUnits'], isNull);
          handler.resolve(Response(requestOptions: request, data: response));
        },
      ),
    );
    return GeminiRouteAdvisor(
      apiKey: '',
      model: 'test',
      backendUrl: 'https://backend.example',
      accessToken: () async => token,
      dio: dio,
    ).compare(
      origin: origin,
      destinationName: 'Destination',
      destination: destination,
      routes: [walk, transit],
      preferences: preferences,
    );
  }

  test(
    'AI can select evidenced mixed journey without changing route facts',
    () async {
      final advice = await compare({
        'routeIds': ['transit', 'walk'],
        'fare': 'GHS 5',
      });
      expect(advice.aiCompared, isTrue);
      expect(advice.routes.first.route, same(transit));
      expect(advice.routes.first.explanation, contains('200 m'));
      expect(advice.routes.first.explanation, contains('100 m'));
      expect(advice.routes.first.route.fareMinorUnits, isNull);
    },
  );
  test(
    'unknown, duplicate and missing route IDs fall back to evidence ranking',
    () async {
      for (final ids in [
        ['imaginary', 'walk'],
        ['transit', 'transit'],
        ['transit'],
      ]) {
        final advice = await compare({'routeIds': ids});
        expect(advice.aiCompared, isFalse);
        expect(advice.routes.first.route, same(walk));
      }
    },
  );
  test('backend token is required and missing auth falls back', () async {
    final advice = await compare({
      'routeIds': ['transit', 'walk'],
    }, token: null);
    expect(advice.aiCompared, isFalse);
  });
  test('explicit fastest priority cannot be overridden by AI', () async {
    final advice = await compare(
      {
        'routeIds': ['transit', 'walk'],
      },
      preferences: const MobilityPreferences(priority: JourneyPriority.fastest),
    );
    expect(advice.routes.first.route, same(walk));
  });
  test(
    'no AI configuration still returns real routes and excludes simulation',
    () async {
      final advice = await GeminiRouteAdvisor(apiKey: '', model: 'test')
          .compare(
            origin: origin,
            destinationName: 'Destination',
            destination: destination,
            routes: [
              walk,
              transit.copyWith(source: JourneyEvidenceSource.simulated),
            ],
            preferences: const MobilityPreferences(),
          );
      expect(advice.aiCompared, isFalse);
      expect(advice.routes.map((r) => r.route), [walk]);
    },
  );
  test(
    'direct Gemini uses structured existing IDs and ignores thinking text',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, '/v1beta/models/test:generateContent');
            expect(request.headers['x-goog-api-key'], 'test-key');
            expect(
              request.data['generationConfig']['responseMimeType'],
              'application/json',
            );
            handler.resolve(
              Response(
                requestOptions: request,
                data: {
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'thought': true, 'text': 'Internal comparison'},
                          {'text': '{"routeIds":["transit","walk"]}'},
                        ],
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final advice =
          await GeminiRouteAdvisor(
            apiKey: 'test-key',
            model: 'test',
            dio: dio,
          ).compare(
            origin: origin,
            destinationName: 'Destination',
            destination: destination,
            routes: [walk, transit],
            preferences: const MobilityPreferences(),
          );
      expect(advice.aiCompared, isTrue);
      expect(advice.routes.first.route, same(transit));
    },
  );
}
