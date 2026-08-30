import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/voice_profile.dart';

final speechOutputServiceProvider = Provider<SpeechOutputService>((ref) {
  final service = SpeechOutputService();
  ref.onDispose(service.dispose);
  return service;
});

class SpeechOutputService {
  SpeechOutputService({FlutterTts? engine}) : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;

  Future<List<DeviceVoice>> availableVoices() async {
    final rawVoices = await _engine.getVoices;
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
    await _engine.stop();
    await _engine.awaitSpeakCompletion(true);
    await _engine.setSpeechRate(profile.speechRate);
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
    await _engine.speak(cleaned, focus: true);
  }

  Future<void> stop() async {
    await _engine.stop();
  }

  void dispose() {
    _engine.stop();
  }
}
