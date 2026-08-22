import 'package:ai_mobility_assistant/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the setup confirmation screen', (tester) async {
    await tester.pumpWidget(const MobilityAssistantApp());

    expect(find.text('AI Mobility Assistant'), findsOneWidget);
    expect(find.text('Project setup complete'), findsOneWidget);
    expect(
      find.text('Flutter and Firebase are ready for feature development.'),
      findsOneWidget,
    );
  });
}
