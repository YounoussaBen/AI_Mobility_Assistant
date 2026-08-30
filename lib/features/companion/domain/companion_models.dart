enum CompanionPhase {
  ready,
  listening,
  understanding,
  clarifying,
  checkingRoutes,
  routeReady,
  guiding,
  paused,
  rerouting,
  arrived,
  error,
}

extension CompanionPhaseLabel on CompanionPhase {
  String get label => switch (this) {
    CompanionPhase.ready => 'Ready',
    CompanionPhase.listening => 'Listening',
    CompanionPhase.understanding => 'Understanding',
    CompanionPhase.clarifying => 'Need one detail',
    CompanionPhase.checkingRoutes => 'Checking routes',
    CompanionPhase.routeReady => 'Routes ready',
    CompanionPhase.guiding => 'Guiding',
    CompanionPhase.paused => 'Journey paused',
    CompanionPhase.rerouting => 'Updating route',
    CompanionPhase.arrived => 'Arrived',
    CompanionPhase.error => 'Needs attention',
  };

  String get assistiveDescription => switch (this) {
    CompanionPhase.ready => 'Mobility AI is ready for a command.',
    CompanionPhase.listening => 'Mobility AI is listening now.',
    CompanionPhase.understanding => 'Mobility AI is interpreting your request.',
    CompanionPhase.clarifying => 'Mobility AI needs more information.',
    CompanionPhase.checkingRoutes => 'Trusted map services are being checked.',
    CompanionPhase.routeReady => 'Verified route choices are available.',
    CompanionPhase.guiding => 'Turn-by-turn guidance is active.',
    CompanionPhase.paused => 'Journey guidance is paused.',
    CompanionPhase.rerouting => 'The route is being recalculated.',
    CompanionPhase.arrived => 'The journey is complete.',
    CompanionPhase.error => 'An action is needed before continuing.',
  };
}

enum AssistantSpeaker { user, companion, system }

class AssistantTurn {
  const AssistantTurn({
    required this.id,
    required this.speaker,
    required this.text,
    required this.createdAt,
    this.isToolStatus = false,
  });

  final String id;
  final AssistantSpeaker speaker;
  final String text;
  final DateTime createdAt;
  final bool isToolStatus;

  Map<String, Object> toJson() => {
    'id': id,
    'speaker': speaker.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'isToolStatus': isToolStatus,
  };

  factory AssistantTurn.fromJson(Map<String, dynamic> json) {
    final speakerName = json['speaker'] as String?;
    final speakers = AssistantSpeaker.values.where(
      (speaker) => speaker.name == speakerName,
    );
    return AssistantTurn(
      id: json['id'] as String? ?? '',
      speaker: speakers.isEmpty ? AssistantSpeaker.system : speakers.first,
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isToolStatus: json['isToolStatus'] as bool? ?? false,
    );
  }
}

enum GuidanceView { guide, map, lookAhead }

extension GuidanceViewLabel on GuidanceView {
  String get label => switch (this) {
    GuidanceView.guide => 'Guide',
    GuidanceView.map => 'Map',
    GuidanceView.lookAhead => 'Look ahead',
  };
}

enum HazardDirection { left, centre, right, unknown }

enum HazardDistanceBand { immediate, near, ahead, unknown }

enum HazardUrgency { informational, caution, critical }

class HazardEvent {
  const HazardEvent({
    required this.type,
    required this.direction,
    required this.distanceBand,
    required this.urgency,
    required this.confidence,
    required this.firstSeen,
    required this.lastSeen,
  });

  final String type;
  final HazardDirection direction;
  final HazardDistanceBand distanceBand;
  final HazardUrgency urgency;
  final double confidence;
  final DateTime firstSeen;
  final DateTime lastSeen;
}

enum ResponsePriority {
  informational,
  conversation,
  routeChange,
  immediateManeuver,
  criticalHazard,
}

class GuidanceMessage {
  const GuidanceMessage({required this.text, required this.priority});

  final String text;
  final ResponsePriority priority;
}

abstract final class ResponsePriorityManager {
  static bool mayInterrupt({
    required ResponsePriority incoming,
    required ResponsePriority active,
  }) {
    return incoming.index > active.index;
  }
}
