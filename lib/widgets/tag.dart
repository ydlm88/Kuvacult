// tag.dart — Renders a small genre/category label as a pill badge with filled or outlined style.
import 'package:flutter/material.dart';
import '../theme.dart';

class TagWidget extends StatelessWidget {
  final String label;
  final bool filled;

  const TagWidget({super.key, required this.label, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? MC.accent1 : Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: filled
            ? null
            : Border.all(color: MC.line, width: 0.5),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: filled ? MC.accentInk : MC.mute,
          height: 1,
        ),
      ),
    );
  }
}
