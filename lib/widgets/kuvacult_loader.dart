// kuvacult_loader.dart — Animated amber/crimson ripple used on the launch screen and profile loading.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

class KuvacultLoader extends StatefulWidget {
  const KuvacultLoader({super.key});

  @override
  State<KuvacultLoader> createState() => _KuvacultLoaderState();
}

class _KuvacultLoaderState extends State<KuvacultLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const amber = MC.accent1;
    const crimson = MC.kuvacultScore;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final pulse = math.sin(t * math.pi * 2) * 0.5 + 0.5;
        final r1 = t;
        final r2 = (t + 0.45) % 1.0;
        final ringColor1 = Color.lerp(amber, crimson, r1)!;
        final ringColor2 = Color.lerp(crimson, amber, r2)!;
        return SizedBox(
          width: 140, height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ripple — amber → crimson
              Opacity(
                opacity: ((1 - r1) * 0.5).clamp(0.0, 1.0),
                child: Container(
                  width: 68 + r1 * 66,
                  height: 68 + r1 * 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor1, width: 1.2),
                  ),
                ),
              ),
              // Trailing ripple — crimson → amber
              Opacity(
                opacity: ((1 - r2) * 0.35).clamp(0.0, 1.0),
                child: Container(
                  width: 68 + r2 * 66,
                  height: 68 + r2 * 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor2, width: 1.2),
                  ),
                ),
              ),
              // Pulsing inner circle with gradient fill
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.lerp(amber, crimson, pulse)!
                          .withAlpha((pulse * 50).toInt()),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(
                    color: Color.lerp(amber, crimson, pulse)!
                        .withAlpha((120 + pulse * 135).toInt()),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.movie_filter_outlined,
                  color: Color.lerp(amber, crimson, pulse)!
                      .withAlpha((140 + pulse * 115).toInt()),
                  size: 24,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
