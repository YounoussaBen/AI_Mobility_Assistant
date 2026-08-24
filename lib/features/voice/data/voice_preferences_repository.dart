import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/voice_profile.dart';

final voicePreferencesRepositoryProvider = Provider<VoicePreferencesRepository>(
  (ref) => throw StateError('VoicePreferencesRepository was not initialized.'),
);

class VoicePreferencesRepository {
  VoicePreferencesRepository(this._storage);

  static const _key = 'voice_guidance_profile_v1';
  final SharedPreferences _storage;

  Future<VoiceProfile> load() async {
    final saved = _storage.getString(_key);
    if (saved == null) return const VoiceProfile();
    try {
      return VoiceProfile.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } on FormatException {
      return const VoiceProfile();
    }
  }

  Future<void> save(VoiceProfile profile) async {
    await _storage.setString(_key, jsonEncode(profile.toJson()));
  }
}
