import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/data/speech_output_service.dart';
import '../../voice/domain/voice_profile.dart';
import '../domain/companion_models.dart';

final responsePriorityServiceProvider = Provider<ResponsePriorityService>((
  ref,
) {
  return ResponsePriorityService(ref.watch(speechOutputServiceProvider));
});

class ResponsePriorityService {
  ResponsePriorityService(this._speech);

  final SpeechOutputService _speech;
  ResponsePriority? _activePriority;
  int _generation = 0;

  Future<bool> speak(
    String text,
    VoiceProfile profile, {
    required ResponsePriority priority,
  }) async {
    if (!profile.speechEnabled) return false;
    final active = _activePriority;
    if (active != null &&
        !ResponsePriorityManager.mayInterrupt(
          incoming: priority,
          active: active,
        )) {
      return false;
    }
    final generation = ++_generation;
    if (active != null) await _speech.stop();
    _activePriority = priority;
    try {
      await _speech.speak(text, profile);
      return true;
    } finally {
      if (_generation == generation) _activePriority = null;
    }
  }

  Future<void> stop() async {
    _generation++;
    _activePriority = null;
    await _speech.stop();
  }
}
