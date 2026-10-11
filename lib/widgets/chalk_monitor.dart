// Chalk monitor glyph — placeholder on the shared stage when no video yet.
// scanning: true adds amber sweep band while connecting.
import 'package:flutter/material.dart';
import 'chalk_paint.dart';
import 'kuva_tokens.dart';

class ChalkMonitor extends StatefulWidget {
  const ChalkMonitor({
    super.key,
    this.width = 54,
    this.scanning = false,
    this.color,
  });

  final double width;
  final bool scanning;
  final Color? color;

  @override
  State<ChalkMonitor> createState() => _ChalkMonitorState();
}

class _ChalkMonitorState extends State<ChalkMonitor>
    with TickerProviderStateMixin, ChalkBeat<ChalkMonitor> {
  late final AnimationController _scan = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.scanning) _scan.repeat();
  }

  @override
  void didUpdateWidget(covariant ChalkMonitor old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !_scan.isAnimating) {
      _scan.repeat();
    } else if (!widget.scanning && _scan.isAnimating) {
      _scan.stop();
      _scan.value = 0;
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final w = widget.width;
    final h = w * 52 / 54;
    return IgnorePointer(
      child: ChalkJitter(
        index: reduce ? 0 : chalkJitter,
        child: SizedBox(
          width: w,
          height: h,
          child: AnimatedBuilder(
            animation: _scan,
            builder: (_, __) => CustomPaint(
              painter: _MonitorPainter(
                seed: reduce ? Chalk.seeds.first : chalkSeed,
                scan: widget.scanning && !reduce ? _scan.value : null,
                color: widget.color ?? Kuva.chalk.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonitorPainter extends CustomPainter {
  _MonitorPainter(
      {required this.seed, required this.scan, required this.color});

  final int seed;
  final double? scan;
  final Color color;

  static const double designW = 54;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / designW;
    canvas.save();
    canvas.scale(s);

    final screen = Chalk.roughen(
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(0, 0, designW, 40),
            const Radius.circular(5))),
      seed,
      amplitude: 1.2,
      step: 3.0,
    );
    canvas.drawPath(screen, Chalk.stroke(color, width: 2.5));

    if (scan != null) {
      canvas.save();
      canvas.clipPath(screen);
      final y = 40 * scan!;
      canvas.drawRect(
        Rect.fromLTWH(0, y - 7, designW, 14),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Kuva.amber.withValues(alpha: 0),
              Kuva.amber.withValues(alpha: 0.22),
              Kuva.amber.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(0, y - 7, designW, 14)),
      );
      canvas.restore();
    }

    final stand = Chalk.roughen(
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(16, 46, 22, 3), const Radius.circular(2))),
      seed + 2,
      amplitude: 0.6,
      step: 2.0,
    );
    canvas.drawPath(stand, Paint()..color = color);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MonitorPainter old) =>
      old.seed != seed || old.scan != scan || old.color != color;
}
