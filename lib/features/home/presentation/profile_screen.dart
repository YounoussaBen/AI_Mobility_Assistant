import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You’ll return to the sign-in screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authRepositoryProvider).currentUser;
    final title = _displayName(user);
    final accountLabel = user?.email ?? 'Guest account';

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Back',
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                        ),
                        Container(
                          width: 82,
                          height: 82,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset(
                            'assets/branding/brand_mark.png',
                            semanticLabel: 'Mobility AI profile image',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 44),
                    _ProfileDetailRow(
                      title: accountLabel,
                      subtitle: user?.isGuest == true ? 'Account' : 'Email',
                    ),
                    const SizedBox(height: 18),
                    _ProfileDetailRow(
                      title: 'Travel profile',
                      subtitle: 'Accessibility and guidance',
                      onTap: () => context.push('/preferences?edit=true'),
                    ),
                    const SizedBox(height: 18),
                    _ProfileDetailRow(
                      title: user?.isGuest == true ? 'Guest mode' : 'Signed in',
                      subtitle: 'Account status',
                      trailing: const Icon(Icons.info_outline_rounded),
                    ),
                    const Spacer(),
                    if (user?.isGuest == true) ...[
                      ElevatedButton(
                        onPressed: () =>
                            context.push('/auth?mode=create&upgrade=true'),
                        child: const Text('Create account'),
                      ),
                    ] else ...[
                      TextButton(
                        onPressed: () => _signOut(context, ref),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Log out'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
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

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

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
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
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
