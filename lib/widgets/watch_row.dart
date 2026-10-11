// watch_row.dart — List-row widget showing a movie's poster, metadata, streaming badge, and social signals.
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
  final int? position;

  const WatchRow({super.key, required this.movie, this.onTap, this.position});

  @override
  Widget build(BuildContext context) {
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
            Stack(
              children: [
                PosterWidget(movie: movie, width: 76, height: 114),
                if (position != null)
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      decoration: BoxDecoration(
                        color: const Color(0xD90B0A09),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: const Color(0xFF3A332C), width: 1),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      child: Text(
                        '$position',
                        style: MT.mono(size: 10, weight: FontWeight.w500, color: MC.ink, letterSpacing: 0),
                      ),
                    ),
                  ),
              ],
            ),
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
