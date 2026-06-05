// AppColorScheme — the theme-aware semantic color layer for App Mode.
//
// GL-003 §8.20.6 ("Implementation note for Felix"): an
// `AppColorScheme extends ThemeExtension<AppColorScheme>` carrying every
// semantic token as a field, with `.dark()` (§8.1–§8.13) and `.light()`
// (§8.20.1) factory constructors, plus a `BuildContext.colors` getter so call
// sites read `context.colors.statusDanger` instead of a hardcoded hex. Mirrors
// the `AppMonoText` ThemeExtension pattern in app_typography.dart — same
// registration shape, same `lerp`/`copyWith` contract.
//
// MIGRATION STRATEGY (Phase 1): the static `AppColors` class in app_tokens.dart
// stays in place and stays dark-correct, so every existing reference keeps
// compiling. This layer is introduced ALONGSIDE it. Screens migrate to
// `context.colors` incrementally; a screen still on `AppColors.*` simply renders
// the dark values in both themes until it is swept (Phase 2). The `.dark()`
// factory below reuses the exact `AppColors` constants, so a half-migrated
// screen is visually consistent in dark mode.
//
// LIGHT-MODE RULES BAKED IN (§8.20.2):
//  - Lime is FILL-ONLY on light. `primary`/`accent`/`pressed` are FILLS in both
//    themes; wherever dark used lime as a FOREGROUND (link/icon/active-label/
//    ring), call sites read `textAccent`, which is lime (#A1CC3A) in dark and
//    darkened-lime #5A7A1C in light. No call-site branching needed.
//  - The four status colors are RE-DERIVED darker for light (not inverted), and
//    each carries a light-only 12%-on-white tint fill + a flattened tint hex for
//    the §8.20.4 filled-pill chips.
//  - `onPrimary` is the dark text that sits ON the lime fill (#30302F in light
//    per §8.20.2; #1A1A1A in dark).

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Every semantic color token the app reads, theme-aware. Read it from a widget
/// via `context.colors` (see [AppColorSchemeContext]); it resolves to
/// [AppColorScheme.dark] under the dark theme and [AppColorScheme.light] under
/// the light theme automatically.
@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  const AppColorScheme({
    required this.brightness,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.inputFill,
    required this.disabledFill,
    required this.scrim,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textAccent,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.pressed,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusDanger,
    required this.statusInfo,
    required this.statusSuccessFill,
    required this.statusWarningFill,
    required this.statusDangerFill,
    required this.statusInfoFill,
  });

  /// Which brightness this scheme is. Lets a widget cheaply branch on theme
  /// where a genuinely light-only treatment is unavoidable (§8.20.3 punch
  /// overrides that have no dark counterpart), without a `Theme.of` round-trip.
  final Brightness brightness;

  /// `true` in light mode — convenience for the §8.20.3 punch branches
  /// (filled-pill chips, accent bars, lime underlines, shadow elevation).
  bool get isLight => brightness == Brightness.light;

  // ── Surface stack (§8.1 dark / §8.20.1 light) ───────────────────────────
  final Color surface0; // canvas
  final Color surface1; // cards, list rows
  final Color surface2; // sheets, dialogs
  final Color surface3; // top of stack

  // ── Borders ──────────────────────────────────────────────────────────────
  /// Decorative-only hairline (never an interactive boundary).
  final Color border;

  /// Required for interactive component boundaries (input outlines, focusable
  /// cards). Passes SC 1.4.11 on its theme's surfaces.
  final Color borderStrong;

  final Color inputFill;
  final Color disabledFill;
  final Color scrim;

  // ── Text ramp (§8.2 dark / §8.20.1 light) ──────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  /// The FOREGROUND lime. Lime #A1CC3A in dark (9.3:1), darkened-lime #5A7A1C in
  /// light (4.8:1). Use this for any link text, active-tab label, numeric
  /// emphasis, icon tint, focus/selection ring — anywhere lime would otherwise
  /// be a thin foreground. §8.20.2 rule 1.
  final Color textAccent;

  // ── Brand fills (§8.3) ─────────────────────────────────────────────────
  /// Brand lime as a FILL (button/toggle/chip background). Never a foreground on
  /// light (§8.20.2) — use [textAccent] for foreground lime.
  final Color primary;

  /// The dark text/icon that sits ON the lime [primary] fill. #1A1A1A in dark;
  /// #30302F in light (§8.20.2, 8.9:1 on lime).
  final Color onPrimary;

  /// Hover companion fill for the primary button (darker lime).
  final Color accent;

  /// Pressed companion fill for the primary button (darker still).
  final Color pressed;

  // ── Status palette — verdict colors (§8.13 dark / §8.20.1 light) ────────
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusDanger;
  final Color statusInfo;

  // ── Status TINT fills — §8.20.4 filled-pill chip backgrounds ────────────
  // The pre-flattened 12%-on-white tint behind a filled-pill status chip. In
  // LIGHT these are the §8.20.4 hexes (≈ status hue @12% over white). In DARK
  // there is no filled-pill design, so they resolve to surface2 (the dark chip
  // background the §8.13 outline chips already sit on) — a widget that always
  // reads the field renders correctly in both themes.
  final Color statusSuccessFill;
  final Color statusWarningFill;
  final Color statusDangerFill;
  final Color statusInfoFill;

  /// DARK scheme — the §8.1–§8.13 values, sourced from the existing [AppColors]
  /// constants so a half-migrated screen stays pixel-identical in dark mode.
  factory AppColorScheme.dark() {
    return const AppColorScheme(
      brightness: Brightness.dark,
      surface0: AppColors.surface0,
      surface1: AppColors.surface1,
      surface2: AppColors.surface2,
      surface3: AppColors.surface3,
      border: AppColors.border,
      borderStrong: AppColors.borderStrong,
      inputFill: AppColors.inputFill,
      disabledFill: AppColors.disabledFill,
      scrim: AppColors.scrim,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      textTertiary: AppColors.textTertiary,
      textDisabled: AppColors.textDisabled,
      textAccent: AppColors.textAccent, // lime #A1CC3A (9.3:1 on dark)
      primary: AppColors.primary,
      onPrimary: AppColors.secondary, // #1A1A1A on lime
      accent: AppColors.accent,
      pressed: AppColors.pressed,
      statusSuccess: AppColors.statusSuccess,
      statusWarning: AppColors.statusWarning,
      statusDanger: AppColors.statusDanger,
      statusInfo: AppColors.statusInfo,
      // No filled-pill design in dark — tint resolves to the dark chip surface.
      statusSuccessFill: AppColors.surface2,
      statusWarningFill: AppColors.surface2,
      statusDangerFill: AppColors.surface2,
      statusInfoFill: AppColors.surface2,
    );
  }

  /// LIGHT scheme — every §8.20.1 value, with the §8.20.2 lime split and the
  /// §8.20.4 filled-pill tints. Each value carries its computed contrast in the
  /// GL-003 §8.20.1 / §8.20.4 tables.
  factory AppColorScheme.light() {
    return const AppColorScheme(
      brightness: Brightness.light,
      // Surface: gray canvas + white cards + shadow elevation (§8.20.2).
      surface0: Color(0xFFF7F6F7), // canvas — brand light gray, not white
      surface1: Color(0xFFFFFFFF), // cards/rows — white sits ABOVE canvas
      surface2: Color(0xFFFFFFFF), // sheets/dialogs — white + shadow
      surface3: Color(0xFFFFFFFF), // top of stack — white + deeper shadow
      border: Color(0xFFE2E1E2), // decorative hairline (~1.1:1, by design)
      borderStrong: Color(0xFF666666), // 3.2:1 white / 3.0:1 canvas — PASS
      inputFill: Color(0xFFFFFFFF), // white field bounded by borderStrong
      disabledFill: Color(0xFFECEBEC),
      scrim: Color(0x66000000), // rgba(0,0,0,0.4) — lighter on light theme
      textPrimary: Color(0xFF1A1A1A), // 17.4:1 white / 16.6:1 canvas
      textSecondary: Color(0xFF4A4A4A), // 9.0:1 / 8.6:1
      textTertiary: Color(0xFF646464), // 5.7:1 / 5.5:1
      textDisabled: Color(0xFF9A9A9A), // 3.0:1 on disabledFill
      // Foreground lime substitute — darkened lime, 4.8:1 white / 4.6:1 canvas.
      textAccent: Color(0xFF5A7A1C),
      primary: Color(0xFFA2CC3A), // brand lime, FILL ONLY on light
      onPrimary: Color(0xFF30302F), // 8.9:1 dark text on the lime fill
      accent: Color(0xFF7A9E26), // hover fill (darker lime)
      pressed: Color(0xFF6B8C20), // pressed fill (darker still)
      statusSuccess: Color(0xFF1E7E45), // 5.2:1 / 5.0:1
      statusWarning: Color(0xFF8A5A00), // bronze — 6.0:1 / 5.7:1
      statusDanger: Color(0xFFC62D2D), // 5.4:1 / 5.2:1
      statusInfo: Color(0xFF1F6FA8), // 5.1:1 / 4.9:1
      // §8.20.4 filled-pill tints — the flattened 12%-on-white hexes.
      statusSuccessFill: Color(0xFFE8F2EC),
      statusWarningFill: Color(0xFFF3EDE2),
      statusDangerFill: Color(0xFFFAE9E9),
      statusInfoFill: Color(0xFFE8F1F7),
    );
  }

  @override
  AppColorScheme copyWith({
    Brightness? brightness,
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderStrong,
    Color? inputFill,
    Color? disabledFill,
    Color? scrim,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textAccent,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? pressed,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusDanger,
    Color? statusInfo,
    Color? statusSuccessFill,
    Color? statusWarningFill,
    Color? statusDangerFill,
    Color? statusInfoFill,
  }) {
    return AppColorScheme(
      brightness: brightness ?? this.brightness,
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      inputFill: inputFill ?? this.inputFill,
      disabledFill: disabledFill ?? this.disabledFill,
      scrim: scrim ?? this.scrim,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      textAccent: textAccent ?? this.textAccent,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      pressed: pressed ?? this.pressed,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusDanger: statusDanger ?? this.statusDanger,
      statusInfo: statusInfo ?? this.statusInfo,
      statusSuccessFill: statusSuccessFill ?? this.statusSuccessFill,
      statusWarningFill: statusWarningFill ?? this.statusWarningFill,
      statusDangerFill: statusDangerFill ?? this.statusDangerFill,
      statusInfoFill: statusInfoFill ?? this.statusInfoFill,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    return AppColorScheme(
      // Brightness is discrete — snap at the midpoint.
      brightness: t < 0.5 ? brightness : other.brightness,
      surface0: Color.lerp(surface0, other.surface0, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      disabledFill: Color.lerp(disabledFill, other.disabledFill, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textAccent: Color.lerp(textAccent, other.textAccent, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      pressed: Color.lerp(pressed, other.pressed, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusSuccessFill:
          Color.lerp(statusSuccessFill, other.statusSuccessFill, t)!,
      statusWarningFill:
          Color.lerp(statusWarningFill, other.statusWarningFill, t)!,
      statusDangerFill:
          Color.lerp(statusDangerFill, other.statusDangerFill, t)!,
      statusInfoFill: Color.lerp(statusInfoFill, other.statusInfoFill, t)!,
    );
  }
}

/// Theme-independent verdict tone for const data tables. Reference screens store
/// a [StatusTone] (not a baked Color, which would be dark-only and break under
/// light) and resolve it to the §8.13 / §8.20.1 status color at render via
/// [AppColorScheme.statusToneColor].
enum StatusTone { danger, warning, success, info }

extension StatusToneResolver on AppColorScheme {
  /// Resolves a [StatusTone] to this scheme's theme-aware status color.
  Color statusToneColor(StatusTone tone) {
    switch (tone) {
      case StatusTone.danger:
        return statusDanger;
      case StatusTone.warning:
        return statusWarning;
      case StatusTone.success:
        return statusSuccess;
      case StatusTone.info:
        return statusInfo;
    }
  }
}

/// `context.colors` — the canonical accessor (§8.20.6). Resolves the registered
/// [AppColorScheme] extension off the active theme. Falls back to the dark
/// scheme if (somehow) unregistered, so a widget can never throw on a missing
/// extension during a migration.
extension AppColorSchemeContext on BuildContext {
  AppColorScheme get colors =>
      Theme.of(this).extension<AppColorScheme>() ?? AppColorScheme.dark();
}
