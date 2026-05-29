// Typography — GL-003 §3 (type scale) and §8.5 (App-Mode usage).
//
// IBM Plex Sans is the only sans face. DM Mono is the only mono face.
// DM Mono is exposed as a ThemeExtension so calculator outputs can pull
// monospace numerics from any widget without hard-coding the family.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

/// Builds the `TextTheme` for the app using IBM Plex Sans, per §8.5.
///
/// Material 3 token mapping (Flutter conventions):
/// - display* → editorial-scale display copy (§3 — rarely used in-app)
/// - headlineLarge / Medium / Small → §3 H1 / H2 / H3
/// - bodyLarge → §3 body (16px / 1.6)
/// - bodyMedium → §3 body small variant
/// - labelLarge / Small → §3 caption + button labels
TextTheme buildAppTextTheme() {
  // Start from a fresh dark-theme TextTheme so default colors are sensible,
  // then apply IBM Plex Sans uniformly.
  final TextTheme base = ThemeData(brightness: Brightness.dark).textTheme;

  return GoogleFonts.ibmPlexSansTextTheme(base).copyWith(
    // Display — editorial only; mapped for completeness.
    displayLarge: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.display,
      fontWeight: FontWeight.w700,
      height: 1.1,
      color: AppColors.textPrimary,
    ),

    // H1 — page-level title for very large screens.
    headlineLarge: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.h1,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: AppColors.textPrimary,
    ),

    // H2 — screen title in the app bar (§8.5).
    headlineMedium: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.h2,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: AppColors.textPrimary,
    ),

    // H3 — section heading within a screen, home grid tile titles (§8.5).
    headlineSmall: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.h3,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: AppColors.textPrimary,
    ),

    // titleMedium — used by AppBar by default in M3; align to H3.
    titleLarge: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.h3,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: AppColors.textPrimary,
    ),

    // Body — paragraphs, field input text.
    bodyLarge: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: AppColors.textPrimary,
    ),
    bodyMedium: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: AppColors.textPrimary,
    ),

    // Caption — field labels, helper text (§8.4).
    labelLarge: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.body,
      fontWeight: FontWeight.w500,
      height: 1.5,
      color: AppColors.textPrimary,
    ),
    labelMedium: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.caption,
      fontWeight: FontWeight.w500,
      height: 1.5,
      color: AppColors.textSecondary,
    ),
    labelSmall: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.caption,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: AppColors.textTertiary,
    ),
    bodySmall: GoogleFonts.ibmPlexSans(
      fontSize: AppTextSize.caption,
      fontWeight: FontWeight.w400,
      height: 1.5,
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
  });

  /// 36px DM Mono 500 — extra-large numeric result (e.g. hero converter value).
  final TextStyle outputXL;

  /// 28px DM Mono 500 — primary calculator output (§8.5: H2-size mono).
  final TextStyle outputLarge;

  /// 22px DM Mono 500 — secondary numeric output or H3-sized result.
  final TextStyle outputMedium;

  /// 16px DM Mono 400 — inline code / CLI fragments.
  final TextStyle inlineCode;

  /// Factory that wires DM Mono via `google_fonts`. Call once at theme build.
  factory AppMonoText.defaults() {
    return AppMonoText(
      outputXL: GoogleFonts.dmMono(
        fontSize: AppTextSize.h1,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.2,
      ),
      outputLarge: GoogleFonts.dmMono(
        fontSize: AppTextSize.h2,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      outputMedium: GoogleFonts.dmMono(
        fontSize: AppTextSize.h3,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.4,
      ),
      inlineCode: GoogleFonts.dmMono(
        fontSize: AppTextSize.body,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.6,
      ),
    );
  }

  @override
  AppMonoText copyWith({
    TextStyle? outputXL,
    TextStyle? outputLarge,
    TextStyle? outputMedium,
    TextStyle? inlineCode,
  }) {
    return AppMonoText(
      outputXL: outputXL ?? this.outputXL,
      outputLarge: outputLarge ?? this.outputLarge,
      outputMedium: outputMedium ?? this.outputMedium,
      inlineCode: inlineCode ?? this.inlineCode,
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
    );
  }
}
