import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/mobility_preferences.dart';

final mobilityPreferencesRepositoryProvider =
    Provider<MobilityPreferencesRepository>((ref) {
      throw StateError('MobilityPreferencesRepository was not initialized.');
    });

class MobilityPreferencesRepository {
  MobilityPreferencesRepository(this._storage);

  static const _preferencesKey = 'mobility_preferences';
  static const _introKey = 'intro_complete_v2';
  static const _profileKey = 'profile_complete_v2';

  final SharedPreferences _storage;

  bool get hasCompletedIntro => _storage.getBool(_introKey) ?? false;

  bool get isProfileComplete => _storage.getBool(_profileKey) ?? false;

  Future<MobilityPreferences> load() async {
    final saved = _storage.getString(_preferencesKey);
    if (saved == null) return const MobilityPreferences();

    try {
      return MobilityPreferences.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } on FormatException {
      return const MobilityPreferences();
    }
  }

  Future<void> save(MobilityPreferences preferences) async {
    await _storage.setString(_preferencesKey, jsonEncode(preferences.toJson()));
  }

  Future<void> completeIntro() async {
    await _storage.setBool(_introKey, true);
  }

  Future<void> completeProfile() async {
    await _storage.setBool(_profileKey, true);
  }
}
