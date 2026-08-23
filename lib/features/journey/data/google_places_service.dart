import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/place.dart';

class GooglePlacesService {
  GooglePlacesService({required String apiKey, Dio? dio})
    : _apiKey = apiKey,
      _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://places.googleapis.com'));

  final String _apiKey;
  final Dio _dio;

  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
    LatLng? near,
  }) async {
    if (input.trim().length < 2) return const [];

    final body = <String, Object>{
      'input': input.trim(),
      'sessionToken': sessionToken,
      'languageCode': 'en',
      if (near != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': 50000.0,
          },
        },
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/places:autocomplete',
      data: body,
      options: Options(
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask':
              'suggestions.placePrediction.placeId,'
              'suggestions.placePrediction.structuredFormat.mainText.text,'
              'suggestions.placePrediction.structuredFormat.secondaryText.text',
        },
      ),
    );

    final suggestions = response.data?['suggestions'] as List<dynamic>? ?? [];
    return suggestions
        .map((item) => item as Map<String, dynamic>)
        .map((item) => item['placePrediction'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(_parseSuggestion)
        .whereType<PlaceSuggestion>()
        .take(5)
        .toList(growable: false);
  }

  Future<JourneyPlace> details({
    required String placeId,
    required String sessionToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/places/$placeId',
      queryParameters: {'sessionToken': sessionToken},
      options: Options(
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
        },
      ),
    );
    final data = response.data;
    final location = data?['location'] as Map<String, dynamic>?;
    if (data == null || location == null) {
      throw StateError('Google Places did not return this location.');
    }

    return JourneyPlace(
      placeId: data['id'] as String? ?? placeId,
      name:
          (data['displayName'] as Map<String, dynamic>?)?['text'] as String? ??
          data['formattedAddress'] as String? ??
          'Selected destination',
      address: data['formattedAddress'] as String? ?? '',
      location: LatLng(
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      ),
    );
  }

  PlaceSuggestion? _parseSuggestion(Map<String, dynamic> prediction) {
    final placeId = prediction['placeId'] as String?;
    final structured =
        prediction['structuredFormat'] as Map<String, dynamic>? ?? const {};
    final primary =
        (structured['mainText'] as Map<String, dynamic>?)?['text'] as String?;
    final secondary =
        (structured['secondaryText'] as Map<String, dynamic>?)?['text']
            as String?;
    if (placeId == null || primary == null) return null;
    return PlaceSuggestion(
      placeId: placeId,
      primaryText: primary,
      secondaryText: secondary ?? '',
    );
  }
}
