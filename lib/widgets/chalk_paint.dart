// Shared chalk rendering — every hand-drawn outline uses this so they all
// "boil" on the same 380ms beat as the candle.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class Chalk {
  static const List<int> seeds = <int>[3, 11, 19];
  static const Duration boil = Duration(milliseconds: 380);
  static const Duration jitter = Duration(milliseconds: 320);

  static const List<Offset> jitterOffsets = <Offset>[
    Offset(0, 0),
    Offset(0.6, -0.4),
    Offset(-0.4, 0.3),
  ];
  static const List<double> jitterRotations = <double>[
    -0.00698,
    0.00873,
    -0.00349,
  ];

  static Path roughen(
    Path source,
    int seed, {
    double amplitude = 1.6,
    double step = 3.0,
  }) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      final n = math.max(3, (metric.length / step).floor());
      for (int i = 0; i <= n; i++) {
        final tan = metric.getTangentForOffset(metric.length * i / n);
        if (tan == null) continue;
        final normal = Offset(-tan.vector.dy, tan.vector.dx);
        final raw = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453;
        final noise = (raw - raw.floorToDouble()) * 2 - 1;
        final p = tan.position + normal * (noise * amplitude);
        i == 0 ? out.moveTo(p.dx, p.dy) : out.lineTo(p.dx, p.dy);
      }
      out.close();
    }
    return out;
  }

  static Paint stroke(Color c, {double width = 3.0}) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round;
}

mixin ChalkBeat<T extends StatefulWidget> on State<T> {
  Timer? _boil;
  Timer? _jitter;
  int _seedIndex = 0;
  int _jitterIndex = 0;

  int get chalkSeed => Chalk.seeds[_seedIndex];
  int get chalkJitter => _jitterIndex;

  @override
  void initState() {
    super.initState();
    _boil = Timer.periodic(Chalk.boil, (_) {
      if (mounted) setState(() => _seedIndex = (_seedIndex + 1) % 3);
    });
    _jitter = Timer.periodic(Chalk.jitter, (_) {
      if (mounted) setState(() => _jitterIndex = (_jitterIndex + 1) % 3);
    });
  }

  @override
  void dispose() {
    _boil?.cancel();
    _jitter?.cancel();
    super.dispose();
  }
}

class ChalkJitter extends StatelessWidget {
  const ChalkJitter({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: Chalk.jitterRotations[index],
        child: Transform.translate(
          offset: Chalk.jitterOffsets[index],
          child: child,
        ),
      );
}
