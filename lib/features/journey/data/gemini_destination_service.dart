import 'package:dio/dio.dart';

enum CompanionAction {
  searchPlaces,
  lookAhead,
  repeatInstruction,
  pauseJourney,
  resumeJourney,
  unknown,
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

  bool get isConfigured => _backendDio != null || _apiKey.isNotEmpty;

  Future<CompanionCommand> interpret(String transcript) async {
    final fallback = _fallbackCommand(transcript);
    final backend = _backendDio;
    if (backend != null) {
      try {
        final response = await backend.post<Map<String, dynamic>>(
          '/v1/companion/interpret',
          data: {'text': transcript},
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
                    'Request exactly one approved function. Never invent a '
                    'destination, route, maneuver, accessibility fact, hazard, '
                    'distance, or live condition. If a destination is ambiguous, '
                    'search using the user’s exact useful place words so the app '
                    'can present choices.',
              },
            ],
          },
          'contents': [
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
                      'Search trusted Places data for a destination or category.',
                  'parameters': {
                    'type': 'OBJECT',
                    'properties': {
                      'query': {
                        'type': 'STRING',
                        'description':
                            'Only the useful destination search text.',
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
    final query = _stripTravelWords(transcript);
    if (query.length >= 2) {
      return CompanionCommand(
        action: CompanionAction.searchPlaces,
        query: query,
      );
    }
    return const CompanionCommand(
      action: CompanionAction.unknown,
      needsClarification: true,
      message: 'Where would you like to go?',
    );
  }

  String _stripTravelWords(String transcript) {
    return transcript
        .trim()
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
