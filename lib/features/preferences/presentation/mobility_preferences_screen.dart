import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
  static const _stepCount = 4;

  MobilityPreferences? _draft;
  late final PageController _pageController;
  int _step = 0;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _changeDraft(MobilityPreferences value) {
    setState(() {
      _draft = value;
      _saveError = null;
    });
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _stepCount || step == _step) return;
    HapticFeedback.selectionClick();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(step);
    } else {
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubic,
      );
    }
    setState(() {
      _step = step;
      _saveError = null;
    });
  }

  void _next() {
    if (_step == _stepCount - 1) {
      _save();
    } else {
      _goToStep(_step + 1);
    }
  }

  void _back() {
    if (_step > 0) {
      _goToStep(_step - 1);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.isEditing ? '/home' : '/auth');
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _isSaving) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      await ref
          .read(mobilityPreferencesControllerProvider.notifier)
          .save(draft);
      await ref.read(mobilityPreferencesRepositoryProvider).completeProfile();
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError =
              'We couldn’t save your profile. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(mobilityPreferencesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('profile_setup_back_button'),
          tooltip: _step == 0 ? 'Leave setup' : 'Previous step',
          onPressed: _isSaving ? null : _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(widget.isEditing ? 'Travel profile' : 'Profile setup'),
        actions: [
          if (!widget.isEditing && _step < _stepCount - 1)
            TextButton(
              key: const Key('skip_profile_setup_button'),
              onPressed: _isSaving ? null : _save,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: preferences.when(
        loading: () => const _ProfileLoadingState(),
        error: (error, stackTrace) => _LoadError(
          onRetry: () => ref.invalidate(mobilityPreferencesControllerProvider),
        ),
        data: (savedPreferences) {
          final draft = _draft ??= savedPreferences;
          return _SetupFlow(
            step: _step,
            stepCount: _stepCount,
            pageController: _pageController,
            preferences: draft,
            isEditing: widget.isEditing,
            isSaving: _isSaving,
            saveError: _saveError,
            onChanged: _changeDraft,
            onContinue: _next,
            onEditStep: _goToStep,
          );
        },
      ),
    );
  }
}

class _SetupFlow extends StatelessWidget {
  const _SetupFlow({
    required this.step,
    required this.stepCount,
    required this.pageController,
    required this.preferences,
    required this.isEditing,
    required this.isSaving,
    required this.saveError,
    required this.onChanged,
    required this.onContinue,
    required this.onEditStep,
  });

  final int step;
  final int stepCount;
  final PageController pageController;
  final MobilityPreferences preferences;
  final bool isEditing;
  final bool isSaving;
  final String? saveError;
  final ValueChanged<MobilityPreferences> onChanged;
  final VoidCallback onContinue;
  final ValueChanged<int> onEditStep;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Column(
      children: [
        _ProgressHeader(step: step, stepCount: stepCount),
        Expanded(
          child: IgnorePointer(
            ignoring: isSaving,
            child: PageView(
              controller: pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _PriorityStep(preferences: preferences, onChanged: onChanged),
                _MobilityStep(preferences: preferences, onChanged: onChanged),
                _GuidanceStep(preferences: preferences, onChanged: onChanged),
                _ReviewStep(
                  preferences: preferences,
                  saveError: saveError,
                  onEditStep: onEditStep,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: Key(
                  step == stepCount - 1
                      ? 'save_preferences_button'
                      : 'profile_setup_continue_button',
                ),
                onPressed: isSaving ? null : onContinue,
                child: AnimatedSwitcher(
                  duration: duration,
                  child: isSaving
                      ? const Row(
                          key: ValueKey('saving'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text('Saving profile…'),
                          ],
                        )
                      : Text(
                          step == stepCount - 1
                              ? (isEditing ? 'Save changes' : 'Finish setup')
                              : 'Continue',
                          key: ValueKey(step),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.stepCount});

  final int step;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 420);

    return Semantics(
      label: 'Step ${step + 1} of $stepCount',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 5,
                  right: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 2,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          AnimatedFractionallySizedBox(
                            duration: duration,
                            curve: Curves.easeInOutCubic,
                            alignment: Alignment.centerLeft,
                            widthFactor: step / (stepCount - 1),
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var index = 0; index < stepCount; index++)
                      AnimatedContainer(
                        duration: duration,
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: index <= step
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment(-1 + (2 * step / (stepCount - 1)), 0),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      Icons.navigation_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriorityStep extends StatelessWidget {
  const _PriorityStep({required this.preferences, required this.onChanged});

  final MobilityPreferences preferences;
  final ValueChanged<MobilityPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScrollView(
      title: 'What matters most?',
      description: 'Choose your main route priority.',
      child: _PriorityGrid(
        selected: preferences.priority,
        onSelected: (priority) {
          HapticFeedback.selectionClick();
          onChanged(preferences.copyWith(priority: priority));
        },
      ),
    );
  }
}

class _MobilityStep extends StatelessWidget {
  const _MobilityStep({required this.preferences, required this.onChanged});

  final MobilityPreferences preferences;
  final ValueChanged<MobilityPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScrollView(
      title: 'What makes travel easier?',
      description: 'Choose any that you need.',
      child: _MobilityRouteSelector(
        preferences: preferences,
        onChanged: onChanged,
      ),
    );
  }
}

class _GuidanceStep extends StatelessWidget {
  const _GuidanceStep({required this.preferences, required this.onChanged});

  final MobilityPreferences preferences;
  final ValueChanged<MobilityPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScrollView(
      title: 'Choose your signals',
      description: 'Pick how the app should guide you.',
      child: _GuidanceSelector(preferences: preferences, onChanged: onChanged),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.preferences,
    required this.saveError,
    required this.onEditStep,
  });

  final MobilityPreferences preferences;
  final String? saveError;
  final ValueChanged<int> onEditStep;

  @override
  Widget build(BuildContext context) {
    final mobilityLabels = <String>[
      if (preferences.wheelchairAccess) 'Step-free access',
      if (preferences.reducedWalking) 'Less walking',
      if (preferences.fewerTransfers) 'Fewer transfers',
    ];
    final guidanceLabels = <String>[
      if (preferences.voiceGuidance) 'Voice guidance',
      if (preferences.vibrationAlerts) 'Vibration alerts',
      if (preferences.largerText) 'Larger journey text',
    ];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              minHeight: constraints.maxHeight - 24,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _ReviewMark(),
                ),
                const SizedBox(height: 18),
                Text(
                  'Ready to go',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'We’ll use these choices to shape your routes.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                _ReviewRow(
                  icon: Icons.route_outlined,
                  title: 'Priority',
                  value: preferences.priority.label,
                  onTap: () => onEditStep(0),
                ),
                const Divider(height: 1, indent: 50),
                _ReviewRow(
                  icon: Icons.accessible_forward_rounded,
                  title: 'Mobility',
                  value: mobilityLabels.isEmpty
                      ? 'Standard options'
                      : mobilityLabels.join(', '),
                  onTap: () => onEditStep(1),
                ),
                const Divider(height: 1, indent: 50),
                _ReviewRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Guidance',
                  value: guidanceLabels.isEmpty
                      ? 'Visual only'
                      : guidanceLabels.join(', '),
                  onTap: () => onEditStep(2),
                ),
                if (saveError != null) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 21,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            saveError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepScrollView extends StatelessWidget {
  const _StepScrollView({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              minHeight: constraints.maxHeight - 24,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriorityGrid extends StatelessWidget {
  const _PriorityGrid({required this.selected, required this.onSelected});

  final JourneyPriority selected;
  final ValueChanged<JourneyPriority> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final priority in JourneyPriority.values)
              SizedBox(
                width: tileWidth,
                child: _PriorityChoice(
                  priority: priority,
                  selected: selected == priority,
                  onTap: () => onSelected(priority),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PriorityChoice extends StatelessWidget {
  const _PriorityChoice({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final JourneyPriority priority;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (priority) {
    JourneyPriority.accessible => Icons.accessible_forward_rounded,
    JourneyPriority.fastest => Icons.bolt_rounded,
    JourneyPriority.simplest => Icons.route_rounded,
    JourneyPriority.affordable => Icons.payments_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 108,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        _icon,
                        size: 27,
                        color: selected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.primary,
                      ),
                      Text(
                        priority.shortLabel,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: _AnimatedCheck(selected: selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on JourneyPriority {
  String get shortLabel => switch (this) {
    JourneyPriority.accessible => 'Easy access',
    JourneyPriority.fastest => 'Fastest route',
    JourneyPriority.simplest => 'Simplest trip',
    JourneyPriority.affordable => 'Lowest cost',
  };
}

class _MobilityRouteSelector extends StatelessWidget {
  const _MobilityRouteSelector({
    required this.preferences,
    required this.onChanged,
  });

  final MobilityPreferences preferences;
  final ValueChanged<MobilityPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RouteStop(
          icon: Icons.accessible_forward_rounded,
          title: 'Step-free routes',
          selected: preferences.wheelchairAccess,
          isFirst: true,
          onTap: () => onChanged(
            preferences.copyWith(
              wheelchairAccess: !preferences.wheelchairAccess,
            ),
          ),
        ),
        _RouteStop(
          icon: Icons.directions_walk_rounded,
          title: 'Shorter walking',
          selected: preferences.reducedWalking,
          onTap: () => onChanged(
            preferences.copyWith(reducedWalking: !preferences.reducedWalking),
          ),
        ),
        _RouteStop(
          icon: Icons.sync_alt_rounded,
          title: 'Fewer changes',
          selected: preferences.fewerTransfers,
          isLast: true,
          onTap: () => onChanged(
            preferences.copyWith(fewerTransfers: !preferences.fewerTransfers),
          ),
        ),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!isFirst)
                      Positioned(
                        top: 0,
                        bottom: 36,
                        child: Container(
                          width: 2,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    if (!isLast)
                      Positioned(
                        top: 36,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    AnimatedContainer(
                      duration: duration,
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 19,
                        color: selected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _AnimatedCheck(selected: selected),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidanceSelector extends StatelessWidget {
  const _GuidanceSelector({required this.preferences, required this.onChanged});

  final MobilityPreferences preferences;
  final ValueChanged<MobilityPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SignalChoice(
            icon: Icons.record_voice_over_rounded,
            title: 'Voice',
            selected: preferences.voiceGuidance,
            onTap: () => onChanged(
              preferences.copyWith(voiceGuidance: !preferences.voiceGuidance),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SignalChoice(
            icon: Icons.vibration_rounded,
            title: 'Haptics',
            selected: preferences.vibrationAlerts,
            onTap: () => onChanged(
              preferences.copyWith(
                vibrationAlerts: !preferences.vibrationAlerts,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SignalChoice(
            icon: Icons.text_increase_rounded,
            title: 'Large type',
            selected: preferences.largerText,
            onTap: () => onChanged(
              preferences.copyWith(largerText: !preferences.largerText),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalChoice extends StatelessWidget {
  const _SignalChoice({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        height: 116,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  child: Icon(
                    selected ? Icons.check_circle_rounded : icon,
                    key: ValueKey(selected),
                    color: Theme.of(context).colorScheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: selected
          ? Icon(
              Icons.check_circle_rounded,
              key: const ValueKey('selected'),
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            )
          : Icon(
              Icons.circle_outlined,
              key: const ValueKey('not-selected'),
              color: Theme.of(context).colorScheme.outline,
              size: 24,
            ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewMark extends StatelessWidget {
  const _ReviewMark();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0.90, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: Opacity(opacity: scale.clamp(0, 1), child: child),
      ),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check_rounded,
          size: 27,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ProfileLoadingState extends StatelessWidget {
  const _ProfileLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Loading your travel profile',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading your profile…',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'We couldn’t load your profile',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Your choices are still safe. Try loading them again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
