// copy_button.dart — Icon button that copies text to the clipboard and briefly shows a checkmark confirmation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyButton extends StatefulWidget {
  final String text;
  final double iconSize;
  final Color? color;

  const CopyButton({
    super.key,
    required this.text,
    this.iconSize = 18,
    this.color,
  });

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    if (_copied) return;
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _copy,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          key: ValueKey(_copied),
          size: widget.iconSize,
          color: widget.color ?? (_copied ? Colors.greenAccent : Colors.white54),
        ),
      ),
    );
  }
}
