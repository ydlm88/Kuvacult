// KuvaAvatar: the profile picture with an optional border.
// Today there are two borders: none, and Dead Channel (Dev Supporter / Founder).
// Reference: reference/Avatar Border.dc.html (kind="tv" and kind="none").
//
// Every measurement below is in the reference's 210 × 210 design box; the widget
// scales that box to [size]. So KuvaAvatar(size: 170) == HTML size="{{ 170 }}".

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'kuva_ui.dart';

enum AvatarBorder { none, deadChannel }

extension AvatarBorderX on AvatarBorder {
  String get label => switch (this) { AvatarBorder.none => 'No border', AvatarBorder.deadChannel => 'Dead Channel' };
  /// Which supporter tier unlocks it. null = everyone.
  bool get needsSupporter => this == AvatarBorder.deadChannel;
}

class KuvaAvatar extends StatelessWidget {
  const KuvaAvatar({super.key, required this.size, this.border = AvatarBorder.none, this.image, this.initial = 'M', this.color = const Color(0xFF7CB6EC), this.animate = true});
  final double size;
  final AvatarBorder border;
  final ImageProvider? image;
  final String initial;
  final Color color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final face = (double s, {bool square = false}) => AvatarFace(size: s, image: image, initial: initial, color: color, square: square);
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        child: SizedBox(
          width: 210,
          height: 210,
          child: switch (border) {
            AvatarBorder.none => Stack(children: [
                // 138 hairline ring at (36,36), 130 avatar with 4px page-colour border at (40,40)
                Positioned(left: 36, top: 36, child: Container(width: 138, height: 138, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: K.whiteA(.12))))),
                Positioned(left: 40, top: 40, child: Container(width: 130, height: 130, padding: const EdgeInsets.all(4), decoration: const BoxDecoration(shape: BoxShape.circle, color: K.page), child: ClipOval(child: face(122)))),
              ]),
            AvatarBorder.deadChannel => _DeadChannel(face: face(128, square: true), animate: animate),
          },
        ),
      ),
    );
  }
}

// ─── Dead Channel ───────────────────────────────────────────────────────────
//
// Motion (all loop forever, all frozen under MediaQuery.disableAnimations):
//   chalk boil      cabinet + antennas swap between 2 jitter seeds every 180ms
//   screen flicker  3.1s, stepped: 0–7% 1.0 · 7–9% .82 · 9–47% 1.0 · 47–49% .90 · 49–71% 1.0 · 71–72% .70 · 72–100% 1.0
//   screen jitter   5s, stepped:   0–92% (0,0) · 92–94% (-2,1) · 94–96% (2,-1) · 96–100% (-1,0)
//   rolling bar     3.6s linear, 28px band slides from y=-40 to y=150 (screen coords)
//   power LED       2.4s, same stepped curve as the flicker

class _DeadChannel extends StatefulWidget {
  const _DeadChannel({required this.face, this.animate = true});
  final Widget face;
  final bool animate;
  @override
  State<_DeadChannel> createState() => _DeadChannelState();
}

class _DeadChannelState extends State<_DeadChannel> with SingleTickerProviderStateMixin {
  double _ms = 0;
  late final Ticker _t = createTicker((e) => setState(() => _ms = e.inMicroseconds / 1000.0));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.animate || (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (still && _t.isActive) _t.stop();
    if (!still && !_t.isActive) _t.start();
  }

  static double _flicker(double p) =>
      p < .07 ? 1 : p < .09 ? .82 : p < .47 ? 1 : p < .49 ? .9 : p < .71 ? 1 : p < .72 ? .7 : 1;
  static Offset _jitter(double p) =>
      p < .92 ? Offset.zero : p < .94 ? const Offset(-2, 1) : p < .96 ? const Offset(2, -1) : const Offset(-1, 0);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (_) {
        final ms = _ms;
        double ph(double periodMs) => (ms % periodMs) / periodMs;
        final seed = (ms ~/ 180) % 2;
        final roll = -40 + 190 * ph(3600);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: _CabinetPainter(seed: seed, led: _flicker(ph(2400))))),
          // screen: (28,56) 128×118, radius 22/26 elliptical
          Positioned(
            left: 28,
            top: 56,
            child: Container(
              width: 128,
              height: 118,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.elliptical(22, 26)),
                border: Border.all(color: K.chalk, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.elliptical(22, 26)),
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Color(0xFF0B0A09)),
                  Opacity(
                    opacity: _flicker(ph(3100)),
                    child: Transform.translate(
                      offset: _jitter(ph(5000)),
                      child: Stack(fit: StackFit.expand, children: [
                        // CSS: saturate(.55) contrast(1.15) brightness(.92)
                        ColorFiltered(colorFilter: ColorFilter.matrix(_tvMatrix), child: widget.face),
                        const CustomPaint(painter: _ScanlinePainter()),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: roll,
                          height: 28,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
                                Color(0x00FFFFFF), Color(0x29FFF0D2), Color(0x00FFFFFF),
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  // vignette: inset 0 0 26px 6px rgba(0,0,0,.75) + glass highlight at 30% 20%
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(center: Alignment(-.4, -.6), radius: 1.0, colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)], stops: [0, .4]),
                    ),
                  ),
                  const CustomPaint(painter: _VignettePainter()),
                  // inset 0 0 0 2px #0b0807
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.elliptical(22, 26)),
                      border: Border.all(color: const Color(0xFF0B0807), width: 2),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// saturate(.55) → contrast(1.15) → brightness(.92), composed as one matrix.
final List<double> _tvMatrix = () {
  const s = .55, c = 1.15, b = .92;
  const lr = .2126, lg = .7152, lb = .0722;
  final sat = [
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s,
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s,
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s,
  ];
  final o = 255 * (.5 - .5 * c) * b;
  final m = <double>[];
  for (var r = 0; r < 3; r++) {
    m.addAll([sat[r * 3] * c * b, sat[r * 3 + 1] * c * b, sat[r * 3 + 2] * c * b, 0, o]);
  }
  m.addAll([0, 0, 0, 1, 0]);
  return m;
}();

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();
  @override
  void paint(Canvas canvas, Size size) {
    // repeating-linear-gradient(0deg, rgba(0,0,0,.32) 0–1px, transparent 1–3px)
    final p = Paint()..color = const Color(0x52000000);
    for (double y = size.height; y > 0; y -= 3) {
      canvas.drawRect(Rect.fromLTWH(0, y - 1, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _VignettePainter extends CustomPainter {
  const _VignettePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.elliptical(22, 26));
    canvas.save();
    canvas.clipRRect(r);
    final shadow = Paint()
      ..color = const Color(0xBF000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 + 6 * 2;
    canvas.drawRRect(r.inflate(6), shadow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CabinetPainter extends CustomPainter {
  _CabinetPainter({required this.seed, required this.led});
  final int seed;
  final double led;

  // Tiny deterministic wobble standing in for the SVG displacement filter (scale 2.2).
  Offset _j(double x, double y) {
    final a = math.sin(x * 12.9898 + y * 78.233 + seed * 37.719) * 43758.5453;
    final b = math.sin(x * 93.989 + y * 47.233 + seed * 11.13) * 24634.6345;
    return Offset(x + (a - a.floorToDouble() - .5) * 1.1, y + (b - b.floorToDouble() - .5) * 1.1);
  }

  Path _wobbleRRect(Rect r, double rad) {
    final base = Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(rad)));
    final out = Path();
    for (final m in base.computeMetrics()) {
      for (double d = 0; d <= m.length; d += 6) {
        final p = m.getTangentForOffset(d)!.position;
        final q = _j(p.dx, p.dy);
        d == 0 ? out.moveTo(q.dx, q.dy) : out.lineTo(q.dx, q.dy);
      }
      out.close();
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chalk = Paint()
      ..color = K.chalk
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // antennas
    final a1 = _j(92, 40), a2 = _j(66, 10), b1 = _j(118, 40), b2 = _j(150, 14);
    canvas.drawLine(a1, a2, chalk..strokeWidth = 1.6);
    canvas.drawLine(b1, b2, chalk);
    canvas.drawCircle(a2, 2.4, Paint()..color = K.chalk);
    canvas.drawCircle(b2, 2.4, Paint()..color = K.chalk);
    // top bump  M86 42 Q105 32 124 42 Z
    final bump = Path()
      ..moveTo(86, 42)
      ..quadraticBezierTo(105, 32, 124, 42)
      ..close();
    canvas.drawPath(bump, Paint()..color = const Color(0xFF1B1512));
    canvas.drawPath(bump, chalk..strokeWidth = 1.2);
    // cabinet 14,42 182×146 rx16
    final cab = _wobbleRRect(const Rect.fromLTWH(14, 42, 182, 146), 16);
    canvas.drawPath(cab, Paint()..color = const Color(0xFF1A1411));
    canvas.drawPath(cab, chalk..strokeWidth = 1.8);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 48, 170, 134), const Radius.circular(12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x47E3BE5E));
    // feet
    for (final x in [40.0, 152.0]) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, 188, 18, 10), const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = const Color(0xFF120E0C));
      canvas.drawRRect(r, chalk..strokeWidth = 1.2);
    }
    // knobs
    final needle = Paint()
      ..color = K.gold
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final k in [(const Offset(173, 76), const Offset(178, 70)), (const Offset(173, 104), const Offset(167, 99))]) {
      canvas.drawCircle(k.$1, 9, Paint()..color = const Color(0xFF120E0C));
      canvas.drawCircle(k.$1, 9, chalk..strokeWidth = 1.4);
      canvas.drawLine(k.$1, k.$2, needle);
    }
    // speaker grille
    final grille = Paint()
      ..color = const Color(0x80E3BE5E)
      ..strokeWidth = 1;
    for (double y = 128; y <= 148; y += 5) {
      canvas.drawLine(Offset(166, y), Offset(180, y), grille);
    }
    // power LED
    canvas.drawCircle(const Offset(173, 166), 2.4, Paint()..color = K.amber.withValues(alpha: led));
  }

  @override
  bool shouldRepaint(covariant _CabinetPainter o) => o.seed != seed || o.led != led;
}
