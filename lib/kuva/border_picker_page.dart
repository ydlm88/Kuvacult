// Profile → Edit → Border (reference 4b). Dead Channel is the only border for now.
// Supporters (either tier) can pick it; free users see it locked and tapping it opens the tiers page.

import 'package:flutter/material.dart';
import 'kuva_ui.dart';
import 'kuva_avatar.dart';
import 'name_badges.dart';

class BorderPickerPage extends StatefulWidget {
  const BorderPickerPage({
    super.key,
    required this.current,
    required this.tier,
    required this.name,
    required this.handle,
    required this.onSave,
    required this.onUnlock,
    this.image,
  });
  final AvatarBorder current;
  final SupporterTier tier;
  final String name, handle;
  final ImageProvider? image;
  final ValueChanged<AvatarBorder> onSave; // persist to the user's profile
  final VoidCallback onUnlock; // push SupportTiersPage

  @override
  State<BorderPickerPage> createState() => _BorderPickerPageState();
}

class _BorderPickerPageState extends State<BorderPickerPage> {
  late AvatarBorder _sel = widget.current;
  bool get _supporter => widget.tier != SupporterTier.none;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: K.page,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 34, 40, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GestureDetector(
              onTap: () => Navigator.maybePop(context),
              child: Row(children: [
                Text('‹', style: mono(18)),
                const SizedBox(width: 12),
                Text('EDIT PROFILE · BORDER', style: mono(11, color: K.inkA(.62), em: .24)),
              ]),
            ),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (_, c) {
              final wide = c.maxWidth >= 820;
              final preview = _preview();
              final options = _options();
              return wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 400, child: preview),
                      const SizedBox(width: 40),
                      Expanded(child: options),
                    ])
                  : Column(children: [preview, const SizedBox(height: 28), options]);
            }),
          ]),
        ),
      ),
    );
  }

  // Left panel: padding 34/20/28, radius 18, #100d0c + radial(70% 60% at 50% 40%, rgba(255,166,71,.1))
  Widget _preview() => Container(
        padding: const EdgeInsets.fromLTRB(20, 34, 20, 28),
        decoration: BoxDecoration(
          color: K.panelDeep,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: K.whiteA(.07)),
          gradient: RadialGradient(center: const Alignment(0, -.2), radius: .8, colors: [K.glowA(.1), K.glowA(0)]),
        ),
        child: Column(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: KuvaAvatar(key: ValueKey(_sel), size: 260, border: _sel, image: widget.image),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.name, style: serif(30)),
            if (_supporter) ...[const SizedBox(width: 10), NameBadge(widget.tier)],
          ]),
          const SizedBox(height: 8),
          Text(widget.handle, style: mono(13, color: K.amber)),
          const SizedBox(height: 16),
          Text(_sel.label.toUpperCase(), style: mono(11, color: K.inkA(.6), em: .14)),
        ]),
      );

  Widget _options() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          const Eyebrow('ACOLYTE PACK'),
          const SizedBox(width: 12),
          Text('Dev Supporter and up', style: mono(11, color: K.inkA(.5))),
        ]),
        const SizedBox(height: 14),
        // 4-column grid, 12 gap — only two tiles today
        LayoutBuilder(builder: (_, c) {
          final w = (c.maxWidth - 12 * 3) / 4;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final b in AvatarBorder.values) SizedBox(width: w.clamp(120, 400), child: _tile(b)),
          ]);
        }),
        const SizedBox(height: 32),
        Row(children: [
          Expanded(
            child: Text(
              _supporter ? 'More borders are on the way. Swap whenever you like.' : 'Become a Dev Supporter to unlock Dead Channel.',
              style: mono(11, color: K.inkA(.55), height: 1.6),
            ),
          ),
          const SizedBox(width: 16),
          AmberButton(_supporter ? 'SAVE BORDER' : 'SEE TIERS',
              height: 46, hPad: 22, radius: 13, em: .18, onTap: _supporter ? () => widget.onSave(_sel) : widget.onUnlock),
        ]),
      ]);

  // Tile: padding 16/10/14, radius 14, #120f0e. Selected: 1px #e8a13c + 0 0 0 1px rgba(232,161,60,.35) + ✓ chip.
  Widget _tile(AvatarBorder b) {
    final locked = b.needsSupporter && !_supporter;
    final on = _sel == b;
    return GestureDetector(
      onTap: () => locked ? widget.onUnlock() : setState(() => _sel = b),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
        decoration: BoxDecoration(
          color: K.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? K.amber : K.whiteA(.07)),
          boxShadow: on ? [BoxShadow(color: K.amberA(.35), spreadRadius: 1)] : null,
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(children: [
            Opacity(opacity: locked ? .35 : 1, child: KuvaAvatar(size: 112, border: b, image: widget.image)),
            const SizedBox(height: 10),
            Text(b.label.toUpperCase(), style: mono(10, color: on ? K.noteText : K.inkA(.7), em: .18)),
          ]),
          if (on)
            Positioned(
              top: -6,
              right: 0,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: K.amber, shape: BoxShape.circle),
                child: Text('✓', style: mono(11, color: K.onAmber)),
              ),
            ),
          if (locked)
            Positioned(
              top: -6,
              right: 0,
              child: Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xD90A0A0A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: K.amberA(.5)),
                ),
                child: Text('SUPPORTER', style: mono(8, color: K.amber, em: .18)),
              ),
            ),
        ]),
      ),
    );
  }
}
