import 'package:ai_mobility_assistant/app/theme/app_theme.dart';
import 'package:ai_mobility_assistant/features/perception/presentation/look_ahead_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Journey Lens explains privacy and safety before camera use', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: JourneyLensView(autoStart: false, onClose: () {}),
        ),
      ),
    );

    expect(find.text('Journey Lens'), findsOneWidget);
    expect(find.textContaining('not recorded'), findsOneWidget);
    expect(find.textContaining('cannot confirm distance'), findsOneWidget);
    expect(find.text('Start Journey Lens'), findsOneWidget);
  });

  testWidgets('Journey Lens introduction remains usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: JourneyLensView(autoStart: false, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final start = find.text('Start Journey Lens');
    await tester.ensureVisible(start);
    expect(start, findsOneWidget);
  });
}
