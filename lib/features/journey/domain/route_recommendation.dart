import '../../preferences/domain/mobility_preferences.dart';
import 'route_option.dart';

class RankedRoute {
  const RankedRoute({
    required this.route,
    required this.title,
    required this.explanation,
    required this.isRecommended,
  });

  final JourneyRouteOption route;
  final String title;
  final String explanation;
  final bool isRecommended;
}

abstract final class RouteRanker {
  static List<RankedRoute> rank(
    List<JourneyRouteOption> routes,
    MobilityPreferences preferences,
  ) {
    routes = routes
        .where(
          (route) =>
              !route.isSimulated &&
              route.availability != RouteAvailability.unavailable,
        )
        .toList();
    if (routes.isEmpty) return const [];

    final sorted = [
      ...routes,
    ]..sort((a, b) => _score(a, preferences).compareTo(_score(b, preferences)));
    final fastest = routes.reduce((a, b) => a.duration <= b.duration ? a : b);
    final leastWalking = routes
        .where((route) => route.walkingDistanceMeters != null)
        .fold<JourneyRouteOption?>(null, (best, route) {
          if (best == null) return route;
          return route.walkingDistanceMeters! < best.walkingDistanceMeters!
              ? route
              : best;
        });

    return [
      for (var index = 0; index < sorted.length; index++)
        RankedRoute(
          route: sorted[index],
          isRecommended: index == 0,
          title: index == 0
              ? 'Recommended for your needs'
              : sorted[index] == leastWalking
              ? 'Least verified walking'
              : sorted[index] == fastest
              ? 'Fastest available'
              : sorted[index].mode.label,
          explanation: _explanation(
            sorted[index],
            preferences,
            fastest: fastest,
            leastWalking: leastWalking,
            recommended: index == 0,
          ),
        ),
    ];
  }

  static double _score(
    JourneyRouteOption route,
    MobilityPreferences preferences,
  ) {
    var score = route.duration.inSeconds / 60.0;
    if (preferences.reducedWalking) {
      score += (route.walkingDistanceMeters ?? route.distanceMeters) / 80.0;
    }
    if (preferences.fewerTransfers) {
      score += (route.transfers ?? 0) * 18;
    }
    if (route.availability == RouteAvailability.limited) score += 4;
    if (preferences.wheelchairAccess &&
        route.displayMode.toLowerCase().contains('wheelchair')) {
      score -= 18;
    }
    if (preferences.priority == JourneyPriority.fastest) {
      score = route.duration.inSeconds / 60.0;
    }
    if (preferences.priority == JourneyPriority.simplest) {
      score += route.steps.length * 0.8 + (route.transfers ?? 0) * 20;
    }
    if (preferences.priority == JourneyPriority.affordable) {
      final fare = route.fareMinorUnits;
      score = fare == null ? 5000 + score : fare / 100;
    }
    return score;
  }

  static String _explanation(
    JourneyRouteOption route,
    MobilityPreferences preferences, {
    required JourneyRouteOption fastest,
    required JourneyRouteOption? leastWalking,
    required bool recommended,
  }) {
    if (recommended &&
        preferences.reducedWalking &&
        route.walkingDistanceMeters != null &&
        route == leastWalking) {
      return 'Best match for your reduced-walking preference based on the '
          'walking distance returned by the route provider.';
    }
    if (recommended &&
        preferences.fewerTransfers &&
        route.transfers != null &&
        route.transfers == 0) {
      return 'Best match because this verified route has no transfers.';
    }
    if (recommended &&
        preferences.priority == JourneyPriority.affordable &&
        route.fareLabel != null) {
      return 'Lowest provider-supplied fare among the '
          'options with price evidence.';
    }
    if (recommended &&
        preferences.wheelchairAccess &&
        route.displayMode.toLowerCase().contains('wheelchair')) {
      return 'Best match for your wheelchair-access preference in the '
          'provider details. Confirm access before travelling.';
    }
    if (route == fastest) {
      return 'Fastest option returned by the route provider right now.';
    }
    return route.connectionSummary;
  }
}
