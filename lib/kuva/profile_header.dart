// Profile header pieces for the current set.
//   EmptyProfileBanner.own      → reference 1a  (your profile, 0 reviews)
//   EmptyProfileBanner.visitor  → reference 5a  (someone else's profile, 0 reviews)
//   ProfileHeader               → avatar + name + badge + handle + stats under the banner
//   SupportKuvacultCard         → the "Support Kuvacult" block at the bottom of your profile (1a)
//
// Users WITH reviews keep the existing poster banner; only swap in EmptyProfileBanner
// when reviews.isEmpty.

import 'package:flutter/material.dart';
import 'kuva_ui.dart';
import 'kuva_avatar.dart';
import 'name_badges.dart';

const double kBannerH = 300;

enum BannerViewer { own, visitor }

class EmptyProfileBanner extends StatelessWidget {
  const EmptyProfileBanner.own({super.key, required this.onWriteReview, required this.onImport})
      : viewer = BannerViewer.own,
        displayName = '',
        onFollow = null;
  const EmptyProfileBanner.visitor({super.key, required this.displayName, required this.onFollow})
      : viewer = BannerViewer.visitor,
        onWriteReview = null,
        onImport = null;

  final BannerViewer viewer;
  final String displayName;
  final VoidCallback? onWriteReview, onImport, onFollow;

  @override
  Widget build(BuildContext context) {
    final own = viewer == BannerViewer.own;
    return SizedBox(
      height: kBannerH,
      child: ClipRect(
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          // On narrow screens the mascot slides right and fades so copy stays readable.
          final narrow = w < 900;
          return Stack(children: [
            // ground
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Color(0xFF14100D), Color(0xFF0B0908)]),
                ),
              ),
            ),
            // warm wash — 1a: radial(70% 120% at 70% 40%, .16 → .04@45% → 0@75%)
            //             5a: radial(55% 120% at 74% 70%, .20 → .05@45% → 0@75%)
            Positioned.fill(
              child: CustomPaint(
                painter: _EllipseWash(
                  cx: own ? .70 : .74, cy: own ? .40 : .70, rx: own ? .70 : .55, ry: 1.2,
                  colors: [K.glowA(own ? .16 : .20), const Color.fromRGBO(255, 140, 43, .05), const Color(0x00000000)],
                  stops: const [0, .45, .75],
                ),
              ),
            ),
            if (!own)
              // 380 breathing glow behind the mascot (4.5s)
              Positioned(
                right: 150,
                top: 40,
                child: Breath(
                  period: const Duration(milliseconds: 4500),
                  child: Container(
                    width: 380,
                    height: 380,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [K.glowA(.18), const Color.fromRGBO(255, 140, 43, .05), const Color(0x00000000)], stops: const [0, .4, .7])),
                  ),
                ),
              ),
            // chalk sigil ring
            //   1a: 420px at right 120 / top -60, opacity .5, turns once per 120s, 3 rings + 8 ticks
            //   5a: 500px at right 90 / top -40, opacity .32, turns backwards once per 160s, 2 rings
            Positioned(
              right: own ? 120 : 90,
              top: own ? -60 : -40,
              child: Opacity(
                opacity: own ? .5 : .32,
                child: Spin(
                  period: Duration(seconds: own ? 120 : 160),
                  reverse: !own,
                  child: CustomPaint(size: Size.square(own ? 420 : 500), painter: _SigilRing(full: own)),
                ),
              ),
            ),
            // mascot — 1a: 1-welcome.png h280 at right 190 / top 10, opacity .85
            //          5a: 5-seance.png  h290 at right 230 / top 8
            Positioned(
              right: narrow ? -40 : (own ? 190 : 230),
              top: own ? 10 : 8,
              child: Opacity(
                opacity: (own ? .85 : 1) * (narrow ? .45 : 1),
                child: Image.asset(own ? 'assets/mascots/1-welcome.png' : 'assets/mascots/5-seance.png', height: own ? 280 : 290),
              ),
            ),
            // bottom fade so the avatar/name row reads: 160 tall, page colour 0 → .92
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Color(0x000A0A0A), Color(0xEB0A0A0A)])),
              ),
            ),
            // copy block — left 200 / top 46, max 520 wide, 12 gap
            Positioned(
              left: narrow ? 24 : 200,
              top: 46,
              right: narrow ? 24 : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow(own ? 'YOUR WALL IS EMPTY' : 'NOTHING ON THE WALL YET'),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(children: own
                        ? [const TextSpan(text: 'Review four films and '), TextSpan(text: "they'll hang here.", style: serif(40, color: K.gold, italic: true, height: 1.02))]
                        : [TextSpan(text: "$displayName hasn't reviewed anything. "), TextSpan(text: 'Follow to see it first.', style: serif(40, color: K.gold, italic: true, height: 1.02))]),
                    style: serif(40, height: 1.02),
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 10, children: own
                      ? [AmberButton('WRITE YOUR FIRST REVIEW', onTap: onWriteReview), OutlineKButton('IMPORT FROM LETTERBOXD', onTap: onImport)]
                      : [AmberButton('FOLLOW', onTap: onFollow)]),
                ]),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

/// Avatar + name/badge/handle + stats. Lay it out as:
///   Stack(clipBehavior: none) [ banner, ProfileHeader.avatarLayer ] then ProfileHeader.row
/// which reproduces the HTML's "avatar pinned to the banner's bottom-left, name row pulled up 78px".
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.banner,
    required this.name,
    required this.handle,
    required this.stats,
    this.border = AvatarBorder.none,
    this.tier = SupporterTier.none,
    this.image,
    this.initial = 'M',
  });
  final Widget banner;
  final String name, handle, initial;
  final List<(String, String)> stats; // ('0', 'FILMS') …
  final AvatarBorder border;
  final SupporterTier tier;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final tv = border == AvatarBorder.deadChannel;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Stack(clipBehavior: Clip.none, children: [
        banner,
        if (tv) ...[
          // soft floor shadow under the TV: 150×18 ellipse at left 22 / bottom 6
          Positioned(
            left: 22,
            bottom: 6,
            child: Container(
              width: 150,
              height: 18,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xB3000000), Color(0x00000000)])),
            ),
          ),
          // Dead Channel at 170, left 14 / bottom -4 — sits inside the banner corner
          Positioned(left: 14, bottom: -4, child: KuvaAvatar(size: 170, border: border, image: image, initial: initial)),
        ] else
          // plain 130 avatar with a 4px page-colour ring at left 22 / bottom 22
          Positioned(
            left: 22,
            bottom: 22,
            child: Container(
              width: 130,
              height: 130,
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: K.page),
              child: ClipOval(child: AvatarFace(size: 122, image: image, initial: initial)),
            ),
          ),
        // Name row. HTML pulls it up 78px (margin-top:-78) and its content is ~78 tall, so its
        // bottom lands on the banner's bottom edge — pinned here. Left inset 172 (plain) / 196 (TV).
        Positioned(
          left: tv ? 196 : 172,
          right: 24,
          bottom: 0,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: serif(32))),
                    if (tier != SupporterTier.none) ...[const SizedBox(width: 10), NameBadge(tier)],
                  ]),
                  const SizedBox(height: 2),
                  Text(handle, style: mono(14, color: K.amber)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 30),
                  Column(children: [
                    Text(stats[i].$1, style: serif(28, color: K.ink)),
                    const SizedBox(height: 4),
                    Text(stats[i].$2, style: mono(10, color: K.inkA(.6), em: .2)),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    ]);
  }
}

/// Bottom-of-profile card (1a). Opens SupportTiersPage.
/// Title "Support Kuvacult" serif 28 above it with 22 gap (part of the profile column).
class SupportKuvacultCard extends StatelessWidget {
  const SupportKuvacultCard({super.key, required this.onSeeTiers});
  final VoidCallback onSeeTiers;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onSeeTiers,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            color: K.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: K.amberA(.4)),
            // radial(40% 120% at 8% 50%, rgba(255,166,71,.14) → 0 @70%)
            gradient: RadialGradient(center: const Alignment(-.84, 0), radius: .9, colors: [K.glowA(.14), K.glowA(0)], stops: const [0, .7]),
          ),
          child: Row(children: [
            Image.asset('assets/brand/sun.png', width: 52, height: 52),
            const SizedBox(width: 22),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Kuvacult is built by two people.', style: mono(15, color: K.title)),
                const SizedBox(height: 5),
                Text('Back it once and get a supporter border, a badge, and custom profiles first. No subscriptions, ever.',
                    style: mono(13, color: K.inkA(.7), height: 1.6)),
              ]),
            ),
            const SizedBox(width: 22),
            AmberButton('SEE TIERS', onTap: onSeeTiers),
          ]),
        ),
      );
}

class _EllipseWash extends CustomPainter {
  _EllipseWash({required this.cx, required this.cy, required this.rx, required this.ry, required this.colors, required this.stops});
  final double cx, cy, rx, ry;
  final List<Color> colors;
  final List<double> stops;
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width * cx, s.height * cy), w = s.width * rx, h = s.height * ry;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(w, h);
    canvas.drawRect(Rect.fromLTRB(-c.dx / w, -c.dy / h, (s.width - c.dx) / w, (s.height - c.dy) / h),
        Paint()..shader = RadialGradient(colors: colors, stops: stops).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

/// viewBox 300: r146 (1px, α.5), r128 (1.4px dashed 2/9, α.6), r104 (1px α.4) + 8 ticks (1.2px α.7).
/// [full]=false (visitor) draws only r146 (1px) and r126 (1.3px dashed 2/9).
class _SigilRing extends CustomPainter {
  _SigilRing({required this.full});
  final bool full;
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 300;
    canvas.scale(k);
    const c = Offset(150, 150);
    Paint p(double w, double a) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = K.chalk.withValues(alpha: a);
    canvas.drawCircle(c, 146, p(1, full ? .5 : 1));
    _dashed(canvas, full ? 128 : 126, p(full ? 1.4 : 1.3, full ? .6 : 1));
    if (!full) return;
    canvas.drawCircle(c, 104, p(1, .4));
    final t = p(1.2, .7);
    for (final l in const [
      [150.0, 4.0, 150.0, 22.0], [150.0, 278.0, 150.0, 296.0], [4.0, 150.0, 22.0, 150.0], [278.0, 150.0, 296.0, 150.0],
      [46.8, 46.8, 59.5, 59.5], [240.5, 240.5, 253.2, 253.2], [46.8, 253.2, 59.5, 240.5], [240.5, 59.5, 253.2, 46.8],
    ]) {
      canvas.drawLine(Offset(l[0], l[1]), Offset(l[2], l[3]), t);
    }
  }

  void _dashed(Canvas canvas, double r, Paint p) {
    final m = (Path()..addOval(Rect.fromCircle(center: const Offset(150, 150), radius: r))).computeMetrics().first;
    for (double d = 0; d < m.length; d += 11) {
      canvas.drawPath(m.extractPath(d, d + 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}
