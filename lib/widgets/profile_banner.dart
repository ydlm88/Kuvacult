// profile_banner.dart — Feathered-seam dissolve banner (design option 4a).
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Four-poster banner: sharp tiles edge-to-edge, bottom-blur bleed,
/// page-background fade, and subtle film grain.
class DissolveBanner extends StatelessWidget {
  const DissolveBanner({super.key, required this.posterUrls, this.height = 340});
  final List<String> posterUrls;
  final double height;

  static const double _blurSigma = 12;

  @override
  Widget build(BuildContext context) {
    if (posterUrls.isEmpty) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: const ColoredBox(color: Color(0xFF0A0806)),
      );
    }

    final providers = posterUrls
        .take(4)
        .map((u) => CachedNetworkImageProvider(u) as ImageProvider)
        .toList();

    Widget posterRow() => Row(
          children: [
            for (final p in providers)
              Expanded(
                child: Image(
                  image: p,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.4),
                  height: height,
                  gaplessPlayback: true,
                ),
              ),
          ],
        );

    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            // Layer 1 — sharp posters, tiled edge-to-edge.
            posterRow(),

            // Layer 2 — blurred copy, revealed from 55 % → 85 % top-to-bottom.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black],
                stops: [0.55, 0.85],
              ).createShader(r),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                    sigmaX: _blurSigma,
                    sigmaY: _blurSigma,
                    tileMode: TileMode.decal),
                child: posterRow(),
              ),
            ),

            // Layer 3 — fade to page background.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x000A0806),
                    Color(0x000A0806),
                    Color(0x660A0806),
                    Color(0xCC0A0806),
                    Color(0xFF0A0806),
                  ],
                  stops: [0, 0.55, 0.75, 0.90, 1.0],
                ),
              ),
            ),

            // Layer 4 — right vignette so stats are always on a dark ground.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, Color(0x80000000)],
                    stops: [0.50, 1.0],
                  ),
                ),
              ),
            ),

            // Layer 5 — film grain.
            IgnorePointer(
              child: Opacity(
                opacity: 0.07,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/grain.png'),
                      repeat: ImageRepeat.repeat,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
