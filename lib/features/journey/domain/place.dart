import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;

  String get description =>
      secondaryText.isEmpty ? primaryText : '$primaryText, $secondaryText';
}

class JourneyPlace {
  const JourneyPlace({
    required this.placeId,
    required this.name,
    required this.address,
    required this.location,
  });

  final String placeId;
  final String name;
  final String address;
  final LatLng location;
}
