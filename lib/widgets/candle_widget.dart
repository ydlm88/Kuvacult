// Chalk-drawn animated candle — Séance card toggle.
// Port of the HTML design reference: SVG turbulence seed-swap becomes
// roughen() cycling three deterministic seeds every 380ms.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class CandleWidget extends StatefulWidget {
  const CandleWidget({
    super.key,
    required this.lit,
    required this.onTap,
    this.width = 86,
    this.height = 118,
  });

  final bool lit;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  State<CandleWidget> createState() => _CandleWidgetState();
}

class _CandleWidgetState extends State<CandleWidget>
    with TickerProviderStateMixin {
  late final AnimationController _flicker = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 170))
    ..repeat(reverse: true);
  late final AnimationController _core = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200))
    ..repeat(reverse: true);
  late final AnimationController _ignite = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400));
  late final AnimationController _halo = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);
  late final AnimationController _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240));
  late final AnimationController _smoke = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));

  Timer? _boilTimer;
  Timer? _jitterTimer;
  Timer? _smokeStop;
  int _seedIndex = 0;
  int _jitterIndex = 0;
  bool _smoking = false;

  @override
  void initState() {
    super.initState();
    if (widget.lit) {
      _fade.value = 1;
      _ignite.value = 1;
    }
    _boilTimer = Timer.periodic(const Duration(milliseconds: 380), (_) {
      if (mounted) setState(() => _seedIndex = (_seedIndex + 1) % 3);
    });
    _jitterTimer = Timer.periodic(const Duration(milliseconds: 320), (_) {
      if (mounted) setState(() => _jitterIndex = (_jitterIndex + 1) % 3);
    });
  }

  @override
  void didUpdateWidget(covariant CandleWidget old) {
    super.didUpdateWidget(old);
    if (widget.lit == old.lit) return;
    if (widget.lit) {
      _smokeStop?.cancel();
      if (_smoking) setState(() => _smoking = false);
      _smoke.stop();
      _fade.forward();
      _ignite.forward(from: 0);
    } else {
      _fade.reverse();
      setState(() => _smoking = true);
      _smoke.repeat();
      _smokeStop = Timer(const Duration(milliseconds: 3000), () {
        if (!mounted) return;
        setState(() => _smoking = false);
        _smoke.stop();
      });
    }
  }

  @override
  void dispose() {
    _boilTimer?.cancel();
    _jitterTimer?.cancel();
    _smokeStop?.cancel();
    _flicker.dispose();
    _core.dispose();
    _ignite.dispose();
    _halo.dispose();
    _fade.dispose();
    _smoke.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: 'Toggle the séance',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: Listenable.merge(
                [_flicker, _core, _ignite, _halo, _fade, _smoke]),
            builder: (_, __) => CustomPaint(
              painter: CandlePainter(
                seedIndex: reduceMotion ? 0 : _seedIndex,
                jitterIndex: reduceMotion ? 0 : _jitterIndex,
                flicker: reduceMotion
                    ? 0.5
                    : Curves.easeInOut.transform(_flicker.value),
                coreSquash: reduceMotion
                    ? 0.5
                    : Curves.easeInOut.transform(_core.value),
                ignite: _ignite.value,
                flameOpacity: _fade.value,
                halo: reduceMotion ? 0 : _halo.value,
                smoke: _smoking ? _smoke.value : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CandlePainter extends CustomPainter {
  CandlePainter({
    required this.seedIndex,
    required this.jitterIndex,
    required this.flicker,
    required this.coreSquash,
    required this.ignite,
    required this.flameOpacity,
    required this.halo,
    required this.smoke,
  });

  final int seedIndex;
  final int jitterIndex;
  final double flicker;
  final double coreSquash;
  final double ignite;
  final double flameOpacity;
  final double halo;
  final double? smoke;

  static const double bodyW = 30, bodyH = 68;
  static const double flameW = 20, flameH = 36;
  static const double headroom = 46;
  static const double bottomGap = 6;
  static const List<int> seeds = <int>[3, 11, 19];
  static const List<Offset> jitterOffsets = <Offset>[
    Offset(0, 0),
    Offset(0.6, -0.4),
    Offset(-0.4, 0.3),
  ];
  static const List<double> jitterRot = <double>[-0.00698, 0.00873, -0.00349];

  // Design colors (verbatim from HTML handoff)
  static const _wax = Color(0xFFF4F0E4);
  static const _chalk = Color(0xFFE3BE5E);
  static const _waxHi = Color(0xFFF8F5EC);
  static const _wick = Color(0xFF2C2318);
  static const _flameFill = Color(0xFFE9C468);
  static const _flameLine = Color(0xFFD8A93F);
  static const _flameCore = Color(0xFFFFF8E4);

  @override
  void paint(Canvas canvas, Size size) {
    const designH = bodyH + headroom + bottomGap;
    final scale = math.min(size.width / (bodyW + 18), size.height / designH);
    final seed = seeds[seedIndex];

    canvas.save();
    canvas.translate(size.width / 2, size.height);
    canvas.scale(scale);
    canvas.translate(0, -bottomGap - bodyH);

    if (flameOpacity > 0.01) _paintHalo(canvas);

    canvas.save();
    final j = jitterOffsets[jitterIndex];
    canvas.translate(j.dx, j.dy);
    canvas.rotate(jitterRot[jitterIndex]);

    _paintBody(canvas, seed);
    _paintHatching(canvas);
    _paintWaxTop(canvas, seed);
    _paintDrip(canvas, seed);
    _paintWick(canvas);
    if (flameOpacity > 0.01) _paintFlame(canvas, seed);

    canvas.restore();

    if (smoke != null) _paintSmoke(canvas);
    canvas.restore();
  }

  void _paintBody(Canvas canvas, int seed) {
    final rect = Rect.fromLTWH(-bodyW / 2, 0, bodyW, bodyH);
    final path = Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.elliptical(13.8, 4.8),
        topRight: const Radius.elliptical(16.2, 4.8),
        bottomRight: const Radius.elliptical(14.4, 3.4),
        bottomLeft: const Radius.elliptical(15.6, 3.4),
      ));
    final rough = roughen(path, seed);
    canvas.drawPath(rough, Paint()..color = _wax);
    canvas.save();
    canvas.clipPath(rough);
    canvas.drawRect(
        Rect.fromLTWH(bodyW / 2 - 7, 0, 7, bodyH),
        Paint()..color = const Color(0x29E3BE5E));
    canvas.drawRect(
        Rect.fromLTWH(-bodyW / 2, 0, 5, bodyH),
        Paint()..color = const Color(0xB3FFFFFF));
    canvas.restore();
    canvas.drawPath(rough, _stroke(_chalk));
  }

  void _paintHatching(Canvas canvas) {
    final clip = Rect.fromLTWH(-bodyW / 2 + 6, 3, bodyW - 11, bodyH - 11);
    canvas.save();
    canvas.clipRect(clip);
    final p = Paint()
      ..color = _chalk.withValues(alpha: 0.28)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const angle = 58 * math.pi / 180;
    final dx = math.cos(angle), dy = math.sin(angle);
    for (double o = -bodyH; o < bodyH * 1.5; o += 6) {
      canvas.drawLine(
        Offset(-bodyW + o * dy * -1, o),
        Offset(bodyW + o * dy * -1 + dx * bodyW, o - dx * bodyW),
        p,
      );
    }
    canvas.restore();
  }

  void _paintWaxTop(Canvas canvas, int seed) {
    final path = Path()
      ..addOval(Rect.fromCenter(
          center: const Offset(0, 0.5), width: 26, height: 9));
    final rough = roughen(path, seed + 1, amplitude: 1.1);
    canvas.drawPath(rough, Paint()..color = _wax);
    canvas.drawPath(rough, _stroke(_chalk));
  }

  void _paintDrip(Canvas canvas, int seed) {
    final rect = Rect.fromLTWH(-bodyW / 2 - 1, 5, 7, 24);
    final path = Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.elliptical(4.2, 5.3),
        topRight: const Radius.elliptical(2.8, 5.3),
        bottomRight: const Radius.elliptical(3.9, 17.3),
        bottomLeft: const Radius.elliptical(3.2, 17.3),
      ));
    final rough = roughen(path, seed + 2, amplitude: 1.0);
    canvas.drawPath(rough, Paint()..color = _waxHi);
    canvas.drawPath(rough, _stroke(_chalk));
  }

  void _paintWick(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(-1.5, -12, 3, 10), const Radius.circular(2)),
      Paint()..color = _wick,
    );
  }

  void _paintFlame(Canvas canvas, int seed) {
    final ig = ignite.clamp(0.0, 1.0);
    double igX, igY;
    if (ig < 0.6) {
      final t = ig / 0.6;
      igX = 0.2 + (1.15 - 0.2) * Curves.easeOut.transform(t);
      igY = 0.3 + (1.06 - 0.3) * Curves.easeOut.transform(t);
    } else {
      final t = (ig - 0.6) / 0.4;
      igX = 1.15 + (1.0 - 1.15) * t;
      igY = 1.06 + (1.0 - 1.06) * t;
    }
    final fx = 1.0 + (0.92 - 1.0) * flicker;
    final fy = 1.0 + (1.08 - 1.0) * flicker;
    final rot = (-1.6 + 2.8 * flicker) * math.pi / 180;

    const bottomY = -headroom + flameH;
    canvas.save();
    canvas.translate(0, bottomY);
    canvas.rotate(rot);
    canvas.scale(fx * igX, fy * igY);

    final rect = Rect.fromLTWH(-flameW / 2, -flameH, flameW, flameH);
    final path = Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.elliptical(10.4, 25.9),
        topRight: const Radius.elliptical(9.6, 25.9),
        bottomRight: const Radius.elliptical(9.2, 11.5),
        bottomLeft: const Radius.elliptical(10.8, 11.5),
      ));
    final rough = roughen(path, seed + 3, amplitude: 1.2);

    canvas.drawPath(
        rough,
        Paint()
          ..color = _flameFill.withValues(alpha: 0.55 * flameOpacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawPath(
        rough, Paint()..color = _flameFill.withValues(alpha: flameOpacity));
    canvas.drawPath(
        rough, _stroke(_flameLine.withValues(alpha: flameOpacity)));
    canvas.restore();

    final coreScale = 1.0 + (0.82 - 1.0) * coreSquash;
    canvas.save();
    canvas.translate(0, -13);
    canvas.scale(1, coreScale);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTWH(-4, -13, 8, 13),
        topLeft: const Radius.elliptical(4.2, 8.3),
        topRight: const Radius.elliptical(3.8, 8.3),
        bottomRight: const Radius.elliptical(3.2, 4.7),
        bottomLeft: const Radius.elliptical(4.8, 4.7),
      ),
      Paint()..color = _flameCore.withValues(alpha: flameOpacity),
    );
    canvas.restore();
  }

  void _paintHalo(Canvas canvas) {
    final r = 85.0 * (1 + 0.05 * halo);
    const center = Offset(0, -28);
    final shader = RadialGradient(
      colors: [
        const Color(0xFFFFBA60).withValues(alpha: 0.45 * flameOpacity),
        const Color(0xFFFF8C2B).withValues(alpha: 0.16 * flameOpacity),
        const Color(0x00FF7814),
      ],
      stops: const [0.0, 0.40, 0.70],
    ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  void _paintSmoke(Canvas canvas) {
    final t = smoke!;
    void puff(double phase, double radius, Color color) {
      final p = (t + phase) % 1.0;
      final o = p < 0.18 ? p / 0.18 * 0.5 : 0.5 * (1 - (p - 0.18) / 0.82);
      canvas.drawCircle(
        Offset(14 * p, -14 - 70 * p),
        radius * (0.4 + 1.5 * p),
        Paint()
          ..color = color.withValues(alpha: color.a * o)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    puff(0.0, 4.5, const Color(0x80D6D6D6));
    puff(0.17, 3.5, const Color(0x73C8C8C8));
  }

  Paint _stroke(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round;

  /// Deterministic per-point displacement — stands in for feTurbulence + feDisplacementMap.
  /// Same seed → same wobble shape; cycling 3 seeds every 380ms gives the boiling line look.
  static Path roughen(Path source, int seed,
      {double amplitude = 1.6, double step = 3.0}) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      final n = math.max(3, (metric.length / step).floor());
      for (int i = 0; i <= n; i++) {
        final d = metric.length * i / n;
        final tan = metric.getTangentForOffset(d);
        if (tan == null) continue;
        final normal = Offset(-tan.vector.dy, tan.vector.dx);
        final raw = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453;
        final noise = (raw - raw.floorToDouble()) * 2 - 1;
        final pt = tan.position + normal * (noise * amplitude);
        if (i == 0) {
          out.moveTo(pt.dx, pt.dy);
        } else {
          out.lineTo(pt.dx, pt.dy);
        }
      }
      out.close();
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant CandlePainter old) =>
      old.seedIndex != seedIndex ||
      old.jitterIndex != jitterIndex ||
      old.flicker != flicker ||
      old.coreSquash != coreSquash ||
      old.ignite != ignite ||
      old.flameOpacity != flameOpacity ||
      old.halo != halo ||
      old.smoke != smoke;
}
