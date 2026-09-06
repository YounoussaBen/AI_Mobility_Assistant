import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../companion/application/response_priority_service.dart';
import '../../companion/domain/companion_models.dart';
import '../../preferences/application/mobility_preferences_controller.dart';
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

class _JourneyLensViewState extends ConsumerState<JourneyLensView>
    with WidgetsBindingObserver {
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
  bool _autoDescribe = true;
  bool _speechPreferenceReady = false;
  bool _torchEnabled = false;
  String? _introMessage;
  String _observation =
      'Stand still, point the phone forward, and start when you are ready.';
  List<HazardEvent> _events = const [];
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpokenUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String? _candidateKey;
  String? _lastAnnouncedKey;
  String? _lastFeedbackKey;
  String? _announcingKey;
  int _candidateFrames = 0;
  Timer? _staleResultsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraController = YOLOViewController();
    unawaited(_cameraController.setShowOverlays(true));
    unawaited(_loadSpeechPreference());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startScan());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _staleResultsTimer?.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_scanning && state != AppLifecycleState.resumed) {
      _stopScan(message: 'Journey Lens paused.');
    }
  }

  Future<void> _loadSpeechPreference() async {
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      final preferences = await ref.read(
        mobilityPreferencesControllerProvider.future,
      );
      if (mounted) {
        setState(() {
          _autoDescribe = profile.speechEnabled && preferences.voiceGuidance;
          _speechPreferenceReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _speechPreferenceReady = true);
    }
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

  void _stopScan({String message = 'Journey Lens stopped.'}) {
    _staleResultsTimer?.cancel();
    setState(() {
      _scanning = false;
      _modelReady = false;
      _events = const [];
      _candidateKey = null;
      _candidateFrames = 0;
      _lastAnnouncedKey = null;
      _lastFeedbackKey = null;
      _announcingKey = null;
      _introMessage = null;
      _observation = message;
    });
  }

  Future<void> _toggleTorch() async {
    await _cameraController.toggleTorch();
    if (!mounted) return;
    setState(() => _torchEnabled = _cameraController.isTorchEnabled);
  }

  void _onResults(List<YOLOResult> results) {
    if (!mounted || !_scanning) return;
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
      return;
    }

    _staleResultsTimer?.cancel();
    _staleResultsTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || !_scanning) return;
      setState(() {
        _events = const [];
        _candidateKey = null;
        _candidateFrames = 0;
        _lastAnnouncedKey = null;
        _lastFeedbackKey = null;
        _observation = 'No supported objects detected.';
      });
    });

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
    if (_lastFeedbackKey != key) {
      _lastFeedbackKey = key;
      unawaited(_directionHaptic(direction));
    }
    if (_lastAnnouncedKey != key &&
        _announcingKey != key &&
        _autoDescribe &&
        _speechPreferenceReady &&
        ref.read(voiceProfileControllerProvider).value?.speechEnabled == true &&
        ref.read(mobilityPreferencesControllerProvider).value?.voiceGuidance ==
            true &&
        now.difference(_lastSpokenUpdate) >= const Duration(seconds: 10)) {
      unawaited(_announce(key));
    }
  }

  Future<void> _announce(String key) async {
    _announcingKey = key;
    final spoken = await _describe(showError: false);
    if (!mounted) return;
    if (spoken && _autoDescribe && _announcingKey == key) {
      _lastAnnouncedKey = key;
      _lastSpokenUpdate = DateTime.now();
    }
    if (_announcingKey == key) _announcingKey = null;
  }

  Future<void> _directionHaptic(HazardDirection direction) async {
    if (ref.read(voiceProfileControllerProvider).value?.haptics != true ||
        ref
                .read(mobilityPreferencesControllerProvider)
                .value
                ?.vibrationAlerts !=
            true)
      return;
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
    return '$descriptions.';
  }

  Future<bool> _describe({bool showError = true}) async {
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      if (profile.haptics) HapticFeedback.selectionClick();
      return await ref
          .read(responsePriorityServiceProvider)
          .speak(
            _observation,
            profile,
            priority: ResponsePriority.informational,
          );
    } catch (_) {
      if (!mounted || !showError) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice playback is unavailable.')),
      );
      return false;
    }
  }

  Future<void> _toggleAutoDescribe() async {
    final profileSpeechEnabled =
        ref.read(voiceProfileControllerProvider).value?.speechEnabled ??
        _autoDescribe;
    final globalSpeechEnabled =
        ref.read(mobilityPreferencesControllerProvider).value?.voiceGuidance ??
        false;
    final enabled = !(profileSpeechEnabled && globalSpeechEnabled);
    setState(() => _autoDescribe = enabled);
    try {
      if (!enabled) {
        _announcingKey = null;
        await ref.read(responsePriorityServiceProvider).stop();
      }
      final profile = await ref.read(voiceProfileControllerProvider.future);
      await ref
          .read(voiceProfileControllerProvider.notifier)
          .save(profile.copyWith(speechEnabled: enabled));
      if (enabled) {
        final preferences = await ref.read(
          mobilityPreferencesControllerProvider.future,
        );
        if (!preferences.voiceGuidance) {
          await ref
              .read(mobilityPreferencesControllerProvider.notifier)
              .save(preferences.copyWith(voiceGuidance: true));
        }
      }
      if (enabled && _events.isNotEmpty) unawaited(_describe());
    } catch (_) {
      if (!mounted) return;
      setState(() => _autoDescribe = !enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save speech preference.')),
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
    final globalSpeechEnabled =
        ref.watch(mobilityPreferencesControllerProvider).value?.voiceGuidance ??
        false;
    final profileSpeechEnabled =
        ref.watch(voiceProfileControllerProvider).value?.speechEnabled ??
        _autoDescribe;
    final speechEnabled = profileSpeechEnabled && globalSpeechEnabled;
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
            unawaited(_cameraController.setShowOverlays(true));
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
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 18,
                ),
                child: IntrinsicHeight(
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
                          const Spacer(),
                          const SizedBox(width: 10),
                          _RoundOverlayButton(
                            tooltip: speechEnabled
                                ? 'Mute automatic descriptions'
                                : 'Turn on automatic descriptions',
                            icon: speechEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            onPressed: _toggleAutoDescribe,
                          ),
                          const SizedBox(width: 6),
                          _LensMenu(
                            torchEnabled: _torchEnabled,
                            modelReady: _modelReady,
                            hasTalk: widget.onTalk != null,
                            onTorch: _toggleTorch,
                            onDescribe: _describe,
                            onTalk: widget.onTalk,
                            onStop: () {
                              _stopScan();
                              if (widget.isJourneyLayer) widget.onClose();
                            },
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
                      const Spacer(flex: 3),
                      _ObservationPanel(
                        observation: _observation,
                        modelReady: _modelReady,
                      ),
                    ],
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

class _ObservationPanel extends StatelessWidget {
  const _ObservationPanel({
    required this.observation,
    required this.modelReady,
  });

  final String observation;
  final bool modelReady;

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
            modelReady
                ? 'Limited recognition · use your mobility aid'
                : 'Starting on-device recognition…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LensMenuAction { torch, describe, talk, stop }

class _LensMenu extends StatelessWidget {
  const _LensMenu({
    required this.torchEnabled,
    required this.modelReady,
    required this.hasTalk,
    required this.onTorch,
    required this.onDescribe,
    required this.onTalk,
    required this.onStop,
  });

  final bool torchEnabled;
  final bool modelReady;
  final bool hasTalk;
  final VoidCallback onTorch;
  final VoidCallback onDescribe;
  final VoidCallback? onTalk;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_LensMenuAction>(
      tooltip: 'More Journey Lens controls',
      color: Theme.of(context).colorScheme.surface,
      iconColor: Colors.white,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: Colors.black.withValues(alpha: 0.64),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
      ),
      onSelected: (action) {
        switch (action) {
          case _LensMenuAction.torch:
            onTorch();
          case _LensMenuAction.describe:
            onDescribe();
          case _LensMenuAction.talk:
            onTalk?.call();
          case _LensMenuAction.stop:
            onStop();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _LensMenuAction.torch,
          child: ListTile(
            leading: Icon(
              torchEnabled
                  ? Icons.flashlight_off_rounded
                  : Icons.flashlight_on_rounded,
            ),
            title: Text(torchEnabled ? 'Turn torch off' : 'Turn torch on'),
          ),
        ),
        PopupMenuItem(
          value: _LensMenuAction.describe,
          enabled: modelReady,
          child: const ListTile(
            leading: Icon(Icons.volume_up_outlined),
            title: Text('Describe now'),
          ),
        ),
        if (hasTalk)
          const PopupMenuItem(
            value: _LensMenuAction.talk,
            child: ListTile(
              leading: Icon(Icons.auto_awesome_rounded),
              title: Text('Ask Mobility AI'),
            ),
          ),
        const PopupMenuItem(
          value: _LensMenuAction.stop,
          child: ListTile(
            leading: Icon(Icons.stop_circle_outlined),
            title: Text('Stop Journey Lens'),
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert_rounded),
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
