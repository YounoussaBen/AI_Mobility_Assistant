import 'package:ai_mobility_assistant/features/perception/presentation/look_ahead_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Look Ahead opens with a concise camera handoff', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LookAheadScreen())),
    );

    expect(find.text('Point your phone forward'), findsOneWidget);
    expect(find.text('Start camera'), findsOneWidget);
    expect(find.text('An intentional camera check'), findsNothing);
    expect(find.text('Conditions matter'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
