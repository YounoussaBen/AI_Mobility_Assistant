import 'dart:async';
import 'dart:math' as math;

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
import '../../preferences/application/mobility_preferences_controller.dart';
import '../../preferences/domain/mobility_preferences.dart';
import '../../voice/application/voice_profile_controller.dart';
import '../../voice/data/accra_speech_locale.dart';
import '../application/journey_session_controller.dart';
import '../data/gemini_destination_service.dart';
import '../data/google_places_service.dart';
import '../data/google_routes_service.dart';
import '../data/route_cache_repository.dart';
import '../domain/accra_operating_area.dart';
import '../domain/place.dart';
import '../domain/route_option.dart';
import '../domain/route_recommendation.dart';
import '../../saved_places/application/saved_places_controller.dart';
import '../../transport/data/transport_availability_service.dart';

class JourneyPlannerScreen extends ConsumerStatefulWidget {
  const JourneyPlannerScreen({
    super.key,
    this.startWithVoice = false,
    this.initialPrompt,
    this.resumeDestination = false,
    this.reroute = false,
    this.transportOnly = false,
  });

  final bool startWithVoice;
  final String? initialPrompt;
  final bool resumeDestination;
  final bool reroute;
  final bool transportOnly;

  @override
  ConsumerState<JourneyPlannerScreen> createState() =>
      _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends ConsumerState<JourneyPlannerScreen>
    with WidgetsBindingObserver {
  late final GooglePlacesService _places;
  late final GoogleRoutesService _routesService;
  late final GeminiDestinationService _gemini;
  final _speech = SpeechToText();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _random = math.Random.secure();

  Timer? _searchDebounce;
  GoogleMapController? _mapController;
  LatLng? _origin;
  JourneyPlace? _destination;
  List<PlaceSuggestion> _suggestions = const [];
  List<RankedRoute> _rankedRoutes = const [];
  String? _selectedRouteKey;
  _LocationState _locationState = _LocationState.loading;
  String _sessionToken = '';
  String? _message;
  bool _searching = false;
  bool _loadingRoutes = false;
  bool _listening = false;
  bool _understandingSpeech = false;
  bool _showMap = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _places = GooglePlacesService(
      apiKey: AppConfig.googleMapsWebServiceApiKey,
      backendUrl: AppConfig.companionBackendUrl,
      accessToken: ref.read(authRepositoryProvider).idToken,
    );
    _routesService = GoogleRoutesService(
      apiKey: AppConfig.googleMapsWebServiceApiKey,
      backendUrl: AppConfig.companionBackendUrl,
      accessToken: ref.read(authRepositoryProvider).idToken,
      cacheRepository: ref.read(routeCacheRepositoryProvider),
    );
    _gemini = GeminiDestinationService(
      apiKey: AppConfig.geminiApiKey,
      model: AppConfig.geminiModel,
      backendUrl: AppConfig.companionBackendUrl,
      accessToken: ref.read(authRepositoryProvider).idToken,
    );
    _sessionToken = _newSessionToken();
    unawaited(_loadCurrentLocation());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prompt = widget.initialPrompt?.trim();
      if (prompt?.isNotEmpty == true) {
        _searchController.text = prompt!;
        unawaited(_searchPlaces(prompt));
      } else if (widget.startWithVoice) {
        unawaited(_startListening());
      } else if (widget.resumeDestination) {
        final session = ref.read(journeySessionControllerProvider);
        final destination = session.destination;
        if (destination != null) {
          if (!AccraOperatingArea.contains(destination.location)) {
            setState(() {
              _message =
                  'That saved destination is outside this Accra-only pilot.';
            });
            return;
          }
          _destination = destination;
          _searchController.text = destination.name;
          if (!widget.reroute && session.routes.isNotEmpty) {
            final preferences =
                ref.read(mobilityPreferencesControllerProvider).value ??
                const MobilityPreferences();
            _rankedRoutes = RouteRanker.rank(session.routes, preferences);
            _selectedRouteKey = session.selectedRoute?.routeKey;
          } else if (widget.reroute) {
            ref.read(journeySessionControllerProvider.notifier).beginReroute();
          }
          setState(() {});
          unawaited(_loadRoutes());
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController?.dispose();
    unawaited(_speech.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_locationState == _LocationState.serviceOff ||
            _locationState == _LocationState.deniedForever)) {
      unawaited(_loadCurrentLocation());
    }
  }

  String _newSessionToken() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  Future<void> _loadCurrentLocation({bool requestPermission = false}) async {
    if (mounted) {
      setState(() => _locationState = _LocationState.loading);
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _locationState = _LocationState.serviceOff);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      if (mounted) setState(() => _locationState = _LocationState.denied);
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _locationState = _LocationState.deniedForever);
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      if (!AccraOperatingArea.contains(point)) {
        setState(() {
          _origin = null;
          _locationState = _LocationState.outsideAccra;
        });
        return;
      }
      setState(() {
        _origin = point;
        _locationState = _LocationState.ready;
      });
      if (_destination != null) unawaited(_loadRoutes());
    } on TimeoutException {
      if (mounted) setState(() => _locationState = _LocationState.unavailable);
    } catch (_) {
      if (mounted) setState(() => _locationState = _LocationState.unavailable);
    }
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      _message = null;
      if (_destination != null && query != _destination!.name) {
        _destination = null;
        _rankedRoutes = const [];
        _selectedRouteKey = null;
        _showMap = false;
      }
      if (query.length < 2) {
        _suggestions = const [];
        _searching = false;
      }
    });
    if (query.length < 2) return;
    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      () => unawaited(_searchPlaces(query)),
    );
  }

  Future<void> _searchPlaces(String query) async {
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _message = null;
      _suggestions = const [];
    });
    ref
        .read(journeySessionControllerProvider.notifier)
        .setPhase(CompanionPhase.clarifying);
    try {
      final suggestions = await _places.autocomplete(
        input: query,
        sessionToken: _sessionToken,
        near: _origin,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _suggestions = suggestions;
        _searching = false;
        _message = suggestions.isEmpty
            ? 'No matching Accra places were found. Try a landmark and neighbourhood.'
            : null;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _message =
            AppConfig.googleMapsWebServiceApiKey.isEmpty &&
                AppConfig.companionBackendUrl.isEmpty
            ? 'Place search needs a configured Maps web-service connection.'
            : 'Place search is unavailable right now. Try again.';
      });
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _suggestions = const [];
      _searching = true;
      _message = null;
    });
    try {
      final destination = await _places.details(
        placeId: suggestion.placeId,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      _sessionToken = _newSessionToken();
      _searchController.value = TextEditingValue(
        text: destination.name,
        selection: TextSelection.collapsed(offset: destination.name.length),
      );
      setState(() {
        _destination = destination;
        _searching = false;
        _message = null;
      });
      ref
          .read(journeySessionControllerProvider.notifier)
          .destinationConfirmed(destination);
      await _loadRoutes();
    } on OutsideAccraOperatingArea {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _message =
            'That place is outside the Accra pilot area. Choose a destination in Accra.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _message =
            'That destination could not be opened. Choose another result.';
      });
    }
  }

  Future<void> _loadRoutes() async {
    final origin = _origin;
    final destination = _destination;
    if (destination == null) return;
    if (origin == null) {
      return;
    }
    if (!AccraOperatingArea.contains(origin) ||
        !AccraOperatingArea.contains(destination.location)) {
      setState(() {
        _message =
            'Route planning is limited to journeys inside the Accra pilot area.';
      });
      return;
    }
    if (_loadingRoutes) return;

    setState(() {
      _loadingRoutes = true;
      _rankedRoutes = const [];
      _selectedRouteKey = null;
      _message = null;
    });
    if (!widget.reroute) {
      ref
          .read(journeySessionControllerProvider.notifier)
          .setPhase(CompanionPhase.checkingRoutes);
    }

    final googleRoutes = await _routesService.routes(
      origin: origin,
      destination: destination.location,
    );
    if (!mounted) return;
    final transportRoutes = await ref
        .read(transportAvailabilityServiceProvider)
        .search(
          origin: origin,
          destination: destination.location,
          baseRoutes: googleRoutes,
        );
    if (!mounted) return;
    final routes = [
      if (!widget.transportOnly) ...googleRoutes,
      ...transportRoutes,
    ];
    final preferences =
        ref.read(mobilityPreferencesControllerProvider).value ??
        const MobilityPreferences();
    final ranked = RouteRanker.rank(routes, preferences);
    final selected = ranked.firstOrNull?.route.routeKey;
    setState(() {
      _loadingRoutes = false;
      _rankedRoutes = ranked;
      _selectedRouteKey = selected;
      _message = ranked.isEmpty
          ? AppConfig.googleMapsWebServiceApiKey.isEmpty &&
                    AppConfig.companionBackendUrl.isEmpty
                ? 'Route comparison needs a configured Maps web-service connection.'
                : 'No verified route options are available right now.'
          : ranked.any(
              (item) => item.route.source == JourneyEvidenceSource.cached,
            )
          ? 'Using an offline route saved on this device. Conditions may have changed.'
          : null;
    });
    final controller = ref.read(journeySessionControllerProvider.notifier);
    if (!widget.reroute) {
      controller.routesReady([
        for (final rankedRoute in ranked) rankedRoute.route,
      ], preferredRouteKey: selected);
      if (selected != null) controller.selectRouteByKey(selected);
    }
  }

  Future<void> _submitSearch() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() => _message = 'Enter a destination or place category.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await _searchPlaces(query);
  }

  Future<void> _startListening() async {
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
          _message = 'Voice input stopped. Type the destination instead.';
        });
      },
    );
    if (!available) {
      if (mounted) {
        setState(() => _message = 'Voice input is unavailable on this device.');
      }
      return;
    }
    final localeId = await preferredAccraSpeechLocale(_speech);
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _message = null;
    });
    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
        localeId: localeId,
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    _searchController.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    setState(() {});
    if (result.finalResult) unawaited(_understandSpeech(words));
  }

  Future<void> _understandSpeech(String transcript) async {
    setState(() {
      _listening = false;
      _understandingSpeech = true;
      _message = null;
    });
    final command = await _gemini.interpret(transcript);
    if (!mounted) return;
    setState(() => _understandingSpeech = false);
    if (command.action == CompanionAction.lookAhead) {
      context.push('/look-ahead');
      return;
    }
    final destination = command.query?.trim();
    if (command.action != CompanionAction.searchPlaces ||
        destination == null ||
        destination.length < 2) {
      setState(() {
        _message = 'Tell me an Accra destination, such as “Osu pharmacy”.';
      });
      return;
    }
    _searchController.value = TextEditingValue(
      text: destination,
      selection: TextSelection.collapsed(offset: destination.length),
    );
    await _searchPlaces(destination);
  }

  Future<void> _openLocationSettings() async {
    if (_locationState == _LocationState.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  void _selectRoute(String routeKey) {
    HapticFeedback.selectionClick();
    setState(() => _selectedRouteKey = routeKey);
    if (!widget.reroute) {
      ref
          .read(journeySessionControllerProvider.notifier)
          .selectRouteByKey(routeKey);
    }
    if (_showMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    }
  }

  Future<void> _hearRoute(RankedRoute ranked) async {
    final route = ranked.route;
    final walking = route.walkingDistanceMeters;
    final text =
        '${ranked.title}. ${ranked.explanation} '
        '${route.displayMode}. ${route.durationLabel}, ${route.distanceLabel}. '
        '${walking == null ? '' : 'Verified walking: $walking metres. '}'
        '${route.waitingLabel == null ? '' : '${route.waitingLabel}. '}'
        '${route.fareLabel == null ? 'Fare unavailable. ' : 'Fare ${route.fareLabel}. '}'
        '${route.source == JourneyEvidenceSource.simulated
            ? 'Provider data is simulated, not live. '
            : route.source == JourneyEvidenceSource.cached
            ? 'This is an offline saved route. '
            : ''}'
        'Step-free access data is unavailable.';
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      await ref
          .read(responsePriorityServiceProvider)
          .speak(text, profile, priority: ResponsePriority.informational);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice playback is unavailable.')),
      );
    }
  }

  Future<void> _startJourney(RankedRoute ranked) async {
    _selectRoute(ranked.route.routeKey);
    final controller = ref.read(journeySessionControllerProvider.notifier);
    if (widget.reroute) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use this replacement route?'),
          content: Text(
            '${ranked.route.displayMode} takes ${ranked.route.durationLabel}. '
            'Guidance will restart from the beginning of this updated route.',
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
      if (confirmed != true) return;
      controller.routesReady([
        for (final item in _rankedRoutes) item.route,
      ], preferredRouteKey: ranked.route.routeKey);
      controller.addTurn(
        AssistantSpeaker.companion,
        'Replacement route confirmed: ${ranked.route.displayMode}.',
        tool: true,
      );
    }
    controller.startJourney();
    if (!mounted) return;
    context.push('/guidance');
  }

  void _leavePlanner() {
    if (widget.reroute) {
      ref.read(journeySessionControllerProvider.notifier).cancelReroute();
    }
    context.pop();
  }

  Future<void> _requestTransport(RankedRoute ranked) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit prototype request?'),
        content: Text(
          '${ranked.route.displayMode}\n\n'
          '${ranked.route.waitingLabel ?? 'Waiting time unknown'} · '
          '${ranked.route.fareLabel ?? 'Fare unknown'}\n\n'
          'This provider is simulated for evaluation. No real vehicle will be dispatched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit simulated request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final request = await ref
        .read(transportAvailabilityServiceProvider)
        .request(ranked.route);
    if (!mounted) return;
    ref
        .read(journeySessionControllerProvider.notifier)
        .addTurn(AssistantSpeaker.companion, request.message, tool: true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${request.message} Reference ${request.id}.')),
    );
  }

  Future<void> _fitMap() async {
    final controller = _mapController;
    final route = _rankedRoutes
        .where((item) => item.route.routeKey == _selectedRouteKey)
        .firstOrNull
        ?.route;
    if (controller == null || route == null || route.path.isEmpty) return;
    var minLat = route.path.first.latitude;
    var maxLat = minLat;
    var minLng = route.path.first.longitude;
    var maxLng = minLng;
    for (final point in route.path.skip(1)) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          48,
        ),
      );
    } catch (_) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          _destination?.location ?? AccraOperatingArea.center,
          14,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedPlaces = ref.watch(savedPlacesControllerProvider);
    final nativeMapAvailable = ref.watch(nativeMapAvailableProvider);
    final phase = _listening
        ? CompanionPhase.listening
        : _understandingSpeech
        ? CompanionPhase.understanding
        : _loadingRoutes
        ? CompanionPhase.checkingRoutes
        : _rankedRoutes.isNotEmpty
        ? CompanionPhase.routeReady
        : CompanionPhase.clarifying;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && widget.reroute) {
          ref.read(journeySessionControllerProvider.notifier).cancelReroute();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _leavePlanner,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Plan in Accra'),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PlannerStatus(phase: phase),
                      const SizedBox(height: 18),
                      Text(
                        _destination == null
                            ? 'Where in Accra should we go?'
                            : 'Here’s what I verified',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _destination == null
                            ? 'Say or type an Accra place or landmark. You’ll confirm the exact result before I compare routes.'
                            : 'Choose a route after reviewing the reason and any missing information.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _DestinationComposer(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        listening: _listening,
                        busy: _searching || _understandingSpeech,
                        onChanged: _onQueryChanged,
                        onSubmitted: (_) => _submitSearch(),
                        onVoice: _startListening,
                        onClear: () {
                          _searchController.clear();
                          _searchFocus.requestFocus();
                          setState(() {
                            _destination = null;
                            _suggestions = const [];
                            _rankedRoutes = const [];
                            _selectedRouteKey = null;
                            _message = null;
                            _showMap = false;
                          });
                        },
                      ),
                      if (_locationState.needsAttention) ...[
                        const SizedBox(height: 12),
                        _LocationIssue(
                          state: _locationState,
                          onRetry: () => _loadCurrentLocation(
                            requestPermission:
                                _locationState == _LocationState.denied,
                          ),
                          onSettings: _openLocationSettings,
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        _InlineMessage(message: _message!),
                      ],
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SuggestionsCard(
                          suggestions: _suggestions,
                          onSelected: _selectSuggestion,
                        ),
                      ],
                      if (_destination != null) ...[
                        const SizedBox(height: 20),
                        _ConfirmedDestinationCard(
                          destination: _destination!,
                          saved: savedPlaces.any(
                            (place) => place.placeId == _destination!.placeId,
                          ),
                          onToggleSaved: () => ref
                              .read(savedPlacesControllerProvider.notifier)
                              .toggle(_destination!),
                        ),
                      ],
                      if (_loadingRoutes) ...[
                        const SizedBox(height: 14),
                        const _RouteLoadingSkeleton(),
                      ],
                      if (_rankedRoutes.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        Text(
                          'Route choices',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Compared by app rules using your saved travel preferences.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        for (final ranked in _rankedRoutes) ...[
                          _RouteDecisionCard(
                            ranked: ranked,
                            selected:
                                ranked.route.routeKey == _selectedRouteKey,
                            onSelect: () => _selectRoute(ranked.route.routeKey),
                            onHear: () => _hearRoute(ranked),
                            onStart: () => _startJourney(ranked),
                            onRequest: ranked.route.isRequestable
                                ? () => _requestTransport(ranked)
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _showMap = !_showMap);
                            if (_showMap && nativeMapAvailable) {
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _fitMap(),
                              );
                            }
                          },
                          icon: Icon(
                            _showMap
                                ? Icons.visibility_off_outlined
                                : nativeMapAvailable
                                ? Icons.map_outlined
                                : Icons.info_outline_rounded,
                          ),
                          label: Text(
                            _showMap
                                ? 'Hide map'
                                : nativeMapAvailable
                                ? 'Show map preview'
                                : 'Map preview unavailable',
                          ),
                        ),
                        if (_showMap) ...[
                          const SizedBox(height: 12),
                          _MapPreview(
                            mapAvailable: nativeMapAvailable,
                            origin: _origin,
                            destination: _destination,
                            routes: [
                              for (final ranked in _rankedRoutes) ranked.route,
                            ],
                            selectedRouteKey: _selectedRouteKey,
                            onCreated: (controller) {
                              _mapController = controller;
                              unawaited(_fitMap());
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        const _WalkingSafetyNotice(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LocationState {
  loading,
  ready,
  outsideAccra,
  serviceOff,
  denied,
  deniedForever,
  unavailable,
}

extension on _LocationState {
  bool get needsAttention =>
      this != _LocationState.loading && this != _LocationState.ready;
}

class _PlannerStatus extends StatelessWidget {
  const _PlannerStatus({required this.phase});

  final CompanionPhase phase;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: phase.assistiveDescription,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              phase == CompanionPhase.checkingRoutes
                  ? Icons.sync_rounded
                  : Icons.auto_awesome_rounded,
              size: 19,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              phase.label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationComposer extends StatelessWidget {
  const _DestinationComposer({
    required this.controller,
    required this.focusNode,
    required this.listening,
    required this.busy,
    required this.onChanged,
    required this.onSubmitted,
    required this.onVoice,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool listening;
  final bool busy;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onVoice;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: 'Destination',
        hintText: 'Accra place, landmark, or category',
        prefixIcon: const Icon(Icons.place_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear destination',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            IconButton(
              tooltip: listening ? 'Stop listening' : 'Speak destination',
              onPressed: busy && !listening ? null : onVoice,
              icon: Icon(
                listening ? Icons.stop_circle_outlined : Icons.mic_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationIssue extends StatelessWidget {
  const _LocationIssue({
    required this.state,
    required this.onRetry,
    required this.onSettings,
  });

  final _LocationState state;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle, action) = switch (state) {
      _LocationState.serviceOff => (
        Icons.location_disabled_outlined,
        'Location is off',
        'Turn it on to compare routes from where you are.',
        'Turn on location',
      ),
      _LocationState.denied => (
        Icons.location_on_outlined,
        'Your location is needed',
        'Use it to compare routes from where you are.',
        'Use my location',
      ),
      _LocationState.deniedForever => (
        Icons.settings_outlined,
        'Location access is blocked',
        'Turn it on in settings to compare routes.',
        'Open settings',
      ),
      _LocationState.unavailable => (
        Icons.gps_off_rounded,
        'Can’t find your location',
        'Move to an open area, then try again.',
        'Try again',
      ),
      _LocationState.outsideAccra => (
        Icons.location_city_outlined,
        'Outside the Accra pilot area',
        'This demo plans journeys only when you and the destination are in Accra.',
        'Check again',
      ),
      _LocationState.loading || _LocationState.ready => throw StateError(
        'Location issues are shown only when attention is needed.',
      ),
    };
    final opensSettings =
        state == _LocationState.serviceOff ||
        state == _LocationState.deniedForever;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: opensSettings ? onSettings : onRetry,
                child: Text(action),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionsCard extends StatelessWidget {
  const _SuggestionsCard({required this.suggestions, required this.onSelected});

  final List<PlaceSuggestion> suggestions;
  final ValueChanged<PlaceSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < suggestions.length; index++) ...[
            InkWell(
              onTap: () => onSelected(suggestions[index]),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 68),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestions[index].primaryText,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (suggestions[index]
                                .secondaryText
                                .isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                suggestions[index].secondaryText,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
            if (index != suggestions.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ConfirmedDestinationCard extends StatelessWidget {
  const _ConfirmedDestinationCard({
    required this.destination,
    required this.saved,
    required this.onToggleSaved,
  });

  final JourneyPlace destination;
  final bool saved;
  final VoidCallback onToggleSaved;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.flag_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirmed destination',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destination.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (destination.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      destination.address,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: saved ? 'Remove saved place' : 'Save place',
              onPressed: onToggleSaved,
              icon: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteLoadingSkeleton extends StatefulWidget {
  const _RouteLoadingSkeleton();

  @override
  State<_RouteLoadingSkeleton> createState() => _RouteLoadingSkeletonState();
}

class _RouteLoadingSkeletonState extends State<_RouteLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 1;
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.10);
    return Semantics(
      liveRegion: true,
      label: 'Comparing routes.',
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.55, end: 1).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          ),
          child: Padding(
            key: const Key('route_loading_skeleton'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _SkeletonShape(
                      width: 42,
                      height: 42,
                      radius: 14,
                      color: placeholder,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.42,
                            child: _SkeletonShape(
                              height: 11,
                              color: placeholder,
                            ),
                          ),
                          const SizedBox(height: 9),
                          FractionallySizedBox(
                            widthFactor: 0.72,
                            child: _SkeletonShape(
                              height: 16,
                              color: placeholder,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _SkeletonShape(
                        height: 30,
                        radius: 15,
                        color: placeholder,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SkeletonShape(
                        height: 30,
                        radius: 15,
                        color: placeholder,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonShape extends StatelessWidget {
  const _SkeletonShape({
    this.width,
    required this.height,
    this.radius = 999,
    required this.color,
  });

  final double? width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _RouteDecisionCard extends StatelessWidget {
  const _RouteDecisionCard({
    required this.ranked,
    required this.selected,
    required this.onSelect,
    required this.onHear,
    required this.onStart,
    this.onRequest,
  });

  final RankedRoute ranked;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onHear;
  final VoidCallback onStart;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final route = ranked.route;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      label:
          '${ranked.title}, ${route.mode.label}, ${route.durationLabel}, '
          '${route.distanceLabel}. ${route.source.name} evidence. '
          'Step-free access data unavailable.',
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(route.mode.icon, color: scheme.primary),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ranked.isRecommended)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                'RECOMMENDED',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: scheme.primary,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                    ),
                              ),
                            ),
                          Text(
                            ranked.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            route.displayMode,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(
                      icon: Icons.schedule_rounded,
                      label: route.durationLabel,
                    ),
                    _MetricChip(
                      icon: Icons.straighten_rounded,
                      label: route.distanceLabel,
                    ),
                    if (route.walkingDistanceMeters != null)
                      _MetricChip(
                        icon: Icons.directions_walk_rounded,
                        label: '${route.walkingDistanceMeters} m walking',
                      ),
                    if (route.transfers != null)
                      _MetricChip(
                        icon: Icons.multiple_stop_rounded,
                        label: '${route.transfers} transfers',
                      ),
                    if (route.waitingLabel != null)
                      _MetricChip(
                        icon: Icons.hourglass_bottom_rounded,
                        label: route.waitingLabel!,
                      ),
                    if (route.fareLabel != null)
                      _MetricChip(
                        icon: Icons.payments_outlined,
                        label: route.fareLabel!,
                      ),
                  ],
                ),
                const SizedBox(height: 13),
                Text(
                  ranked.explanation,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (route.serviceStatus != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    route.serviceStatus!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (route.source != JourneyEvidenceSource.live) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      route.source == JourneyEvidenceSource.simulated
                          ? 'SIMULATED PROVIDER DATA · not live commercial availability'
                          : 'OFFLINE SAVED ROUTE · conditions may have changed',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.help_outline_rounded, size: 20),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Step-free access data is unavailable. This route is not labelled accessible.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Start'),
                    ),
                    if (onRequest != null)
                      ElevatedButton.icon(
                        onPressed: onRequest,
                        icon: const Icon(Icons.local_taxi_outlined),
                        label: const Text('Request'),
                      ),
                    OutlinedButton.icon(
                      onPressed: onHear,
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Hear details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.mapAvailable,
    required this.origin,
    required this.destination,
    required this.routes,
    required this.selectedRouteKey,
    required this.onCreated,
  });

  final bool mapAvailable;
  final LatLng? origin;
  final JourneyPlace? destination;
  final List<JourneyRouteOption> routes;
  final String? selectedRouteKey;
  final ValueChanged<GoogleMapController> onCreated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!mapAvailable) {
      return Semantics(
        container: true,
        label:
            'Visual map unavailable. Route choices remain available as text and speech.',
        child: Container(
          height: 220,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Visual map isn’t available in this build',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'You can still compare route details, hear the journey, and start guidance.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label:
          'Optional visual route map. Route details are also available as text and speech.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 280,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target:
                  destination?.location ?? origin ?? AccraOperatingArea.center,
              zoom: 13,
            ),
            cameraTargetBounds: CameraTargetBounds(AccraOperatingArea.bounds),
            minMaxZoomPreference: const MinMaxZoomPreference(10, 20),
            myLocationEnabled: origin != null,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            markers: {
              if (destination != null)
                Marker(
                  markerId: const MarkerId('destination'),
                  position: destination!.location,
                  infoWindow: InfoWindow(title: destination!.name),
                ),
            },
            polylines: {
              for (final route in routes)
                Polyline(
                  polylineId: PolylineId(route.routeKey),
                  points: route.path,
                  color: route.routeKey == selectedRouteKey
                      ? scheme.primary
                      : scheme.outline.withValues(alpha: 0.7),
                  width: route.routeKey == selectedRouteKey ? 7 : 4,
                  zIndex: route.routeKey == selectedRouteKey ? 2 : 1,
                ),
            },
            onMapCreated: onCreated,
          ),
        ),
      ),
    );
  }
}

class _WalkingSafetyNotice extends StatelessWidget {
  const _WalkingSafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Walking, bicycling, and two-wheeled routes are beta and may not '
              'include clear sidewalks, pedestrian paths, or bicycling paths. '
              'Check actual conditions and follow local rules.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
