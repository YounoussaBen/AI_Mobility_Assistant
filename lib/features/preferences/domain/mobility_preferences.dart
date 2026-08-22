enum JourneyPriority { accessible, fastest, simplest, affordable }

class MobilityPreferences {
  const MobilityPreferences({
    this.voiceGuidance = true,
    this.wheelchairAccess = false,
    this.reducedWalking = false,
    this.fewerTransfers = true,
    this.vibrationAlerts = true,
    this.largerText = false,
    this.priority = JourneyPriority.accessible,
  });

  final bool voiceGuidance;
  final bool wheelchairAccess;
  final bool reducedWalking;
  final bool fewerTransfers;
  final bool vibrationAlerts;
  final bool largerText;
  final JourneyPriority priority;

  MobilityPreferences copyWith({
    bool? voiceGuidance,
    bool? wheelchairAccess,
    bool? reducedWalking,
    bool? fewerTransfers,
    bool? vibrationAlerts,
    bool? largerText,
    JourneyPriority? priority,
  }) {
    return MobilityPreferences(
      voiceGuidance: voiceGuidance ?? this.voiceGuidance,
      wheelchairAccess: wheelchairAccess ?? this.wheelchairAccess,
      reducedWalking: reducedWalking ?? this.reducedWalking,
      fewerTransfers: fewerTransfers ?? this.fewerTransfers,
      vibrationAlerts: vibrationAlerts ?? this.vibrationAlerts,
      largerText: largerText ?? this.largerText,
      priority: priority ?? this.priority,
    );
  }

  Map<String, Object> toJson() => {
    'voiceGuidance': voiceGuidance,
    'wheelchairAccess': wheelchairAccess,
    'reducedWalking': reducedWalking,
    'fewerTransfers': fewerTransfers,
    'vibrationAlerts': vibrationAlerts,
    'largerText': largerText,
    'priority': priority.name,
  };

  factory MobilityPreferences.fromJson(Map<String, dynamic> json) {
    final priorityName = json['priority'] as String?;
    final priority = JourneyPriority.values.where(
      (value) => value.name == priorityName,
    );

    return MobilityPreferences(
      voiceGuidance: json['voiceGuidance'] as bool? ?? true,
      wheelchairAccess: json['wheelchairAccess'] as bool? ?? false,
      reducedWalking: json['reducedWalking'] as bool? ?? false,
      fewerTransfers: json['fewerTransfers'] as bool? ?? true,
      vibrationAlerts: json['vibrationAlerts'] as bool? ?? true,
      largerText: json['largerText'] as bool? ?? false,
      priority: priority.isEmpty ? JourneyPriority.accessible : priority.first,
    );
  }
}

extension JourneyPriorityLabel on JourneyPriority {
  String get label => switch (this) {
    JourneyPriority.accessible => 'Most accessible',
    JourneyPriority.fastest => 'Fastest',
    JourneyPriority.simplest => 'Simplest journey',
    JourneyPriority.affordable => 'Most affordable',
  };

  String get description => switch (this) {
    JourneyPriority.accessible => 'Prioritize your saved accessibility needs',
    JourneyPriority.fastest => 'Prefer the shortest total journey time',
    JourneyPriority.simplest => 'Prefer less walking and fewer changes',
    JourneyPriority.affordable => 'Prefer lower-cost options when prices exist',
  };
}
