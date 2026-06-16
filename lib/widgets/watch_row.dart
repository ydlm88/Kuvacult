import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'poster.dart';
import 'avatar.dart';
import 'stream_badge.dart';
import 'tag.dart';

class WatchRow extends StatelessWidget {
  final Movie movie;
  final VoidCallback? onTap;

  const WatchRow({super.key, required this.movie, this.onTap});

  @override
  Widget build(BuildContext context) {
    final reactionCount = movie.reactions.length;
    final starValues = movie.stars.values.toList();
    final avg = starValues.isEmpty
        ? null
        : (starValues.reduce((a, b) => a + b) / starValues.length)
            .toStringAsFixed(1);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PosterWidget(movie: movie, width: 76, height: 114),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${movie.year} · ${movie.runtime}m',
                      style: MT.mono(size: 10, letterSpacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      movie.title,
                      style: MT.display(size: 19, letterSpacing: -0.3, height: 1.1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      movie.director,
                      style: const TextStyle(fontSize: 12, color: MC.mute),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: movie.genres
                          .take(2)
                          .map((g) => TagWidget(label: g))
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        StreamBadgeWidget(streamId: movie.streamId),
                        const SizedBox(width: 8),
                        Text(
                          '★ ${movie.rating}',
                          style: MT.mono(size: 11, color: MC.accent1, letterSpacing: 0.5),
                        ),
                        const Spacer(),
                        AvatarWidget(memberId: movie.addedBy, size: 18),
                        if (reactionCount > 0) ...[
                          const SizedBox(width: 6),
                          Row(
                            children: [
                              const Text('●', style: TextStyle(color: MC.accent1, fontSize: 8)),
                              const SizedBox(width: 2),
                              Text('$reactionCount',
                                  style: MT.mono(size: 10, color: MC.mute, letterSpacing: 0)),
                            ],
                          ),
                        ],
                        if (avg != null) ...[
                          const SizedBox(width: 6),
                          Text(avg, style: MT.mono(size: 11, color: MC.mute, letterSpacing: 0)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
