import 'package:flutter/material.dart';

/// Design system: Material 3 + soft UI.
/// Radius kartu 24, tombol 16, chip 12; jarak kelipatan 8;
/// satu bayangan halus di mode terang, garis tepi tipis di mode gelap.
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF7B8BFF);

  // Warna aksen per fitur
  static const downloaderColor = Color(0xFFFF7A59);
  static const readerColor = Color(0xFF4F8DF7);
  static const scannerColor = Color(0xFF2EBD85);

  static const radiusCard = 24.0;
  static const radiusButton = 16.0;
  static const radiusChip = 12.0;

  static const _lightBg = Color(0xFFF4F5FA);
  static const _darkBg = Color(0xFF12151F);
  static const _darkSurface = Color(0xFF1B1F2D);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: b).copyWith(
      surface: isDark ? _darkSurface : Colors.white,
      surfaceContainerLowest: isDark ? _darkBg : _lightBg,
      outlineVariant:
          isDark ? const Color(0xFF2A3045) : const Color(0xFFE6E8F0),
    );
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? _darkBg : _lightBg,
      dividerColor: scheme.outlineVariant,
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .englishLike
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            headlineSmall: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
            titleMedium:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? _darkBg : _lightBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: textPrimary),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardTheme(
        color: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: isDark
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF222838) : _lightBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusButton),
          borderSide: const BorderSide(color: seed, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
            color: isDark ? const Color(0xFF6B7394) : const Color(0xFF9B9FAD)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton)),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: seed),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusChip)),
      ),
    );
  }

  /// Satu bayangan halus (mode terang) — mode gelap memakai border.
  static List<BoxShadow> softShadow(BuildContext context, {Color? tint}) {
    if (Theme.of(context).brightness == Brightness.dark) return const [];
    return [
      BoxShadow(
        color: (tint ?? Colors.black).withOpacity(tint == null ? 0.06 : 0.12),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];
  }
}

/// Kartu soft UI: sudut bulat 24, bayangan halus, mengecil sedikit saat
/// ditekan (efek "empuk").
class SoftCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final Color? shadowTint;

  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.gradient,
    this.shadowTint,
  });

  @override
  State<SoftCard> createState() => _SoftCardState();
}

class _SoftCardState extends State<SoftCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap != null && _pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.gradient == null
                ? (widget.color ?? scheme.surface)
                : null,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: isDark && widget.gradient == null
                ? Border.all(color: scheme.outlineVariant)
                : null,
            boxShadow: AppTheme.softShadow(context, tint: widget.shadowTint),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
