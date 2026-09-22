// Kuvacult — Wax Rail bottom navigation.
// Active tab widens into an amber capsule with its label; inactive tabs are
// icon-only chalk sigils, 40px wide. Matches design: wax_rail_nav.dart.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'chalk_paint.dart';
import 'kuva_tokens.dart';

// Tab order: Lists(0) Reviews(1) Search(2) Ritual(3) You(4)
enum _Dest { lists, reviews, search, ritual, you }

const List<String> _kLabels = ['LISTS', 'REVIEWS', 'SEARCH', 'RITUAL', 'YOU'];

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.avatar,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final ImageProvider? avatar;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xF2121010),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x12FFFFFF)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 30,
                  offset: Offset(0, -6)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _Dest.values.length; i++)
                _NavTab(
                  dest: _Dest.values[i],
                  label: _kLabels[i],
                  active: currentIndex == i,
                  avatar: i == 4 ? avatar : null,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.dest,
    required this.label,
    required this.active,
    required this.onTap,
    this.avatar,
  });

  final _Dest dest;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ImageProvider? avatar;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Kuva.amber : Kuva.ink.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: const Cubic(.3, .9, .3, 1),
          height: 48,
          constraints: const BoxConstraints(minWidth: 40),
          padding: EdgeInsets.symmetric(horizontal: active ? 13 : 9),
          decoration: BoxDecoration(
            color: active ? const Color(0x29E8A13C) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NavSigil(
                  dest: dest, active: active, color: fg, avatar: avatar),
              if (active) ...[
                const SizedBox(width: 8),
                Text(label,
                    style: Kuva.liveLabel.copyWith(
                        fontSize: 10, letterSpacing: 1.4, color: fg)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSigil extends StatefulWidget {
  const _NavSigil({
    required this.dest,
    required this.active,
    required this.color,
    this.size = 22,
    this.avatar,
  });

  final _Dest dest;
  final bool active;
  final Color color;
  final double size;
  final ImageProvider? avatar;

  @override
  State<_NavSigil> createState() => _NavSigilState();
}

class _NavSigilState extends State<_NavSigil>
    with ChalkBeat<_NavSigil> {
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (widget.dest == _Dest.you && widget.avatar != null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
              image: widget.avatar!, fit: BoxFit.cover),
          border: Border.all(
              color: widget.active
                  ? widget.color
                  : Kuva.ink.withValues(alpha: 0.3),
              width: 2),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _SigilPainter(
          dest: widget.dest,
          active: widget.active,
          color: widget.color,
          seed: reduce ? Chalk.seeds.first : chalkSeed,
        ),
      ),
    );
  }
}

class _SigilPainter extends CustomPainter {
  _SigilPainter({
    required this.dest,
    required this.active,
    required this.color,
    required this.seed,
  });

  final _Dest dest;
  final bool active;
  final Color color;
  final int seed;

  static const double box = 24;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / box);
    switch (dest) {
      case _Dest.lists:   _paper(canvas);
      case _Dest.reviews: _quill(canvas);
      case _Dest.search:  _glass(canvas);
      case _Dest.ritual:  _sun(canvas);
      case _Dest.you:     _person(canvas);
    }
    canvas.restore();
  }

  Paint get _line => Chalk.stroke(color, width: 1.5);
  Paint get _wash => Paint()..color = color.withValues(alpha: 0.24);

  void _rough(Canvas canvas, Path p, int bump,
      {bool fill = false, double width = 1.5, double amp = 0.55}) {
    final r = Chalk.roughen(p, seed + bump, amplitude: amp, step: 2.0);
    if (fill && active) canvas.drawPath(r, _wash);
    canvas.drawPath(r, Chalk.stroke(color, width: width));
  }

  void _sun(Canvas canvas) {
    _rough(canvas,
        Path()
          ..addOval(
              Rect.fromCircle(center: const Offset(12, 12), radius:5.2)),
        0,
        fill: true, width: 1.7, amp: 0.5);
    _rough(canvas,
        Path()
          ..addOval(
              Rect.fromCircle(center: const Offset(12, 12), radius:2.4)),
        1,
        width: 1.1, amp: 0.35);

    final spokes = Path();
    for (int i = 0; i < 16; i++) {
      final a = -math.pi / 2 + i * (math.pi / 8);
      final r1 = i.isEven ? 11.0 : 8.9;
      spokes.moveTo(12 + 6.6 * math.cos(a), 12 + 6.6 * math.sin(a));
      spokes.lineTo(12 + r1 * math.cos(a), 12 + r1 * math.sin(a));
    }
    canvas.drawPath(
        Chalk.roughen(spokes, seed + 2, amplitude: 0.35, step: 2.2),
        _line);
  }

  void _quill(Canvas canvas) {
    final feather = Path()
      ..moveTo(20, 3.6)
      ..cubicTo(13.6, 4.1, 9.4, 7.6, 7.6, 12.3)
      ..cubicTo(7.0, 13.9, 6.7, 15.3, 6.6, 16.5)
      ..cubicTo(7.8, 16.3, 9.2, 16.0, 10.6, 15.4)
      ..cubicTo(15.5, 13.6, 19.0, 9.6, 20, 3.6)
      ..close();
    _rough(canvas, feather, 0, fill: true);
    final shaft = Path()
      ..moveTo(8.6, 15.4)
      ..lineTo(3.4, 20.6)
      ..moveTo(3.4, 20.6)
      ..lineTo(6.2, 20.4);
    canvas.drawPath(
        Chalk.roughen(shaft, seed + 1, amplitude: 0.35, step: 2.0),
        _line);
  }

  void _glass(Canvas canvas) {
    _rough(
        canvas,
        Path()
          ..addOval(
              Rect.fromCircle(center: const Offset(10.4, 10.4), radius:6.4)),
        0,
        fill: true, width: 1.7);
    final handle = Path()
      ..moveTo(15.2, 15.2)
      ..lineTo(20.4, 20.4);
    canvas.drawPath(
        Chalk.roughen(handle, seed + 1, amplitude: 0.3, step: 2.0),
        Chalk.stroke(color, width: 2.2));
  }

  void _paper(Canvas canvas) {
    final sheet = Path()
      ..moveTo(5.2, 3.4)
      ..lineTo(14.5, 3.4)
      ..lineTo(18.8, 7.7)
      ..lineTo(18.8, 20.6)
      ..lineTo(5.2, 20.6)
      ..close();
    _rough(canvas, sheet, 0, fill: true);
    final fold = Path()
      ..moveTo(14.5, 3.4)
      ..lineTo(14.5, 7.7)
      ..lineTo(18.8, 7.7);
    final rules = Path()
      ..moveTo(8, 11)
      ..lineTo(16, 11)
      ..moveTo(8, 14)
      ..lineTo(16, 14)
      ..moveTo(8, 17)
      ..lineTo(13, 17);
    canvas.drawPath(
        Chalk.roughen(fold, seed + 1, amplitude: 0.3, step: 2.0), _line);
    canvas.drawPath(
        Chalk.roughen(rules, seed + 2, amplitude: 0.3, step: 2.0), _line);
  }

  void _person(Canvas canvas) {
    _rough(canvas,
        Path()
          ..addOval(
              Rect.fromCircle(center: const Offset(12, 8.6), radius:3.9)),
        0,
        fill: true);
    final shoulders = Path()
      ..moveTo(4.8, 20.4)
      ..cubicTo(4.8, 16.5, 8.0, 13.3, 12.0, 13.3)
      ..cubicTo(16.0, 13.3, 19.2, 16.5, 19.2, 20.4);
    _rough(canvas, shoulders, 1, fill: true);
  }

  @override
  bool shouldRepaint(covariant _SigilPainter old) =>
      old.seed != seed ||
      old.active != active ||
      old.color != color ||
      old.dest != dest;
}
