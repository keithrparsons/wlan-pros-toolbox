// Typography — GL-003 §3 (type scale) and §8.5 (App-Mode usage).
//
// IBM Plex Sans is the only sans face. DM Mono is the only mono face.
// DM Mono is exposed as a ThemeExtension so calculator outputs can pull
// monospace numerics from any widget without hard-coding the family.

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// The only sans family name. Declared as a bundled font family in
/// pubspec.yaml (`flutter: fonts:`) with faces at weights 400/500/600/700,
/// so the engine selects the right face by `fontWeight` at render time —
/// no runtime fetch, fully offline.
const String _kSansFamily = 'IBM Plex Sans';

/// The numeric/code mono family. Bundled faces at 400/500.
const String _kMonoFamily = 'DM Mono';

/// The identifier mono (sans-serif) family. Bundled face at 400.
const String _kIdentifierMonoFamily = 'Roboto Mono';

/// Builds the `TextTheme` for the app using IBM Plex Sans, per §8.5.
///
/// Material 3 token mapping (Flutter conventions):
/// - display* → editorial-scale display copy (§3 — rarely used in-app)
/// - headlineLarge / Medium / Small → §3 H1 / H2 / H3
/// - bodyLarge → §3 body (16px / 1.45)
/// - bodyMedium → §3 body small variant
/// - labelLarge / Small → §3 caption + button labels
TextTheme buildAppTextTheme() {
  // Start from a fresh dark-theme TextTheme so default colors are sensible,
  // then apply IBM Plex Sans uniformly across every slot. `.apply` sets the
  // family on all 15 default styles (replacing the former
  // GoogleFonts.ibmPlexSansTextTheme(base) call) before the explicit per-slot
  // overrides below.
  final TextTheme base = ThemeData(
    brightness: Brightness.dark,
  ).textTheme.apply(fontFamily: _kSansFamily);

  return base.copyWith(
    // Display — editorial only; mapped for completeness.
    displayLarge: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.display,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: AppColors.textPrimary,
    ),

    // H1 — page-level title for very large screens.
    headlineLarge: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.h1,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: AppColors.textPrimary,
    ),

    // H2 — screen title in the app bar (§8.5).
    headlineMedium: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.h2,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: AppColors.textPrimary,
    ),

    // H3 — section heading within a screen, home grid tile titles (§8.5).
    headlineSmall: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.h3,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: AppColors.textPrimary,
    ),

    // titleMedium — used by AppBar by default in M3; align to H3.
    titleLarge: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.h3,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: AppColors.textPrimary,
    ),

    // Body — paragraphs, field input text.
    bodyLarge: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textPrimary,
    ),
    bodyMedium: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textPrimary,
    ),

    // Caption — field labels, helper text (§8.4).
    labelLarge: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: AppColors.textPrimary,
    ),
    labelMedium: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.caption,
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: AppColors.textSecondary,
    ),
    labelSmall: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.caption,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: AppColors.textTertiary,
    ),
    bodySmall: const TextStyle(
      fontFamily: _kSansFamily,
      fontSize: AppTextSize.caption,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textTertiary,
    ),
  );
}

/// Mono text theme — exposed via `Theme.of(context).extension<AppMonoText>()`.
///
/// Per GL-003 §8.5: "Numeric outputs (calculators) — DM Mono 500". Anything
/// computed (RF math, unit conversions) reads from here, not from the regular
/// `TextTheme`. Keeps decimal alignment clean and signals "computed value"
/// instead of "label".
@immutable
class AppMonoText extends ThemeExtension<AppMonoText> {
  const AppMonoText({
    required this.outputXL,
    required this.outputLarge,
    required this.outputMedium,
    required this.inlineCode,
    required this.robotoMono,
  });

  /// 36px DM Mono 500 — extra-large numeric result (e.g. hero converter value).
  final TextStyle outputXL;

  /// 28px DM Mono 500 — primary calculator output (§8.5: H2-size mono).
  final TextStyle outputLarge;

  /// 22px DM Mono 500 — secondary numeric output or H3-sized result.
  final TextStyle outputMedium;

  /// 16px DM Mono 400 — inline code / CLI fragments.
  final TextStyle inlineCode;

  /// 16px Roboto Mono 400 — body-size monospaced SANS-SERIF for fixed-width
  /// IDENTIFIERS (IP addresses, MAC addresses, subnet masks, BSSIDs, hex). Its
  /// clean terminals avoid DM Mono's flared, serif-like glyphs that read oddly
  /// in address columns. Calculator numeric outputs stay on DM Mono; this token
  /// is specifically for identifier strings (GL-003 §8.5).
  final TextStyle robotoMono;

  /// Factory that wires the mono faces from the bundled font families
  /// ('DM Mono', 'Roboto Mono') declared in pubspec.yaml. Call once at theme
  /// build. No runtime fetch — renders offline / on first launch.
  factory AppMonoText.defaults() {
    return const AppMonoText(
      outputXL: TextStyle(
        fontFamily: _kMonoFamily,
        fontSize: AppTextSize.h1,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.1,
      ),
      outputLarge: TextStyle(
        fontFamily: _kMonoFamily,
        fontSize: AppTextSize.h2,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.15,
      ),
      outputMedium: TextStyle(
        fontFamily: _kMonoFamily,
        fontSize: AppTextSize.h3,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.2,
      ),
      inlineCode: TextStyle(
        fontFamily: _kMonoFamily,
        fontSize: AppTextSize.body,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.45,
      ),
      robotoMono: TextStyle(
        fontFamily: _kIdentifierMonoFamily,
        fontSize: AppTextSize.body,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
    );
  }

  @override
  AppMonoText copyWith({
    TextStyle? outputXL,
    TextStyle? outputLarge,
    TextStyle? outputMedium,
    TextStyle? inlineCode,
    TextStyle? robotoMono,
  }) {
    return AppMonoText(
      outputXL: outputXL ?? this.outputXL,
      outputLarge: outputLarge ?? this.outputLarge,
      outputMedium: outputMedium ?? this.outputMedium,
      inlineCode: inlineCode ?? this.inlineCode,
      robotoMono: robotoMono ?? this.robotoMono,
    );
  }

  @override
  AppMonoText lerp(ThemeExtension<AppMonoText>? other, double t) {
    if (other is! AppMonoText) return this;
    return AppMonoText(
      outputXL: TextStyle.lerp(outputXL, other.outputXL, t)!,
      outputLarge: TextStyle.lerp(outputLarge, other.outputLarge, t)!,
      outputMedium: TextStyle.lerp(outputMedium, other.outputMedium, t)!,
      inlineCode: TextStyle.lerp(inlineCode, other.inlineCode, t)!,
      robotoMono: TextStyle.lerp(robotoMono, other.robotoMono, t)!,
    );
  }
}
