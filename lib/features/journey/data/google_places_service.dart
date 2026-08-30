import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../domain/accra_operating_area.dart';
import '../domain/place.dart';

class GooglePlacesService {
  GooglePlacesService({
    required String apiKey,
    String backendUrl = '',
    Future<String?> Function()? accessToken,
    Dio? dio,
  }) : _apiKey = apiKey,
       _usesBackend = backendUrl.isNotEmpty,
       _accessToken = accessToken,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: backendUrl.isNotEmpty
                   ? backendUrl.replaceFirst(RegExp(r'/$'), '')
                   : 'https://places.googleapis.com',
             ),
           );

  final String _apiKey;
  final bool _usesBackend;
  final Future<String?> Function()? _accessToken;
  final Dio _dio;
  final LinkedHashMap<
    String,
    ({DateTime createdAt, List<PlaceSuggestion> suggestions})
  >
  _autocompleteCache = LinkedHashMap();
  final LinkedHashMap<String, ({DateTime createdAt, JourneyPlace place})>
  _detailsCache = LinkedHashMap();

  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
    LatLng? near,
  }) async {
    if (input.trim().length < 2) return const [];
    final localOrigin = near != null && AccraOperatingArea.contains(near)
        ? near
        : AccraOperatingArea.center;
    final cacheKey =
        '$sessionToken:${input.trim().toLowerCase()}:'
        '${localOrigin.latitude.toStringAsFixed(3)},${localOrigin.longitude.toStringAsFixed(3)}';
    final cached = _autocompleteCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(seconds: 30)) {
      return cached.suggestions;
    }

    final body = <String, Object>{
      'input': input.trim(),
      'sessionToken': sessionToken,
      'languageCode': 'en',
      'regionCode': AccraOperatingArea.countryCode,
      'includedRegionCodes': const [AccraOperatingArea.countryCode],
      'origin': {
        'latitude': localOrigin.latitude,
        'longitude': localOrigin.longitude,
      },
      'locationRestriction': AccraOperatingArea.placesRestriction,
    };

    final response = await _dio.post<Map<String, dynamic>>(
      _usesBackend ? '/v1/maps/places:autocomplete' : '/v1/places:autocomplete',
      data: body,
      options: _usesBackend
          ? await _authenticatedOptions()
          : Options(
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
    final parsed = suggestions
        .map((item) => item as Map<String, dynamic>)
        .map((item) => item['placePrediction'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map(_parseSuggestion)
        .whereType<PlaceSuggestion>()
        .take(5)
        .toList(growable: false);
    _autocompleteCache[cacheKey] = (
      createdAt: DateTime.now(),
      suggestions: parsed,
    );
    while (_autocompleteCache.length > 20) {
      _autocompleteCache.remove(_autocompleteCache.keys.first);
    }
    return parsed;
  }

  Future<JourneyPlace> details({
    required String placeId,
    required String sessionToken,
  }) async {
    final cached = _detailsCache[placeId];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) <
            const Duration(hours: 24)) {
      if (!AccraOperatingArea.contains(cached.place.location)) {
        throw const OutsideAccraOperatingArea();
      }
      return cached.place;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      _usesBackend ? '/v1/maps/places/$placeId' : '/v1/places/$placeId',
      queryParameters: {
        'sessionToken': sessionToken,
        'languageCode': 'en',
        'regionCode': AccraOperatingArea.countryCode,
      },
      options: _usesBackend
          ? await _authenticatedOptions()
          : Options(
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

    final place = JourneyPlace(
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
    if (!AccraOperatingArea.contains(place.location)) {
      throw const OutsideAccraOperatingArea();
    }
    _detailsCache[placeId] = (createdAt: DateTime.now(), place: place);
    while (_detailsCache.length > 30) {
      _detailsCache.remove(_detailsCache.keys.first);
    }
    return place;
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

  Future<Options?> _authenticatedOptions() async {
    final token = await _accessToken?.call();
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }
}
