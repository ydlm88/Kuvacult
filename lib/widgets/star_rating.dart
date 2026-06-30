// star_rating.dart — Read-only star display and interactive half-star rating input widget.
import 'package:flutter/material.dart';
import '../theme.dart';

class StarDisplay extends StatelessWidget {
  final double value;
  final int max;
  final double size;
  final Color color;
  final Color dimColor;

  const StarDisplay({
    super.key,
    required this.value,
    this.max = 5,
    this.size = 11,
    this.color = MC.accent1,
    this.dimColor = MC.line,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(max, (i) {
        final IconData icon;
        if (value >= i + 1) {
          icon = Icons.star_rounded;
        } else if (value >= i + 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 1),
          child: Icon(icon, size: size, color: value > i ? color : dimColor),
        );
      }),
    );
  }
}

class StarRatingInput extends StatefulWidget {
  final double initialValue;
  final int max;
  final double size;
  final ValueChanged<double> onChanged;

  const StarRatingInput({
    super.key,
    this.initialValue = 0,
    this.max = 5,
    this.size = 36,
    required this.onChanged,
  });

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  void _handleTapDown(TapDownDetails details, int starIndex) {
    final starWidth = widget.size + 4; // size + horizontal padding
    final isLeftHalf = details.localPosition.dx < starWidth / 2;
    final newValue = isLeftHalf ? starIndex + 0.5 : starIndex + 1.0;
    setState(() => _value = newValue);
    widget.onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.max, (i) {
        final IconData icon;
        if (_value >= i + 1) {
          icon = Icons.star_rounded;
        } else if (_value >= i + 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return GestureDetector(
          onTapDown: (d) => _handleTapDown(d, i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(icon, size: widget.size, color: _value > i ? MC.accent1 : MC.line),
          ),
        );
      }),
    );
  }
}
