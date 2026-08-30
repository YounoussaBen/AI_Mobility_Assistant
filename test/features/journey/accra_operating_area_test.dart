import 'package:ai_mobility_assistant/features/journey/data/google_routes_service.dart';
import 'package:ai_mobility_assistant/features/journey/domain/accra_operating_area.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test(
    'the pilot boundary includes Accra and excludes other Ghanaian cities',
    () {
      expect(AccraOperatingArea.contains(AccraOperatingArea.center), isTrue);
      expect(
        AccraOperatingArea.contains(const LatLng(5.5560, -0.1820)),
        isTrue,
      );
      expect(
        AccraOperatingArea.contains(const LatLng(5.6698, 0.0166)),
        isFalse,
        reason: 'Tema is outside this Accra-only pilot',
      );
      expect(
        AccraOperatingArea.contains(const LatLng(6.6885, -1.6244)),
        isFalse,
        reason: 'Kumasi is outside this Accra-only pilot',
      );
    },
  );

  test(
    'route requests fail before networking when a point is outside Accra',
    () async {
      final service = GoogleRoutesService(apiKey: 'unused');

      await expectLater(
        service.routes(
          origin: AccraOperatingArea.center,
          destination: const LatLng(6.6885, -1.6244),
        ),
        throwsA(isA<OutsideAccraOperatingArea>()),
      );
    },
  );
}
