import 'package:ai_mobility_assistant/features/home/presentation/support_screen.dart';
import 'package:ai_mobility_assistant/features/home/presentation/travel_history_screen.dart';
import 'package:ai_mobility_assistant/features/saved_places/presentation/saved_places_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saved places is a working empty state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SavedPlacesScreen())),
    );

    expect(find.text('Saved places'), findsOneWidget);
    expect(find.text('No saved places'), findsOneWidget);
    expect(find.text('Find a place'), findsOneWidget);
  });

  testWidgets('travel history explains local persistence', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TravelHistoryScreen())),
    );

    expect(find.text('Travel history'), findsOneWidget);
    expect(find.text('No journeys yet'), findsOneWidget);
    expect(find.textContaining('stored only on this device'), findsOneWidget);
  });

  testWidgets('support provides actionable help instead of a placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SupportScreen()));

    expect(find.text('Support'), findsOneWidget);
    expect(find.text('I cannot find a destination'), findsOneWidget);
    expect(find.text('Voice input is not responding'), findsOneWidget);
  });
}
