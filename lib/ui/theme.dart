import 'package:flutter/material.dart';

/// Colours that Material's [ColorScheme] has no slot for. Every screen reads
/// them through `context.hc`, so one place defines both light and dark mode.
@immutable
class HostColors extends ThemeExtension<HostColors> {
  const HostColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.warning,
    required this.danger,
    required this.info,
    required this.consoleBackground,
    required this.consoleText,
    required this.consoleLineNumber,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color warning;
  final Color danger;
  final Color info;
  final Color consoleBackground;
  final Color consoleText;
  final Color consoleLineNumber;

  static const dark = HostColors(
    background: Color(0xff0c1117),
    surface: Color(0xff141c25),
    surfaceAlt: Color(0xff1c2733),
    border: Color(0xff293644),
    text: Color(0xffedf4f8),
    muted: Color(0xff9baebe),
    accent: Color(0xff86edb0),
    onAccent: Color(0xff092318),
    accentSoft: Color(0xff203e33),
    warning: Color(0xffe9c46a),
    danger: Color(0xffff8a80),
    info: Color(0xff8ec5ff),
    consoleBackground: Color(0xff0a1016),
    consoleText: Color(0xffd5e6ee),
    consoleLineNumber: Color(0xff708796),
  );

  static const light = HostColors(
    background: Color(0xfff0f4f7),
    surface: Color(0xffffffff),
    surfaceAlt: Color(0xffe8eff3),
    border: Color(0xffd7e1e8),
    text: Color(0xff172b38),
    muted: Color(0xff526a7b),
    accent: Color(0xff14784b),
    onAccent: Color(0xffffffff),
    accentSoft: Color(0xffd5ecdf),
    warning: Color(0xff8a5a00),
    danger: Color(0xffb3261e),
    info: Color(0xff1b5e99),
    consoleBackground: Color(0xfff7faf8),
    consoleText: Color(0xff22362b),
    consoleLineNumber: Color(0xff9aaba1),
  );

  @override
  HostColors copyWith() => this;

  @override
  HostColors lerp(ThemeExtension<HostColors>? other, double t) {
    if (other is! HostColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return HostColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      info: mix(info, other.info),
      consoleBackground: mix(consoleBackground, other.consoleBackground),
      consoleText: mix(consoleText, other.consoleText),
      consoleLineNumber: mix(consoleLineNumber, other.consoleLineNumber),
    );
  }
}

extension HostColorsContext on BuildContext {
  HostColors get hc =>
      Theme.of(this).extension<HostColors>() ?? HostColors.dark;
}

/// Shared desktop and mobile tokens for HostCraft's control room.
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? HostColors.dark : HostColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.accent,
        onSecondary: c.onAccent,
        secondaryContainer: c.accentSoft,
        onSecondaryContainer: c.text,
        surface: c.surface,
        onSurface: c.text,
        onSurfaceVariant: c.muted,
        surfaceContainerHighest: c.surfaceAlt,
        outline: c.border,
        outlineVariant: c.border,
        error: c.danger,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  OutlineInputBorder field(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: width == 0
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Manrope',
    textTheme: ThemeData(brightness: brightness).textTheme
        .apply(bodyColor: c.text, displayColor: c.text, fontFamily: 'Manrope'),
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    splashFactory: InkRipple.splashFactory,
    extensions: [c],
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.accentSoft,
      disabledColor: c.surfaceAlt,
      labelStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c.text,
      ),
      side: BorderSide(color: c.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      showCheckmark: false,
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: field(c.border, 0),
      enabledBorder: field(c.border, 0),
      disabledBorder: field(c.border, 0),
      focusedBorder: field(c.accent, 2),
      errorBorder: field(c.danger, 1),
      focusedErrorBorder: field(c.danger, 2),
      labelStyle: TextStyle(color: c.muted),
      helperStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 0,
        minimumSize: const Size(0, 48),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        elevation: 0,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: c.border),
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        shape: shape,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accentSoft,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      selectedIconTheme: IconThemeData(color: c.accent, size: 21),
      unselectedIconTheme: IconThemeData(color: c.muted, size: 21),
      selectedLabelTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: c.accent,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: 'Manrope',
        color: c.muted,
        fontWeight: FontWeight.w500,
      ),
      elevation: 0,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.surfaceAlt,
      thumbColor: c.accent,
      overlayColor: c.accent.withValues(alpha: .12),
      trackHeight: 4,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.background),
      shape: shape,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        elevation: 0,
        backgroundColor: c.surface,
        foregroundColor: c.muted,
        selectedBackgroundColor: c.accentSoft,
        selectedForegroundColor: c.accent,
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: c.border),
      ),
    ),
  );
}
