import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../app/config/app_config.dart';
import '../../../app/integrations/native_map_configuration.dart';
import '../../auth/data/auth_repository.dart';
import '../../companion/domain/companion_models.dart';
import '../../companion/application/response_priority_service.dart';
import '../../perception/presentation/look_ahead_screen.dart';
import '../../preferences/application/mobility_preferences_controller.dart';
import '../../preferences/domain/mobility_preferences.dart';
import '../../saved_places/application/saved_places_controller.dart';
import '../../voice/application/voice_profile_controller.dart';
import '../../voice/data/accra_speech_locale.dart';
import '../../voice/domain/voice_profile.dart';
import '../application/journey_session_controller.dart';
import '../data/gemini_destination_service.dart';
import '../data/google_routes_service.dart';
import '../data/route_cache_repository.dart';
import '../domain/accra_operating_area.dart';
import '../domain/route_option.dart';
import '../domain/route_recommendation.dart';

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
  late final GoogleRoutesService _routesService;
  late final GeminiDestinationService _interpreter;
  int _offRouteSamples = 0;
  bool _rerouteInFlight = false;

  @override
  void initState() {
    super.initState();
    _routesService = GoogleRoutesService(
      apiKey: AppConfig.googleMapsWebServiceApiKey,
      backendUrl: AppConfig.companionBackendUrl,
      accessToken: ref.read(authRepositoryProvider).idToken,
      cacheRepository: ref.read(routeCacheRepositoryProvider),
    );
    _interpreter = GeminiDestinationService(
      apiKey: AppConfig.geminiApiKey,
      model: AppConfig.geminiModel,
      backendUrl: AppConfig.companionBackendUrl,
      accessToken: ref.read(authRepositoryProvider).idToken,
    );
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
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locationMessage = 'Location unavailable');
      return;
    }
    if (permission == LocationPermission.whileInUse && mounted) {
      final allowBackground = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep guidance active when locked?'),
          content: const Text(
            'Allow background location so verified instructions and off-route checks can continue while this journey is active. Android shows a persistent notification and iPhone shows the location indicator.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Only while open'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow for this journey'),
            ),
          ],
        ),
      );
      if (allowBackground == true) {
        permission = await Geolocator.requestPermission();
      }
    }
    final activeSession = ref.read(journeySessionControllerProvider);
    final backgroundTitle = activeSession.destination == null
        ? 'Mobility AI guidance is active'
        : 'Guiding to ${activeSession.destination!.name}';
    final backgroundInstruction =
        activeSession.lastInstruction ??
        'Location is being used for this active journey.';
    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: backgroundTitle,
          notificationText: backgroundInstruction,
          notificationChannelName: 'Active journey guidance',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
      TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator:
            permission == LocationPermission.always,
        allowBackgroundLocationUpdates: permission == LocationPermission.always,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    };
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
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
    final point = LatLng(position.latitude, position.longitude);
    if (!AccraOperatingArea.contains(point)) {
      setState(() {
        _position = null;
        _locationMessage = 'Outside Accra pilot coverage';
      });
      return;
    }
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
      _offRouteSamples = 0;
      return;
    }

    _checkForDeviation(position, route);
  }

  void _checkForDeviation(Position position, JourneyRouteOption route) {
    if (_rerouteInFlight || route.path.isEmpty || position.accuracy > 45) {
      return;
    }
    final nearest = route.path
        .map(
          (point) => Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            point.latitude,
            point.longitude,
          ),
        )
        .reduce(math.min);
    final threshold = math.max(55.0, position.accuracy * 1.5);
    if (nearest <= threshold) {
      _offRouteSamples = 0;
      return;
    }
    _offRouteSamples++;
    if (_offRouteSamples >= 3) {
      _offRouteSamples = 0;
      unawaited(_offerReroute(position, route));
    }
  }

  Future<void> _offerReroute(
    Position position,
    JourneyRouteOption currentRoute,
  ) async {
    if (_rerouteInFlight) return;
    _rerouteInFlight = true;
    final controller = ref.read(journeySessionControllerProvider.notifier);
    final destination = ref.read(journeySessionControllerProvider).destination;
    if (destination == null) {
      _rerouteInFlight = false;
      return;
    }
    controller.beginReroute();
    final routes = await _routesService.routes(
      origin: LatLng(position.latitude, position.longitude),
      destination: destination.location,
    );
    if (!mounted) return;
    final targetMode = currentRoute.mode == JourneyTravelMode.onDemand
        ? JourneyTravelMode.driving
        : currentRoute.mode;
    var replacement = routes
        .where((route) => route.mode == targetMode)
        .firstOrNull;
    if (replacement == null) {
      controller.cancelReroute();
      controller.addTurn(
        AssistantSpeaker.companion,
        'I could not verify a replacement route. Continue only if the current route is still appropriate.',
        tool: true,
      );
      _rerouteInFlight = false;
      return;
    }
    if (currentRoute.mode == JourneyTravelMode.onDemand) {
      replacement = replacement.copyWith(
        mode: JourneyTravelMode.onDemand,
        routeLabel: currentRoute.routeLabel,
        providerName: currentRoute.providerName,
        fareMinorUnits: currentRoute.fareMinorUnits,
        currencyCode: currentRoute.currencyCode,
        waitingTime: currentRoute.waitingTime,
        serviceStatus: currentRoute.serviceStatus,
        source: currentRoute.source,
        availability: currentRoute.availability,
      );
    }
    final difference = (replacement.duration - currentRoute.duration).inMinutes
        .abs();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('You may be off route'),
        content: Text(
          'A replacement ${replacement!.displayMode.toLowerCase()} route is '
          '${replacement.durationLabel}. '
          '${difference >= 2 ? 'That differs by about $difference minutes. ' : ''}'
          '${replacement.source == JourneyEvidenceSource.cached ? 'It is an offline saved route, so conditions may have changed. ' : ''}'
          'Use the replacement route?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current route'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use replacement'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      final merged = [
        replacement,
        for (final route in routes)
          if (route.routeKey != replacement.routeKey) route,
      ];
      controller.applyReroute(merged);
      controller.addTurn(
        AssistantSpeaker.companion,
        'Replacement route confirmed. Guidance has restarted from your current location.',
        tool: true,
      );
      _lastAnnouncedStep = -1;
      await _announceCurrentInstruction(force: true);
    } else {
      controller.cancelReroute();
    }
    _rerouteInFlight = false;
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
    await ref
        .read(responsePriorityServiceProvider)
        .speak(
          instruction,
          profile,
          priority: session.phase == CompanionPhase.rerouting
              ? ResponsePriority.routeChange
              : ResponsePriority.immediateManeuver,
        );
  }

  Future<void> _repeat() async {
    await _announceCurrentInstruction(force: true);
  }

  Future<void> _togglePause() async {
    ref.read(journeySessionControllerProvider.notifier).togglePaused();
    final session = ref.read(journeySessionControllerProvider);
    if (session.phase == CompanionPhase.paused) {
      await ref.read(responsePriorityServiceProvider).stop();
    } else {
      await _announceCurrentInstruction(force: true);
    }
  }

  CompanionContext _companionContext() {
    final session = ref.read(journeySessionControllerProvider);
    final preferences =
        ref.read(mobilityPreferencesControllerProvider).value ??
        const MobilityPreferences();
    final saved = ref.read(savedPlacesControllerProvider);
    String routeSummary(JourneyRouteOption route) {
      final evidence = switch (route.source) {
        JourneyEvidenceSource.live => 'connected',
        JourneyEvidenceSource.simulated => 'simulated',
        JourneyEvidenceSource.cached => 'cached',
      };
      return '${route.displayMode}: ${route.durationLabel}, '
          '${route.distanceLabel}, fare ${route.fareLabel ?? 'unknown'}, '
          'wait ${route.waitingLabel ?? 'unknown'}, transfers '
          '${route.transfers?.toString() ?? 'unknown'}, $evidence evidence. '
          '${route.connectionSummary}';
    }

    return CompanionContext(
      recentTurns: session.turns,
      destination: session.destination?.name,
      selectedRoute: session.selectedRoute == null
          ? null
          : routeSummary(session.selectedRoute!),
      routeChoices: [for (final route in session.routes) routeSummary(route)],
      savedPlaces: [for (final place in saved) place.name],
      preferenceSummary:
          'priority ${preferences.priority.label}; reduced walking '
          '${preferences.reducedWalking}; fewer transfers '
          '${preferences.fewerTransfers}; wheelchair access '
          '${preferences.wheelchairAccess}',
    );
  }

  Future<_JourneyCompanionReply> _handleJourneyRequest(String request) async {
    final text = request.trim();
    final controller = ref.read(journeySessionControllerProvider.notifier);
    if (text.isEmpty) {
      return const _JourneyCompanionReply(
        message: 'Type or say what you need.',
      );
    }
    controller.beginRequest(text);
    final command = await _interpreter.interpret(
      text,
      context: _companionContext(),
    );
    if (!mounted) {
      return const _JourneyCompanionReply(message: 'The journey view closed.');
    }

    Future<_JourneyCompanionReply> respond(
      String message, {
      bool tool = false,
      _JourneySheetDestination destination = _JourneySheetDestination.none,
      String? query,
    }) async {
      controller.addTurn(AssistantSpeaker.companion, message, tool: tool);
      unawaited(_speakConversation(message));
      return _JourneyCompanionReply(
        message: message,
        destination: destination,
        query: query,
      );
    }

    switch (command.action) {
      case CompanionAction.searchPlaces:
        final query = command.query?.trim();
        if (query == null || query.length < 2) {
          return respond('Where would you like to go?');
        }
        return respond(
          'I’ll keep this journey active while you confirm a new destination.',
          tool: true,
          destination: _JourneySheetDestination.planSearch,
          query: query,
        );
      case CompanionAction.lookAhead:
        return respond(
          'Opening Journey Lens without leaving guidance.',
          tool: true,
          destination: _JourneySheetDestination.lens,
        );
      case CompanionAction.repeatInstruction:
        await _repeat();
        return respond(
          ref.read(journeySessionControllerProvider).lastInstruction ??
              'There is no instruction to repeat yet.',
        );
      case CompanionAction.pauseJourney:
        final current = ref.read(journeySessionControllerProvider);
        if (current.phase != CompanionPhase.paused) {
          await _togglePause();
          return respond('Journey guidance paused.');
        }
        return respond('Journey guidance is already paused.');
      case CompanionAction.resumeJourney:
        final current = ref.read(journeySessionControllerProvider);
        if (current.phase == CompanionPhase.paused) {
          await _togglePause();
          return respond('Journey guidance resumed.');
        }
        return respond('Journey guidance is already active.');
      case CompanionAction.findTransport:
        return respond(
          'I’ll refresh nearby transport choices. Simulated provider results remain clearly labelled.',
          tool: true,
          destination: _JourneySheetDestination.transport,
        );
      case CompanionAction.explainRecommendation:
        final current = ref.read(journeySessionControllerProvider);
        final route = current.selectedRoute;
        if (route == null) return respond('No route is selected yet.');
        final preferences =
            ref.read(mobilityPreferencesControllerProvider).value ??
            const MobilityPreferences();
        final ranked = RouteRanker.rank(current.routes, preferences);
        final decision = ranked
            .where((item) => item.route.routeKey == route.routeKey)
            .firstOrNull;
        return respond(
          '${decision?.explanation ?? 'This is your confirmed route.'} '
          '${route.durationLabel}, ${route.distanceLabel}. '
          '${route.fareLabel == null ? 'Fare is unknown.' : 'Fare: ${route.fareLabel}.'} '
          '${_sourceNotice(route.source)}',
        );
      case CompanionAction.alternativeRoute:
        return respond(
          'I’ll calculate alternatives. Your current guidance stays active until you confirm a replacement.',
          tool: true,
          destination: _JourneySheetDestination.reroute,
        );
      case CompanionAction.reportDelay:
        return respond(
          'I’ll refresh route and transport evidence. You will confirm any material change.',
          tool: true,
          destination: _JourneySheetDestination.reroute,
        );
      case CompanionAction.cheaperRoute:
        return respond(
          'I’ll refresh fares and show cheaper choices without replacing this route automatically.',
          tool: true,
          destination: _JourneySheetDestination.transport,
        );
      case CompanionAction.fewerTransfers:
        return respond(
          'I’ll compare routes with fewer transfers. This route remains active until you confirm another.',
          tool: true,
          destination: _JourneySheetDestination.reroute,
        );
      case CompanionAction.saveDestination:
        final destination = ref
            .read(journeySessionControllerProvider)
            .destination;
        if (destination == null) {
          return respond('There is no destination to save yet.');
        }
        final saved = ref.read(savedPlacesControllerProvider.notifier);
        if (!saved.contains(destination.placeId)) saved.toggle(destination);
        return respond('${destination.name} is saved on this device.');
      case CompanionAction.listSavedPlaces:
        final saved = ref.read(savedPlacesControllerProvider);
        if (saved.isEmpty) return respond('You have no saved places yet.');
        return respond(
          'Your saved places are ${saved.map((place) => place.name).join(', ')}.',
        );
      case CompanionAction.endJourney:
        return respond(
          'I’ll ask you to confirm before ending guidance.',
          destination: _JourneySheetDestination.endJourney,
        );
      case CompanionAction.conversationalReply:
        return respond(
          command.message ??
              'I’m listening. Tell me a little more so I can follow you.',
        );
      case CompanionAction.unknown:
        return respond(
          command.message ??
              'I didn’t quite follow that. Say it another way and I’ll stay with you.',
        );
    }
  }

  Future<void> _speakConversation(String message) async {
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      await ref
          .read(responsePriorityServiceProvider)
          .speak(message, profile, priority: ResponsePriority.conversation);
    } catch (_) {
      // The sheet always preserves a readable text response.
    }
  }

  String _sourceNotice(JourneyEvidenceSource source) => switch (source) {
    JourneyEvidenceSource.live => 'The route came from a connected source.',
    JourneyEvidenceSource.simulated =>
      'Provider availability is simulated, not live.',
    JourneyEvidenceSource.cached =>
      'This is an offline saved route, so conditions may have changed.',
  };

  Future<void> _openCompanionSheet() async {
    final action = await showModalBottomSheet<_JourneyCompanionReply>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (context) =>
          _JourneyCompanionSheet(onSubmit: _handleJourneyRequest),
    );
    if (!mounted || action == null) return;
    switch (action.destination) {
      case _JourneySheetDestination.none:
        return;
      case _JourneySheetDestination.lens:
        ref
            .read(journeySessionControllerProvider.notifier)
            .setGuidanceView(GuidanceView.lookAhead);
        return;
      case _JourneySheetDestination.planSearch:
        final query = action.query;
        if (query != null) {
          context.push('/plan?prompt=${Uri.encodeQueryComponent(query)}');
        }
        return;
      case _JourneySheetDestination.transport:
        context.push(
          '/plan?resumeDestination=true&transport=true&reroute=true',
        );
        return;
      case _JourneySheetDestination.reroute:
        context.push('/plan?resumeDestination=true&reroute=true');
        return;
      case _JourneySheetDestination.endJourney:
        await _endJourney();
        return;
    }
  }

  Future<void> _recenterMap() async {
    final route = ref.read(journeySessionControllerProvider).selectedRoute;
    final target = _position == null
        ? route?.path.firstOrNull
        : LatLng(_position!.latitude, _position!.longitude);
    if (target == null) return;
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 17, tilt: 35),
      ),
    );
  }

  Future<void> _handleMenuAction(_JourneyMenuAction action) async {
    switch (action) {
      case _JourneyMenuAction.repeat:
        await _repeat();
        return;
      case _JourneyMenuAction.pause:
        await _togglePause();
        return;
      case _JourneyMenuAction.settings:
        if (mounted) context.push('/voice-guidance');
        return;
      case _JourneyMenuAction.end:
        await _endJourney();
        return;
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
    await ref.read(responsePriorityServiceProvider).stop();
    ref.read(journeySessionControllerProvider.notifier).endJourney();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(journeySessionControllerProvider);
    final nativeMapAvailable = ref.watch(nativeMapAvailableProvider);
    final route = session.selectedRoute;
    if (route == null || session.destination == null) {
      return _NoActiveJourney(onPlan: () => context.go('/plan'));
    }
    if (!AccraOperatingArea.contains(session.destination!.location) ||
        !AccraOperatingArea.containsRoute(route.path)) {
      return _NoActiveJourney(
        title: 'Journey outside coverage',
        message:
            'This pilot now supports verified journeys inside Accra only. Plan a new Accra route to continue.',
        onPlan: () => context.go('/plan'),
      );
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
    final lensActive = session.guidanceView == GuidanceView.lookAhead;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        child: lensActive
            ? JourneyLensView(
                key: const ValueKey('journey-lens'),
                instruction: instruction,
                distanceLabel: step?.distanceLabel,
                destinationName: session.destination!.name,
                onTalk: _openCompanionSheet,
                onClose: () => ref
                    .read(journeySessionControllerProvider.notifier)
                    .setGuidanceView(GuidanceView.map),
              )
            : _MobilityJourneySurface(
                key: const ValueKey('journey-map'),
                mapAvailable: nativeMapAvailable,
                route: route,
                destinationName: session.destination!.name,
                destination: session.destination!.location,
                position: _position,
                phase: session.phase,
                locationMessage: _locationMessage,
                currentStep: session.currentStepIndex + 1,
                totalSteps: route.steps.length,
                instruction: instruction,
                step: step,
                nextStep: nextStep,
                onMapCreated: (controller) => _mapController = controller,
                onLeave: () => context.go('/home'),
                onRecenter: _recenterMap,
                onTalk: _openCompanionSheet,
                onLens: () => ref
                    .read(journeySessionControllerProvider.notifier)
                    .setGuidanceView(GuidanceView.lookAhead),
                onMenuAction: _handleMenuAction,
              ),
      ),
    );
  }
}

class _MobilityJourneySurface extends StatelessWidget {
  const _MobilityJourneySurface({
    super.key,
    required this.mapAvailable,
    required this.route,
    required this.destinationName,
    required this.destination,
    required this.position,
    required this.phase,
    required this.locationMessage,
    required this.currentStep,
    required this.totalSteps,
    required this.instruction,
    required this.step,
    required this.nextStep,
    required this.onMapCreated,
    required this.onLeave,
    required this.onRecenter,
    required this.onTalk,
    required this.onLens,
    required this.onMenuAction,
  });

  final bool mapAvailable;
  final JourneyRouteOption route;
  final String destinationName;
  final LatLng destination;
  final Position? position;
  final CompanionPhase phase;
  final String? locationMessage;
  final int currentStep;
  final int totalSteps;
  final String instruction;
  final JourneyStep? step;
  final JourneyStep? nextStep;
  final ValueChanged<GoogleMapController> onMapCreated;
  final VoidCallback onLeave;
  final VoidCallback onRecenter;
  final VoidCallback onTalk;
  final VoidCallback onLens;
  final ValueChanged<_JourneyMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final current = position == null
        ? route.path.firstOrNull ?? destination
        : LatLng(position!.latitude, position!.longitude);
    final paused = phase == CompanionPhase.paused;
    final progress = totalSteps <= 0
        ? 0.0
        : (currentStep / totalSteps).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (mapAvailable)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: current,
              zoom: 17,
              tilt: 35,
            ),
            padding: const EdgeInsets.only(top: 210, bottom: 190),
            cameraTargetBounds: CameraTargetBounds(AccraOperatingArea.bounds),
            minMaxZoomPreference: const MinMaxZoomPreference(10, 20),
            myLocationEnabled: position != null,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            trafficEnabled: route.mode == JourneyTravelMode.driving,
            markers: {
              Marker(
                markerId: const MarkerId('destination'),
                position: destination,
                infoWindow: InfoWindow(title: destinationName),
              ),
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('active-route'),
                points: route.path,
                color: Theme.of(context).colorScheme.primary,
                width: 8,
              ),
            },
            onMapCreated: onMapCreated,
          )
        else
          _UnavailableMapJourneyBackdrop(destinationName: destinationName),
        const _MapScrim(),
        SafeArea(
          child: _JourneyOverlayControls(
            route: route,
            destinationName: destinationName,
            phase: phase,
            locationMessage: locationMessage,
            progress: progress,
            currentStep: currentStep,
            totalSteps: totalSteps,
            paused: paused,
            instruction: instruction,
            step: step,
            nextStep: nextStep,
            onLeave: onLeave,
            onRecenter: onRecenter,
            onTalk: onTalk,
            onLens: onLens,
            onMenuAction: onMenuAction,
          ),
        ),
      ],
    );
  }
}

class _JourneyOverlayControls extends StatelessWidget {
  const _JourneyOverlayControls({
    required this.route,
    required this.destinationName,
    required this.phase,
    required this.locationMessage,
    required this.progress,
    required this.currentStep,
    required this.totalSteps,
    required this.paused,
    required this.instruction,
    required this.step,
    required this.nextStep,
    required this.onLeave,
    required this.onRecenter,
    required this.onTalk,
    required this.onLens,
    required this.onMenuAction,
  });

  final JourneyRouteOption route;
  final String destinationName;
  final CompanionPhase phase;
  final String? locationMessage;
  final double progress;
  final int currentStep;
  final int totalSteps;
  final bool paused;
  final String instruction;
  final JourneyStep? step;
  final JourneyStep? nextStep;
  final VoidCallback onLeave;
  final VoidCallback onRecenter;
  final VoidCallback onTalk;
  final VoidCallback onLens;
  final ValueChanged<_JourneyMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final topBar = _JourneyTopBar(
      destinationName: destinationName,
      phase: phase,
      locationMessage: locationMessage,
      onLeave: onLeave,
    );
    final maneuver = _ManeuverCard(
      paused: paused,
      instruction: instruction,
      step: step,
      nextStep: largeText ? null : nextStep,
    );
    final recenter = Align(
      alignment: Alignment.centerRight,
      child: IconButton.filledTonal(
        tooltip: 'Recenter map on my location',
        onPressed: onRecenter,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        icon: const Icon(Icons.my_location_rounded),
      ),
    );
    final capsule = _CompanionCapsule(
      route: route,
      phase: phase,
      progress: progress,
      currentStep: currentStep,
      totalSteps: totalSteps,
      onTalk: onTalk,
      onLens: onLens,
      onMenuAction: onMenuAction,
    );

    if (largeText) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topBar,
            const SizedBox(height: 10),
            maneuver,
            const SizedBox(height: 24),
            recenter,
            const SizedBox(height: 8),
            capsule,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topBar,
          const SizedBox(height: 10),
          maneuver,
          const Spacer(),
          recenter,
          const SizedBox(height: 8),
          capsule,
        ],
      ),
    );
  }
}

class _UnavailableMapJourneyBackdrop extends StatelessWidget {
  const _UnavailableMapJourneyBackdrop({required this.destinationName});

  final String destinationName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          'Visual map unavailable. Guidance to $destinationName continues with text and speech.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.72),
              const Color(0xFF102C34),
              Colors.black,
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_rounded, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Guidance is still active',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 5),
                Text(
                  'The visual map isn’t available in this build. Follow the verified steps and spoken directions.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
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

class _MapScrim extends StatelessWidget {
  const _MapScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.24),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.20),
            ],
            stops: const [0, 0.20, 0.72, 1],
          ),
        ),
      ),
    );
  }
}

class _JourneyTopBar extends StatelessWidget {
  const _JourneyTopBar({
    required this.destinationName,
    required this.phase,
    required this.locationMessage,
    required this.onLeave,
  });

  final String destinationName;
  final CompanionPhase phase;
  final String? locationMessage;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsAttention =
        phase == CompanionPhase.rerouting ||
        locationMessage?.startsWith('Weak') == true ||
        locationMessage?.contains('off') == true ||
        locationMessage?.contains('interrupted') == true;
    return Semantics(
      container: true,
      label:
          'Going to $destinationName. ${phase.assistiveDescription} ${locationMessage ?? ''}',
      child: Material(
        color: scheme.surface.withValues(alpha: 0.96),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Return to Companion home',
                onPressed: onLeave,
                icon: const Icon(Icons.home_outlined),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destinationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Icon(
                          needsAttention
                              ? Icons.info_outline_rounded
                              : Icons.navigation_rounded,
                          size: 15,
                          color: needsAttention
                              ? scheme.tertiary
                              : scheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            locationMessage == null
                                ? phase.label
                                : '${phase.label} · $locationMessage',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManeuverCard extends StatelessWidget {
  const _ManeuverCard({
    required this.paused,
    required this.instruction,
    required this.step,
    required this.nextStep,
  });

  final bool paused;
  final String instruction;
  final JourneyStep? step;
  final JourneyStep? nextStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryText = paused ? 'Guidance paused' : instruction;
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${paused ? 'Guidance paused' : '${step?.distanceLabel ?? 'Now'}. $instruction'}'
          '${nextStep == null ? '' : '. Then ${nextStep!.instruction}'}',
      child: Material(
        color: paused
            ? scheme.surface.withValues(alpha: 0.97)
            : scheme.primaryContainer.withValues(alpha: 0.97),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: paused
                      ? scheme.surfaceContainerHighest
                      : scheme.primary,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  paused
                      ? Icons.pause_rounded
                      : _maneuverIcon(step?.maneuver, step?.travelMode),
                  size: 31,
                  color: paused ? scheme.onSurfaceVariant : scheme.onPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paused
                          ? 'Resume when you are ready'
                          : step?.distanceLabel ?? 'Continue',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: paused
                            ? scheme.onSurfaceVariant
                            : scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      primaryText,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: paused
                                ? scheme.onSurface
                                : scheme.onPrimaryContainer,
                            height: 1.13,
                          ),
                    ),
                    if (!paused && nextStep != null) ...[
                      const SizedBox(height: 9),
                      Text(
                        'Then · ${nextStep!.instruction}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.78,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _maneuverIcon(
    String? maneuver,
    JourneyTravelMode? travelMode,
  ) {
    final value = maneuver?.toLowerCase() ?? '';
    if (value.contains('left')) return Icons.turn_left_rounded;
    if (value.contains('right')) return Icons.turn_right_rounded;
    if (value.contains('u_turn')) return Icons.u_turn_left_rounded;
    return travelMode?.icon ?? Icons.straight_rounded;
  }
}

class _CompanionCapsule extends StatelessWidget {
  const _CompanionCapsule({
    required this.route,
    required this.phase,
    required this.progress,
    required this.currentStep,
    required this.totalSteps,
    required this.onTalk,
    required this.onLens,
    required this.onMenuAction,
  });

  final JourneyRouteOption route;
  final CompanionPhase phase;
  final double progress;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onTalk;
  final VoidCallback onLens;
  final ValueChanged<_JourneyMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Material(
      color: scheme.surface.withValues(alpha: 0.97),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 10, 10),
        child: Column(
          children: [
            if (largeText)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(route.mode.icon, color: scheme.primary, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${route.durationLabel} · ${route.displayMode}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    totalSteps == 0
                        ? route.distanceLabel
                        : 'Step $currentStep of $totalSteps',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(route.mode.icon, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${route.durationLabel} · ${route.displayMode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      totalSteps == 0
                          ? route.distanceLabel
                          : 'Step $currentStep of $totalSteps',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 9),
            Semantics(
              label: '${(progress * 100).round()} percent of route steps',
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Ask Mobility AI without leaving guidance',
                    child: InkWell(
                      key: const Key('journey_companion_capsule'),
                      onTap: onTalk,
                      borderRadius: BorderRadius.circular(18),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 54),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.auto_awesome_rounded,
                                  color: scheme.onPrimary,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ask Mobility',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      'Talk naturally during guidance',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Open Journey Lens',
                  onPressed: onLens,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                  ),
                  icon: const Icon(Icons.center_focus_strong_rounded),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<_JourneyMenuAction>(
                  tooltip: 'More journey controls',
                  onSelected: onMenuAction,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: _JourneyMenuAction.repeat,
                      child: ListTile(
                        leading: Icon(Icons.replay_rounded),
                        title: Text('Repeat instruction'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _JourneyMenuAction.pause,
                      child: ListTile(
                        leading: Icon(
                          phase == CompanionPhase.paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        title: Text(
                          phase == CompanionPhase.paused
                              ? 'Resume guidance'
                              : 'Pause guidance',
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: _JourneyMenuAction.settings,
                      child: ListTile(
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Guidance settings'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _JourneyMenuAction.end,
                      child: ListTile(
                        leading: Icon(
                          Icons.stop_circle_outlined,
                          color: scheme.error,
                        ),
                        title: Text(
                          'End journey',
                          style: TextStyle(color: scheme.error),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _JourneySheetDestination {
  none,
  lens,
  planSearch,
  transport,
  reroute,
  endJourney,
}

class _JourneyCompanionReply {
  const _JourneyCompanionReply({
    required this.message,
    this.destination = _JourneySheetDestination.none,
    this.query,
  });

  final String message;
  final _JourneySheetDestination destination;
  final String? query;
}

enum _JourneyMenuAction { repeat, pause, settings, end }

class _JourneyCompanionSheet extends ConsumerStatefulWidget {
  const _JourneyCompanionSheet({required this.onSubmit});

  final Future<_JourneyCompanionReply> Function(String request) onSubmit;

  @override
  ConsumerState<_JourneyCompanionSheet> createState() =>
      _JourneyCompanionSheetState();
}

class _JourneyCompanionSheetState
    extends ConsumerState<_JourneyCompanionSheet> {
  static const _suggestions = [
    'Why this route?',
    'Find a cheaper option',
    'The trotro is delayed',
    'What’s ahead?',
  ];

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  bool _busy = false;
  bool _listening = false;
  String? _localMessage;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    unawaited(_speech.cancel());
    super.dispose();
  }

  Future<void> _send([String? suppliedText]) async {
    final text = (suppliedText ?? _controller.text).trim();
    if (text.isEmpty || _busy) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _busy = true;
      _listening = false;
      _localMessage = null;
      _controller.clear();
    });
    final reply = await widget.onSubmit(text);
    if (!mounted) return;
    if (reply.destination != _JourneySheetDestination.none) {
      Navigator.pop(context, reply);
      return;
    }
    setState(() {
      _busy = false;
      _localMessage = reply.message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  Future<void> _toggleListening() async {
    if (_busy) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      options: [SpeechToText.androidNoBluetooth],
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _localMessage = 'Voice input stopped. You can type instead.';
        });
      },
    );
    if (!available) {
      if (mounted) {
        setState(() => _localMessage = 'Voice input is unavailable.');
      }
      return;
    }
    final localeId = await preferredAccraSpeechLocale(_speech);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _localMessage = null;
    });
    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
        localeId: localeId,
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final words = result.recognizedWords.trim();
    _controller.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    if (result.finalResult && words.isNotEmpty) unawaited(_send(words));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(journeySessionControllerProvider);
    final turns = session.turns.skip(
      session.turns.length > 8 ? session.turns.length - 8 : 0,
    );
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobility AI',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Guidance continues while we talk',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close conversation',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI conversation may be imperfect. Route facts and changes use verified app tools and require confirmation when material.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  if (turns.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        'Ask naturally about the journey, nearby transport, a delay, or anything else on your mind.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  for (final turn in turns) _ConversationBubble(turn: turn),
                  if (_busy) const _ThinkingBubble(),
                  if (_localMessage != null &&
                      session.turns.lastOrNull?.text != _localMessage)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_localMessage!),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final suggestion in _suggestions) ...[
                    ActionChip(
                      label: Text(suggestion),
                      onPressed: _busy ? null : () => _send(suggestion),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _listening
                          ? 'Listening…'
                          : 'Ask about this journey…',
                      prefixIcon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('journey_companion_microphone'),
                  tooltip: _listening
                      ? 'Stop listening'
                      : 'Speak to Mobility AI',
                  onPressed: _busy ? null : _toggleListening,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(54, 54),
                    backgroundColor: _listening
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    foregroundColor: _listening
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer,
                  ),
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _busy ? null : _send,
                  style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationBubble extends StatelessWidget {
  const _ConversationBubble({required this.turn});

  final AssistantTurn turn;

  @override
  Widget build(BuildContext context) {
    final user = turn.speaker == AssistantSpeaker.user;
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: user ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 5),
            bottomRight: Radius.circular(user ? 5 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!user)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  turn.isToolStatus
                      ? 'Mobility AI · verified action'
                      : 'Mobility AI',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              turn.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: user ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        liveRegion: true,
        label: 'Mobility AI is thinking',
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const SizedBox(
            width: 46,
            child: LinearProgressIndicator(minHeight: 3),
          ),
        ),
      ),
    );
  }
}

class _NoActiveJourney extends StatelessWidget {
  const _NoActiveJourney({
    required this.onPlan,
    this.title = 'No active journey',
    this.message =
        'Choose and confirm a verified route before starting guidance.',
  });

  final VoidCallback onPlan;
  final String title;
  final String message;

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
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    message,
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
