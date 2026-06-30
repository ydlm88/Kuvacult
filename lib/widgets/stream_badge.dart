import 'package:flutter/material.dart';
import '../stream_constants.dart';

enum BadgeSize { sm, md }

class StreamBadgeWidget extends StatelessWidget {
  final String streamId;
  final BadgeSize badgeSize;

  const StreamBadgeWidget({
    super.key,
    required this.streamId,
    this.badgeSize = BadgeSize.sm,
  });

  @override
  Widget build(BuildContext context) {
    final service = kStreams[streamId];
    if (service == null) return const SizedBox.shrink();

    final height = badgeSize == BadgeSize.sm ? 16.0 : 22.0;
    final fontSize = badgeSize == BadgeSize.sm ? 9.0 : 11.0;

    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: service.bg,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.center,
      child: Text(
        service.abbr,
        style: TextStyle(
          color: service.fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          height: 1,
        ),
      ),
    );
  }
}
