// Blackjack tiebreaker screen (reference Blackjack Table v2, frames 7a phone / 7b small window).
// Works from 360 wide upward: < 520 wide → 2 seats per row, cards 38 wide;
// ≥ 520 → 3 seats per row, cards 46 wide. House cards are always card width + 6.
//
// The app's own bottom nav (wax_rail_nav.dart from the earlier handoff, Ritual tab active)
// sits below this — it is NOT part of this widget.

import 'dart:async';
import 'package:flutter/material.dart';
import '../kuva/kuva_ui.dart';
import 'tiebreaker_game.dart';

const double kCardRatio = 261 / 176;

class BlackjackTiebreakerScreen extends StatefulWidget {
  const BlackjackTiebreakerScreen({super.key, required this.players});
  /// Seat 0 must be the local user.
  final List<Player> players;
  @override
  State<BlackjackTiebreakerScreen> createState() => _BlackjackTiebreakerScreenState();
}

class _BlackjackTiebreakerScreenState extends State<BlackjackTiebreakerScreen> {
  late TiebreakerGame g = TiebreakerGame(widget.players);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  // AI seats act every 750ms, the House every 800ms — gives the table a readable rhythm.
  void _schedule() {
    _t?.cancel();
    if (g.phase == Phase.play && !g.isUsersTurn) {
      _t = Timer(const Duration(milliseconds: 750), () => setState(() {
            g.autoPlay(g.currentSeat!);
            _schedule();
          }));
    } else if (g.phase == Phase.house) {
      _t = Timer(const Duration(milliseconds: 800), () => setState(() {
            g.houseStep();
            _schedule();
          }));
    }
  }

  void _act(void Function() f) => setState(() {
        f();
        _schedule();
      });

  @override
  Widget build(BuildContext context) {
    final o = g.outcome();
    return LayoutBuilder(builder: (context, c) {
      final phone = c.maxWidth < 520;
      final cw = phone ? 38.0 : 46.0;
      final cols = phone ? 2 : 3;
      return Container(
        color: K.page,
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(children: [
              Expanded(child: Text('BLACKJACK TIEBREAKER', style: mono(13, color: K.amber, em: .4), overflow: TextOverflow.ellipsis)),
              GestureDetector(
                onTap: () => _act(g.clear),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: K.whiteA(.14))),
                  child: Text('CLEAR', style: mono(10, color: K.inkA(.7), em: .28)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          _housePanel(cw + 6),
          const SizedBox(height: 10),
          Expanded(child: _felt(o, cw, cols)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: Text(o.status, textAlign: TextAlign.center, style: mono(13, color: K.inkA(.85), height: 1.5)),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 56, child: _actions(o)),
        ]),
      );
    });
  }

  // House: padding 12/16, radius 16, #151110, 1px white .07
  Widget _housePanel(double w) {
    final v = handValue(g.house), bust = v > 21;
    final score = g.reveal ? (bust ? 'BUST' : '$v') : '${handValue([g.house.first])}+';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF151110), borderRadius: BorderRadius.circular(16), border: Border.all(color: K.whiteA(.07))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('House', style: serif(22, color: K.gold)),
            const SizedBox(height: 4),
            Text('DEALER', style: mono(9, color: K.inkA(.6), em: .3)),
          ]),
        ),
        _Hand(cards: g.house, width: w, overlap: .3, hideSecond: !g.reveal),
        SizedBox(
          width: 60,
          child: Text(score, textAlign: TextAlign.right, style: serif(28, color: bust ? K.bust : K.title)),
        ),
      ]),
    );
  }

  // Felt: radius 20, padding 12, radial(#1a1411 → #110d0c 65% → #0c0a09), inset shadow 50 black .8,
  // warm top glow, dashed chalk inset (2/9, α.35), Nastia's table art watermark at 6%.
  Widget _felt(Outcome o, double cw, int cols) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -.4), radius: 1.1, colors: [Color(0xFF1A1411), Color(0xFF110D0C), Color(0xFF0C0A09)], stops: [0, .65, 1]),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0, -.6), radius: .9, colors: [K.glowA(.10), K.glowA(0)], stops: const [0, .6]),
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _DashedInset())),
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0, .1),
            child: FractionallySizedBox(
              widthFactor: .7,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Opacity(opacity: .06, child: Image.asset('assets/mascots/4-sacrifice.png')),
              ),
            ),
          ),
        ),
        // inset shadow
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _InsetShadow()))),
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 10 * (cols - 1)) / cols;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < g.n; i++) SizedBox(width: w, child: _seat(i, o, cw)),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _seat(int i, Outcome o, double cw) {
    final out = g.isOut(i);
    final v = handValue(g.hands[i]);
    final active = g.currentSeat == i;
    final win = o.winners.contains(i);
    final bust = !out && v > 21;
    final lost = g.phase == Phase.done && !win;
    final hot = active || win;
    final score = out ? 'OUT' : bust ? 'BUST' : '$v';
    final scoreColor = out ? K.inkA(.6) : bust ? K.bust : hot ? K.gold : K.ink;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: out ? .32 : (bust || lost) ? .55 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xEB120F0E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: hot ? K.gold : K.whiteA(.07), width: hot ? 1.5 : 1),
          boxShadow: hot ? [BoxShadow(color: K.goldA(.18), blurRadius: 22)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Text(widget.players[i].name, overflow: TextOverflow.ellipsis, style: mono(13, color: K.title, w: FontWeight.w500))),
            const SizedBox(width: 6),
            Text(score, style: serif(24, color: scoreColor, height: 1)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: cw * kCardRatio,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Hand(cards: g.hands[i], width: cw, overlap: g.hands[i].length > 3 ? .6 : .42),
            ),
          ),
          const SizedBox(height: 8),
          Text('→ ${out ? 'Out — sacrificed' : widget.players[i].film}',
              overflow: TextOverflow.ellipsis, style: mono(10, color: K.inkA(.6))),
        ]),
      ),
    );
  }

  Widget _actions(Outcome o) {
    if (g.phase == Phase.play && g.isUsersTurn) {
      return Row(children: [
        Expanded(child: _BigButton('Hit', primary: true, onTap: () => _act(() => g.hit(0)))),
        const SizedBox(width: 12),
        Expanded(child: _BigButton('Stand', primary: false, onTap: () => _act(() => g.stand(0)))),
      ]);
    }
    if (g.phase == Phase.done && o.needsDealAgain) {
      return _BigButton('Deal again', primary: true, onTap: () => _act(g.dealAgain));
    }
    return const SizedBox.shrink(); // keeps the 56px slot so nothing jumps
  }
}

/// Overlapping fan of cards. Card i>0 is pulled left by width × overlap.
class _Hand extends StatelessWidget {
  const _Hand({required this.cards, required this.width, required this.overlap, this.hideSecond = false});
  final List<PlayingCard> cards;
  final double width, overlap;
  final bool hideSecond;
  @override
  Widget build(BuildContext context) {
    final step = width * (1 - overlap);
    final h = (width * kCardRatio).roundToDouble();
    return SizedBox(
      width: cards.isEmpty ? 0 : width + step * (cards.length - 1),
      height: h,
      child: Stack(children: [
        for (var i = 0; i < cards.length; i++)
          Positioned(
            left: step * i,
            child: CardFace(card: cards[i], width: width, faceDown: hideSecond && i == 1),
          ),
      ]),
    );
  }
}

/// One card. 176 × 261 art.
///  back  : assets/cards/back-4b-logo.png
///  front : card-tan.png (♥ ♦) or card-dark.png (♠ ♣)
///          rank  r-<R>.png (red) / w-<R>.png (white) at left 8% · top 6% · height 15%
///          small suit <suit>.png at left 9% · top 24% · width 14%
///          big suit centred at (50%, 56%) · width 40%
///  shadow: drop-shadow(0 3px 5px rgba(0,0,0,.55))
class CardFace extends StatelessWidget {
  const CardFace({super.key, required this.card, required this.width, this.faceDown = false});
  final PlayingCard card;
  final double width;
  final bool faceDown;
  @override
  Widget build(BuildContext context) {
    final w = width, h = (width * kCardRatio).roundToDouble();
    final suit = 'assets/cards/${card.suit.name}.png';
    return Container(
      width: w,
      height: h,
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 5, offset: Offset(0, 3))]),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: faceDown
            ? Image.asset('assets/cards/back-4b-logo.png', key: const ValueKey('back'), width: w, height: h, fit: BoxFit.fill)
            : Stack(key: const ValueKey('front'), children: [
                Image.asset(card.red ? 'assets/cards/card-tan.png' : 'assets/cards/card-dark.png', width: w, height: h, fit: BoxFit.fill),
                Positioned(left: w * .08, top: h * .06, height: h * .15, child: Image.asset('assets/cards/${card.red ? 'r' : 'w'}-${card.rank}.png')),
                Positioned(left: w * .09, top: h * .24, width: w * .14, child: Image.asset(suit)),
                Positioned(
                  left: w * .5 - w * .2,
                  top: h * .56 - w * .2,
                  width: w * .4,
                  height: w * .4,
                  child: Image.asset(suit, fit: BoxFit.contain),
                ),
              ]),
      ),
    );
  }
}

/// Hit / Deal again: 56 tall, radius 14, gradient #f2c35a → #e3a43a, shadow 0 8 24 rgba(232,161,60,.25),
/// Instrument Serif 22 #1b1210. Stand: 1px rgba(255,255,255,.22), text #f7ecdc.
class _BigButton extends StatelessWidget {
  const _BigButton(this.label, {required this.primary, required this.onTap});
  final String label;
  final bool primary;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: primary ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF2C35A), Color(0xFFE3A43A)]) : null,
            border: primary ? null : Border.all(color: K.whiteA(.22)),
            boxShadow: primary ? [BoxShadow(color: K.amberA(.25), blurRadius: 24, offset: const Offset(0, 8))] : null,
          ),
          child: Text(label, style: serif(22, color: primary ? K.onAmber : K.title)),
        ),
      );
}

class _DashedInset extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    // inset 5px; corner radii 5% × 3% of the box (SVG rx=5 ry=3 in a 100×100 stretched viewBox)
    final r = Rect.fromLTWH(5, 5, s.width - 10, s.height - 10);
    final rr = RRect.fromRectAndRadius(r, Radius.elliptical(r.width * .05, r.height * .03));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = K.chalk.withValues(alpha: .35);
    for (final m in (Path()..addRRect(rr)).computeMetrics()) {
      for (double d = 0; d < m.length; d += 11) {
        canvas.drawPath(m.extractPath(d, d + 2), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

class _InsetShadow extends CustomPainter {
  const _InsetShadow();
  @override
  void paint(Canvas canvas, Size s) {
    final rr = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(20));
    canvas.clipRRect(rr);
    canvas.drawRRect(
        rr.inflate(25),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 50
          ..color = const Color(0xCC000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25));
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}
