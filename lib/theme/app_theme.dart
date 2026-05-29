// AppTheme — builds the `ThemeData` for the WLAN Pros Toolbox.
//
// All values trace back to GL-003 §8 (App Mode / Dark Theme). The Material 3
// mapping follows §8.10. Lime primary, dark surface stack, IBM Plex Sans body,
// DM Mono numerics via `AppMonoText` extension.
//
// Dark only — there is no light variant in MVP (§8 scope rule).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_tokens.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  /// The one and only `ThemeData` for the app. Apply to `MaterialApp.theme`
  /// AND to `MaterialApp.darkTheme`; lock `themeMode: ThemeMode.dark`.
  static ThemeData dark() {
    final TextTheme textTheme = buildAppTextTheme();
    final AppMonoText monoExtension = AppMonoText.defaults();

    // §8.10 — Material 3 ColorScheme mapping.
    final ColorScheme colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.secondary, // dark text on lime
      secondary: AppColors.primary, // lime is the only accent
      onSecondary: AppColors.secondary,
      tertiary: AppColors.accent,
      onTertiary: AppColors.neutral0,
      surface: AppColors.surface0,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.surface0,
      surfaceContainerLow: AppColors.surface1,
      surfaceContainer: AppColors.surface1,
      surfaceContainerHigh: AppColors.surface2,
      surfaceContainerHighest: AppColors.surface3,
      onSurfaceVariant: AppColors.textSecondary,
      // §8.10 — `outline` carries the interactive boundary (3:1+), so it maps
      // to borderStrong. `outlineVariant` is the decorative divider.
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
      error: const Color(0xFFE04646), // §8.4 — proposed v1.1 token. See gap note.
      onError: AppColors.neutral0,
      scrim: Colors.black,
      shadow: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface0,
      canvasColor: AppColors.surface0,

      // §8.3 — disabled field/control text resolves to textDisabled (#7F7F7F),
      // not the Material 3 0.38-opacity default. On disabledFill (#2A2A2A) this
      // is 3.05:1 (passes SC 1.4.11). Closes the F-02 trap at the theme level.
      disabledColor: AppColors.textDisabled,

      textTheme: textTheme,
      primaryTextTheme: textTheme,

      extensions: <ThemeExtension<dynamic>>[
        monoExtension,
      ],

      // App bar — flat on canvas, no tonal elevation.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface0,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: const IconThemeData(
          color: AppColors.textPrimary,
          size: 24, // §8.6 — nav icon size
        ),
      ),

      // Cards — surface1, hairline border, no shadow on dark.
      cardTheme: CardThemeData(
        color: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Cards in this app are non-interactive containers — hairline border
          // is decorative. Anything tappable (tiles, rows) takes borderStrong
          // at its widget site, not here.
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      // Inputs — recessed within cards (§8.4).
      // Borders use borderStrong (#808080) per §8.4 — 3.83:1 on inputFill
      // passes SC 1.4.11.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // §8.10 / §8.3 — disabled fields must not fall through to Material 3
        // opacity defaults (that path produced the 2.13:1 F-02 failure).
        // Resolve disabled fill to disabledFill (#2A2A2A); disabled field text
        // and label resolve to textDisabled (#7F7F7F) below + via disabledColor.
        // disabledFill #2A2A2A vs textDisabled #7F7F7F = 3.05:1 (passes SC 1.4.11).
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.disabledFill;
          }
          return AppColors.inputFill;
        }),
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 12,
        ),
        // Disabled label resolves to textDisabled (#7F7F7F) on disabledFill
        // (#2A2A2A) = 3.05:1, passes SC 1.4.11. Other states keep secondary.
        labelStyle: WidgetStateTextStyle.resolveWith((states) {
          final TextStyle base =
              textTheme.labelMedium ?? const TextStyle();
          if (states.contains(WidgetState.disabled)) {
            return base.copyWith(color: AppColors.textDisabled);
          }
          return base;
        }),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.primary,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: AppColors.textTertiary),
        helperStyle: textTheme.labelSmall,
        errorStyle: textTheme.labelSmall?.copyWith(color: const Color(0xFFE04646)),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: AppColors.borderStrong, width: 1),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: AppColors.borderStrong, width: 1),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: Color(0xFFE04646), width: 1),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: Color(0xFFE04646), width: 2),
        ),
        // Disabled fields still need a perceivable boundary — keep borderStrong
        // so the field reads as "present but inactive" rather than vanishing.
        disabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: AppColors.borderStrong, width: 1),
        ),
      ),

      // Primary filled button — lime on dark text (§8.3).
      // Disabled pair = disabledFill (#2A2A2A) + textDisabled (#7F7F7F) =
      // 3.05:1 — passes SC 1.4.11. Updated 2026-05-29 to close Vera F-02.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.disabledFill;
            }
            if (states.contains(WidgetState.pressed)) return AppColors.pressed;
            if (states.contains(WidgetState.hovered)) return AppColors.accent;
            return AppColors.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textDisabled;
            }
            return AppColors.secondary;
          }),
          minimumSize: WidgetStateProperty.all(
            const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),

      // Secondary outline button — lime border, lime text (§8.3).
      // Idle border stays at --color-primary 1.5px (9.31:1 — already passes
      // SC 1.4.11; Larry's override of the §8.3 cell). Disabled border uses
      // disabledFill per the updated §8.3 disabled cell.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textDisabled;
            }
            return AppColors.primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const BorderSide(color: AppColors.disabledFill, width: 1);
            }
            return const BorderSide(color: AppColors.primary, width: 1.5);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primary.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.primary.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
          minimumSize: WidgetStateProperty.all(
            const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),

      // Tertiary text button.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textDisabled;
            }
            return AppColors.primary;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primary.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return AppColors.primary.withValues(alpha: 0.08);
            }
            return null;
          }),
          minimumSize: WidgetStateProperty.all(
            const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),

      // Dividers — §8.1 hairline.
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      iconTheme: const IconThemeData(
        color: AppColors.textPrimary,
        size: 20, // §8.6 — content icon default
      ),

      // Focus — §8.3 lime ring.
      focusColor: AppColors.primary.withValues(alpha: 0.16),
      hoverColor: AppColors.primary.withValues(alpha: 0.08),
      splashColor: AppColors.primary.withValues(alpha: 0.16),
      highlightColor: AppColors.primary.withValues(alpha: 0.08),

      // List tiles — rows on surface1.
      listTileTheme: ListTileThemeData(
        tileColor: AppColors.surface1,
        iconColor: AppColors.textPrimary,
        textColor: AppColors.textPrimary,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.labelMedium,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),

      visualDensity: VisualDensity.standard,
    );
  }
}
