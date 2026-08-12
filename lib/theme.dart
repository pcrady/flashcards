import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two looks the app ships with.
///
/// [aurora] is the original polar-night design; [hacker] is a green-phosphor
/// terminal skin — black ground, monospace type, square corners, scanlines.
enum SprakSkin {
  aurora('Aurora', 'Polar night with mint and violet'),
  hacker('Hacker', 'Green phosphor terminal, scanlines and all');

  final String label;
  final String blurb;
  const SprakSkin(this.label, this.blurb);
}

/// Every color and type decision for one skin. [SprakTheme] forwards its
/// static members to the active palette, so widgets keep reading
/// `SprakTheme.inkSoft` and follow the toggle for free.
class SprakPalette {
  final SprakSkin skin;

  // Backgrounds
  final Color bg;
  final Color surface;
  final Color panel;
  final Color line;
  final Color surfaceContainer;

  // Text
  final Color ink;
  final Color inkSoft;

  // Accents
  final Color fjord; // primary
  final Color neon;
  final Color magenta;
  final Color success;
  final Color danger;
  final Color warning;
  final Color onFjord;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final List<Color> tagPalette;
  final LinearGradient gradient;

  /// Google Fonts families: [displayFamily] is the wordmark / vocabulary
  /// face, [bodyFamily] everything else.
  final String displayFamily;
  final String bodyFamily;
  final FontStyle wordmarkStyle;
  final double cardRadius;
  final double fieldRadius;

  /// Pill-shaped buttons in aurora; square-cut ones in hacker.
  final bool roundButtons;

  /// Letter spacing for button labels — the terminal skin runs wider.
  final double buttonTracking;

  /// Whether to bloom accent text and lay scanlines over the app.
  final bool crt;

  const SprakPalette({
    required this.skin,
    required this.bg,
    required this.surface,
    required this.panel,
    required this.line,
    required this.surfaceContainer,
    required this.ink,
    required this.inkSoft,
    required this.fjord,
    required this.neon,
    required this.magenta,
    required this.success,
    required this.danger,
    required this.warning,
    required this.onFjord,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tagPalette,
    required this.gradient,
    required this.displayFamily,
    required this.bodyFamily,
    required this.wordmarkStyle,
    required this.cardRadius,
    required this.fieldRadius,
    required this.roundButtons,
    required this.buttonTracking,
    required this.crt,
  });

  static const SprakPalette aurora = SprakPalette(
    skin: SprakSkin.aurora,
    bg: Color(0xFF0B101E), // midnight
    surface: Color(0xFF151C30), // cards
    panel: Color(0xFF0F1526), // chat panel, chips
    line: Color(0xFF283354), // hairline borders
    surfaceContainer: Color(0xFF1A2238),
    ink: Color(0xFFEDF1FB),
    inkSoft: Color(0xFF93A0BD),
    fjord: Color(0xFF2BE4A2), // electric mint
    neon: Color(0xFFB95CF4), // aurora violet
    magenta: Color(0xFFF0509E),
    success: Color(0xFF35E08C),
    danger: Color(0xFFFF6B7A),
    warning: Color(0xFFF5C542),
    onFjord: Color(0xFF04231A),
    secondaryContainer: Color(0xFF20304F),
    onSecondaryContainer: Color(0xFF9BEFD4),
    tagPalette: [
      Color(0xFF5AA9FF), // blue
      Color(0xFF2BE4A2), // mint
      Color(0xFFB95CF4), // violet
      Color(0xFFF0509E), // magenta
      Color(0xFFF5C542), // amber
      Color(0xFFFF8A5B), // coral
      Color(0xFF4FD8E8), // cyan
      Color(0xFFA8E05F), // lime
      Color(0xFF8E9CFF), // periwinkle
      Color(0xFFFF6B7A), // rose
    ],
    gradient: LinearGradient(
      colors: [
        Color(0xFF2BE4A2),
        Color(0xFF4EA8F5),
        Color(0xFFB95CF4),
        Color(0xFFF0509E)
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ),
    displayFamily: 'Playfair Display',
    bodyFamily: 'Nunito Sans',
    wordmarkStyle: FontStyle.italic,
    cardRadius: 18,
    fieldRadius: 12,
    roundButtons: true,
    buttonTracking: 0,
    crt: false,
  );

  /// Green-phosphor CRT. Colors are picked so that everything still clears
  /// contrast against the near-black ground: [ink] for prose, [fjord] for
  /// anything that should look energized.
  static const SprakPalette hacker = SprakPalette(
    skin: SprakSkin.hacker,
    bg: Color(0xFF030603),
    surface: Color(0xFF071108),
    panel: Color(0xFF050C05),
    line: Color(0xFF1E4426),
    surfaceContainer: Color(0xFF0B190D),
    ink: Color(0xFFBDFFCC),
    inkSoft: Color(0xFF5DB273),
    fjord: Color(0xFF00FF6A), // phosphor green
    neon: Color(0xFF00E5FF), // terminal cyan
    magenta: Color(0xFFFF2D95),
    success: Color(0xFF00FF6A),
    danger: Color(0xFFFF4040),
    warning: Color(0xFFFFB000), // amber CRT
    onFjord: Color(0xFF001A08),
    secondaryContainer: Color(0xFF0E2A16),
    onSecondaryContainer: Color(0xFF7CFFAB),
    tagPalette: [
      Color(0xFF00FF6A), // phosphor
      Color(0xFF00E5FF), // cyan
      Color(0xFFFFB000), // amber
      Color(0xFFFF2D95), // magenta
      Color(0xFF7CFF4F), // lime
      Color(0xFF4FE3C1), // teal
      Color(0xFFC6FF00), // acid
      Color(0xFFFF6B3D), // ember
      Color(0xFF59C2FF), // ice
      Color(0xFFB388FF), // violet
    ],
    gradient: LinearGradient(
      colors: [
        Color(0xFF00FF6A),
        Color(0xFF7CFF4F),
        Color(0xFF00E5FF),
        Color(0xFF00FF6A)
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ),
    // Monospace with full Cyrillic coverage — vocabulary needs it.
    displayFamily: 'JetBrains Mono',
    bodyFamily: 'JetBrains Mono',
    wordmarkStyle: FontStyle.normal,
    cardRadius: 2,
    fieldRadius: 2,
    roundButtons: false,
    buttonTracking: 1.2,
    crt: true,
  );

  static SprakPalette of(SprakSkin skin) =>
      skin == SprakSkin.hacker ? hacker : aurora;

  /// Phosphor bloom around accent text, and nothing at all in aurora.
  List<Shadow> glow(Color color, {double blur = 12}) => crt
      ? [Shadow(color: color.withValues(alpha: 0.55), blurRadius: blur)]
      : const [];
}

/// Design system for språk. Colors resolve through the active [SprakPalette],
/// which the user flips between with [setSkin].
class SprakTheme {
  static const String skinPref = 'theme_skin';

  /// Bumped whenever the skin changes so the app can rebuild.
  static final ValueNotifier<SprakSkin> skin =
      ValueNotifier<SprakSkin>(SprakSkin.aurora);

  static SprakPalette get palette => SprakPalette.of(skin.value);

  /// Restores the saved skin. Call before `runApp` to avoid a flash of the
  /// wrong theme.
  static Future<void> loadSkin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(skinPref);
      skin.value = SprakSkin.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => SprakSkin.aurora,
      );
    } catch (_) {
      // No prefs available (tests, first run) — stay on the default.
    }
  }

  static Future<void> setSkin(SprakSkin value) async {
    if (skin.value == value) return;
    skin.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(skinPref, value.name);
    } catch (_) {
      // Persisting is best-effort; the toggle still applies this session.
    }
  }

  static Future<void> toggleSkin() => setSkin(
      skin.value == SprakSkin.aurora ? SprakSkin.hacker : SprakSkin.aurora);

  // Backgrounds
  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get panel => palette.panel;
  static Color get line => palette.line;

  // Text
  static Color get ink => palette.ink;
  static Color get inkSoft => palette.inkSoft;

  // Accents
  static Color get fjord => palette.fjord;
  static Color get neon => palette.neon;
  static Color get magenta => palette.magenta;
  static Color get success => palette.success;
  static Color get danger => palette.danger;
  static Color get warning => palette.warning;
  static Color get onFjord => palette.onFjord;

  /// Label colors for tags — distinct hues that all read on the dark
  /// surfaces. Order matters: it is baked into which tag gets which color,
  /// so append rather than reorder.
  static List<Color> get tagPalette => palette.tagPalette;

  /// The color for a tag, derived from its spelling alone, so "verb" looks
  /// the same in every deck and on every machine. Case and surrounding
  /// space are ignored. Deliberately not [String.hashCode], which Dart
  /// does not promise to keep stable between runs.
  static Color tagColor(String tag) {
    var hash = 0;
    for (final unit in tag.trim().toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return tagPalette[hash % tagPalette.length];
  }

  static LinearGradient get aurora => palette.gradient;

  static TextStyle wordmark({double size = 26, Color? color}) {
    final p = palette;
    return GoogleFonts.getFont(
      p.displayFamily,
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontStyle: p.wordmarkStyle,
      letterSpacing: p.crt ? 1.5 : 0.5,
      color: color ?? p.ink,
    );
  }

  /// Display style used for vocabulary words (supports Cyrillic).
  static TextStyle vocab({double size = 40, FontWeight? weight}) {
    final p = palette;
    return GoogleFonts.getFont(
      p.displayFamily,
      fontSize: size,
      fontWeight: weight ?? FontWeight.w600,
      color: p.ink,
      shadows: p.glow(p.fjord, blur: 18),
    );
  }

  static ThemeData dark() {
    final p = palette;
    final scheme = ColorScheme.fromSeed(
      seedColor: p.fjord,
      brightness: Brightness.dark,
    ).copyWith(
      primary: p.fjord,
      onPrimary: p.onFjord,
      secondary: p.neon,
      secondaryContainer: p.secondaryContainer,
      onSecondaryContainer: p.onSecondaryContainer,
      surface: p.bg,
      onSurface: p.ink,
      surfaceContainerLowest: p.panel,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceContainer,
      outlineVariant: p.line,
      error: p.danger,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = GoogleFonts.getTextTheme(p.bodyFamily, base.textTheme).apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    );

    TextStyle display(double size, {FontWeight weight = FontWeight.w600}) =>
        GoogleFonts.getFont(
          p.displayFamily,
          fontSize: size,
          fontWeight: weight,
          color: p.ink,
          letterSpacing: p.crt ? 0.5 : null,
          shadows: p.glow(p.fjord, blur: 14),
        );

    final buttonShape = p.roundButtons
        ? const StadiumBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.fieldRadius));

    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      textTheme: text.copyWith(
        titleLarge: display(24),
        headlineSmall: display(28),
        displaySmall: display(42),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.getFont(
          p.bodyFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.ink,
          letterSpacing: p.buttonTracking,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.cardRadius),
          side: BorderSide(color: p.line),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.fjord,
          foregroundColor: p.onFjord,
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.getFont(
            p.bodyFamily,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: p.buttonTracking,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.fjord,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.fjord,
          side: BorderSide(color: p.line),
          shape: buttonShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(p.fieldRadius),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(p.fieldRadius),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(p.fieldRadius),
          borderSide: BorderSide(color: p.fjord, width: 1.6),
        ),
        hintStyle: GoogleFonts.getFont(p.bodyFamily, color: p.inkSoft),
        labelStyle: GoogleFonts.getFont(p.bodyFamily, color: p.inkSoft),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.fjord,
        foregroundColor: p.onFjord,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.roundButtons ? 16 : 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.roundButtons ? 20 : 2),
          side: BorderSide(color: p.line),
        ),
        titleTextStyle: display(24),
      ),
      iconTheme: IconThemeData(color: p.inkSoft),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.fjord),
    );
  }
}

/// Wordmark rendered with the skin's gradient. In the hacker skin it gets a
/// shell prompt and a blinking block cursor.
class AuroraWordmark extends StatelessWidget {
  final double size;
  const AuroraWordmark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final p = SprakTheme.palette;
    final label = p.crt ? 'språk' : 'Språk';
    final word = ShaderMask(
      shaderCallback: (bounds) => p.gradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        label,
        style: SprakTheme.wordmark(size: size, color: Colors.white),
      ),
    );
    if (!p.crt) return word;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('>',
            style: SprakTheme.wordmark(size: size, color: p.inkSoft)),
        SizedBox(width: size * 0.3),
        word,
        SizedBox(width: size * 0.22),
        _BlinkingCursor(size: size),
      ],
    );
  }
}

/// One-tap flip between the two skins.
class SkinToggleButton extends StatelessWidget {
  const SkinToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final hacker = SprakTheme.skin.value == SprakSkin.hacker;
    return IconButton(
      icon: Icon(hacker ? Icons.terminal : Icons.auto_awesome_outlined),
      color: hacker ? SprakTheme.fjord : null,
      tooltip: hacker ? 'Back to the Aurora theme' : 'Go full terminal',
      onPressed: SprakTheme.toggleSkin,
    );
  }
}

/// Block cursor that blinks on a one-second beat, terminal style.
class _BlinkingCursor extends StatefulWidget {
  final double size;
  const _BlinkingCursor({required this.size});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SprakTheme.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        // Hard on/off rather than a fade — CRTs did not ease.
        opacity: _controller.value < 0.5 ? 1 : 0.08,
        child: Container(
          width: widget.size * 0.5,
          height: widget.size * 0.9,
          decoration: BoxDecoration(
            color: p.fjord,
            boxShadow: [
              BoxShadow(
                  color: p.fjord.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scanlines, a green wash and a vignette laid over the whole app — only in
/// the hacker skin, and never eating pointer events.
class CrtOverlay extends StatelessWidget {
  final Widget child;
  const CrtOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = SprakTheme.palette;
    if (!p.crt) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ScanlinePainter(p.fjord)),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final Color phosphor;
  const _ScanlinePainter(this.phosphor);

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal scanlines, 3px pitch.
    final line = Paint()..color = Colors.black.withValues(alpha: 0.16);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    // Phosphor wash, brightest in the middle of the tube.
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            phosphor.withValues(alpha: 0.035),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    // Vignette.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.45),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) =>
      oldDelegate.phosphor != phosphor;
}
