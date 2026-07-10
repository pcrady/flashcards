import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system for språk — polar-night dark theme with aurora accents:
/// deep midnight background, electric mint primary, violet-magenta highlights,
/// serif display type for vocabulary.
class SprakTheme {
  // Backgrounds
  static const Color bg = Color(0xFF0B101E); // midnight
  static const Color surface = Color(0xFF151C30); // cards
  static const Color panel = Color(0xFF0F1526); // chat panel, chips
  static const Color line = Color(0xFF283354); // hairline borders

  // Text
  static const Color ink = Color(0xFFEDF1FB);
  static const Color inkSoft = Color(0xFF93A0BD);

  // Accents
  static const Color fjord = Color(0xFF2BE4A2); // electric mint (primary)
  static const Color neon = Color(0xFFB95CF4); // aurora violet
  static const Color magenta = Color(0xFFF0509E);
  static const Color success = Color(0xFF35E08C);
  static const Color danger = Color(0xFFFF6B7A);
  static const Color onFjord = Color(0xFF04231A); // text on mint

  static const LinearGradient aurora = LinearGradient(
    colors: [fjord, Color(0xFF4EA8F5), neon, magenta],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static TextStyle wordmark({double size = 26, Color? color}) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.5,
        color: color ?? ink,
      );

  /// Serif display style used for vocabulary words (supports Cyrillic).
  static TextStyle vocab({double size = 40, FontWeight? weight}) =>
      GoogleFonts.playfairDisplay(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w600,
        color: ink,
      );

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: fjord,
      brightness: Brightness.dark,
    ).copyWith(
      primary: fjord,
      onPrimary: onFjord,
      secondary: neon,
      secondaryContainer: const Color(0xFF20304F),
      onSecondaryContainer: const Color(0xFF9BEFD4),
      surface: bg,
      onSurface: ink,
      surfaceContainerLowest: panel,
      surfaceContainerLow: surface,
      surfaceContainer: const Color(0xFF1A2238),
      outlineVariant: line,
      error: danger,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = GoogleFonts.nunitoSansTextTheme(base.textTheme).apply(
      bodyColor: ink,
      displayColor: ink,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: text.copyWith(
        titleLarge: GoogleFonts.playfairDisplay(
            fontSize: 24, fontWeight: FontWeight.w600, color: ink),
        headlineSmall: GoogleFonts.playfairDisplay(
            fontSize: 28, fontWeight: FontWeight.w600, color: ink),
        displaySmall: GoogleFonts.playfairDisplay(
            fontSize: 42, fontWeight: FontWeight.w600, color: ink),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunitoSans(
            fontSize: 18, fontWeight: FontWeight.w700, color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: line),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fjord,
          foregroundColor: onFjord,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.nunitoSans(
              fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fjord,
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: fjord, width: 1.6),
        ),
        hintStyle: GoogleFonts.nunitoSans(color: inkSoft),
        labelStyle: GoogleFonts.nunitoSans(color: inkSoft),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: fjord,
        foregroundColor: onFjord,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
        titleTextStyle: GoogleFonts.playfairDisplay(
            fontSize: 24, fontWeight: FontWeight.w600, color: ink),
      ),
      iconTheme: const IconThemeData(color: inkSoft),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: fjord),
    );
  }
}

/// Wordmark rendered with the aurora gradient.
class AuroraWordmark extends StatelessWidget {
  final double size;
  const AuroraWordmark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => SprakTheme.aurora.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text('språk',
          style: SprakTheme.wordmark(size: size, color: Colors.white)),
    );
  }
}
