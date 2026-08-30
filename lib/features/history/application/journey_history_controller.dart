import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/domain/place.dart';
import '../../journey/domain/route_option.dart';
import '../data/journey_history_repository.dart';
import '../domain/journey_record.dart';

final journeyHistoryControllerProvider =
    NotifierProvider<JourneyHistoryController, List<JourneyRecord>>(
      JourneyHistoryController.new,
    );

final historyPrivacyControllerProvider =
    NotifierProvider<HistoryPrivacyController, bool>(
      HistoryPrivacyController.new,
    );

class JourneyHistoryController extends Notifier<List<JourneyRecord>> {
  @override
  List<JourneyRecord> build() {
    return ref.watch(journeyHistoryRepositoryProvider).load();
  }

  void recordCompleted(JourneyPlace destination, JourneyRouteOption route) {
    final repository = ref.read(journeyHistoryRepositoryProvider);
    if (!repository.isEnabled) return;
    final now = DateTime.now();
    final record = JourneyRecord(
      id: '${now.microsecondsSinceEpoch}-${route.routeKey}',
      destination: destination,
      route: route,
      completedAt: now,
    );
    state = [record, ...state].take(100).toList(growable: false);
    unawaited(repository.save(state));
  }

  void remove(String id) {
    state = [
      for (final record in state)
        if (record.id != id) record,
    ];
    unawaited(ref.read(journeyHistoryRepositoryProvider).save(state));
  }

  void clear() {
    state = const [];
    unawaited(ref.read(journeyHistoryRepositoryProvider).clear());
  }
}

class HistoryPrivacyController extends Notifier<bool> {
  @override
  bool build() => ref.watch(journeyHistoryRepositoryProvider).isEnabled;

  void setEnabled(bool enabled) {
    state = enabled;
    unawaited(ref.read(journeyHistoryRepositoryProvider).setEnabled(enabled));
    if (!enabled) ref.read(journeyHistoryControllerProvider.notifier).clear();
  }
}
