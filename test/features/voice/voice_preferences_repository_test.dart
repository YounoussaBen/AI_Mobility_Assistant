import 'package:ai_mobility_assistant/features/voice/data/voice_preferences_repository.dart';
import 'package:ai_mobility_assistant/features/voice/domain/voice_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saves and restores every voice guidance choice', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = VoicePreferencesRepository(
      await SharedPreferences.getInstance(),
    );
    const profile = VoiceProfile(
      speechEnabled: false,
      voiceName: 'Test voice',
      voiceLocale: 'en-GH',
      speechRate: 0.42,
      verbosity: GuidanceVerbosity.brief,
      speakStreetNames: false,
      repeatCriticalWarnings: false,
      haptics: false,
      captions: false,
      systemVoiceFallback: false,
    );

    await repository.save(profile);
    final restored = await repository.load();

    expect(restored.speechEnabled, isFalse);
    expect(restored.voiceName, 'Test voice');
    expect(restored.voiceLocale, 'en-GH');
    expect(restored.speechRate, 0.42);
    expect(restored.verbosity, GuidanceVerbosity.brief);
    expect(restored.speakStreetNames, isFalse);
    expect(restored.repeatCriticalWarnings, isFalse);
    expect(restored.haptics, isFalse);
    expect(restored.captions, isFalse);
    expect(restored.systemVoiceFallback, isFalse);
  });

  test(
    'speech remains enabled for profiles saved before the setting existed',
    () {
      final restored = VoiceProfile.fromJson(const {});

      expect(restored.speechEnabled, isTrue);
    },
  );
}
