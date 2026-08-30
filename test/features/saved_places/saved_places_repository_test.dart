import 'package:ai_mobility_assistant/app/storage/app_storage.dart';
import 'package:ai_mobility_assistant/features/journey/domain/place.dart';
import 'package:ai_mobility_assistant/features/saved_places/data/saved_places_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('saved places persist locally and restore', () async {
    final storage = MemoryAppStorage();
    final repository = SavedPlacesRepository(storage);
    const place = JourneyPlace(
      placeId: 'home',
      name: 'Home',
      address: 'Accra',
      location: LatLng(5.6, -0.18),
    );

    await repository.save(const [place]);
    final restored = repository.load();

    expect(restored, hasLength(1));
    expect(restored.single.placeId, 'home');
    expect(restored.single.location, place.location);
  });
}
