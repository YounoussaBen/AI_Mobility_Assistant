import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../companion/domain/companion_models.dart';
import '../../voice/application/voice_profile_controller.dart';
import '../../voice/data/speech_output_service.dart';
import '../../voice/domain/voice_profile.dart';
import '../application/journey_session_controller.dart';
import '../domain/route_option.dart';

class ActiveJourneyScreen extends ConsumerStatefulWidget {
  const ActiveJourneyScreen({super.key});

  @override
  ConsumerState<ActiveJourneyScreen> createState() =>
      _ActiveJourneyScreenState();
}

class _ActiveJourneyScreenState extends ConsumerState<ActiveJourneyScreen> {
  StreamSubscription<Position>? _positionSubscription;
  GoogleMapController? _mapController;
  Position? _position;
  String? _locationMessage;
  int _lastAnnouncedStep = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startLocationUpdates());
      unawaited(_announceCurrentInstruction());
    });
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _locationMessage = 'GPS is off');
      return;
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locationMessage = 'Location unavailable');
      return;
    }
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen(
          _onPosition,
          onError: (_) {
            if (mounted) {
              setState(() => _locationMessage = 'GPS signal interrupted');
            }
          },
        );
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      _locationMessage = position.accuracy > 35
          ? 'Weak GPS · ±${position.accuracy.round()} m'
          : 'GPS ready · ±${position.accuracy.round()} m';
    });

    final session = ref.read(journeySessionControllerProvider);
    if (session.phase != CompanionPhase.guiding) return;
    final route = session.selectedRoute;
    if (route == null || session.currentStepIndex >= route.steps.length) return;
    final end = route.steps[session.currentStepIndex].endLocation;
    if (end == null) return;
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      end.latitude,
      end.longitude,
    );
    final arrivalThreshold = math.max(
      12.0,
      math.min(25.0, position.accuracy * 0.75),
    );
    if (distance <= arrivalThreshold) {
      ref.read(journeySessionControllerProvider.notifier).advanceStep();
      unawaited(_announceCurrentInstruction(force: true));
    }
  }

  Future<VoiceProfile?> _voiceProfile() async {
    try {
      return await ref.read(voiceProfileControllerProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<void> _announceCurrentInstruction({bool force = false}) async {
    final session = ref.read(journeySessionControllerProvider);
    final instruction = session.lastInstruction;
    if (instruction == null) return;
    if (!force && _lastAnnouncedStep == session.currentStepIndex) return;
    _lastAnnouncedStep = session.currentStepIndex;
    final profile = await _voiceProfile();
    if (profile == null) return;
    if (profile.haptics) HapticFeedback.mediumImpact();
    await ref.read(speechOutputServiceProvider).speak(instruction, profile);
  }

  Future<void> _repeat() async {
    await _announceCurrentInstruction(force: true);
  }

  Future<void> _togglePause() async {
    ref.read(journeySessionControllerProvider.notifier).togglePaused();
    final session = ref.read(journeySessionControllerProvider);
    if (session.phase == CompanionPhase.paused) {
      await ref.read(speechOutputServiceProvider).stop();
    } else {
      await _announceCurrentInstruction(force: true);
    }
  }

  Future<void> _endJourney() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this journey?'),
        content: const Text(
          'Voice, text, and haptic guidance will stop. You can plan again from the Companion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep guiding'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End journey'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(speechOutputServiceProvider).stop();
    ref.read(journeySessionControllerProvider.notifier).endJourney();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(journeySessionControllerProvider);
    final route = session.selectedRoute;
    if (route == null || session.destination == null) {
      return _NoActiveJourney(onPlan: () => context.go('/plan'));
    }

    final step = route.steps.isEmpty
        ? null
        : route.steps[session.currentStepIndex.clamp(
            0,
            route.steps.length - 1,
          )];
    final nextStep = route.steps.length > session.currentStepIndex + 1
        ? route.steps[session.currentStepIndex + 1]
        : null;
    final instruction =
        session.lastInstruction ??
        step?.instruction ??
        'Continue toward ${session.destination!.name}.';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Return to Companion',
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.home_outlined),
        ),
        title: Text(session.destination!.name),
        actions: [
          IconButton(
            tooltip: 'Voice and guidance settings',
            onPressed: () => context.push('/voice-guidance'),
            icon: const Icon(Icons.record_voice_over_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
              children: [
                _JourneyStatus(
                  phase: session.phase,
                  locationMessage: _locationMessage,
                ),
                const SizedBox(height: 14),
                _ViewChooser(
                  selected: session.guidanceView,
                  onSelected: (view) => ref
                      .read(journeySessionControllerProvider.notifier)
                      .setGuidanceView(view),
                ),
                const SizedBox(height: 18),
                switch (session.guidanceView) {
                  GuidanceView.guide => _GuideView(
                    instruction: instruction,
                    step: step,
                    nextStep: nextStep,
                    route: route,
                    paused: session.phase == CompanionPhase.paused,
                  ),
                  GuidanceView.map => _GuidanceMap(
                    route: route,
                    destination: session.destination!.location,
                    position: _position,
                    onCreated: (controller) => _mapController = controller,
                  ),
                  GuidanceView.lookAhead => _LookAheadPrompt(
                    onOpen: () => context.push('/look-ahead'),
                  ),
                },
                const SizedBox(height: 20),
                _JourneyControls(
                  paused: session.phase == CompanionPhase.paused,
                  onRepeat: _repeat,
                  onTalk: () => context.go('/home'),
                  onPause: _togglePause,
                  onLookAhead: () => context.push('/look-ahead'),
                  onEnd: _endJourney,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JourneyStatus extends StatelessWidget {
  const _JourneyStatus({required this.phase, required this.locationMessage});

  final CompanionPhase phase;
  final String? locationMessage;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '${phase.assistiveDescription} ${locationMessage ?? ''}',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatusChip(
            icon: phase == CompanionPhase.paused
                ? Icons.pause_rounded
                : Icons.navigation_rounded,
            label: phase.label,
            emphasized: true,
          ),
          _StatusChip(
            icon: locationMessage?.startsWith('Weak') == true
                ? Icons.gps_off_rounded
                : Icons.gps_fixed_rounded,
            label: locationMessage ?? 'Connecting to GPS',
          ),
          const _StatusChip(
            icon: Icons.verified_outlined,
            label: 'Google route',
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: emphasized ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: emphasized ? scheme.primary : null),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ViewChooser extends StatelessWidget {
  const _ViewChooser({required this.selected, required this.onSelected});

  final GuidanceView selected;
  final ValueChanged<GuidanceView> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final view in GuidanceView.values)
          ChoiceChip(
            label: Text(view.label),
            selected: selected == view,
            onSelected: (_) => onSelected(view),
            avatar: Icon(switch (view) {
              GuidanceView.guide => Icons.signpost_outlined,
              GuidanceView.map => Icons.map_outlined,
              GuidanceView.lookAhead => Icons.center_focus_strong_rounded,
            }, size: 19),
          ),
      ],
    );
  }
}

class _GuideView extends StatelessWidget {
  const _GuideView({
    required this.instruction,
    required this.step,
    required this.nextStep,
    required this.route,
    required this.paused,
  });

  final String instruction;
  final JourneyStep? step;
  final JourneyStep? nextStep;
  final JourneyRouteOption route;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: paused ? scheme.surface : scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      paused
                          ? Icons.pause_circle_outline
                          : _maneuverIcon(step?.maneuver),
                      size: 32,
                      color: paused ? scheme.onSurfaceVariant : scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        paused
                            ? 'Guidance paused'
                            : step?.distanceLabel ?? 'Start',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  paused
                      ? 'Resume when you are ready to continue.'
                      : instruction,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Journey overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      '${route.durationLabel} estimated journey time',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      route.distanceLabel,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
                if (nextStep != null) ...[
                  const Divider(height: 26),
                  Text('Then', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    nextStep!.instruction,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static IconData _maneuverIcon(String? maneuver) {
    final value = maneuver?.toLowerCase() ?? '';
    if (value.contains('left')) return Icons.turn_left_rounded;
    if (value.contains('right')) return Icons.turn_right_rounded;
    if (value.contains('u_turn')) return Icons.u_turn_left_rounded;
    return Icons.straight_rounded;
  }
}

class _GuidanceMap extends StatelessWidget {
  const _GuidanceMap({
    required this.route,
    required this.destination,
    required this.position,
    required this.onCreated,
  });

  final JourneyRouteOption route;
  final LatLng destination;
  final Position? position;
  final ValueChanged<GoogleMapController> onCreated;

  @override
  Widget build(BuildContext context) {
    final current = position == null
        ? route.path.firstOrNull ?? destination
        : LatLng(position!.latitude, position!.longitude);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 430,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: current, zoom: 16),
              myLocationEnabled: position != null,
              myLocationButtonEnabled: true,
              compassEnabled: true,
              mapToolbarEnabled: false,
              zoomControlsEnabled: false,
              markers: {
                Marker(
                  markerId: const MarkerId('destination'),
                  position: destination,
                ),
              },
              polylines: {
                Polyline(
                  polylineId: const PolylineId('active-route'),
                  points: route.path,
                  color: Theme.of(context).colorScheme.primary,
                  width: 7,
                ),
              },
              onMapCreated: onCreated,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The map is optional. The same guidance remains available through speech, text, and haptics.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _LookAheadPrompt extends StatelessWidget {
  const _LookAheadPrompt({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.center_focus_strong_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Scan when you choose',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Look Ahead observes a small set of common objects on your device. '
              'It cannot confirm distance, curb edges, holes, or that a path is safe.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Open Look Ahead'),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyControls extends StatelessWidget {
  const _JourneyControls({
    required this.paused,
    required this.onRepeat,
    required this.onTalk,
    required this.onPause,
    required this.onLookAhead,
    required this.onEnd,
  });

  final bool paused;
  final VoidCallback onRepeat;
  final VoidCallback onTalk;
  final VoidCallback onPause;
  final VoidCallback onLookAhead;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Journey controls', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 540
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ControlButton(
                  width: width,
                  icon: Icons.replay_rounded,
                  label: 'Repeat',
                  onTap: onRepeat,
                ),
                _ControlButton(
                  width: width,
                  icon: Icons.mic_rounded,
                  label: 'Talk',
                  onTap: onTalk,
                ),
                _ControlButton(
                  width: width,
                  icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  label: paused ? 'Resume' : 'Pause',
                  onTap: onPause,
                ),
                _ControlButton(
                  width: width,
                  icon: Icons.center_focus_strong_rounded,
                  label: 'Look ahead',
                  onTap: onLookAhead,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: onEnd,
          icon: Icon(
            Icons.stop_circle_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          label: Text(
            'End journey',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _NoActiveJourney extends StatelessWidget {
  const _NoActiveJourney({required this.onPlan});

  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_outlined, size: 56),
                  const SizedBox(height: 18),
                  Text(
                    'No active journey',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose and confirm a verified route before starting guidance.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: onPlan,
                    child: const Text('Plan a journey'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
