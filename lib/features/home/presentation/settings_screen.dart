import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../journey/data/route_cache_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _showTraffic = false;
  bool _journeyAlerts = true;

  @override
  Widget build(BuildContext context) {
    final user = ref.read(authRepositoryProvider).currentUser;
    final accountLabel = user?.email ?? 'Guest account';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 32),
            Text('Settings', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 46),
            const _SectionTitle('General'),
            const SizedBox(height: 20),
            _SettingsRow(
              title: accountLabel,
              subtitle: 'Account',
              onTap: () => context.push('/profile'),
            ),
            _SettingsRow(
              title: 'Travel preferences',
              subtitle: 'Accessibility and guidance',
              onTap: () => context.push('/preferences?edit=true'),
            ),
            _SettingsRow(
              title: 'Voice and guidance',
              subtitle: 'Voice, speed, detail, captions, and haptics',
              onTap: () => context.push('/voice-guidance'),
            ),
            const SizedBox(height: 34),
            const _SectionTitle('Map'),
            const SizedBox(height: 16),
            _SwitchRow(
              title: 'Display traffic',
              value: _showTraffic,
              onChanged: (value) => setState(() => _showTraffic = value),
            ),
            _SettingsRow(
              title: 'Offline route cache',
              subtitle: 'Remove routes saved for temporary network outages',
              onTap: () async {
                await ref.read(routeCacheRepositoryProvider).clear();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Offline routes removed.')),
                );
              },
            ),
            const SizedBox(height: 34),
            const _SectionTitle('Notifications'),
            const SizedBox(height: 16),
            _SwitchRow(
              title: 'Journey alerts',
              subtitle: 'Delays, route changes, and safety updates',
              value: _journeyAlerts,
              onChanged: (value) => setState(() => _journeyAlerts = value),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.onTap, this.subtitle});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
