import 'package:ai_mobility_assistant/features/companion/domain/companion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only higher-priority guidance may interrupt active guidance', () {
    expect(
      ResponsePriorityManager.mayInterrupt(
        incoming: ResponsePriority.criticalHazard,
        active: ResponsePriority.immediateManeuver,
      ),
      isTrue,
    );
    expect(
      ResponsePriorityManager.mayInterrupt(
        incoming: ResponsePriority.conversation,
        active: ResponsePriority.immediateManeuver,
      ),
      isFalse,
    );
  });
}
