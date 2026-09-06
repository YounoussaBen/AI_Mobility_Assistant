import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../preferences/application/mobility_preferences_controller.dart';
import '../application/voice_profile_controller.dart';
import '../domain/voice_profile.dart';

final speechOutputServiceProvider = Provider<SpeechOutputService>((ref) {
  final preferences = ref.watch(mobilityPreferencesControllerProvider);
  final profile = ref.read(voiceProfileControllerProvider);
  final service = SpeechOutputService(
    outputEnabled: preferences.value?.voiceGuidance ?? false,
    profileEnabled: profile.value?.speechEnabled ?? false,
  );
  ref.listen(voiceProfileControllerProvider, (_, next) {
    service.setSpeechEnabled(next.value?.speechEnabled ?? false);
  });
  ref.onDispose(service.dispose);
  return service;
});

class SpeechOutputService {
  SpeechOutputService({
    SpeechEngine? engine,
    bool outputEnabled = true,
    bool profileEnabled = true,
  }) : _engine = engine ?? FlutterTtsSpeechEngine(),
       _outputEnabled = outputEnabled,
       _profileEnabled = profileEnabled;

  final SpeechEngine _engine;
  final bool _outputEnabled;
  bool _profileEnabled;
  bool _disposed = false;
  int _operation = 0;

  Future<List<DeviceVoice>> availableVoices() async {
    final rawVoices = await _engine.voices;
    if (rawVoices is! List) return const [];

    final seen = <String>{};
    final voices = <DeviceVoice>[];
    for (final raw in rawVoices) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString();
      final locale = raw['locale']?.toString();
      if (name == null || name.isEmpty || locale == null || locale.isEmpty) {
        continue;
      }
      final voice = DeviceVoice(name: name, locale: locale);
      if (seen.add(voice.id)) voices.add(voice);
    }
    voices.sort((a, b) {
      final localeOrder = a.locale.compareTo(b.locale);
      return localeOrder == 0
          ? a.displayName.compareTo(b.displayName)
          : localeOrder;
    });
    return voices;
  }

  Future<void> speak(String text, VoiceProfile profile) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return;
    if (!profile.speechEnabled || !_outputEnabled || !_profileEnabled) {
      await _engine.stop();
      return;
    }
    final operation = ++_operation;
    await _engine.stop();
    if (!_canContinue(operation)) return;
    await _engine.awaitSpeakCompletion(true);
    if (!_canContinue(operation)) return;
    await _engine.setSpeechRate(profile.speechRate);
    if (!_canContinue(operation)) return;
    if (profile.voiceName != null) {
      try {
        await _engine.setVoice({
          'name': profile.voiceName!,
          'locale': profile.voiceLocale,
        });
      } catch (_) {
        if (!profile.systemVoiceFallback) rethrow;
        await _engine.setLanguage(profile.voiceLocale);
      }
    } else {
      await _engine.setLanguage(profile.voiceLocale);
    }
    if (!_canContinue(operation)) return;
    await _engine.speak(cleaned, focus: true);
  }

  Future<void> setSpeechEnabled(bool enabled) async {
    _profileEnabled = enabled;
    ++_operation;
    if (!enabled) await _engine.stop();
  }

  bool _canContinue(int operation) =>
      !_disposed &&
      _outputEnabled &&
      _profileEnabled &&
      operation == _operation;

  Future<void> stop() async {
    ++_operation;
    await _engine.stop();
  }

  void dispose() {
    _disposed = true;
    ++_operation;
    _engine.stop();
  }
}

abstract class SpeechEngine {
  Future<dynamic> get voices;
  Future<dynamic> stop();
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion);
  Future<dynamic> setSpeechRate(double rate);
  Future<dynamic> setVoice(Map<String, String> voice);
  Future<dynamic> setLanguage(String language);
  Future<dynamic> speak(String text, {bool focus = false});
}

class FlutterTtsSpeechEngine implements SpeechEngine {
  FlutterTtsSpeechEngine({FlutterTts? engine})
    : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;

  @override
  Future<dynamic> get voices => _engine.getVoices;
  @override
  Future<dynamic> stop() => _engine.stop();
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) =>
      _engine.awaitSpeakCompletion(awaitCompletion);
  @override
  Future<dynamic> setSpeechRate(double rate) => _engine.setSpeechRate(rate);
  @override
  Future<dynamic> setVoice(Map<String, String> voice) =>
      _engine.setVoice(voice);
  @override
  Future<dynamic> setLanguage(String language) => _engine.setLanguage(language);
  @override
  Future<dynamic> speak(String text, {bool focus = false}) =>
      _engine.speak(text, focus: focus);
}
