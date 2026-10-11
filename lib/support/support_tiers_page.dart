// Support Kuvacult → tiers (reference 2b). Both avatars always visible; the selected one
// grows, the other dims. Pay button goes to a Stripe Payment Link (one-time price).
//
// Stripe setup (dashboard):
//   1. Product "Dev Supporter" — one-time price $5.00.  Product "Founder" — one-time price $10.00.
//   2. Create a Payment Link for each. Under "After payment" → "Don't show confirmation page" →
//      redirect to your thanks page:  https://<your-pages-site>/thanks.html
//   3. Paste the two links below. Append ?client_reference_id=<userId> so your webhook
//      (checkout.session.completed) knows which Kuvacult account to upgrade.
//   4. Webhook sets user.tier = devSupporter | founder. The app reads the tier on resume
//      ("your supporter badge will show up shortly").

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../kuva/kuva_ui.dart';
import '../kuva/kuva_avatar.dart';
import '../kuva/name_badges.dart';
import '../services/api_service.dart';
import '../app_state.dart';

class _Plan {
  const _Plan(this.tier, this.tag, this.tagColor, this.name, this.price, this.perks, this.cta, this.apiTier);
  final SupporterTier tier;
  final String tag, name, price, cta, apiTier;
  final Color tagColor;
  final List<String> perks;
}

const _plans = [
  _Plan(SupporterTier.devSupporter, 'TIER I', K.amber, 'Dev Supporter', r'$5', [
    'Dead Channel profile border',
    'More borders and banners on the way',
    'Supporter badge next to your name',
    'Custom profiles before everyone else',
    'Lifetime. No subscriptions, ever.',
  ], r'SUPPORT FOR $5', 'dev_supporter'),
  _Plan(SupporterTier.founder, 'TIER II', K.gold, 'Founder', r'$10', [
    'Dead Channel border now',
    'Extra animated borders, for Elders only, coming soon',
    'Founder badge next to your name',
    'Extra profile customization: banner styles and accent colour',
    'Everything in Dev Supporter',
  ], r'BECOME A FOUNDER · $10', 'founder'),
];

class SupportTiersPage extends StatefulWidget {
  const SupportTiersPage({super.key, required this.userId, required this.name, this.image});
  final String userId, name;
  final ImageProvider? image;
  @override
  State<SupportTiersPage> createState() => _SupportTiersPageState();
}

class _SupportTiersPageState extends State<SupportTiersPage> {
  int _sel = 1; // Founder preselected

  Future<void> _pay(BuildContext context) async {
    final p = _plans[_sel];
    try {
      final email = context.read<AppState>().currentUser?.email;
      final url = await ApiService.createSupporterCheckout(tier: p.apiTier, email: email);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: K.page,
      body: Stack(children: [
        // top glow: 900×600 ellipse centred at top -220, radial .12 → 0 @70%
        Positioned(
          top: -220,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 900,
              height: 600,
              decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [K.glowA(.12), K.glowA(0)], stops: const [0, .7])),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 52),
            child: Column(children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.maybePop(context),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('‹', style: mono(18)),
                    const SizedBox(width: 10),
                    Text('SUPPORT KUVACULT', style: mono(11, color: K.inkA(.62), em: .24)),
                  ]),
                ),
              ),
              const SizedBox(height: 38),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(children: [
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Pay once. '),
                      TextSpan(text: 'Keep it forever.', style: serif(50, color: K.gold, italic: true, height: 1)),
                    ]),
                    textAlign: TextAlign.center,
                    style: serif(50, height: 1),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      'Everything in Kuvacult stays free. These are one-time upgrades for people who want to back the two of us building it.',
                      textAlign: TextAlign.center,
                      style: mono(13, color: K.inkA(.74), height: 1.85),
                    ),
                  ),
                  const SizedBox(height: 38),
                  // both avatars, 72 gap; selected scale 1.08 / opacity 1, other .92 / .45, 300ms
                  Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i > 0) const SizedBox(width: 72),
                      GestureDetector(
                        onTap: () => setState(() => _sel = i),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: _sel == i ? 1 : .45,
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 300),
                            scale: _sel == i ? 1.08 : .92,
                            child: Column(children: [
                              KuvaAvatar(size: 170, border: AvatarBorder.deadChannel, image: widget.image),
                              const SizedBox(height: 14),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(widget.name, style: serif(26)),
                                const SizedBox(width: 10),
                                NameBadge(_plans[i].tier),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 38),
                  LayoutBuilder(builder: (_, c) {
                    final two = c.maxWidth >= 720;
                    final cards = [for (var i = 0; i < 2; i++) _card(i)];
                    return two
                        ? IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 20),
                            Expanded(child: cards[1]),
                          ]))
                        : Column(children: [cards[0], const SizedBox(height: 20), cards[1]]);
                  }),
                  const SizedBox(height: 38),
                  AmberButton(_plans[_sel].cta, width: 420, height: 54, radius: 13, em: .18, onTap: () => _pay(context)),
                  const SizedBox(height: 20),
                  Text('Payments are handled by Stripe. Kuvacult never sees your card details.',
                      textAlign: TextAlign.center, style: mono(11, color: K.inkA(.6), em: .06)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                        color: K.amberA(.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: K.amberA(.25))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: K.amber, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text('More borders and banners are coming for every supporter, plus extra animated ones just for Elders.',
                            style: mono(11, color: K.noteText, em: .04, height: 1.6)),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // padding 28/28/24 · radius 20 · #120f0e · selected: 1px #E9C468 + ring rgba(233,196,104,.35) + 0 20 50 rgba(0,0,0,.5)
  Widget _card(int i) {
    final p = _plans[i], on = _sel == i;
    return GestureDetector(
      onTap: () => setState(() => _sel = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        decoration: BoxDecoration(
          color: K.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? K.gold : K.whiteA(.08)),
          boxShadow: on
              ? [BoxShadow(color: K.goldA(.35), spreadRadius: 1), const BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20))]
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // radio 18, 1.5px border; dot 8 amber
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 10, right: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? K.amber : K.inkA(.3), width: 1.5)),
              child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: on ? 1 : 0,
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: K.amber, shape: BoxShape.circle))),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow(p.tag, color: p.tagColor),
                const SizedBox(height: 6),
                Text(p.name, style: serif(32, height: 1)),
              ]),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(p.price, style: serif(58, color: K.gold, height: .85)),
              const SizedBox(width: 8),
              Text('once', style: mono(11, color: K.inkA(.62), em: .1)),
            ]),
          ]),
          const SizedBox(height: 20),
          Container(height: 1, color: K.whiteA(.07)),
          const SizedBox(height: 20),
          for (final k in p.perks)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 6, height: 6, margin: const EdgeInsets.only(top: 8, right: 12),
                    decoration: const BoxDecoration(color: K.amber, shape: BoxShape.circle)),
                Expanded(child: Text(k, style: mono(13, color: K.inkA(.84), height: 1.6))),
              ]),
            ),
        ]),
      ),
    );
  }
}
