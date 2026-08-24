import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../companion/domain/companion_models.dart';
import '../../voice/application/voice_profile_controller.dart';
import '../../voice/data/speech_output_service.dart';

class LookAheadScreen extends ConsumerStatefulWidget {
  const LookAheadScreen({super.key});

  @override
  ConsumerState<LookAheadScreen> createState() => _LookAheadScreenState();
}

class _LookAheadScreenState extends ConsumerState<LookAheadScreen> {
  static const _supportedClasses = {
    'person',
    'bicycle',
    'car',
    'motorcycle',
    'bus',
    'truck',
    'bench',
    'chair',
    'dog',
  };

  bool _scanning = false;
  bool _modelReady = false;
  bool _requestingPermission = false;
  bool _permissionBlocked = false;
  String? _introMessage;
  String _observation =
      'Start a scan when you are standing still and ready to point the phone forward.';
  List<HazardEvent> _events = const [];
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String? _candidateKey;
  int _candidateFrames = 0;

  Future<void> _startScan() async {
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
        _observation = 'Loading the on-device detection model…';
      });
      return;
    }
    setState(() {
      _requestingPermission = false;
      _permissionBlocked = status.isPermanentlyDenied || status.isRestricted;
      _introMessage = 'Camera access is needed to look ahead.';
      _observation = 'Camera access was not granted. Look Ahead remains off.';
    });
  }

  void _stopScan() {
    setState(() {
      _scanning = false;
      _modelReady = false;
      _events = const [];
      _introMessage = null;
      _observation = 'Scan stopped. Camera processing is no longer active.';
    });
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
      if (mounted) {
        setState(() {
          _events = const [];
          _observation =
              'No supported objects detected in this view. This does not mean the path is clear.';
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
    if (mounted) {
      setState(() {
        _events = events;
        _observation = summary;
      });
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
          final label = event.type == 'person'
              ? 'Person'
              : '${event.type[0].toUpperCase()}${event.type.substring(1)}';
          final direction = switch (event.direction) {
            HazardDirection.left => 'to the left',
            HazardDirection.centre => 'near the centre',
            HazardDirection.right => 'to the right',
            HazardDirection.unknown => 'direction uncertain',
          };
          return '$label $direction';
        })
        .join('. ');
    return '$descriptions. Distance is not available. Check with your usual mobility aid.';
  }

  Future<void> _describe() async {
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      if (profile.haptics) HapticFeedback.selectionClick();
      await ref.read(speechOutputServiceProvider).speak(_observation, profile);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice playback is unavailable.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Look Ahead'),
        actions: [
          if (_scanning)
            TextButton(onPressed: _stopScan, child: const Text('Stop scan')),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _scanning ? _buildScanner(context) : _buildIntroduction(context),
      ),
    );
  }

  Widget _buildIntroduction(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.center_focus_strong_rounded,
                          size: 44,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Point your phone forward',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hold it upright, then start the camera.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (_introMessage != null) ...[
                      const SizedBox(height: 18),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _introMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(color: scheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
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
                            : 'Start camera',
                      ),
                    ),
                    if (_permissionBlocked) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: openAppSettings,
                        child: const Text('Open app settings'),
                      ),
                    ],
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanner(BuildContext context) {
    final model = YOLO.defaultOfficialModel() ?? 'yolo26n';
    return Column(
      children: [
        Expanded(
          child: YOLOView(
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
              if (!mounted) return;
              setState(() {
                _modelReady = true;
                _observation =
                    'Scan ready. Keep the phone upright and move it slowly.';
              });
            },
            onModelError: (_, _, _) {
              if (!mounted) return;
              setState(() {
                _modelReady = false;
                _observation =
                    'The on-device model could not start. Camera guidance is unavailable.';
              });
            },
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  label: _observation,
                  child: Text(
                    _observation,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_events.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_events.length} stable observation${_events.length == 1 ? '' : 's'} · confidence-filtered',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _modelReady ? _describe : null,
                        icon: const Icon(Icons.volume_up_outlined),
                        label: const Text('Describe'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _stopScan,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Stop'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
