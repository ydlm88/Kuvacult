// Kuvacult design tokens — colours and base text styles.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Kuva {
  // Surfaces
  static const Color bg    = Color(0xFF080707);
  static const Color panel = Color(0xFF100F0E);
  static const Color card  = Color(0xFF121010);
  static const Color row   = Color(0xFF131211);

  // Amber
  static const Color amber      = Color(0xFFE8A13C);
  static const Color amberHover = Color(0xFFF2B257);
  static const Color chalk      = Color(0xFFE3BE5E);
  static const Color flameFill  = Color(0xFFE9C468);
  static const Color flameLine  = Color(0xFFD8A93F);
  static const Color flameCore  = Color(0xFFFFF8E4);
  static const Color cardBorder = Color(0x47E8A13C);
  static const Color buttonBorder = Color(0x66E8A13C);
  static const Color onAmber    = Color(0xFF1B1210);

  // Wax / candle
  static const Color wax  = Color(0xFFF4F0E4);
  static const Color waxHi = Color(0xFFF8F5EC);
  static const Color wick = Color(0xFF2C2318);

  // Text
  static const Color ink       = Color(0xFFF3E4CF);
  static const Color inkBright = Color(0xFFF7ECDC);
  static Color ink62 = ink.withValues(alpha: 0.62);
  static Color ink55 = ink.withValues(alpha: 0.55);
  static Color ink42 = ink.withValues(alpha: 0.66);
  static Color ink35 = ink.withValues(alpha: 0.62);

  // Live / status
  static const Color liveDot  = Color(0xFF4ADE80);
  static const Color liveText = Color(0xFF7FE0A0);

  // Radii
  static const double rCard   = 18.0;
  static const double rRow    = 12.0;
  static const double rButton = 10.0;

  // Font family helpers — use the app's registered faces.
  static String get _display => GoogleFonts.newsreader().fontFamily!;
  static String get _mono    => GoogleFonts.martianMono().fontFamily!;

  // Text styles
  static TextStyle get liveLabel => TextStyle(
    fontFamily: _mono, fontSize: 9, letterSpacing: 1.8,
    fontWeight: FontWeight.w500, color: liveText,
  );

  static TextStyle get hint => TextStyle(
    fontFamily: _mono, fontSize: 9, letterSpacing: 1.2, color: ink.withValues(alpha: 0.5),
  );

  static TextStyle get eyebrow => TextStyle(
    fontFamily: _mono, fontSize: 10, letterSpacing: 3.0,
    color: ink42,
  );

  static TextStyle get subtitle => TextStyle(
    fontFamily: _mono, fontSize: 11, height: 1.6, color: ink55,
  );

  static const TextStyle buttonLabel = TextStyle(
    fontFamily: 'Martian Mono', fontSize: 11, letterSpacing: 1.98, color: onAmber,
  );

  static TextStyle get title => TextStyle(
    fontFamily: _display, fontSize: 27, height: 1.1, color: ink,
  );

  static TextStyle get hero => TextStyle(
    fontFamily: _display, fontSize: 46, height: 1.0, color: inkBright,
  );

  static TextStyle get panelTitle => TextStyle(
    fontFamily: _display, fontSize: 30, height: 1.1, color: inkBright,
  );
}
