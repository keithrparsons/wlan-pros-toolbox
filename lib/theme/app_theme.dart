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

  /// §8.3 keyboard focus ring — a 2px solid primary (lime) border drawn on
  /// `WidgetState.focused`. This is the same lime focus treatment the input
  /// `focusedBorder` already uses (§8.4), now applied app-wide to every
  /// FilledButton, OutlinedButton, TextButton, and ChoiceChip/FilterChip via the
  /// shared theme below — so keyboard focus is a visible lime ring, not
  /// Material's default low-contrast `focusColor` overlay.
  ///
  /// Contrast: primary #A2CC3A measures 9.31:1 on surface0 (#1A1A1A), 8.59:1 on
  /// surface1 (#222222), and 7.36:1 on surface2 (#2A2A2A) — every dark surface a
  /// button or chip sits on clears the SC 1.4.11 / §8.11 3:1 non-text floor with
  /// wide margin. (Computed per §8.12; spot-checked WebAIM.)
  static const BorderSide _focusRingSide =
      BorderSide(color: AppColors.primary, width: 2);

  /// Shared chip border resolver — drop into a `ChoiceChip`/`FilterChip`'s
  /// `side:` so every chip in the app carries the same §8.3 treatment:
  ///
  ///  - **focused** (keyboard): 2px solid primary (lime) ring — same ring as
  ///    buttons and the input focusedBorder. 7.36–9.31:1 on the dark surface
  ///    stack, clears SC 1.4.11.
  ///  - **disabled**: 1px disabledFill border (recedes, stays perceivable).
  ///  - **selected**: 1px primary border (matches the lime fill).
  ///  - **idle/unselected**: 1px borderStrong (#808080) — the §8.1 interactive
  ///    boundary, 3.63:1 on surface2, passes SC 1.4.11.
  ///
  /// Centralising this here removes the per-screen `selected ? primary :
  /// borderStrong` ternary and guarantees the focus ring is never dropped.
  static WidgetStateBorderSide chipSide() {
    return WidgetStateBorderSide.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.focused)) return _focusRingSide;
      if (states.contains(WidgetState.disabled)) {
        return const BorderSide(color: AppColors.disabledFill, width: 1);
      }
      if (states.contains(WidgetState.selected)) {
        return const BorderSide(color: AppColors.primary, width: 1);
      }
      return const BorderSide(color: AppColors.borderStrong, width: 1);
    });
  }

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
      // §8.4 / §8.13 — the input error color resolves to the published status
      // palette danger token (#F26E6E). Replaces the retired v1.1 #E04646,
      // which never passed normal-text AA. As a 2px border it clears SC 1.4.11
      // comfortably; paired with a text error message, never color-only.
      error: AppColors.statusDanger,
      onError: AppColors.secondary,
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
        errorStyle: textTheme.labelSmall?.copyWith(color: AppColors.statusDanger),
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
        // §8.4 — error border is statusDanger (#F26E6E) at 2px, paired with a
        // text error message (§8.13 rule 2). 2px clears SC 1.4.11.
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: AppColors.statusDanger, width: 2),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: AppColors.statusDanger, width: 2),
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
          // §8.3 — keyboard focus shows the 2px lime ring; idle/hover/pressed
          // carry no border (the fill is the affordance).
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return _focusRingSide;
            return null;
          }),
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
            // §8.3 — keyboard focus thickens the lime border to the 2px focus
            // ring so focus is distinguishable from the 1.5px idle outline.
            if (states.contains(WidgetState.focused)) return _focusRingSide;
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
          // §8.3 — keyboard focus shows the 2px lime ring on the otherwise
          // borderless text button.
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) return _focusRingSide;
            return null;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),

      // Chips (ChoiceChip / FilterChip) — §8.3.
      // Selected = lime fill / dark text; unselected = surface2 / secondary
      // text. The §8.3 focus ring is applied through the per-chip `side`
      // resolver (`AppTheme.chipSide()`) at each chip's widget site, because
      // a chip's own `side` takes precedence over this theme `side` (Flutter
      // RawChip._getShape resolves `widget.side` before `chipTheme.side`). The
      // theme defaults below cover fills, radius, label, and any chip that does
      // NOT pass its own side.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.disabledFill,
        side: chipSide(),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.secondary,
          fontWeight: FontWeight.w500,
        ),
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        // Note: ChipThemeData exposes no materialTapTargetSize — each chip sets
        // MaterialTapTargetSize.padded at its widget site to hold the §8.3 48dp
        // hit region.
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

      // Focus — §8.3 lime ring. The ring (a 2px solid primary border resolved
      // on WidgetState.focused in each button/chip theme above) is the sole
      // keyboard-focus indicator, replacing Material's default low-contrast
      // focusColor overlay that Vera flagged. Keep focusColor transparent so the
      // ring isn't muddied by an overlay fill.
      focusColor: Colors.transparent,
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
