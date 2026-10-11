// Kuvacult shared UI tokens + small primitives used by every file in this handoff.
// Values are 1:1 with reference/*.dc.html. CSS letter-spacing is em → px = em × fontSize.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class K {
  // surfaces
  static const page = Color(0xFF0A0A0A);
  static const canvas = Color(0xFF050404);
  static const panel = Color(0xFF120F0E);
  static const panelDeep = Color(0xFF100D0C);
  static const tabTrack = Color(0xFF141110);
  static const tabOn = Color(0xFF231C18);
  static const input = Color(0xFF1D1816);
  // ink
  static const title = Color(0xFFF7ECDC);
  static const ink = Color(0xFFF3E4CF);
  static Color inkA(double a) => Color.fromRGBO(243, 228, 207, a);
  // accents
  static const amber = Color(0xFFE8A13C);
  static const amberHi = Color(0xFFF2B257);
  static const gold = Color(0xFFE9C468);
  static const chalk = Color(0xFFE3BE5E);
  static const noteText = Color(0xFFF0D3A6);
  static const onAmber = Color(0xFF1B1210);
  static const flame = Color(0xFFFFB347);
  static const bust = Color(0xFFC9604F);
  static Color amberA(double a) => Color.fromRGBO(232, 161, 60, a);
  static Color goldA(double a) => Color.fromRGBO(233, 196, 104, a);
  static Color glowA(double a) => Color.fromRGBO(255, 166, 71, a);
  static Color whiteA(double a) => Color.fromRGBO(255, 255, 255, a);
}

TextStyle serif(double size, {Color color = K.title, double? height, bool italic = false}) =>
    GoogleFonts.instrumentSerif(
        fontSize: size, color: color, height: height, fontStyle: italic ? FontStyle.italic : FontStyle.normal);

TextStyle mono(double size, {Color color = K.ink, double em = 0, double? height, FontWeight w = FontWeight.w400}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color, letterSpacing: em * size, height: height, fontWeight: w);

/// UPPERCASE label, e.g. "YOUR WALL IS EMPTY" (10px, .3em).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = K.amber, this.size = 10, this.em = .3});
  final String text;
  final Color color;
  final double size, em;
  @override
  Widget build(BuildContext context) => Text(text, style: mono(size, color: color, em: em));
}

/// Amber pill/rect button. Default = 40 tall, 18 side padding, radius 12, 11px .16em.
class AmberButton extends StatefulWidget {
  const AmberButton(this.label,
      {super.key, required this.onTap, this.height = 40, this.hPad = 18, this.radius = 12, this.size = 11, this.em = .16, this.width, this.leading});
  final String label;
  final VoidCallback? onTap;
  final double height, hPad, radius, size, em;
  final double? width;
  final Widget? leading;
  @override
  State<AmberButton> createState() => _AmberButtonState();
}

class _AmberButtonState extends State<AmberButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? .98 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            height: widget.height,
            width: widget.width,
            padding: EdgeInsets.symmetric(horizontal: widget.hPad),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: K.amber, borderRadius: BorderRadius.circular(widget.radius)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 9)],
              Text(widget.label, style: mono(widget.size, color: K.onAmber, em: widget.em)),
            ]),
          ),
        ),
      );
}

/// Outline button: 1px rgba(243,228,207,.2), 40 tall, 16 padding, radius 12.
class OutlineKButton extends StatelessWidget {
  const OutlineKButton(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: K.inkA(.2))),
          child: Text(label, style: mono(11, em: .16)),
        ),
      );
}

/// Repeating animation driver used for the slow sigil ring, breathing glows etc.
class Spin extends StatefulWidget {
  const Spin({super.key, required this.period, required this.child, this.reverse = false});
  final Duration period;
  final Widget child;
  final bool reverse;
  @override
  State<Spin> createState() => _SpinState();
}

class _SpinState extends State<Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return widget.child;
    return RotationTransition(turns: widget.reverse ? ReverseAnimation(_c) : _c, child: widget.child);
  }
}

/// CSS `pfBreath`: opacity .55 ↔ .95 (ease-in-out), full cycle = [period].
class Breath extends StatefulWidget {
  const Breath({super.key, required this.period, required this.child, this.min = .55, this.max = .95});
  final Duration period;
  final Widget child;
  final double min, max;
  @override
  State<Breath> createState() => _BreathState();
}

class _BreathState extends State<Breath> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period ~/ 2)..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: Tween(begin: widget.min, end: widget.max).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child);
}

/// Initials avatar used across the designs (flat colour circle, Arial-bold letter).
/// In the app pass the user's photo as [image].
class AvatarFace extends StatelessWidget {
  const AvatarFace({super.key, required this.size, this.image, this.initial = 'M', this.color = const Color(0xFF7CB6EC), this.square = false});
  final double size;
  final ImageProvider? image;
  final String initial;
  final Color color;
  final bool square;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          image: image == null ? null : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        child: image == null
            ? Text(initial,
                style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w700, fontSize: size * .42, color: K.page))
            : null,
      );
}
