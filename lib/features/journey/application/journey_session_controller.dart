import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../companion/domain/companion_models.dart';
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
    this.currentStepIndex = 0,
    this.guidanceView = GuidanceView.guide,
    this.lastInstruction,
  });

  final CompanionPhase phase;
  final List<AssistantTurn> turns;
  final JourneyPlace? destination;
  final List<JourneyRouteOption> routes;
  final JourneyTravelMode? selectedMode;
  final int currentStepIndex;
  final GuidanceView guidanceView;
  final String? lastInstruction;

  JourneyRouteOption? get selectedRoute =>
      routes.where((route) => route.mode == selectedMode).firstOrNull;

  bool get hasActiveJourney =>
      destination != null &&
      selectedRoute != null &&
      (phase == CompanionPhase.guiding || phase == CompanionPhase.paused);

  JourneySessionState copyWith({
    CompanionPhase? phase,
    List<AssistantTurn>? turns,
    JourneyPlace? destination,
    List<JourneyRouteOption>? routes,
    JourneyTravelMode? selectedMode,
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
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      guidanceView: guidanceView ?? this.guidanceView,
      lastInstruction: lastInstruction ?? this.lastInstruction,
    );
  }
}

class JourneySessionController extends Notifier<JourneySessionState> {
  @override
  JourneySessionState build() => const JourneySessionState();

  void setPhase(CompanionPhase phase) {
    state = state.copyWith(phase: phase);
  }

  void addTurn(AssistantSpeaker speaker, String text, {bool tool = false}) {
    final turn = AssistantTurn(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      speaker: speaker,
      text: text,
      createdAt: DateTime.now(),
      isToolStatus: tool,
    );
    state = state.copyWith(turns: [...state.turns, turn]);
  }

  void beginRequest(String prompt) {
    state = state.copyWith(
      phase: state.hasActiveJourney
          ? state.phase
          : CompanionPhase.understanding,
      turns: [
        ...state.turns,
        AssistantTurn(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          speaker: AssistantSpeaker.user,
          text: prompt,
          createdAt: DateTime.now(),
        ),
      ],
    );
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
  }

  void routesReady(List<JourneyRouteOption> routes) {
    state = state.copyWith(
      phase: routes.isEmpty ? CompanionPhase.error : CompanionPhase.routeReady,
      routes: routes,
      selectedMode: routes.firstOrNull?.mode,
    );
  }

  void selectRoute(JourneyTravelMode mode) {
    state = state.copyWith(selectedMode: mode);
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
  }

  void setGuidanceView(GuidanceView view) {
    state = state.copyWith(guidanceView: view);
  }

  void togglePaused() {
    if (state.phase == CompanionPhase.paused) {
      state = state.copyWith(phase: CompanionPhase.guiding);
    } else if (state.phase == CompanionPhase.guiding) {
      state = state.copyWith(phase: CompanionPhase.paused);
    }
  }

  void advanceStep() {
    final route = state.selectedRoute;
    if (route == null || route.steps.isEmpty) return;
    final nextIndex = state.currentStepIndex + 1;
    if (nextIndex >= route.steps.length) {
      state = state.copyWith(
        phase: CompanionPhase.arrived,
        lastInstruction: 'You have arrived at ${state.destination?.name}.',
      );
      return;
    }
    final instruction = route.steps[nextIndex].instruction;
    state = state.copyWith(
      currentStepIndex: nextIndex,
      lastInstruction: instruction,
    );
  }

  void endJourney() {
    state = const JourneySessionState();
  }
}
