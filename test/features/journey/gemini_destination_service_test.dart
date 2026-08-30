import 'package:ai_mobility_assistant/features/companion/domain/companion_models.dart';
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

  test('offline interpreter resolves contextual companion tools', () async {
    expect(
      (await service.interpret('Why is this route recommended?')).action,
      CompanionAction.explainRecommendation,
    );
    expect(
      (await service.interpret('The bus is delayed, what should I do?')).action,
      CompanionAction.reportDelay,
    );
    expect(
      (await service.interpret('Give me a cheaper option')).action,
      CompanionAction.cheaperRoute,
    );
    expect(
      (await service.interpret('Use a route with fewer transfers')).action,
      CompanionAction.fewerTransfers,
    );
  });

  test('ordinary conversation gets a natural reply', () async {
    final command = await service.interpret('How are you today?');

    expect(command.action, CompanionAction.conversationalReply);
    expect(command.message, 'I’m good—thanks for asking. How are you doing?');
  });

  test('a broad Accra outing request starts a useful conversation', () async {
    final command = await service.interpret(
      'Can you suggest me somewhere to go out and have fun',
    );

    expect(command.action, CompanionAction.conversationalReply);
    expect(command.needsClarification, isTrue);
    expect(command.message, contains('What kind of outing'));
    expect(command.message, isNot(contains('Accra')));
  });

  test('an outing follow-up searches the chosen category', () async {
    final command = await service.interpret(
      'Live music',
      context: CompanionContext(
        recentTurns: [
          AssistantTurn(
            id: '1',
            speaker: AssistantSpeaker.companion,
            text:
                'Absolutely. What kind of outing sounds good—live music, a beach, food, art, or somewhere relaxed?',
            createdAt: DateTime(2026),
          ),
        ],
      ),
    );

    expect(command.action, CompanionAction.searchPlaces);
    expect(command.query, 'live music');
  });

  test('a specific leisure suggestion searches trusted places', () async {
    final command = await service.interpret(
      'Can you recommend somewhere with live music?',
    );

    expect(command.action, CompanionAction.searchPlaces);
    expect(command.query, 'live music');
  });

  test('offline interpreter understands an Accra trotro request', () async {
    final command = await service.interpret('Catch a trotro to Madina station');

    expect(command.action, CompanionAction.searchPlaces);
    expect(command.query, 'Madina station');
  });
}
