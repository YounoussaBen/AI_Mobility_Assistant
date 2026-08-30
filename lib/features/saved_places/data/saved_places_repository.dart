import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/storage/app_storage.dart';
import '../../journey/domain/place.dart';

final savedPlacesRepositoryProvider = Provider<SavedPlacesRepository>((ref) {
  return SavedPlacesRepository(ref.watch(appStorageProvider));
});

class SavedPlacesRepository {
  SavedPlacesRepository(this._storage);

  static const _key = 'companion.saved_places.v1';
  final AppStorage _storage;

  List<JourneyPlace> load() {
    final raw = _storage.readString(_key);
    if (raw == null) return const [];
    try {
      final items = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in items.whereType<Map<String, dynamic>>())
          JourneyPlace.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<JourneyPlace> places) {
    return _storage.writeString(
      _key,
      jsonEncode([for (final place in places) place.toJson()]),
    );
  }
}
