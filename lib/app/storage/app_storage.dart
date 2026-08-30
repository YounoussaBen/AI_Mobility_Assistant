import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, injectable key-value boundary used by the companion's local memory.
///
/// The in-memory default keeps widgets and domain tests deterministic. The app
/// replaces it with [SharedPreferencesAppStorage] during startup.
final appStorageProvider = Provider<AppStorage>((ref) => MemoryAppStorage());

abstract interface class AppStorage {
  String? readString(String key);

  bool? readBool(String key);

  Future<void> writeString(String key, String value);

  Future<void> writeBool(String key, bool value);

  Future<void> remove(String key);
}

class SharedPreferencesAppStorage implements AppStorage {
  SharedPreferencesAppStorage(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? readString(String key) => _preferences.getString(key);

  @override
  bool? readBool(String key) => _preferences.getBool(key);

  @override
  Future<void> writeString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    await _preferences.setBool(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}

class MemoryAppStorage implements AppStorage {
  MemoryAppStorage([Map<String, Object>? initialValues])
    : _values = {...?initialValues};

  final Map<String, Object> _values;

  @override
  String? readString(String key) => _values[key] as String?;

  @override
  bool? readBool(String key) => _values[key] as bool?;

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
