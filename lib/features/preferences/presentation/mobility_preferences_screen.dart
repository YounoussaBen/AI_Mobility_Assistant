import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/mobility_preferences_controller.dart';
import '../data/mobility_preferences_repository.dart';
import '../domain/mobility_preferences.dart';

class MobilityPreferencesScreen extends ConsumerStatefulWidget {
  const MobilityPreferencesScreen({super.key, required this.isEditing});

  final bool isEditing;

  @override
  ConsumerState<MobilityPreferencesScreen> createState() =>
      _MobilityPreferencesScreenState();
}

class _MobilityPreferencesScreenState
    extends ConsumerState<MobilityPreferencesScreen> {
  MobilityPreferences? _draft;

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(mobilityPreferencesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Go back',
          onPressed: () => context.go(widget.isEditing ? '/home' : '/auth'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.isEditing ? 'Travel preferences' : 'Set up your trip',
        ),
      ),
      body: preferences.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _LoadError(
          onRetry: () => ref.invalidate(mobilityPreferencesControllerProvider),
        ),
        data: (savedPreferences) {
          final draft = _draft ??= savedPreferences;
          return _PreferencesForm(
            preferences: draft,
            isSaving: preferences.isLoading,
            onChanged: (value) => setState(() => _draft = value),
            onSave: () => _save(draft),
          );
        },
      ),
    );
  }

  Future<void> _save(MobilityPreferences preferences) async {
    await ref
        .read(mobilityPreferencesControllerProvider.notifier)
        .save(preferences);

    if (!mounted) return;

    final result = ref.read(mobilityPreferencesControllerProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your preferences.')),
      );
      return;
    }

    await ref.read(mobilityPreferencesRepositoryProvider).completeProfile();

    if (mounted) context.go('/home');
  }
}

class _PreferencesForm extends StatelessWidget {
  const _PreferencesForm({
    required this.preferences,
    required this.isSaving,
    required this.onChanged,
    required this.onSave,
  });

  final MobilityPreferences preferences;
  final bool isSaving;
  final ValueChanged<MobilityPreferences> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What would make your journeys easier?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Choose only what matters to you. You can change these settings later.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                _PreferenceSwitch(
                  icon: Icons.record_voice_over_rounded,
                  title: 'Voice guidance',
                  subtitle: 'Read important directions and alerts aloud',
                  value: preferences.voiceGuidance,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(voiceGuidance: value)),
                ),
                _PreferenceSwitch(
                  icon: Icons.accessible_forward_rounded,
                  title: 'Wheelchair access',
                  subtitle: 'Prefer step-free routes and accessible vehicles',
                  value: preferences.wheelchairAccess,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(wheelchairAccess: value)),
                ),
                _PreferenceSwitch(
                  icon: Icons.directions_walk_rounded,
                  title: 'Reduce walking',
                  subtitle: 'Prefer journeys with shorter walking sections',
                  value: preferences.reducedWalking,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(reducedWalking: value)),
                ),
                _PreferenceSwitch(
                  icon: Icons.sync_alt_rounded,
                  title: 'Fewer transfers',
                  subtitle: 'Prefer journeys with fewer vehicle changes',
                  value: preferences.fewerTransfers,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(fewerTransfers: value)),
                ),
                _PreferenceSwitch(
                  icon: Icons.vibration_rounded,
                  title: 'Vibration alerts',
                  subtitle: 'Vibrate for important warnings and next steps',
                  value: preferences.vibrationAlerts,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(vibrationAlerts: value)),
                ),
                _PreferenceSwitch(
                  icon: Icons.text_increase_rounded,
                  title: 'Larger text',
                  subtitle: 'Use larger text for key journey information',
                  value: preferences.largerText,
                  showDivider: false,
                  onChanged: (value) =>
                      onChanged(preferences.copyWith(largerText: value)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Main journey priority',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          RadioGroup<JourneyPriority>(
            groupValue: preferences.priority,
            onChanged: (priority) {
              if (priority != null) {
                onChanged(preferences.copyWith(priority: priority));
              }
            },
            child: Card(
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < JourneyPriority.values.length;
                    index++
                  ) ...[
                    _PriorityOption(
                      priority: JourneyPriority.values[index],
                      selected:
                          preferences.priority == JourneyPriority.values[index],
                    ),
                    if (index < JourneyPriority.values.length - 1)
                      const Divider(height: 1, indent: 16),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            key: const Key('save_preferences_button'),
            onPressed: isSaving ? null : onSave,
            child: Text(isSaving ? 'Saving…' : 'Save and continue'),
          ),
        ],
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        ),
        if (showDivider) const Divider(height: 1, indent: 64, endIndent: 16),
      ],
    );
  }
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({required this.priority, required this.selected});

  final JourneyPriority priority;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        child: RadioListTile<JourneyPriority>(
          value: priority,
          title: Text(
            priority.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(priority.description),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            const Text('Could not load your preferences.'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
