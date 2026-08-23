import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum JourneyTravelMode { driving, walking, bicycling }

extension JourneyTravelModeInfo on JourneyTravelMode {
  String get apiValue => switch (this) {
    JourneyTravelMode.driving => 'DRIVE',
    JourneyTravelMode.walking => 'WALK',
    JourneyTravelMode.bicycling => 'BICYCLE',
  };

  String get label => switch (this) {
    JourneyTravelMode.driving => 'Drive',
    JourneyTravelMode.walking => 'Walk',
    JourneyTravelMode.bicycling => 'Bicycle',
  };

  IconData get icon => switch (this) {
    JourneyTravelMode.driving => Icons.directions_car_outlined,
    JourneyTravelMode.walking => Icons.directions_walk_rounded,
    JourneyTravelMode.bicycling => Icons.pedal_bike_rounded,
  };
}

class JourneyRouteOption {
  const JourneyRouteOption({
    required this.mode,
    required this.duration,
    required this.distanceMeters,
    required this.path,
  });

  final JourneyTravelMode mode;
  final Duration duration;
  final int distanceMeters;
  final List<LatLng> path;

  String get durationLabel {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
  }

  String get distanceLabel {
    if (distanceMeters < 1000) return '$distanceMeters m';
    final kilometres = distanceMeters / 1000;
    return '${kilometres.toStringAsFixed(kilometres < 10 ? 1 : 0)} km';
  }
}
