import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../journey/application/journey_session_controller.dart';
import '../application/saved_places_controller.dart';

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(savedPlacesControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            Text(
              'Saved places',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 9),
            const Text('Accra destinations you save remain on this device.'),
            const SizedBox(height: 26),
            if (places.isEmpty) ...[
              const SizedBox(height: 42),
              const Icon(Icons.bookmark_outline_rounded, size: 58),
              const SizedBox(height: 18),
              Text(
                'No saved places',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirm a destination while planning, then choose Save place.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              OutlinedButton(
                onPressed: () => context.go('/plan'),
                child: const Text('Find a place'),
              ),
            ] else
              for (final place in places) ...[
                Card(
                  child: ListTile(
                    minVerticalPadding: 14,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(place.name),
                    subtitle: place.address.isEmpty
                        ? null
                        : Text(place.address),
                    trailing: IconButton(
                      tooltip: 'Remove saved place',
                      onPressed: () => ref
                          .read(savedPlacesControllerProvider.notifier)
                          .remove(place.placeId),
                      icon: const Icon(Icons.bookmark_remove_outlined),
                    ),
                    onTap: () {
                      ref
                          .read(journeySessionControllerProvider.notifier)
                          .destinationConfirmed(place);
                      context.go('/plan?resumeDestination=true');
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}
