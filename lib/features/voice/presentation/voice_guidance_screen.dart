import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/voice_profile_controller.dart';
import '../data/speech_output_service.dart';
import '../domain/voice_profile.dart';

class VoiceGuidanceScreen extends ConsumerStatefulWidget {
  const VoiceGuidanceScreen({super.key});

  @override
  ConsumerState<VoiceGuidanceScreen> createState() =>
      _VoiceGuidanceScreenState();
}

class _VoiceGuidanceScreenState extends ConsumerState<VoiceGuidanceScreen> {
  VoiceProfile? _draft;
  List<DeviceVoice> _voices = const [];
  bool _loadingVoices = true;
  bool _saving = false;
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices());
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await ref
          .read(speechOutputServiceProvider)
          .availableVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _loadingVoices = false;
        _voiceError = voices.isEmpty
            ? 'No selectable system voices were reported by this device.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingVoices = false;
        _voiceError =
            'Voice choices could not be loaded. The system fallback remains available.';
      });
    }
  }

  Future<void> _playSample() async {
    final profile = _draft;
    if (profile == null) return;
    try {
      await ref
          .read(speechOutputServiceProvider)
          .speak(profile.verbosity.sample, profile);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This voice could not play a sample.')),
      );
    }
  }

  void _setSpeechEnabled(bool enabled) {
    if (!enabled) {
      unawaited(ref.read(speechOutputServiceProvider).setSpeechEnabled(false));
    }
    setState(() => _draft = _draft?.copyWith(speechEnabled: enabled));
  }

  Future<void> _save() async {
    final profile = _draft;
    if (profile == null || _saving) return;
    setState(() => _saving = true);
    await ref.read(voiceProfileControllerProvider.notifier).save(profile);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice and guidance settings saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(voiceProfileControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Voice and guidance'),
      ),
      body: SafeArea(
        top: false,
        child: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _LoadError(
            onRetry: () => ref.invalidate(voiceProfileControllerProvider),
          ),
          data: (saved) {
            _draft ??= saved;
            return _VoiceEditor(
              profile: _draft!,
              voices: _voices,
              loadingVoices: _loadingVoices,
              voiceError: _voiceError,
              saving: _saving,
              onChanged: (value) => setState(() => _draft = value),
              onSpeechEnabledChanged: _setSpeechEnabled,
              onPlaySample: _playSample,
              onReloadVoices: _loadVoices,
              onSave: _save,
            );
          },
        ),
      ),
    );
  }
}

class _VoiceEditor extends StatelessWidget {
  const _VoiceEditor({
    required this.profile,
    required this.voices,
    required this.loadingVoices,
    required this.voiceError,
    required this.saving,
    required this.onChanged,
    required this.onSpeechEnabledChanged,
    required this.onPlaySample,
    required this.onReloadVoices,
    required this.onSave,
  });

  final VoiceProfile profile;
  final List<DeviceVoice> voices;
  final bool loadingVoices;
  final String? voiceError;
  final bool saving;
  final ValueChanged<VoiceProfile> onChanged;
  final ValueChanged<bool> onSpeechEnabledChanged;
  final VoidCallback onPlaySample;
  final VoidCallback onReloadVoices;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    const systemVoiceId = '__system_voice__';
    final locales = <String>{
      profile.voiceLocale,
      for (final voice in voices) voice.locale,
    }.toList()..sort();
    final localeVoices = voices
        .where((voice) => voice.locale == profile.voiceLocale)
        .toList();
    final selectedVoice = localeVoices
        .where((voice) => voice.name == profile.voiceName)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Make guidance sound right for you',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'These choices apply to route explanations, maneuvers, warnings, and Look Ahead descriptions.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 30),
                _SectionCard(
                  title: 'Assistant voice',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (loadingVoices)
                        const LinearProgressIndicator(minHeight: 2)
                      else ...[
                        DropdownButtonFormField<String>(
                          initialValue: locales.contains(profile.voiceLocale)
                              ? profile.voiceLocale
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Language and accent',
                          ),
                          items: [
                            for (final locale in locales)
                              DropdownMenuItem(
                                value: locale,
                                child: Text(_localeLabel(locale)),
                              ),
                          ],
                          onChanged: (locale) {
                            if (locale == null) return;
                            onChanged(
                              profile.copyWith(
                                voiceLocale: locale,
                                clearVoice: true,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: selectedVoice?.id ?? systemVoiceId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Voice'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: systemVoiceId,
                              child: Text('System default'),
                            ),
                            for (final voice in localeVoices)
                              DropdownMenuItem<String>(
                                value: voice.id,
                                child: Text(
                                  voice.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (id) {
                            if (id == null || id == systemVoiceId) {
                              onChanged(profile.copyWith(clearVoice: true));
                              return;
                            }
                            final voice = localeVoices
                                .where((item) => item.id == id)
                                .firstOrNull;
                            if (voice == null) return;
                            onChanged(
                              profile.copyWith(
                                voiceName: voice.name,
                                voiceLocale: voice.locale,
                              ),
                            );
                          },
                        ),
                      ],
                      if (voiceError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          voiceError!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: onReloadVoices,
                            child: const Text('Try again'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: loadingVoices || !profile.speechEnabled
                            ? null
                            : onPlaySample,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play sample'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Speech',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PreferenceSwitch(
                        title: 'Spoken guidance',
                        subtitle:
                            'Read route guidance, warnings, and assistant responses aloud',
                        value: profile.speechEnabled,
                        onChanged: onSpeechEnabledChanged,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Speed',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            _speedLabel(profile.speechRate),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      Slider(
                        value: profile.speechRate.clamp(0.30, 0.70),
                        min: 0.30,
                        max: 0.70,
                        divisions: 8,
                        label: _speedLabel(profile.speechRate),
                        onChanged: (value) =>
                            onChanged(profile.copyWith(speechRate: value)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Detail level',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in GuidanceVerbosity.values)
                            ChoiceChip(
                              label: Text(value.label),
                              selected: profile.verbosity == value,
                              onSelected: (_) =>
                                  onChanged(profile.copyWith(verbosity: value)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Example: ${profile.verbosity.sample}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Guidance channels',
                  child: Column(
                    children: [
                      _PreferenceSwitch(
                        title: 'Speak street names',
                        subtitle:
                            'When the route provider supplies a verified name',
                        value: profile.speakStreetNames,
                        onChanged: (value) => onChanged(
                          profile.copyWith(speakStreetNames: value),
                        ),
                      ),
                      _PreferenceSwitch(
                        title: 'Repeat critical warnings',
                        subtitle: 'Repeat only urgent, validated warnings',
                        value: profile.repeatCriticalWarnings,
                        onChanged: (value) => onChanged(
                          profile.copyWith(repeatCriticalWarnings: value),
                        ),
                      ),
                      _PreferenceSwitch(
                        title: 'Haptics',
                        subtitle: 'Pair key spoken guidance with vibration',
                        value: profile.haptics,
                        onChanged: (value) =>
                            onChanged(profile.copyWith(haptics: value)),
                      ),
                      _PreferenceSwitch(
                        title: 'Captions and transcript',
                        subtitle: 'Keep spoken exchanges available as text',
                        value: profile.captions,
                        onChanged: (value) =>
                            onChanged(profile.copyWith(captions: value)),
                      ),
                      _PreferenceSwitch(
                        title: 'System voice fallback',
                        subtitle:
                            'Keep basic guidance when premium voice is offline',
                        value: profile.systemVoiceFallback,
                        onChanged: (value) => onChanged(
                          profile.copyWith(systemVoiceFallback: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(saving ? 'Saving…' : 'Save settings'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _localeLabel(String locale) {
    final parts = locale.replaceAll('_', '-').split('-');
    final language = switch (parts.first.toLowerCase()) {
      'en' => 'English',
      'fr' => 'French',
      'es' => 'Spanish',
      'de' => 'German',
      'it' => 'Italian',
      'pt' => 'Portuguese',
      'ar' => 'Arabic',
      _ => parts.first.toUpperCase(),
    };
    return parts.length > 1
        ? '$language (${parts.sublist(1).join('-')})'
        : language;
  }

  static String _speedLabel(double speed) {
    if (speed < 0.43) return 'Slower';
    if (speed > 0.57) return 'Faster';
    return 'Natural';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      value: value,
      onChanged: onChanged,
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
            const SizedBox(height: 14),
            Text(
              'Settings could not be loaded.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
