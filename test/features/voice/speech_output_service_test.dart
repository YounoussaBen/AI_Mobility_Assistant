import 'dart:async';

import 'package:ai_mobility_assistant/features/voice/data/speech_output_service.dart';
import 'package:ai_mobility_assistant/features/voice/domain/voice_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled profile stops output without speaking', () async {
    final engine = _FakeSpeechEngine();
    final service = SpeechOutputService(engine: engine);

    await service.speak(
      'Do not read this',
      const VoiceProfile(speechEnabled: false),
    );

    expect(engine.stopCalls, 1);
    expect(engine.spoken, isEmpty);
  });

  test('global voice-guidance opt-out prevents speech', () async {
    final engine = _FakeSpeechEngine();
    final service = SpeechOutputService(engine: engine, outputEnabled: false);

    await service.speak('Do not read this', const VoiceProfile());

    expect(engine.stopCalls, 1);
    expect(engine.spoken, isEmpty);
  });

  test('disabling during async setup prevents the pending speech', () async {
    final engine = _FakeSpeechEngine()..pauseSpeechRate();
    final service = SpeechOutputService(engine: engine);

    final pending = service.speak('Pending guidance', const VoiceProfile());
    await engine.speechRateStarted.future;
    await service.setSpeechEnabled(false);
    engine.finishSpeechRate();
    await pending;

    expect(engine.stopCalls, 2);
    expect(engine.spoken, isEmpty);
  });

  test('stale enabled profile cannot override the persistent mute', () async {
    final engine = _FakeSpeechEngine();
    final service = SpeechOutputService(engine: engine);
    await service.setSpeechEnabled(false);

    await service.speak('Stale guidance', const VoiceProfile());

    expect(engine.stopCalls, 2);
    expect(engine.spoken, isEmpty);
  });
}

class _FakeSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  final speechRateStarted = Completer<void>();
  Completer<void>? _speechRateGate;
  int stopCalls = 0;

  void pauseSpeechRate() {
    _speechRateGate = Completer<void>();
  }

  void finishSpeechRate() {
    _speechRateGate?.complete();
  }

  @override
  Future<dynamic> get voices async => const [];

  @override
  Future<dynamic> stop() async {
    stopCalls++;
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {}

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    if (!speechRateStarted.isCompleted) speechRateStarted.complete();
    await _speechRateGate?.future;
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {}

  @override
  Future<dynamic> setLanguage(String language) async {}

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
  }
}
