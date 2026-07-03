// profile_banner.dart — Full-bleed profile header that tiles watchlist poster images with a gradient scrim overlay.
import 'package:flutter/material.dart';
import 'app_image.dart';
import '../theme.dart';

class ProfileBannerWidget extends StatelessWidget {
  final List<String> posterUrls;
  final Color avatarColor;

  const ProfileBannerWidget({
    super.key,
    required this.posterUrls,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrls.isEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  avatarColor.withAlpha(70),
                  avatarColor.withAlpha(20),
                  MC.bg0,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
              ),
            ),
          )
        else
          Row(
            children: posterUrls
                .map((url) => Expanded(
                      child: AppImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        errorWidget: (_, __, ___) =>
                            ColoredBox(color: avatarColor.withAlpha(40)),
                      ),
                    ))
                .toList(),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(60),
                  Colors.transparent,
                  MC.bg0.withAlpha(210),
                  MC.bg0,
                ],
                stops: const [0.0, 0.3, 0.75, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
