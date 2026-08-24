import 'package:ai_mobility_assistant/features/journey/domain/route_option.dart';
import 'package:ai_mobility_assistant/features/journey/domain/route_recommendation.dart';
import 'package:ai_mobility_assistant/features/preferences/domain/mobility_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reduced-walking preference deterministically favors less walking', () {
    const routes = [
      JourneyRouteOption(
        mode: JourneyTravelMode.walking,
        duration: Duration(minutes: 12),
        distanceMeters: 900,
        walkingDistanceMeters: 900,
        path: [],
      ),
      JourneyRouteOption(
        mode: JourneyTravelMode.transit,
        duration: Duration(minutes: 18),
        distanceMeters: 4000,
        walkingDistanceMeters: 120,
        transfers: 0,
        path: [],
      ),
    ];

    final ranked = RouteRanker.rank(
      routes,
      const MobilityPreferences(reducedWalking: true),
    );

    expect(ranked.first.route.mode, JourneyTravelMode.transit);
    expect(ranked.first.isRecommended, isTrue);
    expect(ranked.first.explanation, contains('reduced-walking'));
    expect(
      ranked.expand((route) => [route.title, route.explanation]).join(' '),
      isNot(contains('step-free')),
    );
  });

  test('fastest priority ignores preference weighting', () {
    const routes = [
      JourneyRouteOption(
        mode: JourneyTravelMode.walking,
        duration: Duration(minutes: 9),
        distanceMeters: 700,
        walkingDistanceMeters: 700,
        path: [],
      ),
      JourneyRouteOption(
        mode: JourneyTravelMode.transit,
        duration: Duration(minutes: 16),
        distanceMeters: 4200,
        walkingDistanceMeters: 80,
        transfers: 0,
        path: [],
      ),
    ];

    final ranked = RouteRanker.rank(
      routes,
      const MobilityPreferences(
        reducedWalking: true,
        priority: JourneyPriority.fastest,
      ),
    );

    expect(ranked.first.route.mode, JourneyTravelMode.walking);
  });
}
