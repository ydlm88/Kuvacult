// Kuvacult — Onboarding (6 screens).
//
// Self-contained: no dependency on other Kuvacult Dart files.
// Design reference: reference/Onboarding.dc.html (open in a browser).
// Design canvas: 390 × 844 logical px. Every number below is taken 1:1 from it.
//
// pubspec.yaml
//   dependencies:
//     google_fonts: ^6.2.1
//   flutter:
//     assets:
//       - assets/onboarding/
//
// Usage
//   KuvaOnboarding(
//     onFinish: () => ...,          // "Nah, I'm chill — start free"
//     onBecomeSupporter: () => ..., // "Become a Dev Supporter · $5"
//   )

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Tokens (exact values from the design) ──────────────────────────────────

class _C {
  static const screen = Color(0xFF0A0A0A);
  static const title = Color(0xFFF7ECDC);
  static const ink = Color(0xFFF3E4CF);
  static const body = Color(0xB8F3E4CF); //  rgba(243,228,207,.72)
  static const eyebrow = Color(0x80F3E4CF); // .50
  static const secondary = Color(0xA8F3E4CF); // .66
  static const dotOff = Color(0x40F3E4CF); // .25
  static const amber = Color(0xFFE8A13C);
  static const onAmber = Color(0xFF1B1210);
  static const noteText = Color(0xFFF0D3A6);
  static const noteFill = Color(0x14E8A13C); // rgba(232,161,60,.08)
  static const noteLine = Color(0x40E8A13C); // .25
}

// CSS letter-spacing is in em; Flutter wants logical px → em × fontSize.
TextStyle _mono(double size, Color color, {double em = 0, double? height}) =>
    GoogleFonts.jetBrainsMono(
        fontSize: size, color: color, letterSpacing: em * size, height: height, fontWeight: FontWeight.w400);

TextStyle _serif(double size, Color color, {double? height}) =>
    GoogleFonts.instrumentSerif(fontSize: size, color: color, height: height, fontWeight: FontWeight.w400);

// ─── Content ────────────────────────────────────────────────────────────────

/// CSS `radial-gradient(RX% RY% at CX% CY%, stops…)`. RX/RY are ellipse radii as
/// a fraction of the screen's width/height; CX/CY the centre.
class _Wash {
  const _Wash(this.rx, this.ry, this.cx, this.cy, this.colors, this.stops);
  final double rx, ry, cx, cy;
  final List<Color> colors;
  final List<double> stops;
}

class _Screen {
  const _Screen({
    required this.art,
    required this.title,
    required this.body,
    required this.wash,
    this.eyebrow = '',
    this.note,
    this.cta,
    this.premium = false,
  });
  final String art, title, body, eyebrow;
  final String? note, cta;
  final _Wash wash;
  final bool premium;
}

const _screens = <_Screen>[
  _Screen(
    eyebrow: 'KUVACULT', // only screen 1 carries the brand name
    art: 'assets/onboarding/1-welcome.png',
    title: 'Watch together, argue later.',
    body: 'Finally finish that backlog you made with the boys. Skip the boring parts.',
    cta: 'BEGIN',
    wash: _Wash(.75, .55, .50, .28, [Color(0x1AFFA647), Color(0x08FF8C2B), Color(0x00000000)], [0, .48, .78]),
  ),
  _Screen(
    art: 'assets/onboarding/2-reviews.png',
    title: 'One review per film. Make it count.',
    body:
        'Rate with stars, react in a word, and say whatever you want — free speech rules this site. Friends can comment, and nobody gets a second draft.',
    cta: 'NEXT',
    wash: _Wash(.70, .50, .50, .30, [Color(0x12C9B6E4), Color(0x00000000)], [0, .74]),
  ),
  _Screen(
    art: 'assets/onboarding/3-watchlists.png',
    title: 'Lists your friends can edit.',
    body:
        'Build a watchlist with anyone, add films from a shared catalogue, and watch it update live as they pile on.',
    note:
        "Don't start over. Import your Letterboxd export and your watchlists and review history come with you.",
    cta: 'NEXT',
    wash: _Wash(.70, .50, .50, .30, [Color(0x129FD6C0), Color(0x00000000)], [0, .74]),
  ),
  _Screen(
    art: 'assets/onboarding/4-sacrifice.png',
    title: 'Veto until one film survives.',
    body: "Sacrifice films you'd rather die than watch, then gamble with what's left.",
    cta: 'NEXT',
    wash: _Wash(.70, .50, .50, .30, [Color(0x14E4A9A0), Color(0x00000000)], [0, .74]),
  ),
  _Screen(
    art: 'assets/onboarding/5-seance.png',
    title: 'Light the candle, share the screen.',
    body:
        'Watch together with media you own and play from your own machine. No subscription required, and Kuvacult never hosts, stores, or transmits your files — the séance only mirrors your screen to people you invite.',
    note: 'Screen share is in beta. Expect 30fps. You are responsible for the content you share.',
    cta: 'NEXT',
    wash: _Wash(.75, .55, .50, .30, [Color(0x29FFA647), Color(0x0DFF8C2B), Color(0x00000000)], [0, .46, .78]),
  ),
  _Screen(
    art: 'assets/onboarding/6-feed-a-dev.png',
    title: 'Five dollars, once, forever.',
    body:
        'Kuvacult is built by two people. If you want to back it, five dollars buys a lifetime Dev Supporter upgrade — deeply customisable profiles are coming, and supporters get them first.',
    note: "No subscriptions, ever. Everything you've just seen stays free.",
    premium: true,
    wash: _Wash(.80, .60, .50, .32, [Color(0x21FFA647), Color(0x0AFF8C2B), Color(0x00000000)], [0, .50, .80]),
  ),
];

// ─── Onboarding ─────────────────────────────────────────────────────────────

class KuvaOnboarding extends StatefulWidget {
  const KuvaOnboarding({super.key, required this.onFinish, required this.onBecomeSupporter});
  final VoidCallback onFinish;
  final VoidCallback onBecomeSupporter;

  @override
  State<KuvaOnboarding> createState() => _KuvaOnboardingState();
}

class _KuvaOnboardingState extends State<KuvaOnboarding> {
  final _pages = PageController();
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final s in _screens) {
      precacheImage(AssetImage(s.art), context);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final s = _screens[_index];
    return Scaffold(
      backgroundColor: _C.screen,
      body: SafeArea(
        child: Column(children: [
          // Pages: wash + top label + art + copy. Swipeable.
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _screens.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _Page(screen: _screens[i]),
            ),
          ),
          // Bottom bar is shared so the dots can animate between pages.
          // padding: 22 top, 24 sides, 26 bottom (CSS: 22px 24px 26px).
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: s.premium
                  ? _PremiumBar(
                      key: const ValueKey('premium'),
                      onSupport: widget.onBecomeSupporter,
                      onSkip: widget.onFinish,
                    )
                  : _StandardBar(
                      key: const ValueKey('standard'),
                      index: _index,
                      count: _screens.length,
                      label: s.cta!,
                      onTap: _next,
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.screen});
  final _Screen screen;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _WashPainter(screen.wash)))),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Top row — padding 22 top / 24 sides. Height is kept on screens 2–6
        // even though the label is empty, so the art never jumps.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: SizedBox(
            height: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(screen.eyebrow, style: _mono(9, _C.eyebrow, em: .26, height: 1.33)),
            ),
          ),
        ),
        // Art — 342 × 380 frame, image contained & centred, padding 18 top.
        // Flexible so it shrinks on short phones; never grows past 342 × 380.
        Flexible(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
                child: AspectRatio(
                  aspectRatio: 342 / 380,
                  child: Image.asset(screen.art, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                ),
              ),
            ),
          ),
        ),
        // Copy — padding 24 top / 24 sides, 12 gap.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(screen.title, style: _serif(40, _C.title, height: 1.05)),
            const SizedBox(height: 12),
            Text(screen.body, style: _mono(12, _C.body, height: 1.8)),
            if (screen.note != null) ...[
              const SizedBox(height: 12),
              _Note(screen.note!),
            ],
          ]),
        ),
      ]),
    ]);
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _C.noteFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.noteLine, width: 1),
      ),
      child: Row(children: [
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: _C.amber, shape: BoxShape.circle)),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: _mono(10, _C.noteText, em: .04, height: 1.6))),
      ]),
    );
  }
}

// ─── Bottom bars ────────────────────────────────────────────────────────────

class _StandardBar extends StatelessWidget {
  const _StandardBar({super.key, required this.index, required this.count, required this.label, required this.onTap});
  final int index, count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      // Dots: 6 × 6, current one stretches to 22 wide. 7 gap. 240ms ease.
      Row(children: [
        for (var j = 0; j < count; j++) ...[
          if (j > 0) const SizedBox(width: 7),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.ease,
            width: j == index ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: j == index ? _C.amber : _C.dotOff,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ]),
      const SizedBox(width: 14),
      // CTA: 50 tall, 26 horizontal padding, radius 13.
      _AmberButton(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        onTap: onTap,
        child: Text(label, style: _mono(11, _C.onAmber, em: .18)),
      ),
    ]);
  }
}

class _PremiumBar extends StatelessWidget {
  const _PremiumBar({super.key, required this.onSupport, required this.onSkip});
  final VoidCallback onSupport, onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _AmberButton(
        height: 52,
        onTap: onSupport,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const FlickerCandleGlyph(),
          const SizedBox(width: 9),
          Text(r'BECOME A DEV SUPPORTER · $5', style: _mono(11, _C.onAmber, em: .18)),
        ]),
      ),
      const SizedBox(height: 4),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSkip,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 2),
          child: Text("NAH, I'M CHILL — START FREE",
              textAlign: TextAlign.center, style: _mono(10, _C.secondary, em: .14)),
        ),
      ),
    ]);
  }
}

class _AmberButton extends StatefulWidget {
  const _AmberButton({required this.height, required this.child, required this.onTap, this.padding = EdgeInsets.zero});
  final double height;
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;

  @override
  State<_AmberButton> createState() => _AmberButtonState();
}

class _AmberButtonState extends State<_AmberButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? .98 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: widget.height,
          padding: widget.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _C.amber, borderRadius: BorderRadius.circular(13)),
          child: widget.child,
        ),
      ),
    );
  }
}

// ─── Candle glyph on the Dev Supporter button ──────────────────────────────
//
// Matches the HTML exactly:
//   box   12 × 18
//   wax   12 × 11, radius 3, bottom-aligned, colour #1b1210
//   flame  7 × 9, centred, bottom edge 11px from the box bottom (sits on the
//          wax; its top pokes 2px above the 18px box — do not clip)
//   flame shape  border-radius: 52% 48% 46% 54% / 72% 72% 32% 32%
//   flicker  keyframes, 170ms, ease-in-out, infinite alternate
//     0%   scale(1.00, 1.00) rotate(-1.6°)
//     50%  scale(0.92, 1.08) rotate( 1.2°)
//     100% scale(1.03, 0.96) rotate(-0.5°)
//   transform-origin: centre of the flame box.
//   Reduced motion: holds the 0% pose.

class FlickerCandleGlyph extends StatefulWidget {
  const FlickerCandleGlyph({super.key, this.color = _C.onAmber});
  final Color color;

  @override
  State<FlickerCandleGlyph> createState() => _FlickerCandleGlyphState();
}

class _FlickerCandleGlyphState extends State<FlickerCandleGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 170));

  static const _kf = [
    (sx: 1.00, sy: 1.00, deg: -1.6),
    (sx: 0.92, sy: 1.08, deg: 1.2),
    (sx: 1.03, sy: 0.96, deg: -0.5),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true); // CSS "alternate"
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // CSS applies the timing function per keyframe segment.
  Matrix4 _pose(double t) {
    final seg = t < .5 ? 0 : 1;
    final local = Curves.easeInOut.transform(seg == 0 ? t / .5 : (t - .5) / .5);
    final a = _kf[seg], b = _kf[seg + 1];
    double lerp(double x, double y) => x + (y - x) * local;
    final sx = lerp(a.sx, b.sx), sy = lerp(a.sy, b.sy), deg = lerp(a.deg, b.deg);
    // CSS "scale() rotate()" == S · R
    return Matrix4.identity()
      ..scale(sx, sy, 1.0)
      ..rotateZ(deg * math.pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 18,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(
            width: 12,
            height: 11,
            decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Positioned(
          left: (12 - 7) / 2,
          bottom: 11,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Transform(alignment: Alignment.center, transform: _pose(_c.value), child: child),
            child: CustomPaint(size: const Size(7, 9), painter: _FlamePainter(widget.color)),
          ),
        ),
      ]),
    );
  }
}

/// Exact CSS `border-radius: 52% 48% 46% 54% / 72% 72% 32% 32%` on a 7 × 9 box.
/// Vertical radii sum to 104% on each side, so CSS scales every radius by
/// 100/104 — reproduced here.
class _FlamePainter extends CustomPainter {
  _FlamePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final f = math.min(1.0, math.min(1 / (.52 + .48), math.min(1 / (.46 + .54), 1 / (.72 + .32))));
    Radius r(double px, double py) => Radius.elliptical(px * w * f, py * h * f);
    final rr = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: r(.52, .72),
      topRight: r(.48, .72),
      bottomRight: r(.46, .32),
      bottomLeft: r(.54, .32),
    );
    canvas.drawRRect(rr, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) => old.color != color;
}

// ─── Background wash ────────────────────────────────────────────────────────

class _WashPainter extends CustomPainter {
  _WashPainter(this.wash);
  final _Wash wash;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw a unit-radius circle gradient, then stretch it into the CSS ellipse.
    final c = Offset(size.width * wash.cx, size.height * wash.cy);
    final rx = size.width * wash.rx, ry = size.height * wash.ry;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(rx, ry);
    final paint = Paint()
      ..shader = RadialGradient(colors: wash.colors, stops: wash.stops)
          .createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    // cover the whole screen in unit space
    canvas.drawRect(
        Rect.fromLTRB(-c.dx / rx, -c.dy / ry, (size.width - c.dx) / rx, (size.height - c.dy) / ry), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WashPainter old) => old.wash != wash;
}
