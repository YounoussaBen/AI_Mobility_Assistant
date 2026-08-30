import '../../journey/domain/route_option.dart';

enum TransportRequestStatus { confirmed, unavailable, cancelled }

class TransportRequest {
  const TransportRequest({
    required this.id,
    required this.route,
    required this.status,
    required this.createdAt,
    required this.message,
    required this.simulated,
  });

  final String id;
  final JourneyRouteOption route;
  final TransportRequestStatus status;
  final DateTime createdAt;
  final String message;
  final bool simulated;

  Map<String, Object> toJson() => {
    'id': id,
    'route': route.toJson(),
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'message': message,
    'simulated': simulated,
  };
}
