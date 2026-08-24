import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum JourneyTravelMode { walking, transit, driving }

extension JourneyTravelModeInfo on JourneyTravelMode {
  String get apiValue => switch (this) {
    JourneyTravelMode.walking => 'WALK',
    JourneyTravelMode.transit => 'TRANSIT',
    JourneyTravelMode.driving => 'DRIVE',
  };

  String get label => switch (this) {
    JourneyTravelMode.walking => 'Walk',
    JourneyTravelMode.transit => 'Public transport',
    JourneyTravelMode.driving => 'Drive',
  };

  IconData get icon => switch (this) {
    JourneyTravelMode.walking => Icons.directions_walk_rounded,
    JourneyTravelMode.transit => Icons.directions_transit_rounded,
    JourneyTravelMode.driving => Icons.directions_car_outlined,
  };
}

class JourneyStep {
  const JourneyStep({
    required this.instruction,
    required this.distanceMeters,
    required this.duration,
    required this.travelMode,
    this.maneuver,
    this.endLocation,
  });

  final String instruction;
  final int distanceMeters;
  final Duration duration;
  final JourneyTravelMode travelMode;
  final String? maneuver;
  final LatLng? endLocation;

  String get distanceLabel {
    if (distanceMeters < 1000) return '$distanceMeters m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }
}

class JourneyRouteOption {
  const JourneyRouteOption({
    required this.mode,
    required this.duration,
    required this.distanceMeters,
    required this.path,
    this.steps = const [],
    this.walkingDistanceMeters,
    this.transfers,
  });

  final JourneyTravelMode mode;
  final Duration duration;
  final int distanceMeters;
  final List<LatLng> path;
  final List<JourneyStep> steps;
  final int? walkingDistanceMeters;
  final int? transfers;

  JourneyStep? get firstStep => steps.firstOrNull;

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
