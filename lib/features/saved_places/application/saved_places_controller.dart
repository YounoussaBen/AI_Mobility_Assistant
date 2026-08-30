import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/domain/accra_operating_area.dart';
import '../../journey/domain/place.dart';
import '../data/saved_places_repository.dart';

final savedPlacesControllerProvider =
    NotifierProvider<SavedPlacesController, List<JourneyPlace>>(
      SavedPlacesController.new,
    );

class SavedPlacesController extends Notifier<List<JourneyPlace>> {
  @override
  List<JourneyPlace> build() {
    return ref
        .watch(savedPlacesRepositoryProvider)
        .load()
        .where((place) => AccraOperatingArea.contains(place.location))
        .toList(growable: false);
  }

  bool contains(String placeId) {
    return state.any((place) => place.placeId == placeId);
  }

  void toggle(JourneyPlace place) {
    if (!AccraOperatingArea.contains(place.location)) return;
    if (contains(place.placeId)) {
      state = [
        for (final item in state)
          if (item.placeId != place.placeId) item,
      ];
    } else {
      state = [place, ...state];
    }
    unawaited(ref.read(savedPlacesRepositoryProvider).save(state));
  }

  void remove(String placeId) {
    state = [
      for (final item in state)
        if (item.placeId != placeId) item,
    ];
    unawaited(ref.read(savedPlacesRepositoryProvider).save(state));
  }
}
