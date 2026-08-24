import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../app/config/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../companion/domain/companion_models.dart';
import '../../journey/application/journey_session_controller.dart';
import '../../journey/data/gemini_destination_service.dart';
import '../../voice/application/voice_profile_controller.dart';
import '../../voice/data/speech_output_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _speech = SpeechToText();
  late final GeminiDestinationService _interpreter;
  String _liveTranscript = '';
  String? _localMessage;
  bool _listening = false;
  bool _understanding = false;

  static const _suggestions = [
    'Take me to the nearest pharmacy',
    'Find a route with less walking',
    'What’s ahead of me?',
    'Repeat the last instruction',
  ];

  @override
  void initState() {
    super.initState();
    _interpreter = GeminiDestinationService(
      apiKey: AppConfig.geminiApiKey,
      model: AppConfig.geminiModel,
      backendUrl: AppConfig.companionBackendUrl,
      accessToken: ref.read(authRepositoryProvider).idToken,
    );
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    super.dispose();
  }

  Future<void> _toggleListening() async {
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
          _localMessage =
              'Voice input stopped. You can type the same request instead.';
        });
      },
    );

    if (!available) {
      if (mounted) {
        setState(() {
          _localMessage =
              'Voice input is unavailable. Type your request instead.';
        });
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _liveTranscript = '';
      _localMessage = null;
    });
    ref
        .read(journeySessionControllerProvider.notifier)
        .setPhase(CompanionPhase.listening);
    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 20),
      ),
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final words = result.recognizedWords.trim();
    setState(() => _liveTranscript = words);
    if (result.finalResult && words.isNotEmpty) {
      unawaited(_handleCommand(words));
    }
  }

  Future<void> _handleCommand(String request) async {
    final text = request.trim();
    if (text.isEmpty || _understanding) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _understanding = true;
      _liveTranscript = text;
      _localMessage = null;
    });
    final session = ref.read(journeySessionControllerProvider.notifier);
    session.beginRequest(text);

    final command = await _interpreter.interpret(text);
    if (!mounted) return;
    setState(() => _understanding = false);

    switch (command.action) {
      case CompanionAction.searchPlaces:
        final query = command.query?.trim();
        if (query == null || query.length < 2) {
          session.setPhase(CompanionPhase.clarifying);
          setState(() => _localMessage = 'Where would you like to go?');
          return;
        }
        session.addTurn(
          AssistantSpeaker.companion,
          'I’ll check trusted place results for “$query”.',
          tool: true,
        );
        context.push('/plan?prompt=${Uri.encodeQueryComponent(query)}');
      case CompanionAction.lookAhead:
        session.addTurn(
          AssistantSpeaker.companion,
          'Opening an on-device Look Ahead scan.',
          tool: true,
        );
        context.push('/look-ahead');
      case CompanionAction.repeatInstruction:
        await _repeatInstruction();
      case CompanionAction.pauseJourney:
        if (ref.read(journeySessionControllerProvider).hasActiveJourney) {
          session.togglePaused();
          setState(() => _localMessage = 'Journey guidance paused.');
        } else {
          session.setPhase(CompanionPhase.ready);
          setState(
            () => _localMessage = 'There is no active journey to pause.',
          );
        }
      case CompanionAction.resumeJourney:
        final current = ref.read(journeySessionControllerProvider);
        if (current.phase == CompanionPhase.paused) {
          session.togglePaused();
          context.push('/guidance');
        } else {
          session.setPhase(CompanionPhase.ready);
          setState(
            () => _localMessage = 'There is no paused journey to resume.',
          );
        }
      case CompanionAction.unknown:
        if (!ref.read(journeySessionControllerProvider).hasActiveJourney) {
          session.setPhase(CompanionPhase.clarifying);
        }
        setState(() {
          _localMessage =
              command.message ??
              'I can plan a journey, repeat guidance, pause, or look ahead.';
        });
    }
  }

  Future<void> _repeatInstruction() async {
    final state = ref.read(journeySessionControllerProvider);
    final instruction = state.lastInstruction;
    if (instruction == null) {
      ref
          .read(journeySessionControllerProvider.notifier)
          .setPhase(CompanionPhase.ready);
      setState(() => _localMessage = 'There is no instruction to repeat yet.');
      return;
    }
    try {
      final profile = await ref.read(voiceProfileControllerProvider.future);
      await ref.read(speechOutputServiceProvider).speak(instruction, profile);
      if (mounted) setState(() => _localMessage = instruction);
    } catch (_) {
      if (mounted) setState(() => _localMessage = instruction);
    }
  }

  Future<void> _showTextComposer() async {
    var draft = _liveTranscript;
    final submitted = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Type a request',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask for a destination or a companion action.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                initialValue: draft,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Your request',
                  hintText: 'Take me to…',
                ),
                onChanged: (value) => draft = value,
                onFieldSubmitted: (value) => Navigator.pop(context, value),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, draft),
                icon: const Icon(Icons.arrow_upward_rounded),
                label: const Text('Send request'),
              ),
            ],
          ),
        ),
      ),
    );
    if (submitted?.trim().isNotEmpty == true) {
      await _handleCommand(submitted!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(journeySessionControllerProvider);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final transcript = _liveTranscript.isNotEmpty
        ? _liveTranscript
        : session.turns.lastOrNull?.text;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HomeHeader(onOpenMenu: () => context.push('/menu')),
                        const SizedBox(height: 34),
                        Text(
                          session.hasActiveJourney
                              ? 'Your companion is with you'
                              : 'How can I help you move?',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 30),
                        Center(
                          child: _CompanionMic(
                            listening: _listening,
                            busy: _understanding,
                            reduceMotion: reduceMotion,
                            onPressed: _toggleListening,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          _listening
                              ? 'Listening… tap to stop'
                              : _understanding
                              ? 'Understanding your request…'
                              : 'Talk to Mobility AI',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Push to talk · listening stops automatically',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (transcript != null || _localMessage != null) ...[
                          const SizedBox(height: 28),
                          _TranscriptCard(
                            transcript: transcript,
                            response: _localMessage,
                          ),
                        ],
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Try saying',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _showTextComposer,
                              icon: const Icon(Icons.keyboard_rounded),
                              label: const Text('Type'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final suggestion in _suggestions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SuggestionButton(
                              label: suggestion,
                              onPressed: () => _handleCommand(suggestion),
                            ),
                          ),
                        const SizedBox(height: 22),
                        Text(
                          'Quick actions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        _QuickActions(
                          canResume:
                              session.hasActiveJourney ||
                              session.phase == CompanionPhase.paused,
                          onPlan: () => context.push('/plan'),
                          onLookAhead: () => context.push('/look-ahead'),
                          onSavedPlaces: () => _showUnavailable(
                            'Saved places are not connected yet.',
                          ),
                          onResume: () => context.push('/guidance'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnavailable(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onOpenMenu});

  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.asset(
            'assets/branding/app_icon.png',
            width: 38,
            height: 38,
            semanticLabel: 'Mobility AI logo',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Mobility AI',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          tooltip: 'Voice and guidance settings',
          onPressed: () => context.push('/voice-guidance'),
          icon: const Icon(Icons.record_voice_over_outlined),
        ),
        IconButton(
          tooltip: 'Open menu',
          onPressed: onOpenMenu,
          icon: const Icon(Icons.menu_rounded),
        ),
      ],
    );
  }
}

class _CompanionMic extends StatelessWidget {
  const _CompanionMic({
    required this.listening,
    required this.busy,
    required this.reduceMotion,
    required this.onPressed,
  });

  final bool listening;
  final bool busy;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Talk to Mobility AI',
      hint: listening
          ? 'Stops voice input'
          : 'Starts short push-to-talk voice input',
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
        width: listening ? 124 : 116,
        height: listening ? 124 : 116,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: listening
              ? scheme.primary.withValues(alpha: 0.15)
              : scheme.primaryContainer.withValues(alpha: 0.5),
        ),
        child: Material(
          color: listening ? scheme.error : scheme.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('companion_microphone_button'),
            onTap: busy ? null : onPressed,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Icon(
                      listening ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 42,
                      color: scheme.onPrimary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({this.transcript, this.response});

  final String? transcript;
  final String? response;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (transcript != null) ...[
                Text('You', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 5),
                Text(
                  '“$transcript”',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (response != null) ...[
                if (transcript != null) const Divider(height: 26),
                Text(
                  'Mobility AI',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(response!, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionButton extends StatelessWidget {
  const _SuggestionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    '“$label”',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.canResume,
    required this.onPlan,
    required this.onLookAhead,
    required this.onSavedPlaces,
    required this.onResume,
  });

  final bool canResume;
  final VoidCallback onPlan;
  final VoidCallback onLookAhead;
  final VoidCallback onSavedPlaces;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 520
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QuickAction(
              width: itemWidth,
              icon: Icons.route_outlined,
              title: 'Plan a journey',
              subtitle: 'Compare verified options',
              onTap: onPlan,
            ),
            _QuickAction(
              width: itemWidth,
              icon: Icons.center_focus_strong_rounded,
              title: 'Look ahead',
              subtitle: 'Intentional camera scan',
              onTap: onLookAhead,
            ),
            _QuickAction(
              width: itemWidth,
              icon: Icons.bookmark_outline_rounded,
              title: 'Saved places',
              subtitle: 'Home and familiar places',
              onTap: onSavedPlaces,
            ),
            _QuickAction(
              width: itemWidth,
              icon: Icons.play_arrow_rounded,
              title: 'Resume journey',
              subtitle: canResume ? 'Continue guidance' : 'No journey paused',
              onTap: canResume ? onResume : null,
            ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 82),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: onTap == null
                          ? Theme.of(context).disabledColor
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
            ),
          ),
        ),
      ),
    );
  }
}
