import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../companion/application/response_priority_service.dart';
import '../../companion/domain/companion_models.dart';
import '../../voice/application/voice_profile_controller.dart';

class LookAheadScreen extends StatelessWidget {
  const LookAheadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: JourneyLensView(onClose: () => context.pop(), autoStart: false),
    );
  }
}

/// An intentionally simple, on-device perception layer that can be used on its
/// own or embedded in active guidance without interrupting the journey.
class JourneyLensView extends ConsumerStatefulWidget {
  const JourneyLensView({
    super.key,
    required this.onClose,
    this.onTalk,
    this.instruction,
    this.distanceLabel,
    this.destinationName,
    this.autoStart = true,
  });

  final VoidCallback onClose;
  final VoidCallback? onTalk;
  final String? instruction;
  final String? distanceLabel;
  final String? destinationName;
  final bool autoStart;

  bool get isJourneyLayer => instruction != null || destinationName != null;

  @override
  ConsumerState<JourneyLensView> createState() => _JourneyLensViewState();
}

class _JourneyLensViewState extends ConsumerState<JourneyLensView> {
  static const _supportedClasses = {
    'person',
    'bicycle',
    'car',
    'motorcycle',
    'bus',
    'truck',
    'traffic light',
    'stop sign',
  };

  late final YOLOViewController _cameraController;
  bool _scanning = false;
  bool _modelReady = false;
  bool _requestingPermission = false;
  bool _permissionBlocked = false;
  bool _autoDescribe = false;
  bool _torchEnabled = false;
  String? _introMessage;
  String _observation =
      'Stand still, point the phone forward, and start when you are ready.';
  List<HazardEvent> _events = const [];
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpokenUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String? _candidateKey;
  String? _lastAnnouncedKey;
  int _candidateFrames = 0;

  @override
  void initState() {
    super.initState();
    _cameraController = YOLOViewController();
    unawaited(_cameraController.setShowOverlays(false));
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startScan());
      });
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_requestingPermission || _scanning) return;
    setState(() => _requestingPermission = true);
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      HapticFeedback.mediumImpact();
      setState(() {
        _requestingPermission = false;
        _permissionBlocked = false;
        _scanning = true;
        _modelReady = false;
        _introMessage = null;
        _observation = 'Preparing the on-device camera…';
      });
      return;
    }
    setState(() {
      _requestingPermission = false;
      _permissionBlocked = status.isPermanentlyDenied || status.isRestricted;
      _introMessage = 'Camera access is needed to use Journey Lens.';
      _observation = 'Journey Lens is off. Navigation remains available.';
    });
  }

  void _stopScan() {
    setState(() {
      _scanning = false;
      _modelReady = false;
      _events = const [];
      _introMessage = null;
      _observation = 'Journey Lens stopped.';
    });
  }

  Future<void> _toggleTorch() async {
    await _cameraController.toggleTorch();
    if (!mounted) return;
    setState(() => _torchEnabled = _cameraController.isTorchEnabled);
  }

  void _onResults(List<YOLOResult> results) {
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate) < const Duration(milliseconds: 180)) {
      return;
    }
    _lastUiUpdate = now;

    final relevant =
        results
            .where(
              (result) =>
                  _supportedClasses.contains(result.className.toLowerCase()) &&
                  result.confidence >= 0.55,
            )
            .toList()
          ..sort((a, b) {
            final aArea = a.normalizedBox.width * a.normalizedBox.height;
            final bArea = b.normalizedBox.width * b.normalizedBox.height;
            return bArea.compareTo(aArea);
          });

    if (relevant.isEmpty) {
      _candidateKey = null;
      _candidateFrames = 0;
      if (mounted && _events.isNotEmpty) {
        setState(() {
          _events = const [];
          _observation =
              'No supported objects are visible. This is not a path-clear confirmation.';
        });
      }
      return;
    }

    final primary = relevant.first;
    final direction = _direction(primary.normalizedBox.center.dx);
    final key = '${primary.className}-${direction.name}';
    if (_candidateKey == key) {
      _candidateFrames += 1;
    } else {
      _candidateKey = key;
      _candidateFrames = 1;
    }
    if (_candidateFrames < 3) return;

    final events = [
      for (final result in relevant.take(3))
        HazardEvent(
          type: result.className.toLowerCase(),
          direction: _direction(result.normalizedBox.center.dx),
          distanceBand: HazardDistanceBand.unknown,
          urgency: HazardUrgency.informational,
          confidence: result.confidence,
          firstSeen: now,
          lastSeen: now,
        ),
    ];
    final summary = _summarize(events);
    if (!mounted) return;
    setState(() {
      _events = events;
      _observation = summary;
    });
    if (_lastAnnouncedKey != key) {
      _lastAnnouncedKey = key;
      unawaited(_directionHaptic(direction));
      if (_autoDescribe &&
          now.difference(_lastSpokenUpdate) >= const Duration(seconds: 6)) {
        _lastSpokenUpdate = now;
        unawaited(_describe());
      }
    }
  }

  Future<void> _directionHaptic(HazardDirection direction) async {
    switch (direction) {
      case HazardDirection.left:
        await HapticFeedback.selectionClick();
        return;
      case HazardDirection.centre:
        await HapticFeedback.mediumImpact();
        return;
      case HazardDirection.right:
        await HapticFeedback.heavyImpact();
        return;
      case HazardDirection.unknown:
        return;
    }
  }

  HazardDirection _direction(double centreX) {
    if (centreX < 0.38) return HazardDirection.left;
    if (centreX > 0.62) return HazardDirection.right;
    return HazardDirection.centre;
  }

  String _summarize(List<HazardEvent> events) {
    final descriptions = events
        .map((event) {
          final label = switch (event.type) {
            'person' => 'Person',
            'motorcycle' => 'Motorbike',
            'bus' => 'Bus-type vehicle',
            'truck' => 'Large vehicle',
            'traffic light' => 'Traffic light',
            'stop sign' => 'Stop sign',
            _ => '${event.type[0].toUpperCase()}${event.type.substring(1)}',
          };
          final direction = switch (event.direction) {
            HazardDirection.left => 'slightly left',
            HazardDirection.centre => 'ahead',
            HazardDirection.right => 'slightly right',
            HazardDirection.unknown => 'with an uncertain direction',
          };
          return '$label $direction';
        })
        .join('. ');
    return '$descriptions. Distance is unavailable.';
  }

  Future<void> _describe() async {
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      if (profile.haptics) HapticFeedback.selectionClick();
      await ref
          .read(responsePriorityServiceProvider)
          .speak(
            '$_observation Use your usual mobility aid to confirm the path.',
            profile,
            priority: ResponsePriority.informational,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice playback is unavailable.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: _scanning ? _buildScanner(context) : _buildIntroduction(context),
    );
  }

  Widget _buildIntroduction(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 4,
            child: _RoundOverlayButton(
              tooltip: 'Close Journey Lens',
              icon: Icons.close_rounded,
              onPressed: widget.onClose,
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 76, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.center_focus_strong_rounded,
                      size: 72,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Journey Lens',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'For the Accra pilot, Lens reports people, common road vehicles, bicycles, traffic lights, and stop signs. Processing stays on this device and is not recorded.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _SafetyNotice(dark: true),
                    if (_introMessage != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _introMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.errorContainer),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: _requestingPermission ? null : _startScan,
                      icon: _requestingPermission
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        _requestingPermission
                            ? 'Opening camera…'
                            : 'Start Journey Lens',
                      ),
                    ),
                    if (_permissionBlocked) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: openAppSettings,
                        child: const Text('Open app settings'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    final model = YOLO.defaultOfficialModel() ?? 'yolo26n';
    return Stack(
      fit: StackFit.expand,
      children: [
        YOLOView(
          controller: _cameraController,
          modelPath: model,
          task: YOLOTask.detect,
          cameraResolution: '720p',
          confidenceThreshold: 0.55,
          iouThreshold: 0.55,
          streamingConfig: YOLOStreamingConfig.throttled(
            maxFPS: 15,
            inferenceFrequency: 12,
            includeMasks: false,
            includeOriginalImage: false,
            includePoses: false,
            includeOBB: false,
          ),
          onResult: _onResults,
          onModelLoad: (_, _) {
            unawaited(_cameraController.setShowOverlays(false));
            if (!mounted) return;
            setState(() {
              _modelReady = true;
              _observation =
                  'Lens ready. Keep the phone upright and move it slowly.';
            });
          },
          onModelError: (_, _, _) {
            if (!mounted) return;
            setState(() {
              _modelReady = false;
              _observation =
                  'The on-device model could not start. Navigation is still available.';
            });
          },
        ),
        const _CameraScrim(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _RoundOverlayButton(
                      tooltip: widget.isJourneyLayer
                          ? 'Return to map guidance'
                          : 'Close Journey Lens',
                      icon: widget.isJourneyLayer
                          ? Icons.map_outlined
                          : Icons.close_rounded,
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: _PrivacyPill()),
                    const SizedBox(width: 10),
                    _RoundOverlayButton(
                      tooltip: _torchEnabled
                          ? 'Turn torch off'
                          : 'Turn torch on',
                      icon: _torchEnabled
                          ? Icons.flashlight_off_rounded
                          : Icons.flashlight_on_rounded,
                      onPressed: _toggleTorch,
                    ),
                  ],
                ),
                if (widget.instruction != null) ...[
                  const SizedBox(height: 12),
                  _LensManeuverCard(
                    distanceLabel: widget.distanceLabel,
                    instruction: widget.instruction!,
                    destinationName: widget.destinationName,
                  ),
                ],
                const Spacer(),
                if (_events.isNotEmpty)
                  _DirectionIndicator(direction: _events.first.direction),
                const Spacer(),
                _ObservationPanel(
                  observation: _observation,
                  modelReady: _modelReady,
                  autoDescribe: _autoDescribe,
                  hasTalk: widget.onTalk != null,
                  onDescribe: _describe,
                  onToggleAutoDescribe: () {
                    setState(() => _autoDescribe = !_autoDescribe);
                    if (_autoDescribe && _events.isNotEmpty) {
                      unawaited(_describe());
                    }
                  },
                  onTalk: widget.onTalk,
                  onStop: () {
                    _stopScan();
                    if (widget.isJourneyLayer) widget.onClose();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraScrim extends StatelessWidget {
  const _CameraScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.58),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.78),
            ],
            stops: const [0, 0.25, 0.60, 1],
          ),
        ),
      ),
    );
  }
}

class _PrivacyPill extends StatelessWidget {
  const _PrivacyPill();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Camera processing is on device and is not recording',
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, color: Colors.white, size: 18),
            SizedBox(width: 7),
            Flexible(
              child: Text(
                'On device · not recording',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LensManeuverCard extends StatelessWidget {
  const _LensManeuverCard({
    required this.distanceLabel,
    required this.instruction,
    required this.destinationName,
  });

  final String? distanceLabel;
  final String instruction;
  final String? destinationName;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '${distanceLabel ?? 'Current instruction'}. $instruction. Destination ${destinationName ?? ''}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.navigation_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    distanceLabel ?? destinationName ?? 'Continue',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    instruction,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionIndicator extends StatelessWidget {
  const _DirectionIndicator({required this.direction});

  final HazardDirection direction;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (direction) {
      HazardDirection.left => Alignment.centerLeft,
      HazardDirection.centre => Alignment.center,
      HazardDirection.right => Alignment.centerRight,
      HazardDirection.unknown => Alignment.center,
    };
    final icon = switch (direction) {
      HazardDirection.left => Icons.arrow_back_rounded,
      HazardDirection.centre => Icons.arrow_upward_rounded,
      HazardDirection.right => Icons.arrow_forward_rounded,
      HazardDirection.unknown => Icons.help_outline_rounded,
    };
    final label = switch (direction) {
      HazardDirection.left => 'Detected on the left',
      HazardDirection.centre => 'Detected ahead',
      HazardDirection.right => 'Detected on the right',
      HazardDirection.unknown => 'Direction uncertain',
    };
    return Align(
      alignment: alignment,
      child: Semantics(
        label: label,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.46),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, color: Colors.white, size: 42),
        ),
      ),
    );
  }
}

class _ObservationPanel extends StatelessWidget {
  const _ObservationPanel({
    required this.observation,
    required this.modelReady,
    required this.autoDescribe,
    required this.hasTalk,
    required this.onDescribe,
    required this.onToggleAutoDescribe,
    required this.onTalk,
    required this.onStop,
  });

  final String observation;
  final bool modelReady;
  final bool autoDescribe;
  final bool hasTalk;
  final VoidCallback onDescribe;
  final VoidCallback onToggleAutoDescribe;
  final VoidCallback? onTalk;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.center_focus_strong_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Journey Lens',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label: observation,
            child: Text(
              observation,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                height: 1.22,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Limited recognition · use your usual mobility aid',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LensAction(
                tooltip: 'Speak current observation',
                icon: Icons.volume_up_outlined,
                label: 'Describe',
                onPressed: modelReady ? onDescribe : null,
              ),
              _LensAction(
                tooltip: autoDescribe
                    ? 'Turn automatic descriptions off'
                    : 'Turn automatic descriptions on',
                icon: autoDescribe
                    ? Icons.hearing_disabled_outlined
                    : Icons.hearing_rounded,
                label: autoDescribe ? 'Auto on' : 'Auto off',
                selected: autoDescribe,
                onPressed: modelReady ? onToggleAutoDescribe : null,
              ),
              if (hasTalk)
                _LensAction(
                  tooltip: 'Talk to Mobility AI',
                  icon: Icons.auto_awesome_rounded,
                  label: 'Ask',
                  onPressed: onTalk,
                ),
              _LensAction(
                tooltip: 'Stop Journey Lens',
                icon: Icons.stop_circle_outlined,
                label: 'Stop',
                onPressed: onStop,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LensAction extends StatelessWidget {
  const _LensAction({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.white.withValues(alpha: 0.14),
          foregroundColor: selected
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Colors.white,
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _RoundOverlayButton extends StatelessWidget {
  const _RoundOverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: Colors.black.withValues(alpha: 0.64),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
      ),
      icon: Icon(icon),
    );
  }
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: dark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'It cannot confirm distance, curbs, potholes, open drains, trotro routes, or whether a path is safe.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark
                    ? Colors.white.withValues(alpha: 0.82)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
