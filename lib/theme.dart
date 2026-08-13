import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Palette mirrors the Tailwind @theme block in index.css.
const Color kPaper = Color(0xFFF9F9F7);
const Color kSurface = Color(0xFFFFFFFF);
const Color kInk = Color(0xFF111111);
const Color kInkMuted = Color(0xFF666666);
const Color kBorder = Color(0xFFE0E0DC);
const Color kBorderDark = Color(0xFF111111);

// Tailwind grays used across the JSX components.
const Color kGray50 = Color(0xFFF9FAFB);
const Color kGray100 = Color(0xFFF3F4F6);
const Color kGray200 = Color(0xFFE5E7EB);
const Color kGray300 = Color(0xFFD1D5DB);
const Color kGray400 = Color(0xFF9CA3AF);
const Color kGray500 = Color(0xFF6B7280);

// Stock / availability accent (available quantities).
const Color kGreen = Color(0xFF2E7D32);

// Unavailability accent (out-of-stock materials).
const Color kRed = Color(0xFFB71C1C);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: kPaper,
    colorScheme: const ColorScheme.light(
      primary: kInk,
      onPrimary: kSurface,
      surface: kSurface,
      onSurface: kInk,
      outline: kBorderDark,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.workSansTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.workSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5, // tracking-tight
        color: kInk,
      ),
      titleMedium: GoogleFonts.workSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: kInk,
      ),
      bodyMedium: GoogleFonts.workSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: kInk,
      ),
      bodySmall: GoogleFonts.workSans(
        fontSize: 12,
        color: kInkMuted,
      ),
    ),
  );
}

/// Mono-styled text (IBM Plex Mono). Callers opt into wide tracking
/// (`tracking-widest`) where the JSX used it; the default stays normal.
TextStyle monoStyle({
  double size = 10,
  FontWeight weight = FontWeight.w400,
  Color color = kInkMuted,
  double letterSpacing = 0,
}) {
  return GoogleFonts.ibmPlexMono(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
  );
}
