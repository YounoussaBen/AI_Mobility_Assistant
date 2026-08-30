import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/storage/app_storage.dart';
import '../../companion/domain/companion_models.dart';
import '../../history/application/journey_history_controller.dart';
import '../domain/place.dart';
import '../domain/route_option.dart';

final journeySessionControllerProvider =
    NotifierProvider<JourneySessionController, JourneySessionState>(
      JourneySessionController.new,
    );

class JourneySessionState {
  const JourneySessionState({
    this.phase = CompanionPhase.ready,
    this.turns = const [],
    this.destination,
    this.routes = const [],
    this.selectedMode,
    this.selectedRouteKey,
    this.currentStepIndex = 0,
    this.guidanceView = GuidanceView.guide,
    this.lastInstruction,
  });

  final CompanionPhase phase;
  final List<AssistantTurn> turns;
  final JourneyPlace? destination;
  final List<JourneyRouteOption> routes;
  final JourneyTravelMode? selectedMode;
  final String? selectedRouteKey;
  final int currentStepIndex;
  final GuidanceView guidanceView;
  final String? lastInstruction;

  JourneyRouteOption? get selectedRoute {
    final byKey = routes
        .where((route) => route.routeKey == selectedRouteKey)
        .firstOrNull;
    return byKey ??
        routes.where((route) => route.mode == selectedMode).firstOrNull;
  }

  bool get hasActiveJourney =>
      destination != null &&
      selectedRoute != null &&
      (phase == CompanionPhase.guiding ||
          phase == CompanionPhase.paused ||
          phase == CompanionPhase.rerouting);

  JourneySessionState copyWith({
    CompanionPhase? phase,
    List<AssistantTurn>? turns,
    JourneyPlace? destination,
    List<JourneyRouteOption>? routes,
    JourneyTravelMode? selectedMode,
    String? selectedRouteKey,
    int? currentStepIndex,
    GuidanceView? guidanceView,
    String? lastInstruction,
    bool clearDestination = false,
    bool clearSelection = false,
  }) {
    return JourneySessionState(
      phase: phase ?? this.phase,
      turns: turns ?? this.turns,
      destination: clearDestination ? null : destination ?? this.destination,
      routes: routes ?? this.routes,
      selectedMode: clearSelection ? null : selectedMode ?? this.selectedMode,
      selectedRouteKey: clearSelection
          ? null
          : selectedRouteKey ?? this.selectedRouteKey,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      guidanceView: guidanceView ?? this.guidanceView,
      lastInstruction: lastInstruction ?? this.lastInstruction,
    );
  }

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'turns': [for (final turn in turns.takeLast(60)) turn.toJson()],
    'destination': destination?.toJson(),
    'routes': [for (final route in routes) route.toJson()],
    'selectedMode': selectedMode?.name,
    'selectedRouteKey': selectedRouteKey,
    'currentStepIndex': currentStepIndex,
    'guidanceView': guidanceView.name,
    'lastInstruction': lastInstruction,
  };

  factory JourneySessionState.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) {
      final matches = values.where((value) => value.name == name);
      return matches.isEmpty ? fallback : matches.first;
    }

    final rawTurns = json['turns'] as List<dynamic>? ?? const [];
    final rawRoutes = json['routes'] as List<dynamic>? ?? const [];
    final rawDestination = json['destination'] as Map<String, dynamic>?;
    return JourneySessionState(
      phase: enumValue(
        CompanionPhase.values,
        json['phase'] as String?,
        CompanionPhase.ready,
      ),
      turns: [
        for (final turn in rawTurns.whereType<Map<String, dynamic>>())
          AssistantTurn.fromJson(turn),
      ],
      destination: rawDestination == null
          ? null
          : JourneyPlace.fromJson(rawDestination),
      routes: [
        for (final route in rawRoutes.whereType<Map<String, dynamic>>())
          JourneyRouteOption.fromJson(route),
      ],
      selectedMode: json['selectedMode'] == null
          ? null
          : enumValue(
              JourneyTravelMode.values,
              json['selectedMode'] as String?,
              JourneyTravelMode.walking,
            ),
      selectedRouteKey: json['selectedRouteKey'] as String?,
      currentStepIndex: json['currentStepIndex'] as int? ?? 0,
      guidanceView: enumValue(
        GuidanceView.values,
        json['guidanceView'] as String?,
        GuidanceView.guide,
      ),
      lastInstruction: json['lastInstruction'] as String?,
    );
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    return values.skip(values.length > count ? values.length - count : 0);
  }
}

class JourneySessionController extends Notifier<JourneySessionState> {
  static const _storageKey = 'companion.session.v2';

  @override
  JourneySessionState build() {
    final raw = ref.watch(appStorageProvider).readString(_storageKey);
    if (raw == null) return const JourneySessionState();
    try {
      return JourneySessionState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const JourneySessionState();
    }
  }

  void _persist() {
    unawaited(
      ref
          .read(appStorageProvider)
          .writeString(_storageKey, jsonEncode(state.toJson())),
    );
  }

  void setPhase(CompanionPhase phase) {
    state = state.copyWith(phase: phase);
    _persist();
  }

  void addTurn(AssistantSpeaker speaker, String text, {bool tool = false}) {
    final turn = AssistantTurn(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      speaker: speaker,
      text: text,
      createdAt: DateTime.now(),
      isToolStatus: tool,
    );
    state = state.copyWith(turns: [...state.turns, turn].takeLast(60).toList());
    _persist();
  }

  void beginRequest(String prompt) {
    state = state.copyWith(
      phase: state.hasActiveJourney
          ? state.phase
          : CompanionPhase.understanding,
      turns: <AssistantTurn>[
        ...state.turns,
        AssistantTurn(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          speaker: AssistantSpeaker.user,
          text: prompt,
          createdAt: DateTime.now(),
        ),
      ].takeLast(60).toList(),
    );
    _persist();
  }

  void destinationConfirmed(JourneyPlace destination) {
    state = state.copyWith(
      phase: CompanionPhase.checkingRoutes,
      destination: destination,
      routes: const [],
      clearSelection: true,
    );
    addTurn(
      AssistantSpeaker.companion,
      'Destination confirmed: ${destination.name}. Comparing verified routes.',
      tool: true,
    );
    _persist();
  }

  void routesReady(
    List<JourneyRouteOption> routes, {
    String? preferredRouteKey,
    JourneyTravelMode? preferredMode,
  }) {
    final preferred = routes
        .where((route) => route.routeKey == preferredRouteKey)
        .firstOrNull;
    final sameMode = routes
        .where((route) => route.mode == (preferredMode ?? state.selectedMode))
        .firstOrNull;
    final selected = preferred ?? sameMode ?? routes.firstOrNull;
    state = state.copyWith(
      phase: routes.isEmpty ? CompanionPhase.error : CompanionPhase.routeReady,
      routes: routes,
      selectedMode: selected?.mode,
      selectedRouteKey: selected?.routeKey,
    );
    _persist();
  }

  void selectRoute(JourneyTravelMode mode) {
    final route = state.routes.where((route) => route.mode == mode).firstOrNull;
    if (route == null) return;
    selectRouteByKey(route.routeKey);
  }

  void selectRouteByKey(String routeKey) {
    final route = state.routes
        .where((route) => route.routeKey == routeKey)
        .firstOrNull;
    if (route == null) return;
    state = state.copyWith(
      selectedMode: route.mode,
      selectedRouteKey: route.routeKey,
    );
    _persist();
  }

  JourneyRouteOption? selectAlternative() {
    if (state.routes.length < 2) return null;
    final current = state.selectedRoute;
    final index = current == null ? -1 : state.routes.indexOf(current);
    final next = state.routes[(index + 1) % state.routes.length];
    selectRouteByKey(next.routeKey);
    return next;
  }

  JourneyRouteOption? selectCheapest() {
    final priced = state.routes.where((route) => route.fareMinorUnits != null);
    if (priced.isEmpty) return null;
    final route = priced.reduce(
      (a, b) => a.fareMinorUnits! <= b.fareMinorUnits! ? a : b,
    );
    selectRouteByKey(route.routeKey);
    return route;
  }

  JourneyRouteOption? selectFewestTransfers() {
    final evidenced = state.routes.where((route) => route.transfers != null);
    if (evidenced.isEmpty) return null;
    final route = evidenced.reduce(
      (a, b) => a.transfers! <= b.transfers! ? a : b,
    );
    selectRouteByKey(route.routeKey);
    return route;
  }

  void startJourney() {
    final route = state.selectedRoute;
    if (route == null) return;
    final instruction =
        route.firstStep?.instruction ??
        'Start toward ${state.destination?.name ?? 'your destination'}.';
    state = state.copyWith(
      phase: CompanionPhase.guiding,
      currentStepIndex: 0,
      guidanceView: GuidanceView.guide,
      lastInstruction: instruction,
    );
    _persist();
  }

  void setGuidanceView(GuidanceView view) {
    state = state.copyWith(guidanceView: view);
    _persist();
  }

  void togglePaused() {
    if (state.phase == CompanionPhase.paused) {
      state = state.copyWith(phase: CompanionPhase.guiding);
    } else if (state.phase == CompanionPhase.guiding) {
      state = state.copyWith(phase: CompanionPhase.paused);
    }
    _persist();
  }

  void beginReroute() {
    if (!state.hasActiveJourney) return;
    state = state.copyWith(phase: CompanionPhase.rerouting);
    _persist();
  }

  void cancelReroute() {
    if (state.phase != CompanionPhase.rerouting) return;
    state = state.copyWith(phase: CompanionPhase.guiding);
    _persist();
  }

  void applyReroute(List<JourneyRouteOption> routes) {
    final previousMode = state.selectedMode;
    routesReady(routes, preferredMode: previousMode);
    startJourney();
  }

  void advanceStep() {
    if (state.phase == CompanionPhase.arrived) return;
    final route = state.selectedRoute;
    if (route == null || route.steps.isEmpty) return;
    final nextIndex = state.currentStepIndex + 1;
    if (nextIndex >= route.steps.length) {
      state = state.copyWith(
        phase: CompanionPhase.arrived,
        lastInstruction: 'You have arrived at ${state.destination?.name}.',
      );
      final destination = state.destination;
      if (destination != null) {
        ref
            .read(journeyHistoryControllerProvider.notifier)
            .recordCompleted(destination, route);
      }
      _persist();
      return;
    }
    final instruction = route.steps[nextIndex].instruction;
    state = state.copyWith(
      currentStepIndex: nextIndex,
      lastInstruction: instruction,
    );
    _persist();
  }

  void endJourney({bool clearConversation = false}) {
    final turns = clearConversation ? const <AssistantTurn>[] : state.turns;
    state = JourneySessionState(turns: turns);
    _persist();
  }

  void clearConversation() {
    state = state.copyWith(turns: const []);
    _persist();
  }
}
