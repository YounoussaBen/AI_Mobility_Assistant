enum GuidanceVerbosity { brief, standard, detailed }

extension GuidanceVerbosityLabel on GuidanceVerbosity {
  String get label => switch (this) {
    GuidanceVerbosity.brief => 'Brief',
    GuidanceVerbosity.standard => 'Standard',
    GuidanceVerbosity.detailed => 'Detailed',
  };

  String get sample => switch (this) {
    GuidanceVerbosity.brief => 'Turn left in 20 metres.',
    GuidanceVerbosity.standard =>
      'In 20 metres, turn left. The corner is after the pharmacy.',
    GuidanceVerbosity.detailed =>
      'Continue for 20 metres, then turn left after the pharmacy. '
          'The next instruction follows in about one minute.',
  };
}

class DeviceVoice {
  const DeviceVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  String get id => '$name::$locale';

  String get displayName {
    final cleaned = name.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return cleaned.isEmpty ? locale : cleaned;
  }

  Map<String, String> get platformValue => {'name': name, 'locale': locale};
}

class VoiceProfile {
  const VoiceProfile({
    this.voiceName,
    this.voiceLocale = 'en-US',
    this.speechRate = 0.48,
    this.verbosity = GuidanceVerbosity.standard,
    this.speakStreetNames = true,
    this.repeatCriticalWarnings = true,
    this.haptics = true,
    this.captions = true,
    this.systemVoiceFallback = true,
  });

  final String? voiceName;
  final String voiceLocale;
  final double speechRate;
  final GuidanceVerbosity verbosity;
  final bool speakStreetNames;
  final bool repeatCriticalWarnings;
  final bool haptics;
  final bool captions;
  final bool systemVoiceFallback;

  VoiceProfile copyWith({
    String? voiceName,
    String? voiceLocale,
    double? speechRate,
    GuidanceVerbosity? verbosity,
    bool? speakStreetNames,
    bool? repeatCriticalWarnings,
    bool? haptics,
    bool? captions,
    bool? systemVoiceFallback,
    bool clearVoice = false,
  }) {
    return VoiceProfile(
      voiceName: clearVoice ? null : voiceName ?? this.voiceName,
      voiceLocale: voiceLocale ?? this.voiceLocale,
      speechRate: speechRate ?? this.speechRate,
      verbosity: verbosity ?? this.verbosity,
      speakStreetNames: speakStreetNames ?? this.speakStreetNames,
      repeatCriticalWarnings:
          repeatCriticalWarnings ?? this.repeatCriticalWarnings,
      haptics: haptics ?? this.haptics,
      captions: captions ?? this.captions,
      systemVoiceFallback: systemVoiceFallback ?? this.systemVoiceFallback,
    );
  }

  Map<String, Object?> toJson() => {
    'voiceName': voiceName,
    'voiceLocale': voiceLocale,
    'speechRate': speechRate,
    'verbosity': verbosity.name,
    'speakStreetNames': speakStreetNames,
    'repeatCriticalWarnings': repeatCriticalWarnings,
    'haptics': haptics,
    'captions': captions,
    'systemVoiceFallback': systemVoiceFallback,
  };

  factory VoiceProfile.fromJson(Map<String, dynamic> json) {
    final verbosityName = json['verbosity'] as String?;
    final verbosity = GuidanceVerbosity.values.where(
      (value) => value.name == verbosityName,
    );
    return VoiceProfile(
      voiceName: json['voiceName'] as String?,
      voiceLocale: json['voiceLocale'] as String? ?? 'en-US',
      speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.48,
      verbosity: verbosity.isEmpty
          ? GuidanceVerbosity.standard
          : verbosity.first,
      speakStreetNames: json['speakStreetNames'] as bool? ?? true,
      repeatCriticalWarnings: json['repeatCriticalWarnings'] as bool? ?? true,
      haptics: json['haptics'] as bool? ?? true,
      captions: json['captions'] as bool? ?? true,
      systemVoiceFallback: json['systemVoiceFallback'] as bool? ?? true,
    );
  }
}
