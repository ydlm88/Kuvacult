// Top-aligned toast that slides down from the status bar and auto-dismisses.
// Drop-in replacement for showSnackBar — shows for 2 seconds, slides back up.
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

void showTopToast(BuildContext context, String message, {Color? bg}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopToast(
      message: message,
      bg: bg,
      onRemove: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
    this.bg,
    required this.onRemove,
  });
  final String message;
  final Color? bg;
  final VoidCallback onRemove;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    Timer(const Duration(milliseconds: 3000), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _c.reverse();
    widget.onRemove();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1.8),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _c,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          )),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: widget.bg ?? MC.bg1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MC.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              widget.message,
              style: const TextStyle(
                color: MC.ink,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
