import 'package:ai_mobility_assistant/features/journey/data/google_places_service.dart';
import 'package:ai_mobility_assistant/features/journey/domain/accra_operating_area.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test(
    'autocomplete sends a hard Accra restriction and Ghana region',
    () async {
      Map<String, dynamic>? requestBody;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestBody = Map<String, dynamic>.from(
              options.data as Map<String, dynamic>,
            );
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: const {'suggestions': <Object>[]},
              ),
            );
          },
        ),
      );
      final service = GooglePlacesService(apiKey: 'test', dio: dio);

      await service.autocomplete(
        input: 'pharmacy',
        sessionToken: 'session',
        near: const LatLng(6.6885, -1.6244),
      );

      expect(requestBody?['includedRegionCodes'], const ['gh']);
      expect(requestBody?['regionCode'], 'gh');
      expect(requestBody?['locationRestriction'], isNotNull);
      expect(requestBody?['origin'], {
        'latitude': AccraOperatingArea.center.latitude,
        'longitude': AccraOperatingArea.center.longitude,
      });
    },
  );

  test('place details outside Accra are rejected', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: const {
                'id': 'kumasi',
                'displayName': {'text': 'Kumasi'},
                'formattedAddress': 'Kumasi, Ghana',
                'location': {'latitude': 6.6885, 'longitude': -1.6244},
              },
            ),
          );
        },
      ),
    );
    final service = GooglePlacesService(apiKey: 'test', dio: dio);

    await expectLater(
      service.details(placeId: 'kumasi', sessionToken: 'session'),
      throwsA(isA<OutsideAccraOperatingArea>()),
    );
  });
}
