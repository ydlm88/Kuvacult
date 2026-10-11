// Name badges (reference 2a, "Badges" row). Shown right of the display name,
// 10px gap, vertically centred on the 30–32px serif name.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'kuva_ui.dart';

enum SupporterTier { none, devSupporter, founder }

/// Picks the right badge for a tier. Returns an empty box for free users.
class NameBadge extends StatelessWidget {
  const NameBadge(this.tier, {super.key});
  final SupporterTier tier;
  @override
  Widget build(BuildContext context) => switch (tier) {
        SupporterTier.none => const SizedBox.shrink(),
        SupporterTier.devSupporter => const SupporterBadge(),
        SupporterTier.founder => const FounderBadge(),
      };
}

/// h22 · padding 0 9 0 4 · radius 999 · 1px rgba(232,161,60,.5) · fill rgba(232,161,60,.08)
/// sun 15×15 · gap 6 · "SUPPORTER" JetBrains Mono 9px .18em #f0d3a6
class SupporterBadge extends StatelessWidget {
  const SupporterBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.only(left: 4, right: 9),
        decoration: BoxDecoration(
            color: K.amberA(.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: K.amberA(.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/brand/sun.png', width: 15, height: 15),
          const SizedBox(width: 6),
          Text('SUPPORTER', style: mono(9, color: K.noteText, em: .18)),
        ]),
      );
}

/// h22 · padding 0 9 0 8 · 1px rgba(233,196,104,.7) · fill rgba(233,196,104,.1)
/// candle 7×14 · gap 7 · "FOUNDER" 9px .18em #E9C468
class FounderBadge extends StatelessWidget {
  const FounderBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.only(left: 8, right: 9),
        decoration: BoxDecoration(
            color: K.goldA(.1), borderRadius: BorderRadius.circular(999), border: Border.all(color: K.goldA(.7))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const BadgeCandle(),
          const SizedBox(width: 7),
          Text('FOUNDER', style: mono(9, color: K.gold, em: .18)),
        ]),
      );
}

/// 7 × 14 box. Wax 7×8 radius 1.5 #f3e4cf at the bottom. Flame 5×6 #ffb347, left 1,
/// bottom 8, shape `border-radius: 52% 48% 46% 54% / 72% 72% 32% 32%`.
/// Flicker: 170ms, ease-in-out per segment, alternate, origin = flame bottom-centre.
///   0% scale(1, 1)    rotate(-2°)
///  50% scale(.9, 1.1) rotate(1.5°)
/// 100% scale(1.04,.95) rotate(-.6°)
class BadgeCandle extends StatefulWidget {
  const BadgeCandle({super.key});
  @override
  State<BadgeCandle> createState() => _BadgeCandleState();
}

class _BadgeCandleState extends State<BadgeCandle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
  static const _kf = [(1.0, 1.0, -2.0), (.9, 1.1, 1.5), (1.04, .95, -.6)];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Matrix4 _pose(double t) {
    final seg = t < .5 ? 0 : 1;
    final u = Curves.easeInOut.transform(seg == 0 ? t * 2 : (t - .5) * 2);
    final a = _kf[seg], b = _kf[seg + 1];
    double l(double x, double y) => x + (y - x) * u;
    return Matrix4.identity()
      ..scale(l(a.$1, b.$1), l(a.$2, b.$2), 1.0)
      ..rotateZ(l(a.$3, b.$3) * math.pi / 180);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 7,
        height: 14,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
              left: 0,
              bottom: 0,
              child: Container(width: 7, height: 8, decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(1.5)))),
          Positioned(
            left: 1,
            bottom: 8,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, child) => Transform(alignment: Alignment.bottomCenter, transform: _pose(_c.value), child: child),
              child: CustomPaint(size: const Size(5, 6), painter: _Flame()),
            ),
          ),
        ]),
      );
}

class _Flame extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    // CSS radius overlap rule: vertical sums 104% → every radius × 100/104
    const f = 1 / 1.04;
    Radius r(double x, double y) => Radius.elliptical(x * s.width * f, y * s.height * f);
    canvas.drawRRect(
        RRect.fromRectAndCorners(Offset.zero & s,
            topLeft: r(.52, .72), topRight: r(.48, .72), bottomRight: r(.46, .32), bottomLeft: r(.54, .32)),
        Paint()..color = K.flame);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
