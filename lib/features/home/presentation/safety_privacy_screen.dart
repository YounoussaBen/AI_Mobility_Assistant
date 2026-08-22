import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SafetyPrivacyScreen extends StatelessWidget {
  const SafetyPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            Text(
              'Safety and privacy',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 9),
            Text(
              'Control how the app supports and protects your journeys.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 42),
            Text('Safety', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _NavigationRow(
              icon: Icons.accessibility_new_rounded,
              title: 'Travel preferences',
              subtitle: 'Accessibility and guidance choices',
              onTap: () => context.push('/preferences?edit=true'),
            ),
            const SizedBox(height: 30),
            Text('Privacy', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            const _PrivacyInfoRow(
              icon: Icons.location_on_outlined,
              title: 'Location',
              subtitle: 'Requested only when you plan or follow a journey.',
            ),
            const _PrivacyInfoRow(
              icon: Icons.camera_alt_outlined,
              title: 'Camera assistance',
              subtitle:
                  'Camera frames will be processed on your device and not stored.',
            ),
            const _PrivacyInfoRow(
              icon: Icons.mic_none_rounded,
              title: 'Voice input',
              subtitle:
                  'Microphone access is requested only when you use voice features.',
            ),
            const SizedBox(height: 30),
            Text('Account data', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _NavigationRow(
              icon: Icons.person_outline_rounded,
              title: 'Profile and account',
              subtitle: 'Review your current account',
              onTap: () => context.push('/profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
            Icon(icon, size: 25, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 17),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
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

class _PrivacyInfoRow extends StatelessWidget {
  const _PrivacyInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
