import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../../preferences/data/mobility_preferences_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.value = 1;
      unawaited(_openNextScreen(const Duration(milliseconds: 280)));
    } else {
      unawaited(_controller.forward());
      unawaited(_openNextScreen(const Duration(milliseconds: 1040)));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openNextScreen(Duration minimumDisplayTime) async {
    await Future<void>.delayed(minimumDisplayTime);
    if (!mounted) return;

    final preferences = ref.read(mobilityPreferencesRepositoryProvider);
    final user = ref.read(authRepositoryProvider).currentUser;

    if (!preferences.hasCompletedIntro) {
      context.go('/onboarding');
    } else if (user == null) {
      context.go('/auth');
    } else if (!preferences.isProfileComplete) {
      context.go('/preferences');
    } else {
      context.go('/home');
    }
  }

  Offset _quadratic(Offset start, Offset control, Offset end, double t) {
    final inverse = 1 - t;
    return Offset(
      inverse * inverse * start.dx +
          2 * inverse * t * control.dx +
          t * t * end.dx,
      inverse * inverse * start.dy +
          2 * inverse * t * control.dy +
          t * t * end.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3EF),
      body: Semantics(
        label: 'Mobility AI is starting',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final center = Offset(size.width / 2, size.height / 2 - 12);

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final approach = Curves.easeOutCubic.transform(
                  const Interval(0, 0.62).transform(_controller.value),
                );
                final reveal = Curves.easeOutBack.transform(
                  const Interval(0.48, 0.84).transform(_controller.value),
                );
                final titleReveal = Curves.easeOut.transform(
                  const Interval(0.68, 1).transform(_controller.value),
                );
                final strokeOpacity = (1 - reveal).clamp(0.0, 1.0);

                final cyanPosition = _quadratic(
                  Offset(size.width + 42, size.height * 0.34),
                  Offset(size.width * 0.78, size.height * 0.46),
                  center,
                  approach,
                );
                final inkPosition = _quadratic(
                  Offset(-42, size.height + 24),
                  Offset(size.width * 0.20, size.height * 0.66),
                  center,
                  approach,
                );

                return Stack(
                  children: [
                    Positioned(
                      left: cyanPosition.dx - 24,
                      top: cyanPosition.dy - 4,
                      child: Opacity(
                        opacity: strokeOpacity,
                        child: Transform.rotate(
                          angle: -math.pi / 5,
                          child: const _MovingStroke(color: Color(0xFF00A9CF)),
                        ),
                      ),
                    ),
                    Positioned(
                      left: inkPosition.dx - 24,
                      top: inkPosition.dy - 4,
                      child: Opacity(
                        opacity: strokeOpacity,
                        child: Transform.rotate(
                          angle: math.pi / 4,
                          child: const _MovingStroke(color: Color(0xFF17191C)),
                        ),
                      ),
                    ),
                    Center(
                      child: Transform.translate(
                        offset: const Offset(0, -12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Opacity(
                              opacity: reveal.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: 0.86 + (0.14 * reveal),
                                child: Image.asset(
                                  'assets/branding/brand_mark.png',
                                  width: 132,
                                  height: 132,
                                  excludeFromSemantics: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Opacity(
                              opacity: titleReveal,
                              child: Transform.translate(
                                offset: Offset(0, 8 * (1 - titleReveal)),
                                child: const Text(
                                  'Mobility AI',
                                  style: TextStyle(
                                    color: Color(0xFF17191C),
                                    fontSize: 29,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MovingStroke extends StatelessWidget {
  const _MovingStroke({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox(width: 48, height: 8),
      ),
    );
  }
}
