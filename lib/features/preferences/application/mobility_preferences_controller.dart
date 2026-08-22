import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mobility_preferences_repository.dart';
import '../domain/mobility_preferences.dart';

final mobilityPreferencesControllerProvider =
    AsyncNotifierProvider<MobilityPreferencesController, MobilityPreferences>(
      MobilityPreferencesController.new,
    );

class MobilityPreferencesController extends AsyncNotifier<MobilityPreferences> {
  @override
  Future<MobilityPreferences> build() {
    return ref.watch(mobilityPreferencesRepositoryProvider).load();
  }

  Future<void> save(MobilityPreferences preferences) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(mobilityPreferencesRepositoryProvider).save(preferences);
      return preferences;
    });
  }
}
