import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/storage/app_storage.dart';
import '../domain/accra_operating_area.dart';
import '../domain/route_option.dart';

final routeCacheRepositoryProvider = Provider<RouteCacheRepository>((ref) {
  return RouteCacheRepository(ref.watch(appStorageProvider));
});

class RouteCacheRepository {
  RouteCacheRepository(this._storage);

  static const _key = 'companion.route_cache.v1';
  static const maxAge = Duration(hours: 24);
  final AppStorage _storage;

  String keyFor(LatLng origin, LatLng destination) {
    String rounded(double value) => value.toStringAsFixed(4);
    return '${rounded(origin.latitude)},${rounded(origin.longitude)}:'
        '${rounded(destination.latitude)},${rounded(destination.longitude)}';
  }

  List<JourneyRouteOption> load(LatLng origin, LatLng destination) {
    if (!AccraOperatingArea.contains(origin) ||
        !AccraOperatingArea.contains(destination)) {
      return const [];
    }
    final raw = _storage.readString(_key);
    if (raw == null) return const [];
    try {
      final all = jsonDecode(raw) as Map<String, dynamic>;
      final entry = all[keyFor(origin, destination)] as Map<String, dynamic>?;
      if (entry == null) return const [];
      final savedAt = DateTime.tryParse(entry['savedAt'] as String? ?? '');
      if (savedAt == null || DateTime.now().difference(savedAt) > maxAge) {
        return const [];
      }
      final routes = entry['routes'] as List<dynamic>? ?? const [];
      final parsed = <JourneyRouteOption>[];
      for (final rawRoute in routes.whereType<Map<String, dynamic>>()) {
        final route = JourneyRouteOption.fromJson(rawRoute);
        if (route.path.isEmpty ||
            !AccraOperatingArea.containsRoute(route.path)) {
          continue;
        }
        parsed.add(
          route.copyWith(
            source: JourneyEvidenceSource.cached,
            serviceStatus: 'Saved route · verify conditions before travel',
          ),
        );
      }
      return parsed;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(
    LatLng origin,
    LatLng destination,
    List<JourneyRouteOption> routes,
  ) async {
    if (!AccraOperatingArea.contains(origin) ||
        !AccraOperatingArea.contains(destination) ||
        routes.any(
          (route) =>
              route.path.isEmpty ||
              !AccraOperatingArea.containsRoute(route.path),
        )) {
      return;
    }
    Map<String, dynamic> all = {};
    final raw = _storage.readString(_key);
    if (raw != null) {
      try {
        all = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        all = {};
      }
    }
    all[keyFor(origin, destination)] = {
      'savedAt': DateTime.now().toIso8601String(),
      'routes': [for (final route in routes) route.toJson()],
    };
    while (all.length > 8) {
      all.remove(all.keys.first);
    }
    await _storage.writeString(_key, jsonEncode(all));
  }

  Future<void> clear() => _storage.remove(_key);
}
