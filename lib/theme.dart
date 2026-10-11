import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MC {
  static const Color bg0 = Color(0xFF0A0806);
  static const Color bg1 = Color(0xFF141010);
  static const Color bg2 = Color(0xFF1F1814);

  //Text
  static const Color ink = Color(0xFFF4ECDE);
  static const Color mute = Color(0x8CF4ECDE); 
  static const Color dim = Color(0x4DF4ECDE);  
  static const Color line = Color(0x14F4ECDE); 

  //Kuvacult accent
  static const Color accent1 = Color(0xFFF6C453);
  static const Color accent2 = Color(0xFFE8A93A);
  static const Color accentInk = Color(0xFF1A1206);

  static const Color kuvacultScore = Color.fromARGB(255, 211, 89, 44);
  static const Color kuvacultScoreInk = Color(0xFF061A1B);
}

class MT {
  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: MC.bg0,
        colorScheme: const ColorScheme.dark(
          surface: MC.bg1,
          primary: MC.accent1,
          onPrimary: MC.accentInk,
          onSurface: MC.ink,
        ),
        textTheme: TextTheme(
          displayLarge: GoogleFonts.newsreader(
            color: MC.ink,
            fontWeight: FontWeight.w400,
            fontSize: 40,
            letterSpacing: -0.5,
            height: 1.0,
          ),
          displayMedium: GoogleFonts.newsreader(
            color: MC.ink,
            fontWeight: FontWeight.w400,
            fontSize: 34,
            letterSpacing: -0.5,
            height: 1.0,
          ),
          displaySmall: GoogleFonts.newsreader(
            color: MC.ink,
            fontWeight: FontWeight.w400,
            fontSize: 26,
            letterSpacing: -0.3,
            height: 1.0,
          ),
          headlineMedium: GoogleFonts.newsreader(
            color: MC.ink,
            fontWeight: FontWeight.w400,
            fontSize: 22,
            letterSpacing: -0.3,
          ),
          titleLarge: const TextStyle(
            color: MC.ink,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: -0.2,
          ),
          bodyLarge: const TextStyle(
            color: MC.ink,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
          bodyMedium: const TextStyle(
            color: MC.ink,
            fontSize: 14,
            height: 1.55,
          ),
          bodySmall: const TextStyle(
            color: MC.mute,
            fontSize: 12,
          ),
          labelSmall: TextStyle(
            fontFamily: GoogleFonts.martianMono().fontFamily,
            color: MC.dim,
            fontSize: 10,
            letterSpacing: 2.0,
          ),
        ),
        useMaterial3: true,
      );

  // Instrument Serif display helper
  static TextStyle display({
    double size = 34,
    Color? color,
    bool italic = false,
    double letterSpacing = -0.5,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      GoogleFonts.newsreader(
        fontSize: size,
        color: color ?? MC.ink,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: letterSpacing,
        fontWeight: weight,
        height: height ?? 1.0,
      );

  //Monospace helper
  static TextStyle mono({
    double size = 10,
    Color? color,
    double letterSpacing = 2.0,
    FontWeight weight = FontWeight.normal,
  }) =>
      TextStyle(
        fontFamily: GoogleFonts.martianMono().fontFamily,
        fontSize: size,
        color: color ?? MC.dim,
        letterSpacing: letterSpacing,
        fontWeight: weight,
      );
}
