import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum JourneyTravelMode {
  walking,
  transit,
  driving,
  bicycling,
  twoWheeled,
  onDemand,
}

extension JourneyTravelModeInfo on JourneyTravelMode {
  String get apiValue => switch (this) {
    JourneyTravelMode.walking => 'WALK',
    JourneyTravelMode.transit => 'TRANSIT',
    JourneyTravelMode.driving => 'DRIVE',
    JourneyTravelMode.bicycling => 'BICYCLE',
    JourneyTravelMode.twoWheeled => 'TWO_WHEELER',
    JourneyTravelMode.onDemand => 'DRIVE',
  };

  String get label => switch (this) {
    JourneyTravelMode.walking => 'Walk',
    JourneyTravelMode.transit => 'Public transport',
    JourneyTravelMode.driving => 'Drive',
    JourneyTravelMode.bicycling => 'Bicycle',
    JourneyTravelMode.twoWheeled => 'Two-wheeled',
    JourneyTravelMode.onDemand => 'On-demand transport',
  };

  IconData get icon => switch (this) {
    JourneyTravelMode.walking => Icons.directions_walk_rounded,
    JourneyTravelMode.transit => Icons.directions_transit_rounded,
    JourneyTravelMode.driving => Icons.directions_car_outlined,
    JourneyTravelMode.bicycling => Icons.directions_bike_rounded,
    JourneyTravelMode.twoWheeled => Icons.two_wheeler_rounded,
    JourneyTravelMode.onDemand => Icons.local_taxi_outlined,
  };
}

enum JourneyEvidenceSource { live, simulated, cached }

enum RouteAvailability { available, limited, unavailable, unknown }

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

  Map<String, Object?> toJson() => {
    'instruction': instruction,
    'distanceMeters': distanceMeters,
    'durationSeconds': duration.inSeconds,
    'travelMode': travelMode.name,
    'maneuver': maneuver,
    if (endLocation != null) 'endLatitude': endLocation!.latitude,
    if (endLocation != null) 'endLongitude': endLocation!.longitude,
  };

  factory JourneyStep.fromJson(Map<String, dynamic> json) {
    final modeName = json['travelMode'] as String?;
    final modes = JourneyTravelMode.values.where(
      (mode) => mode.name == modeName,
    );
    final latitude = json['endLatitude'] as num?;
    final longitude = json['endLongitude'] as num?;
    return JourneyStep(
      instruction: json['instruction'] as String? ?? 'Continue on the route',
      distanceMeters: json['distanceMeters'] as int? ?? 0,
      duration: Duration(seconds: json['durationSeconds'] as int? ?? 0),
      travelMode: modes.isEmpty ? JourneyTravelMode.walking : modes.first,
      maneuver: json['maneuver'] as String?,
      endLocation: latitude == null || longitude == null
          ? null
          : LatLng(latitude.toDouble(), longitude.toDouble()),
    );
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
    this.providerRouteId,
    this.routeLabel,
    this.providerName = 'Google Routes',
    this.fareMinorUnits,
    this.currencyCode,
    this.waitingTime,
    this.serviceStatus,
    this.source = JourneyEvidenceSource.live,
    this.availability = RouteAvailability.unknown,
    this.lastUpdated,
  });

  final JourneyTravelMode mode;
  final Duration duration;
  final int distanceMeters;
  final List<LatLng> path;
  final List<JourneyStep> steps;
  final int? walkingDistanceMeters;
  final int? transfers;
  final String? providerRouteId;
  final String? routeLabel;
  final String providerName;
  final int? fareMinorUnits;
  final String? currencyCode;
  final Duration? waitingTime;
  final String? serviceStatus;
  final JourneyEvidenceSource source;
  final RouteAvailability availability;
  final DateTime? lastUpdated;

  String get routeKey =>
      providerRouteId ??
      '${mode.name}-${duration.inSeconds}-$distanceMeters-${path.length}-${routeLabel ?? ''}';

  String get displayMode => routeLabel ?? mode.label;

  bool get isRequestable => mode == JourneyTravelMode.onDemand;

  bool get isSimulated => source == JourneyEvidenceSource.simulated;

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

  String? get fareLabel {
    final amount = fareMinorUnits;
    if (amount == null) return null;
    final currency = currencyCode ?? 'GHS';
    return '$currency ${(amount / 100).toStringAsFixed(2)}';
  }

  String? get waitingLabel {
    final wait = waitingTime;
    if (wait == null) return null;
    return '${wait.inMinutes} min wait';
  }

  JourneyRouteOption copyWith({
    JourneyTravelMode? mode,
    Duration? duration,
    int? distanceMeters,
    List<LatLng>? path,
    List<JourneyStep>? steps,
    int? walkingDistanceMeters,
    int? transfers,
    String? providerRouteId,
    String? routeLabel,
    String? providerName,
    int? fareMinorUnits,
    String? currencyCode,
    Duration? waitingTime,
    String? serviceStatus,
    JourneyEvidenceSource? source,
    RouteAvailability? availability,
    DateTime? lastUpdated,
  }) => JourneyRouteOption(
    mode: mode ?? this.mode,
    duration: duration ?? this.duration,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    path: path ?? this.path,
    steps: steps ?? this.steps,
    walkingDistanceMeters: walkingDistanceMeters ?? this.walkingDistanceMeters,
    transfers: transfers ?? this.transfers,
    providerRouteId: providerRouteId ?? this.providerRouteId,
    routeLabel: routeLabel ?? this.routeLabel,
    providerName: providerName ?? this.providerName,
    fareMinorUnits: fareMinorUnits ?? this.fareMinorUnits,
    currencyCode: currencyCode ?? this.currencyCode,
    waitingTime: waitingTime ?? this.waitingTime,
    serviceStatus: serviceStatus ?? this.serviceStatus,
    source: source ?? this.source,
    availability: availability ?? this.availability,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'durationSeconds': duration.inSeconds,
    'distanceMeters': distanceMeters,
    'path': [
      for (final point in path)
        {'latitude': point.latitude, 'longitude': point.longitude},
    ],
    'steps': [for (final step in steps) step.toJson()],
    'walkingDistanceMeters': walkingDistanceMeters,
    'transfers': transfers,
    'providerRouteId': providerRouteId,
    'routeLabel': routeLabel,
    'providerName': providerName,
    'fareMinorUnits': fareMinorUnits,
    'currencyCode': currencyCode,
    'waitingSeconds': waitingTime?.inSeconds,
    'serviceStatus': serviceStatus,
    'source': source.name,
    'availability': availability.name,
    'lastUpdated': lastUpdated?.toIso8601String(),
  };

  factory JourneyRouteOption.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      final matches = values.where((value) => value.name == name);
      return matches.isEmpty ? fallback : matches.first;
    }

    final rawPath = json['path'] as List<dynamic>? ?? const [];
    final rawSteps = json['steps'] as List<dynamic>? ?? const [];
    return JourneyRouteOption(
      mode: enumValue(
        JourneyTravelMode.values,
        json['mode'] as String?,
        JourneyTravelMode.walking,
      ),
      duration: Duration(seconds: json['durationSeconds'] as int? ?? 0),
      distanceMeters: json['distanceMeters'] as int? ?? 0,
      path: [
        for (final item in rawPath.whereType<Map<String, dynamic>>())
          LatLng(
            (item['latitude'] as num?)?.toDouble() ?? 0,
            (item['longitude'] as num?)?.toDouble() ?? 0,
          ),
      ],
      steps: [
        for (final item in rawSteps.whereType<Map<String, dynamic>>())
          JourneyStep.fromJson(item),
      ],
      walkingDistanceMeters: json['walkingDistanceMeters'] as int?,
      transfers: json['transfers'] as int?,
      providerRouteId: json['providerRouteId'] as String?,
      routeLabel: json['routeLabel'] as String?,
      providerName: json['providerName'] as String? ?? 'Google Routes',
      fareMinorUnits: json['fareMinorUnits'] as int?,
      currencyCode: json['currencyCode'] as String?,
      waitingTime: json['waitingSeconds'] == null
          ? null
          : Duration(seconds: json['waitingSeconds'] as int),
      serviceStatus: json['serviceStatus'] as String?,
      source: enumValue(
        JourneyEvidenceSource.values,
        json['source'] as String?,
        JourneyEvidenceSource.live,
      ),
      availability: enumValue(
        RouteAvailability.values,
        json['availability'] as String?,
        RouteAvailability.unknown,
      ),
      lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? ''),
    );
  }
}
