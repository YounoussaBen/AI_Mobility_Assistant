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

  Map<String, Object> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'latitude': location.latitude,
    'longitude': location.longitude,
  };

  factory JourneyPlace.fromJson(Map<String, dynamic> json) => JourneyPlace(
    placeId: json['placeId'] as String? ?? '',
    name: json['name'] as String? ?? 'Saved destination',
    address: json['address'] as String? ?? '',
    location: LatLng(
      (json['latitude'] as num?)?.toDouble() ?? 0,
      (json['longitude'] as num?)?.toDouble() ?? 0,
    ),
  );
}
