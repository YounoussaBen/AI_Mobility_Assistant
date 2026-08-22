import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../preferences/application/mobility_preferences_controller.dart';
import '../../preferences/domain/mobility_preferences.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(mobilityPreferencesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobility AI'),
        actions: [
          IconButton(
            tooltip: 'Edit travel preferences',
            onPressed: () => context.go('/preferences?edit=true'),
            icon: const Icon(Icons.tune_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) async {
              if (value != 'sign-out') return;
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/auth');
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text(
              'Good to go',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Plan a journey that works with the way you move.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.assistant_navigation,
                      size: 42,
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Where would you like to go?',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.surface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Accessible destination search and route guidance are the next feature we’ll build.',
                      style: TextStyle(
                        color: Color(0xFFD2D5D8),
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Plan a journey — coming next'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your travel profile',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit preferences',
                          onPressed: () => context.go('/preferences?edit=true'),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    preferences.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, stackTrace) => const Text(
                        'Preferences are temporarily unavailable.',
                      ),
                      data: (value) => _PreferenceSummary(preferences: value),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceSummary extends StatelessWidget {
  const _PreferenceSummary({required this.preferences});

  final MobilityPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      preferences.priority.label,
      if (preferences.voiceGuidance) 'Voice guidance',
      if (preferences.wheelchairAccess) 'Wheelchair access',
      if (preferences.reducedWalking) 'Reduced walking',
      if (preferences.fewerTransfers) 'Fewer transfers',
      if (preferences.vibrationAlerts) 'Vibration alerts',
      if (preferences.largerText) 'Larger text',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          Chip(
            avatar: const Icon(Icons.check_rounded, size: 18),
            label: Text(label),
          ),
      ],
    );
  }
}
