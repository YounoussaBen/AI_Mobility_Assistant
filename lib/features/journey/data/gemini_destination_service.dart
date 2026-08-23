import 'package:dio/dio.dart';

class GeminiDestinationService {
  GeminiDestinationService({
    required String apiKey,
    required String model,
    Dio? dio,
  }) : _apiKey = apiKey,
       _model = model,
       _dio =
           dio ??
           Dio(
             BaseOptions(baseUrl: 'https://generativelanguage.googleapis.com'),
           );

  final String _apiKey;
  final String _model;
  final Dio _dio;

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<String> destinationFromSpeech(String transcript) async {
    final fallback = _fallback(transcript);
    if (!isConfigured) return fallback;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1beta/models/$_model:generateContent',
        data: {
          'contents': [
            {
              'parts': [
                {
                  'text':
                      'Extract only the destination place or address from this '
                      'travel request. Do not add facts, explanations, quotation '
                      'marks, or a starting location. If there is no clear '
                      'destination, return the original words. Request: '
                      '$transcript',
                },
              ],
            },
          ],
          'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 80},
        },
        options: Options(headers: {'x-goog-api-key': _apiKey}),
      );
      final candidates = response.data?['candidates'] as List<dynamic>?;
      final content = candidates?.firstOrNull as Map<String, dynamic>?;
      final parts =
          (content?['content'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      final text =
          (parts?.firstOrNull as Map<String, dynamic>?)?['text'] as String?;
      final cleaned = text?.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
      return cleaned == null || cleaned.isEmpty ? fallback : cleaned;
    } catch (_) {
      return fallback;
    }
  }

  String _fallback(String transcript) {
    return transcript
        .trim()
        .replaceFirst(
          RegExp(
            r'^(please\s+)?(take|bring|navigate|drive|walk|go|get)\s+(me\s+)?(to\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }
}
