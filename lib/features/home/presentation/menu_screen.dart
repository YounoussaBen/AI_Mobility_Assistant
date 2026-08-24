import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  void _showNotReady(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$feature will be added soon.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authRepositoryProvider).currentUser;
    final title = _displayName(user);
    final subtitle = user?.email ?? 'Guest account';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => context.push('/profile'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Container(
                      width: 106,
                      height: 106,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'assets/branding/brand_mark.png',
                        semanticLabel: 'Mobility AI profile image',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                final width = largeText
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth / 4;
                return Wrap(
                  spacing: largeText ? 12 : 0,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _QuickAction(
                        icon: Icons.history_rounded,
                        label: 'History',
                        onTap: () => context.push('/history'),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _QuickAction(
                        icon: Icons.support_agent_rounded,
                        label: 'Support',
                        onTap: () => _showNotReady(context, 'Support'),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _QuickAction(
                        icon: Icons.place_outlined,
                        label: 'Places',
                        onTap: () => _showNotReady(context, 'Saved places'),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _QuickAction(
                        icon: Icons.settings_rounded,
                        label: 'Settings',
                        onTap: () => context.push('/settings'),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 30),
            Card(
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.accessibility_new_rounded,
                    title: 'Travel profile',
                    subtitle: 'Accessibility and guidance',
                    onTap: () => context.push('/preferences?edit=true'),
                  ),
                  const Divider(height: 1, indent: 58),
                  _MenuRow(
                    icon: Icons.record_voice_over_outlined,
                    title: 'Voice and guidance',
                    subtitle: 'Voice, speech speed, captions, and haptics',
                    onTap: () => context.push('/voice-guidance'),
                  ),
                  const Divider(height: 1, indent: 58),
                  _MenuRow(
                    icon: Icons.shield_outlined,
                    title: 'Safety and privacy',
                    onTap: () => context.push('/safety-privacy'),
                  ),
                  const Divider(height: 1, indent: 58),
                  _MenuRow(
                    icon: Icons.info_outline_rounded,
                    title: 'About Mobility AI',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Mobility AI',
                      applicationVersion: '1.0.0',
                      applicationIcon: Image.asset(
                        'assets/branding/app_icon.png',
                        width: 52,
                        height: 52,
                      ),
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

String _displayName(AppUser? user) {
  if (user == null || user.isGuest || user.email == null) {
    return 'Guest traveler';
  }
  final source = user.email!
      .split('@')
      .first
      .replaceAll(RegExp(r'[._-]+'), ' ');
  if (source.isEmpty) return 'Traveler';
  return source
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 25),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 25),
              const SizedBox(width: 17),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
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
      ),
    );
  }
}
