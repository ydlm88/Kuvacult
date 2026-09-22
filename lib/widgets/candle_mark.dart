// Small chalk candle mark — header / decorative scale.
// 18x42 ratio. Lit state animates; use lit: false for wick-only.
// Not tappable — wrap in GestureDetector only if needed.
import 'package:flutter/material.dart';
import 'chalk_paint.dart';
import 'kuva_tokens.dart';

class CandleMark extends StatefulWidget {
  const CandleMark({super.key, this.size = 42, this.lit = true});

  final double size;
  final bool lit;

  @override
  State<CandleMark> createState() => _CandleMarkState();
}

class _CandleMarkState extends State<CandleMark>
    with TickerProviderStateMixin, ChalkBeat<CandleMark> {
  late final AnimationController _flicker = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 170))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce && _flicker.isAnimating) _flicker.stop();

    final h = widget.size;
    final w = h * 18 / 42;
    return IgnorePointer(
      child: ChalkJitter(
        index: reduce ? 0 : chalkJitter,
        child: SizedBox(
          width: w,
          height: h,
          child: AnimatedBuilder(
            animation: _flicker,
            builder: (_, __) => CustomPaint(
              painter: _CandleMarkPainter(
                seed: reduce ? Chalk.seeds.first : chalkSeed,
                flicker: reduce
                    ? 0.5
                    : Curves.easeInOut.transform(_flicker.value),
                lit: widget.lit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CandleMarkPainter extends CustomPainter {
  _CandleMarkPainter({
    required this.seed,
    required this.flicker,
    required this.lit,
  });

  final int seed;
  final double flicker;
  final bool lit;

  static const double designW = 18, designH = 42;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / designH;
    canvas.save();
    canvas.scale(s);
    canvas.translate((size.width / s - designW) / 2, 0);

    final stroke = Chalk.stroke(Kuva.chalk, width: 2);

    final body = Chalk.roughen(
      Path()
        ..addRRect(RRect.fromRectAndCorners(
          const Rect.fromLTWH(0, 22, 18, 20),
          topLeft: const Radius.elliptical(8.3, 2.4),
          topRight: const Radius.elliptical(9.7, 2.4),
          bottomRight: const Radius.elliptical(8.6, 1.6),
          bottomLeft: const Radius.elliptical(9.4, 1.6),
        )),
      seed,
      amplitude: 0.9,
      step: 2.2,
    );
    canvas.drawPath(body, Paint()..color = Kuva.wax);
    canvas.drawPath(body, stroke);

    final top = Chalk.roughen(
      Path()
        ..addOval(Rect.fromCenter(
            center: const Offset(9, 23), width: 16, height: 6)),
      seed + 1,
      amplitude: 0.7,
      step: 2.0,
    );
    canvas.drawPath(top, Paint()..color = Kuva.wax);
    canvas.drawPath(top, stroke);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 15, 2, 6), const Radius.circular(2)),
      Paint()..color = Kuva.wick,
    );

    if (lit) _paintFlame(canvas, stroke);
    canvas.restore();
  }

  void _paintFlame(Canvas canvas, Paint stroke) {
    final fx = 1.0 + (0.92 - 1.0) * flicker;
    final fy = 1.0 + (1.08 - 1.0) * flicker;
    final rot = (-1.6 + 2.8 * flicker) * 3.1415926 / 180;

    canvas.save();
    canvas.translate(9, 16);
    canvas.rotate(rot);
    canvas.scale(fx, fy);

    final path = Chalk.roughen(
      Path()
        ..addRRect(RRect.fromRectAndCorners(
          const Rect.fromLTWH(-6, -16, 12, 16),
          topLeft: const Radius.elliptical(6.2, 11.5),
          topRight: const Radius.elliptical(5.8, 11.5),
          bottomRight: const Radius.elliptical(5.5, 5.1),
          bottomLeft: const Radius.elliptical(6.5, 5.1),
        )),
      seed + 3,
      amplitude: 0.8,
      step: 2.0,
    );
    canvas.drawPath(
        path,
        Paint()
          ..color = Kuva.flameFill.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawPath(path, Paint()..color = Kuva.flameFill);
    canvas.drawPath(path, Chalk.stroke(Kuva.flameLine, width: 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CandleMarkPainter old) =>
      old.seed != seed || old.flicker != flicker || old.lit != lit;
}
