// poster.dart — Movie poster widget that shows a network image or a styled typographic gradient fallback.
import 'package:flutter/material.dart';
import 'app_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models.dart';

class PosterWidget extends StatelessWidget {
  final Movie movie;
  final double width;
  final double height;
  final BoxDecoration? extraDecoration;

  const PosterWidget({
    super.key,
    required this.movie,
    this.width = 100,
    this.height = 150,
    this.extraDecoration,
  });


  @override
  Widget build(BuildContext context) {
    final imageUrl = movie.poster.imageUrl;

    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AppImage(
          imageUrl: imageUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 250),
          fadeOutDuration: Duration.zero,
          placeholder: (_, __) => _buildGradientPoster(context),
          errorWidget: (_, __, ___) => _buildGradientPoster(context),
        ),
      );
    }
    return _buildGradientPoster(context);
  }

  Widget _buildGradientPoster(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: movie.poster.gradient,
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Typographic treatment
          Positioned.fill(
            child: _buildTreatment(movie),
          ),
          // Subtle highlight
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.7),
                  radius: 0.9,
                  colors: [
                    Colors.white.withAlpha(20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreatment(Movie m) {
    final accent = m.poster.accent;
    final fontSize = (width / 9).clamp(10.0, 22.0);

    switch (m.poster.style) {
      case 'editorial':
        return Padding(
          padding: EdgeInsets.all(width * 0.1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  m.title,
                  overflow: TextOverflow.clip,
                  maxLines: 3,
                  style: GoogleFonts.playfairDisplay(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                    fontSize: fontSize * 1.3,
                    color: accent,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${m.year}',
                overflow: TextOverflow.clip,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize * 0.55,
                  color: accent.withAlpha(178),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        );

      case 'block':
        return Padding(
          padding: EdgeInsets.all(width * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title.toUpperCase(),
                overflow: TextOverflow.clip,
                maxLines: 4,
                style: TextStyle(
                  fontFamily: 'sans-serif',
                  fontWeight: FontWeight.w900,
                  fontSize: fontSize * 1.1,
                  color: accent,
                  height: 1.0,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        );

      case 'blocky':
        return Padding(
          padding: EdgeInsets.all(width * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  m.title.toUpperCase(),
                  overflow: TextOverflow.clip,
                  maxLines: 4,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize * 1.15,
                    color: accent,
                    height: 0.95,
                  ),
                ),
              ),
              Text(
                '${m.year}',
                overflow: TextOverflow.clip,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize * 0.5,
                  color: accent.withAlpha(204),
                ),
              ),
            ],
          ),
        );

      case 'epic':
        return Padding(
          padding: EdgeInsets.all(width * 0.1),
          child: Center(
            child: Text(
              m.title.toUpperCase(),
              textAlign: TextAlign.center,
              overflow: TextOverflow.clip,
              maxLines: 4,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize * 1.4,
                color: accent,
                letterSpacing: 1,
                height: 1.0,
              ),
            ),
          ),
        );

      case 'quiet':
        return Padding(
          padding: EdgeInsets.all(width * 0.12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                overflow: TextOverflow.clip,
                maxLines: 3,
                style: GoogleFonts.playfairDisplay(
                  fontSize: fontSize * 1.0,
                  color: accent,
                  height: 1.1,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );

      case 'loud':
        return Padding(
          padding: EdgeInsets.all(width * 0.06),
          child: Center(
            child: Text(
              m.title.toUpperCase(),
              textAlign: TextAlign.center,
              overflow: TextOverflow.clip,
              maxLines: 4,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: fontSize * 1.5,
                color: accent,
                height: 0.9,
                letterSpacing: -1,
              ),
            ),
          ),
        );

      case 'retro':
        return Padding(
          padding: EdgeInsets.all(width * 0.1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                overflow: TextOverflow.clip,
                maxLines: 3,
                style: GoogleFonts.playfairDisplay(
                  fontStyle: FontStyle.italic,
                  fontSize: fontSize * 1.2,
                  color: accent,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'A FILM BY ${(m.director).toUpperCase()}',
                overflow: TextOverflow.clip,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fontSize * 0.45,
                  color: accent.withAlpha(178),
                ),
              ),
            ],
          ),
        );

      case 'ominous':
        return Padding(
          padding: EdgeInsets.all(width * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                overflow: TextOverflow.clip,
                maxLines: 3,
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize * 1.1,
                  color: accent,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );

      case 'surreal':
        return Padding(
          padding: EdgeInsets.all(width * 0.08),
          child: Center(
            child: Text(
              m.title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.clip,
              maxLines: 4,
              style: GoogleFonts.playfairDisplay(
                fontStyle: FontStyle.italic,
                fontSize: fontSize * 1.3,
                color: accent,
                height: 1.0,
              ),
            ),
          ),
        );

      case 'warm':
        return Padding(
          padding: EdgeInsets.all(width * 0.1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.title,
                overflow: TextOverflow.clip,
                maxLines: 3,
                style: GoogleFonts.playfairDisplay(
                  fontStyle: FontStyle.italic,
                  fontSize: fontSize * 1.4,
                  color: accent,
                  height: 0.95,
                ),
              ),
            ],
          ),
        );

      default:
        return Padding(
          padding: EdgeInsets.all(width * 0.1),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              m.title,
              overflow: TextOverflow.clip,
              maxLines: 3,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
              ),
            ),
          ),
        );
    }
  }
}
