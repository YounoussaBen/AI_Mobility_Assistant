import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../app/config/app_config.dart';
import '../data/gemini_destination_service.dart';
import '../data/google_places_service.dart';
import '../data/google_routes_service.dart';
import '../domain/place.dart';
import '../domain/route_option.dart';

class JourneyPlannerScreen extends StatefulWidget {
  const JourneyPlannerScreen({super.key, this.startWithVoice = false});

  final bool startWithVoice;

  @override
  State<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends State<JourneyPlannerScreen> {
  static const _accra = LatLng(5.6037, -0.1870);

  late final GooglePlacesService _places;
  late final GoogleRoutesService _routesService;
  late final GeminiDestinationService _gemini;
  final _speech = SpeechToText();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _random = math.Random.secure();

  GoogleMapController? _mapController;
  Timer? _searchDebounce;
  LatLng? _origin;
  JourneyPlace? _destination;
  List<PlaceSuggestion> _suggestions = const [];
  List<JourneyRouteOption> _routes = const [];
  JourneyTravelMode? _selectedMode;
  _LocationState _locationState = _LocationState.loading;
  String _sessionToken = '';
  String? _message;
  bool _searching = false;
  bool _listening = false;
  bool _understandingSpeech = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _places = GooglePlacesService(apiKey: AppConfig.googleMapsApiKey);
    _routesService = GoogleRoutesService(apiKey: AppConfig.googleMapsApiKey);
    _gemini = GeminiDestinationService(
      apiKey: AppConfig.geminiApiKey,
      model: AppConfig.geminiModel,
    );
    _sessionToken = _newSessionToken();
    unawaited(_loadCurrentLocation());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dismissKeyboard();
      if (widget.startWithVoice) {
        unawaited(_startListening());
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController?.dispose();
    unawaited(_speech.cancel());
    super.dispose();
  }

  String _newSessionToken() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  Future<void> _loadCurrentLocation() async {
    if (mounted) {
      setState(() {
        _locationState = _LocationState.loading;
        _message = null;
      });
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _locationState = _LocationState.serviceOff);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
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
      final origin = LatLng(position.latitude, position.longitude);
      setState(() {
        _origin = origin;
        _locationState = _LocationState.ready;
      });
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(origin, 15),
      );
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
        _routes = const [];
        _selectedMode = null;
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
    });
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
        if (suggestions.isEmpty) {
          _message = 'No matching places found. Try a wider search.';
        }
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _message = 'We couldn’t search for places right now. Please try again.';
      });
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    HapticFeedback.selectionClick();
    _searchDebounce?.cancel();
    _dismissKeyboard();
    setState(() {
      _suggestions = const [];
      _searching = false;
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
      setState(() => _destination = destination);
      await _loadRoutes();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'We couldn’t open that destination. Please choose another.';
      });
    }
  }

  Future<void> _loadRoutes() async {
    final origin = _origin;
    final destination = _destination;
    if (destination == null) return;
    if (origin == null) {
      setState(() {
        _message =
            'Turn on location access to calculate routes from where you are.';
      });
      return;
    }

    setState(() {
      _routes = const [];
      _selectedMode = null;
      _message = null;
    });
    final routes = await _routesService.routes(
      origin: origin,
      destination: destination.location,
    );
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _selectedMode = routes
          .where((route) => route.mode == JourneyTravelMode.driving)
          .firstOrNull
          ?.mode;
      _selectedMode ??= routes.firstOrNull?.mode;
      if (routes.isEmpty) {
        _message = 'No route options are available for this destination.';
      }
    });
    if (routes.isNotEmpty) await _fitJourney(origin, destination.location);
  }

  Future<void> _fitJourney(LatLng origin, LatLng destination) async {
    final controller = _mapController;
    if (controller == null) return;
    final southwest = LatLng(
      math.min(origin.latitude, destination.latitude),
      math.min(origin.longitude, destination.longitude),
    );
    final northeast = LatLng(
      math.max(origin.latitude, destination.latitude),
      math.max(origin.longitude, destination.longitude),
    );
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: southwest, northeast: northeast),
          84,
        ),
      );
    } catch (_) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(destination, 14),
      );
    }
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
          _message =
              'Voice input stopped. You can type the destination instead.';
        });
      },
    );
    if (!available) {
      if (mounted) {
        setState(() {
          _message =
              'Voice input isn’t available. Type the destination instead.';
        });
      }
      return;
    }

    _dismissKeyboard();
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
    if (result.finalResult) {
      unawaited(_understandSpeech(words));
    }
  }

  Future<void> _understandSpeech(String transcript) async {
    setState(() {
      _listening = false;
      _understandingSpeech = _gemini.isConfigured;
      _message = null;
    });
    final destination = await _gemini.destinationFromSpeech(transcript);
    if (!mounted) return;
    _searchController.value = TextEditingValue(
      text: destination,
      selection: TextSelection.collapsed(offset: destination.length),
    );
    setState(() {
      _understandingSpeech = false;
      _message = null;
    });
    await _searchPlaces(destination);
  }

  Future<void> _submitSearch() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 2) return;
    await _searchPlaces(query);
    if (mounted && _suggestions.isNotEmpty) {
      await _selectSuggestion(_suggestions.first);
    }
  }

  Future<void> _openLocationSettings() async {
    if (_locationState == _LocationState.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Set<Polyline> _buildPolylines(Color primary, Color secondary) {
    return _routes.map((route) {
      final selected = route.mode == _selectedMode;
      return Polyline(
        polylineId: PolylineId(route.mode.name),
        points: route.path,
        color: selected ? primary : secondary.withValues(alpha: 0.72),
        width: selected ? 7 : 4,
        zIndex: selected ? 2 : 1,
        consumeTapEvents: true,
        onTap: () => setState(() => _selectedMode = route.mode),
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initialTarget = _origin ?? _accra;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialTarget,
                  zoom: _origin == null ? 12 : 15,
                ),
                myLocationEnabled: _locationState == _LocationState.ready,
                myLocationButtonEnabled: _locationState == _LocationState.ready,
                compassEnabled: true,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                padding: EdgeInsets.only(
                  top: 150,
                  bottom: _routes.isEmpty ? 44 : 190,
                ),
                markers: {
                  if (_destination != null)
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: _destination!.location,
                      infoWindow: InfoWindow(title: _destination!.name),
                    ),
                },
                polylines: _buildPolylines(
                  scheme.primary,
                  scheme.outlineVariant,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  if (_origin != null && _destination == null) {
                    unawaited(
                      controller.animateCamera(
                        CameraUpdate.newLatLngZoom(_origin!, 15),
                      ),
                    );
                  }
                },
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SearchCard(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      isListening: _listening,
                      isBusy: _searching || _understandingSpeech,
                      onBack: () => Navigator.of(context).pop(),
                      onChanged: _onQueryChanged,
                      onSubmitted: (_) => _submitSearch(),
                      onVoice: _startListening,
                      onClear: () {
                        _searchController.clear();
                        _searchFocus.requestFocus();
                        setState(() {
                          _destination = null;
                          _suggestions = const [];
                          _routes = const [];
                          _selectedMode = null;
                          _message = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_suggestions.isNotEmpty)
                      _SuggestionsCard(
                        suggestions: _suggestions,
                        onSelected: _selectSuggestion,
                      )
                    else if (_message != null)
                      _MessageCard(message: _message!)
                    else if (_locationState != _LocationState.ready &&
                        _locationState != _LocationState.loading)
                      _LocationCard(
                        state: _locationState,
                        onRetry: _loadCurrentLocation,
                        onSettings: _openLocationSettings,
                      ),
                  ],
                ),
              ),
            ),
            if (_routes.isNotEmpty && _destination != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: _RouteOptionsCard(
                    destination: _destination!,
                    routes: _routes,
                    selectedMode: _selectedMode,
                    onSelected: (mode) {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedMode = mode);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _LocationState {
  loading,
  ready,
  serviceOff,
  denied,
  deniedForever,
  unavailable,
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.focusNode,
    required this.isListening,
    required this.isBusy,
    required this.onBack,
    required this.onChanged,
    required this.onSubmitted,
    required this.onVoice,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isListening;
  final bool isBusy;
  final VoidCallback onBack;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onVoice;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    hintText: 'Where are you going?',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 17),
                  ),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear destination',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
              IconButton(
                tooltip: isListening ? 'Stop listening' : 'Speak destination',
                onPressed: onVoice,
                color: isListening
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                icon: Icon(
                  isListening ? Icons.stop_circle_outlined : Icons.mic_rounded,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if (isBusy)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
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
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return ListTile(
              minTileHeight: 62,
              leading: const Icon(Icons.location_on_outlined),
              title: Text(suggestion.primaryText),
              subtitle: suggestion.secondaryText.isEmpty
                  ? null
                  : Text(
                      suggestion.secondaryText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => onSelected(suggestion),
            );
          },
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.state,
    required this.onRetry,
    required this.onSettings,
  });

  final _LocationState state;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final (message, action, openSettings) = switch (state) {
      _LocationState.loading => ('Finding your current location…', null, false),
      _LocationState.serviceOff => (
        'Turn on location services to calculate your journey.',
        'Settings',
        true,
      ),
      _LocationState.denied => (
        'Allow location access to calculate your journey.',
        'Try again',
        false,
      ),
      _LocationState.deniedForever => (
        'Allow location access in Settings to calculate your journey.',
        'Settings',
        true,
      ),
      _LocationState.unavailable => (
        'Your current location is temporarily unavailable.',
        'Retry',
        false,
      ),
      _LocationState.ready => throw StateError('Ready is not displayed'),
    };

    return Semantics(
      liveRegion: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              if (state == _LocationState.loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                const Icon(Icons.my_location_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
              if (action != null)
                TextButton(
                  onPressed: openSettings ? onSettings : onRetry,
                  child: Text(action),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteOptionsCard extends StatelessWidget {
  const _RouteOptionsCard({
    required this.destination,
    required this.routes,
    required this.selectedMode,
    required this.onSelected,
  });

  final JourneyPlace destination;
  final List<JourneyRouteOption> routes;
  final JourneyTravelMode? selectedMode;
  final ValueChanged<JourneyTravelMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              destination.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: routes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final route = routes[index];
                  final selected = route.mode == selectedMode;
                  return _RouteOptionButton(
                    route: route,
                    selected: selected,
                    onTap: () => onSelected(route.mode),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteOptionButton extends StatelessWidget {
  const _RouteOptionButton({
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final JourneyRouteOption route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${route.mode.label}, ${route.durationLabel}, ${route.distanceLabel}',
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 126,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(route.mode.icon, size: 24),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.durationLabel,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${route.mode.label} · ${route.distanceLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(fontSize: 12),
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
    );
  }
}
