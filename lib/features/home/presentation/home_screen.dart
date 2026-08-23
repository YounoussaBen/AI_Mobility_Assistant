import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openPlanner(BuildContext context, {bool voice = false}) {
    HapticFeedback.selectionClick();
    context.push(voice ? '/plan?voice=true' : '/plan');
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Transform.translate(
                        offset: Offset(0, 14 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HomeHeader(onOpenMenu: () => context.push('/menu')),
                          const SizedBox(height: 42),
                          Text(
                            'Where do you want to go?',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 24),
                          const _CurrentLocationLabel(),
                          const SizedBox(height: 12),
                          _DestinationComposer(
                            onSearch: () => _openPlanner(context),
                            onVoice: () => _openPlanner(context, voice: true),
                          ),
                          const SizedBox(height: 34),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Recent journeys',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/history'),
                                child: const Text('See all'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const _EmptyTravelHistory(),
                        ],
                      ),
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
          tooltip: 'Open menu',
          onPressed: onOpenMenu,
          icon: const Icon(Icons.menu_rounded),
        ),
      ],
    );
  }
}

class _CurrentLocationLabel extends StatelessWidget {
  const _CurrentLocationLabel();

  @override
  Widget build(BuildContext context) {
    return Semantics(label: 'Starting point: your current location');
  }
}

class _DestinationComposer extends StatelessWidget {
  const _DestinationComposer({required this.onSearch, required this.onVoice});

  final VoidCallback onSearch;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        textField: true,
        label: 'Search for a destination',
        child: InkWell(
          onTap: onSearch,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Row(
              children: [
                const SizedBox(width: 18),
                Icon(
                  Icons.search_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Search a place or address',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                IconButton(
                  tooltip: 'Speak destination',
                  onPressed: onVoice,
                  icon: const Icon(Icons.mic_none_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTravelHistory extends StatelessWidget {
  const _EmptyTravelHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No journeys yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  'Journeys you plan will appear here.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
