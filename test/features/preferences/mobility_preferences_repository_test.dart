import 'package:ai_mobility_assistant/features/preferences/data/mobility_preferences_repository.dart';
import 'package:ai_mobility_assistant/features/preferences/domain/mobility_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saves and restores mobility preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = MobilityPreferencesRepository(
      await SharedPreferences.getInstance(),
    );
    const expected = MobilityPreferences(
      wheelchairAccess: true,
      reducedWalking: true,
      largerText: true,
      priority: JourneyPriority.simplest,
    );

    await repository.save(expected);
    await repository.completeIntro();
    await repository.completeProfile();

    final restored = await repository.load();
    expect(restored.wheelchairAccess, isTrue);
    expect(restored.reducedWalking, isTrue);
    expect(restored.largerText, isTrue);
    expect(restored.priority, JourneyPriority.simplest);
    expect(repository.hasCompletedIntro, isTrue);
    expect(repository.isProfileComplete, isTrue);
  });
}
