import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/storage/app_storage.dart';
import '../domain/journey_record.dart';

final journeyHistoryRepositoryProvider = Provider<JourneyHistoryRepository>((
  ref,
) {
  return JourneyHistoryRepository(ref.watch(appStorageProvider));
});

class JourneyHistoryRepository {
  JourneyHistoryRepository(this._storage);

  static const _historyKey = 'companion.journey_history.v1';
  static const _enabledKey = 'companion.journey_history.enabled';
  final AppStorage _storage;

  bool get isEnabled => _storage.readBool(_enabledKey) ?? true;

  List<JourneyRecord> load() {
    final raw = _storage.readString(_historyKey);
    if (raw == null) return const [];
    try {
      final items = jsonDecode(raw) as List<dynamic>;
      return [
        for (final item in items.whereType<Map<String, dynamic>>())
          JourneyRecord.fromJson(item),
      ].where((record) => !record.route.isSimulated).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<JourneyRecord> records) {
    return _storage.writeString(
      _historyKey,
      jsonEncode([for (final record in records) record.toJson()]),
    );
  }

  Future<void> setEnabled(bool enabled) {
    return _storage.writeBool(_enabledKey, enabled);
  }

  Future<void> clear() => _storage.remove(_historyKey);
}
