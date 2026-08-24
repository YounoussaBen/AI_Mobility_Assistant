import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/voice_preferences_repository.dart';
import '../domain/voice_profile.dart';

final voiceProfileControllerProvider =
    AsyncNotifierProvider<VoiceProfileController, VoiceProfile>(
      VoiceProfileController.new,
    );

class VoiceProfileController extends AsyncNotifier<VoiceProfile> {
  @override
  Future<VoiceProfile> build() {
    return ref.watch(voicePreferencesRepositoryProvider).load();
  }

  Future<void> save(VoiceProfile profile) async {
    await ref.read(voicePreferencesRepositoryProvider).save(profile);
    state = AsyncData(profile);
  }
}
