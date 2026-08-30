import 'dart:collection';

import 'package:dio/dio.dart';

import '../../companion/domain/companion_models.dart';
import '../domain/accra_operating_area.dart';

enum CompanionAction {
  searchPlaces,
  lookAhead,
  repeatInstruction,
  pauseJourney,
  resumeJourney,
  findTransport,
  explainRecommendation,
  alternativeRoute,
  reportDelay,
  cheaperRoute,
  fewerTransfers,
  saveDestination,
  listSavedPlaces,
  endJourney,
  conversationalReply,
  unknown,
}

class CompanionContext {
  const CompanionContext({
    this.recentTurns = const [],
    this.destination,
    this.selectedRoute,
    this.routeChoices = const [],
    this.savedPlaces = const [],
    this.preferenceSummary,
  });

  final List<AssistantTurn> recentTurns;
  final String? destination;
  final String? selectedRoute;
  final List<String> routeChoices;
  final List<String> savedPlaces;
  final String? preferenceSummary;

  Map<String, Object?> toJson() => {
    'operatingArea': AccraOperatingArea.name,
    'language': AccraOperatingArea.languageCode,
    'destination': destination,
    'selectedRoute': selectedRoute,
    'routeChoices': routeChoices,
    'savedPlaces': savedPlaces,
    'preferenceSummary': preferenceSummary,
    'recentTurns': [
      for (final turn in recentTurns.takeLast(12))
        {'speaker': turn.speaker.name, 'text': turn.text},
    ],
  };

  String get fingerprint => [
    destination,
    selectedRoute,
    ...routeChoices,
    ...savedPlaces,
    preferenceSummary,
    for (final turn in recentTurns.takeLast(4)) turn.text,
  ].whereType<String>().join('|').toLowerCase();

  String get modelSummary {
    return 'Deployment context: Accra, Ghana only; Ghanaian English. '
        'Verified app context: destination=${destination ?? 'none'}; '
        'selectedRoute=${selectedRoute ?? 'none'}; '
        'routeChoices=${routeChoices.isEmpty ? 'none' : routeChoices.join(' / ')}; '
        'savedPlaces=${savedPlaces.isEmpty ? 'none' : savedPlaces.join(' / ')}; '
        'preferences=${preferenceSummary ?? 'not loaded'}.';
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    return values.skip(values.length > count ? values.length - count : 0);
  }
}

class CompanionCommand {
  const CompanionCommand({
    required this.action,
    this.query,
    this.needsClarification = false,
    this.message,
  });

  final CompanionAction action;
  final String? query;
  final bool needsClarification;
  final String? message;
}

/// Interprets a short user command and returns an approved app action.
///
/// The model never executes map, navigation, camera, or journey actions. It can
/// only request one of the declarations below; the app validates and performs
/// that action. Production builds should call this contract through the
/// protected companion backend rather than ship a Gemini key in the client.
class GeminiDestinationService {
  GeminiDestinationService({
    required String apiKey,
    required String model,
    String backendUrl = '',
    Future<String?> Function()? accessToken,
    Dio? dio,
  }) : _apiKey = apiKey,
       _model = model,
       _backendDio = backendUrl.isEmpty
           ? null
           : Dio(
               BaseOptions(baseUrl: backendUrl.replaceFirst(RegExp(r'/$'), '')),
             ),
       _accessToken = accessToken,
       _dio =
           dio ??
           Dio(
             BaseOptions(baseUrl: 'https://generativelanguage.googleapis.com'),
           );

  final String _apiKey;
  final String _model;
  final Dio _dio;
  final Dio? _backendDio;
  final Future<String?> Function()? _accessToken;
  final LinkedHashMap<String, ({DateTime createdAt, CompanionCommand command})>
  _commandCache = LinkedHashMap();

  bool get isConfigured => _backendDio != null || _apiKey.isNotEmpty;

  Future<CompanionCommand> interpret(
    String transcript, {
    CompanionContext context = const CompanionContext(),
  }) async {
    final key = '${transcript.trim().toLowerCase()}::${context.fingerprint}';
    final cached = _commandCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(minutes: 10)) {
      return cached.command;
    }
    final command = await _interpretUncached(transcript, context);
    _commandCache[key] = (createdAt: DateTime.now(), command: command);
    while (_commandCache.length > 48) {
      _commandCache.remove(_commandCache.keys.first);
    }
    return command;
  }

  Future<CompanionCommand> _interpretUncached(
    String transcript,
    CompanionContext context,
  ) async {
    final fallback = _fallbackCommand(transcript);
    final backend = _backendDio;
    if (backend != null) {
      try {
        final response = await backend.post<Map<String, dynamic>>(
          '/v1/companion/interpret',
          data: {'text': transcript, 'context': context.toJson()},
          options: await _authenticatedOptions(),
        );
        return _fromBackend(response.data, fallback);
      } catch (_) {
        return fallback;
      }
    }
    if (!isConfigured) return fallback;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1beta/models/$_model:generateContent',
        data: {
          'systemInstruction': {
            'parts': [
              {
                'text':
                    'You interpret short commands for a mobility companion. '
                    'This deployment serves Accra, Ghana only. Understand '
                    'Ghanaian English and Accra travel language such as trotro, '
                    'shared taxi, station, lorry station, junction, Circle, 37, '
                    'Madina, Osu, Kaneshie, and Accra Mall. Preserve useful '
                    'local landmark and neighbourhood words in place queries. '
                    'If the user clearly asks for a destination outside Accra, '
                    'use reply to say that the pilot currently covers Accra only. '
                    'Request exactly one approved function. Never invent a '
                    'destination, route, maneuver, accessibility fact, hazard, '
                    'distance, or live condition. If a destination is ambiguous, '
                    'search using the user’s exact useful place words so the app '
                    'can present choices. Use the verified context to resolve '
                    'follow-ups such as “why”, “another one”, “cheaper”, and '
                    '“the bus is delayed”. Never describe simulated transport '
                    'as live and never claim an action was executed.',
              },
              {'text': context.modelSummary},
            ],
          },
          'contents': [
            for (final turn in context.recentTurns.takeLast(12))
              {
                'role': turn.speaker == AssistantSpeaker.user
                    ? 'user'
                    : 'model',
                'parts': [
                  {'text': turn.text},
                ],
              },
            {
              'role': 'user',
              'parts': [
                {'text': transcript},
              ],
            },
          ],
          'tools': [
            {
              'functionDeclarations': [
                {
                  'name': 'search_places',
                  'description':
                      'Search trusted Places data inside the Accra pilot area.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': {
                      'query': {
                        'type': 'STRING',
                        'description':
                            'Only the useful Accra destination, landmark, neighbourhood, or category words.',
                      },
                    },
                    'required': ['query'],
                  },
                },
                {
                  'name': 'look_ahead',
                  'description':
                      'Open the intentional on-device camera observation tool.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'repeat_instruction',
                  'description':
                      'Repeat the verified current navigation instruction.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'pause_journey',
                  'description': 'Pause active journey guidance.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'resume_journey',
                  'description': 'Resume a paused journey.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'find_transport',
                  'description':
                      'Show transport availability for the current journey context.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'explain_recommendation',
                  'description':
                      'Explain the selected or recommended route using verified route evidence.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'find_alternative_route',
                  'description': 'Select or calculate another route.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'report_delay',
                  'description':
                      'Report a delay or disruption and request updated choices.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'prefer_cheaper_route',
                  'description':
                      'Choose a route with lower verified fare evidence.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'prefer_fewer_transfers',
                  'description':
                      'Choose a route with fewer verified transfers.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'save_destination',
                  'description':
                      'Save the confirmed current destination on device.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'list_saved_places',
                  'description': 'Show destinations saved on this device.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'end_journey',
                  'description': 'Ask to end the active journey.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': <String, Object>{},
                  },
                },
                {
                  'name': 'reply',
                  'description':
                      'Give a brief companion reply that makes no unverified route, place, safety, or live-condition claims.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': {
                      'message': {'type': 'STRING'},
                    },
                    'required': ['message'],
                  },
                },
              ],
            },
          ],
          'toolConfig': {
            'functionCallingConfig': {'mode': 'ANY'},
          },
          'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 120},
        },
        options: Options(headers: {'x-goog-api-key': _apiKey}),
      );

      final candidates = response.data?['candidates'] as List<dynamic>?;
      final candidate = candidates?.firstOrNull as Map<String, dynamic>?;
      final parts =
          (candidate?['content'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      for (final rawPart in parts ?? const <dynamic>[]) {
        final part = rawPart as Map<String, dynamic>?;
        final call = part?['functionCall'] as Map<String, dynamic>?;
        if (call == null) continue;
        final name = call['name'] as String?;
        final args = call['args'] as Map<String, dynamic>? ?? const {};
        return _fromFunction(name, args, fallback);
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<String> destinationFromSpeech(String transcript) async {
    final command = await interpret(transcript);
    return command.action == CompanionAction.searchPlaces &&
            command.query?.trim().isNotEmpty == true
        ? command.query!.trim()
        : _stripTravelWords(transcript);
  }

  CompanionCommand _fromFunction(
    String? name,
    Map<String, dynamic> args,
    CompanionCommand fallback,
  ) {
    return switch (name) {
      'search_places' => CompanionCommand(
        action: CompanionAction.searchPlaces,
        query: (args['query'] as String?)?.trim(),
      ),
      'look_ahead' => const CompanionCommand(action: CompanionAction.lookAhead),
      'repeat_instruction' => const CompanionCommand(
        action: CompanionAction.repeatInstruction,
      ),
      'pause_journey' => const CompanionCommand(
        action: CompanionAction.pauseJourney,
      ),
      'resume_journey' => const CompanionCommand(
        action: CompanionAction.resumeJourney,
      ),
      'find_transport' => const CompanionCommand(
        action: CompanionAction.findTransport,
      ),
      'explain_recommendation' => const CompanionCommand(
        action: CompanionAction.explainRecommendation,
      ),
      'find_alternative_route' => const CompanionCommand(
        action: CompanionAction.alternativeRoute,
      ),
      'report_delay' => const CompanionCommand(
        action: CompanionAction.reportDelay,
      ),
      'prefer_cheaper_route' => const CompanionCommand(
        action: CompanionAction.cheaperRoute,
      ),
      'prefer_fewer_transfers' => const CompanionCommand(
        action: CompanionAction.fewerTransfers,
      ),
      'save_destination' => const CompanionCommand(
        action: CompanionAction.saveDestination,
      ),
      'list_saved_places' => const CompanionCommand(
        action: CompanionAction.listSavedPlaces,
      ),
      'end_journey' => const CompanionCommand(
        action: CompanionAction.endJourney,
      ),
      'reply' => CompanionCommand(
        action: CompanionAction.conversationalReply,
        message: (args['message'] as String?)?.trim(),
      ),
      _ => fallback,
    };
  }

  CompanionCommand _fromBackend(
    Map<String, dynamic>? data,
    CompanionCommand fallback,
  ) {
    if (data == null) return fallback;
    final action = switch (data['action'] as String?) {
      'search_places' => CompanionAction.searchPlaces,
      'look_ahead' => CompanionAction.lookAhead,
      'repeat_instruction' => CompanionAction.repeatInstruction,
      'pause_journey' => CompanionAction.pauseJourney,
      'resume_journey' => CompanionAction.resumeJourney,
      'find_transport' => CompanionAction.findTransport,
      'explain_recommendation' => CompanionAction.explainRecommendation,
      'find_alternative_route' => CompanionAction.alternativeRoute,
      'report_delay' => CompanionAction.reportDelay,
      'prefer_cheaper_route' => CompanionAction.cheaperRoute,
      'prefer_fewer_transfers' => CompanionAction.fewerTransfers,
      'save_destination' => CompanionAction.saveDestination,
      'list_saved_places' => CompanionAction.listSavedPlaces,
      'end_journey' => CompanionAction.endJourney,
      'reply' => CompanionAction.conversationalReply,
      _ => CompanionAction.unknown,
    };
    if (action == CompanionAction.unknown) return fallback;
    return CompanionCommand(
      action: action,
      query: (data['query'] as String?)?.trim(),
      needsClarification: data['needsClarification'] as bool? ?? false,
      message: data['message'] as String?,
    );
  }

  Future<Options?> _authenticatedOptions() async {
    final token = await _accessToken?.call();
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  CompanionCommand _fallbackCommand(String transcript) {
    final normalized = transcript.trim().toLowerCase();
    if (RegExp(
      r"what('s| is)? ahead|look ahead|scan ahead",
    ).hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.lookAhead);
    }
    if (normalized.contains('repeat')) {
      return const CompanionCommand(action: CompanionAction.repeatInstruction);
    }
    if (normalized.contains('pause')) {
      return const CompanionCommand(action: CompanionAction.pauseJourney);
    }
    if (normalized.contains('resume') ||
        normalized.contains('continue guidance')) {
      return const CompanionCommand(action: CompanionAction.resumeJourney);
    }
    if (RegExp(
      r'available transport|transport.*near|find.*(taxi|bus|trotro|ride)',
    ).hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.findTransport);
    }
    if (RegExp(
      r'why.*(route|recommend)|why this|explain.*route',
    ).hasMatch(normalized)) {
      return const CompanionCommand(
        action: CompanionAction.explainRecommendation,
      );
    }
    if (RegExp(
      r'another route|alternative route|different route',
    ).hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.alternativeRoute);
    }
    if (RegExp(
      r'delay|disruption|cancelled bus|canceled bus',
    ).hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.reportDelay);
    }
    if (RegExp(r'cheaper|lowest fare|less expensive').hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.cheaperRoute);
    }
    if (RegExp(
      r'fewer transfers|less transfers|fewer changes',
    ).hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.fewerTransfers);
    }
    if (RegExp(r'save (this|the) (place|destination)').hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.saveDestination);
    }
    if (RegExp(r'saved places|show.*places').hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.listSavedPlaces);
    }
    if (RegExp(r'end (the )?journey|stop navigation').hasMatch(normalized)) {
      return const CompanionCommand(action: CompanionAction.endJourney);
    }
    final localTransitTrip = RegExp(
      r'^(?:please\s+)?(?:i\s+(?:need|want)\s+to\s+)?(?:take|catch|board|get)\s+'
      r'(?:me\s+)?(?:a\s+)?(?:trotro|bus|shared\s+taxi|taxi)\s+(?:to|for)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(transcript.trim());
    if (localTransitTrip != null) {
      return CompanionCommand(
        action: CompanionAction.searchPlaces,
        query: localTransitTrip.group(1)?.trim(),
      );
    }
    final query = _stripTravelWords(transcript);
    final looksLikeDestination = RegExp(
      r'^(please\s+)?(take|bring|navigate|direct|guide|drive|walk|go|get|find)\b|'
      r'^i\s+(want|need)\s+to\s+go\b|'
      r'\b(nearest|nearby|pharmacy|clinic|hospital|station|lorry\s+station|'
      r'junction|school|market|mall|airport|trotro|circle|interchange)\b',
    ).hasMatch(normalized);
    if (query.length >= 2 && looksLikeDestination) {
      return CompanionCommand(
        action: CompanionAction.searchPlaces,
        query: query,
      );
    }
    return const CompanionCommand(
      action: CompanionAction.conversationalReply,
      message:
          'I’m here with your Accra journey context. Ask me to plan, compare, explain, save, repeat, pause, or adapt a route.',
    );
  }

  String _stripTravelWords(String transcript) {
    return transcript
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:please\s+)?i\s+(?:want|need)\s+to\s+go\s+(?:to\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            r'^(please\s+)?(take|bring|navigate|direct|guide|drive|walk|go|get|find)\s+'
            r'(me\s+)?(to\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }
}
