import '../../journey/domain/place.dart';
import '../../journey/domain/route_option.dart';

class JourneyRecord {
  const JourneyRecord({
    required this.id,
    required this.destination,
    required this.route,
    required this.completedAt,
  });

  final String id;
  final JourneyPlace destination;
  final JourneyRouteOption route;
  final DateTime completedAt;

  Map<String, Object> toJson() => {
    'id': id,
    'destination': destination.toJson(),
    'route': route.toJson(),
    'completedAt': completedAt.toIso8601String(),
  };

  factory JourneyRecord.fromJson(Map<String, dynamic> json) => JourneyRecord(
    id: json['id'] as String? ?? '',
    destination: JourneyPlace.fromJson(
      json['destination'] as Map<String, dynamic>? ?? const {},
    ),
    route: JourneyRouteOption.fromJson(
      json['route'] as Map<String, dynamic>? ?? const {},
    ),
    completedAt:
        DateTime.tryParse(json['completedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
