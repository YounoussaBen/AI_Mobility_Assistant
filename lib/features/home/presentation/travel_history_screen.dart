import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../history/application/journey_history_controller.dart';
import '../../history/domain/journey_record.dart';
import '../../journey/application/journey_session_controller.dart';
import '../../journey/domain/route_option.dart';

class TravelHistoryScreen extends ConsumerWidget {
  const TravelHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(journeyHistoryControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (records.isNotEmpty)
            TextButton(
              onPressed: () => _clear(context, ref),
              child: const Text('Clear all'),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            Text(
              'Travel history',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 9),
            Text(
              'Completed journeys are stored only on this device.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            if (records.isEmpty)
              _EmptyHistory(onPlan: () => context.go('/home'))
            else
              for (final record in records) ...[
                _JourneyHistoryCard(
                  record: record,
                  onRepeat: () {
                    ref
                        .read(journeySessionControllerProvider.notifier)
                        .destinationConfirmed(record.destination);
                    context.go('/plan?resumeDestination=true');
                  },
                  onDelete: () => ref
                      .read(journeyHistoryControllerProvider.notifier)
                      .remove(record.id),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear travel history?'),
        content: const Text(
          'This removes all locally stored completed journeys.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(journeyHistoryControllerProvider.notifier).clear();
    }
  }
}

class _JourneyHistoryCard extends StatelessWidget {
  const _JourneyHistoryCard({
    required this.record,
    required this.onRepeat,
    required this.onDelete,
  });

  final JourneyRecord record;
  final VoidCallback onRepeat;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = record.completedAt.toLocal();
    final dateLabel =
        '${date.day}/${date.month}/${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(record.route.mode.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.destination.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(dateLabel),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete journey',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${record.route.displayMode} · ${record.route.durationLabel} · '
              '${record.route.distanceLabel}',
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRepeat,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Plan this journey again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.onPlan});

  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Column(
        children: [
          const Icon(Icons.route_outlined, size: 58),
          const SizedBox(height: 18),
          Text(
            'No journeys yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Completed journeys will appear here.'),
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: onPlan,
            child: const Text('Plan a journey'),
          ),
        ],
      ),
    );
  }
}
