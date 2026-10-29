import 'package:flutter/material.dart';

abstract final class AppColors {
  static const canvas = Color(0xFFF7F5EF);
  static const surface = Color(0xFFFFFDF9);
  static const sidebar = Color(0xFFEEEBE3);
  static const text = Color(0xFF292D25);
  static const muted = Color(0xFF62665D);
  static const accent = Color(0xFF536445);
  static const selected = Color(0xFFE4EAD9);
  static const border = Color(0xFFDEDCD3);
  static const input = Color(0xFF858A7D);
  static const warning = Color(0xFF8F562C);
  static const danger = Color(0xFFA44035);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color canvas, surface, sidebar, accent, selected, border, input;
  const AppPalette({
    this.canvas = AppColors.canvas,
    this.surface = AppColors.surface,
    this.sidebar = AppColors.sidebar,
    this.accent = AppColors.accent,
    this.selected = AppColors.selected,
    this.border = AppColors.border,
    this.input = AppColors.input,
  });

  factory AppPalette.fromSeed(int value) {
    if (value == 0xff536445) return const AppPalette();
    final base = HSLColor.fromColor(Color(value));
    final s = base.saturation.clamp(.12, .40);
    Color tone(double saturation, double lightness) =>
        HSLColor.fromAHSL(1, base.hue, saturation, lightness).toColor();
    var light = base.lightness.clamp(.38, .56);
    var accent = tone(s, light);
    final selected = tone(s * .65, .91);
    while ((contrastRatio(accent, Colors.white) < 4.6 ||
            contrastRatio(accent, selected) < 4.6) &&
        light > .25) {
      light -= .005;
      accent = tone(s, light);
    }
    return AppPalette(
      accent: accent,
      selected: selected,
      canvas: tone(s * .30, .967),
      surface: tone(s * .20, .991),
      sidebar: tone(s * .40, .935),
      border: tone(s * .25, .857),
      input: tone(s * .30, .51),
    );
  }
  @override
  AppPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? sidebar,
    Color? accent,
    Color? selected,
    Color? border,
    Color? input,
  }) => AppPalette(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    sidebar: sidebar ?? this.sidebar,
    accent: accent ?? this.accent,
    selected: selected ?? this.selected,
    border: border ?? this.border,
    input: input ?? this.input,
  );
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      border: Color.lerp(border, other.border, t)!,
      input: Color.lerp(input, other.input, t)!,
    );
  }
}

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

extension AppPaletteContext on BuildContext {
  AppPalette get appColors =>
      Theme.of(this).extension<AppPalette>() ?? const AppPalette();
}

ThemeData appTheme([int seed = 0xff536445]) {
  final colors = AppPalette.fromSeed(seed);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: colors.accent,
        onPrimary: Colors.white,
        surface: colors.surface,
        onSurface: AppColors.text,
        onSurfaceVariant: AppColors.muted,
        outline: colors.input,
        outlineVariant: colors.border,
        error: AppColors.danger,
        secondaryContainer: colors.selected,
        onSecondaryContainer: colors.accent,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.canvas,
    extensions: [colors],
    fontFamily: 'NotoSansSC',
    fontFamilyFallback: const ['Microsoft YaHei', 'PingFang SC', 'sans-serif'],
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      bodySmall: TextStyle(fontSize: 12, height: 1.45, color: AppColors.muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    dividerTheme: DividerThemeData(
      color: colors.border,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(80, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(72, 40),
        side: BorderSide(color: colors.input),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}
