import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The deliberately bounded pilot area for the Accra deployment.
///
/// The rectangle covers central Accra and the surrounding urban districts used
/// in the evaluation. It is intentionally enforced by data services as well as
/// the map camera so an external destination cannot silently enter a journey.
abstract final class AccraOperatingArea {
  static const name = 'Accra, Ghana';
  static const countryCode = 'gh';
  static const languageCode = 'en-GH';
  static const center = LatLng(5.6037, -0.1870);
  static const southwest = LatLng(5.45, -0.36);
  static const northeast = LatLng(5.78, -0.05);

  static final bounds = LatLngBounds(
    southwest: southwest,
    northeast: northeast,
  );

  static bool contains(LatLng point) =>
      point.latitude >= southwest.latitude &&
      point.latitude <= northeast.latitude &&
      point.longitude >= southwest.longitude &&
      point.longitude <= northeast.longitude;

  static bool containsRoute(Iterable<LatLng> points) => points.every(contains);

  static Map<String, Object> get placesRestriction => {
    'rectangle': {
      'low': {'latitude': southwest.latitude, 'longitude': southwest.longitude},
      'high': {
        'latitude': northeast.latitude,
        'longitude': northeast.longitude,
      },
    },
  };
}

class OutsideAccraOperatingArea implements Exception {
  const OutsideAccraOperatingArea([
    this.message = 'This pilot currently supports destinations in Accra only.',
  ]);

  final String message;

  @override
  String toString() => message;
}
