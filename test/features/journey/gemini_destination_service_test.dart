import 'package:ai_mobility_assistant/features/journey/data/gemini_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = GeminiDestinationService(apiKey: '', model: 'unused');

  test(
    'offline interpreter requests a place search without inventing a route',
    () async {
      final command = await service.interpret('Take me to Osu pharmacy');

      expect(command.action, CompanionAction.searchPlaces);
      expect(command.query, 'Osu pharmacy');
    },
  );

  test(
    'offline interpreter recognizes Look Ahead as an approved action',
    () async {
      final command = await service.interpret('What is ahead of me?');

      expect(command.action, CompanionAction.lookAhead);
      expect(command.query, isNull);
    },
  );
}
