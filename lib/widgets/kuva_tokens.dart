// Kuvacult design tokens — colours and base text styles.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Kuva {
  // Core palette
  static const Color amber    = Color(0xFFE8A13C);
  static const Color ink      = Color(0xFFF3E4CF);
  static const Color chalk    = Color(0xFFE3BE5E);
  static const Color wax      = Color(0xFFF4F0E4);
  static const Color wick     = Color(0xFF2C2318);
  static const Color flameFill = Color(0xFFE9C468);
  static const Color flameLine = Color(0xFFD8A93F);
  static const Color onAmber  = Color(0xFF1B1210);

  // Text styles — MartianMono for all labels/buttons
  static TextStyle get liveLabel => TextStyle(
    fontFamily: GoogleFonts.martianMono().fontFamily,
    fontSize: 9,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w500,
  );

  static TextStyle get hint => TextStyle(
    fontFamily: GoogleFonts.martianMono().fontFamily,
    fontSize: 9,
    letterSpacing: 1.2,
    color: ink.withValues(alpha: 0.5),
  );
}
