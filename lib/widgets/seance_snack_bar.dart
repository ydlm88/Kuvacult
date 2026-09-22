// Séance control bar — Mute, Share, End Séance.
// Slides up 18px + fades in on entry (320ms easeOutCubic).
import 'package:flutter/material.dart';
import 'kuva_tokens.dart';

class SeanceSnackBar extends StatefulWidget {
  const SeanceSnackBar({
    super.key,
    required this.muted,
    required this.onToggleMute,
    required this.onShare,
    required this.onEnd,
    this.onPickMic,
  });

  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onShare;
  final VoidCallback onEnd;
  final VoidCallback? onPickMic;

  @override
  State<SeanceSnackBar> createState() => _SeanceSnackBarState();
}

class _SeanceSnackBarState extends State<SeanceSnackBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320))
    ..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
            offset: Offset(0, 18 * (1 - t.value)), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          color: Color(0xFF0D0C0B),
          border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _MicGroup(
              muted: widget.muted,
              onToggle: widget.onToggleMute,
              onPick: widget.onPickMic,
            ),
            SeanceControlButton(
              icon: Icons.screen_share_outlined,
              label: 'SHARE',
              active: false,
              onTap: widget.onShare,
            ),
            Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: const Color(0x14FFFFFF)),
            _EndButton(onTap: widget.onEnd),
          ],
        ),
      ),
    );
  }
}

// Mic button + optional ▾ arrow for mic picker
class _MicGroup extends StatelessWidget {
  const _MicGroup(
      {required this.muted, required this.onToggle, this.onPick});
  final bool muted;
  final VoidCallback onToggle;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    if (onPick == null) {
      return SeanceControlButton(
        icon: muted ? Icons.mic_off_outlined : Icons.mic_none_outlined,
        label: muted ? 'UNMUTE' : 'MUTE',
        active: muted,
        onTap: onToggle,
      );
    }
    final fg = muted ? Kuva.onAmber : Kuva.ink.withValues(alpha: 0.75);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 56,
      constraints: const BoxConstraints(minWidth: 76),
      decoration: BoxDecoration(
        color: muted ? Kuva.amber : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    muted ? Icons.mic_off_outlined : Icons.mic_none_outlined,
                    size: 18,
                    color: fg,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    muted ? 'UNMUTE' : 'MUTE',
                    style: Kuva.liveLabel.copyWith(
                        letterSpacing: 1.08, color: fg),
                  ),
                ],
              ),
            ),
          ),
          Container(
              width: 1,
              height: 28,
              color: fg.withValues(alpha: 0.2)),
          GestureDetector(
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.keyboard_arrow_down,
                  size: 16, color: fg.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}

class SeanceControlButton extends StatefulWidget {
  const SeanceControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<SeanceControlButton> createState() => _SeanceControlButtonState();
}

class _SeanceControlButtonState extends State<SeanceControlButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final fg =
        widget.active ? Kuva.onAmber : Kuva.ink.withValues(alpha: 0.75);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minWidth: 76),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.active
                ? Kuva.amber
                : (_down ? const Color(0x0DFFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(height: 5),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style:
                    Kuva.liveLabel.copyWith(letterSpacing: 1.08, color: fg),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0x29D34B3B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x8CD34B3B)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.close, size: 15, color: Color(0xFFF0B6AC)),
            const SizedBox(width: 9),
            Text('END SÉANCE',
                style: Kuva.hint.copyWith(
                    color: const Color(0xFFF0B6AC), letterSpacing: 1.8)),
          ]),
        ),
      );
}
