// review_text.dart — Renders review text with italic HTML tag support and an expandable "Read more" toggle.
import 'package:flutter/material.dart';
import '../theme.dart';

/// Renders review text, converting <i>...</i> HTML tags to italic TextSpans.
class ReviewText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  const ReviewText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  static final _tag = RegExp(r'<i>(.*?)</i>', dotAll: true, caseSensitive: false);

  static List<TextSpan> _spans(String text, TextStyle base) {
    final result = <TextSpan>[];
    int last = 0;
    for (final m in _tag.allMatches(text)) {
      if (m.start > last) result.add(TextSpan(text: text.substring(last, m.start), style: base));
      result.add(TextSpan(text: m.group(1), style: base.copyWith(fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < text.length) result.add(TextSpan(text: text.substring(last), style: base));
    return result.isEmpty ? [TextSpan(text: text, style: base)] : result;
  }

  @override
  Widget build(BuildContext context) {
    if (!text.contains('<i>')) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    return Text.rich(
      TextSpan(children: _spans(text, style)),
      maxLines: maxLines,
      overflow: overflow ?? (maxLines != null ? TextOverflow.ellipsis : null),
    );
  }
}

class ExpandableReviewText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int collapsedLines;

  const ExpandableReviewText({
    super.key,
    required this.text,
    required this.style,
    this.collapsedLines = 3,
  });

  @override
  State<ExpandableReviewText> createState() => _ExpandableReviewTextState();
}

class _ExpandableReviewTextState extends State<ExpandableReviewText> {
  bool _expanded = false;

  bool _wouldOverflow(double maxWidth, TextScaler scaler) {
    // Use plain text (no italic spans) to avoid style-stacking height artifacts.
    // Trim trailing whitespace — trailing newlines add phantom line metrics.
    final painter = TextPainter(
      text: TextSpan(
        style: widget.style,
        text: widget.text.trimRight(),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    painter.layout(maxWidth: maxWidth);
    return painter.computeLineMetrics().length > widget.collapsedLines;
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (ctx, constraints) {
      final overflows = _wouldOverflow(constraints.maxWidth, scaler);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReviewText(
            text: widget.text,
            style: widget.style,
            maxLines: _expanded ? null : widget.collapsedLines,
            overflow: _expanded ? null : TextOverflow.ellipsis,
          ),
          if (overflows) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Show less' : 'Read more',
                style: TextStyle(
                  color: _expanded ? MC.dim : MC.accent1,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}
