import 'package:ai_mobility_assistant/features/perception/presentation/look_ahead_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Look Ahead opens as a privacy-first Journey Lens', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LookAheadScreen())),
    );

    expect(find.text('Journey Lens'), findsOneWidget);
    expect(find.text('Start Journey Lens'), findsOneWidget);
    expect(find.textContaining('not recorded'), findsOneWidget);
    expect(find.textContaining('whether a path is safe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
