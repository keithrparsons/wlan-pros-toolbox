// AppTheme — builds the `ThemeData` for the WLAN Pros Toolbox.
//
// Two parallel themes (GL-003 §8 Dark / §8.20 Light), built from one shared
// `_build()` so they never drift on structure. Dark is the brand default; light
// is the opt-in §8.20 theme selected via the §8.20.5 toggle (ThemeController).
//
//   AppTheme.dark()  → §8.1–§8.13 dark surface stack, lime primary.
//   AppTheme.light() → §8.20.1 light token table + §8.20.3 punch overrides
//                      (heavier weights, 1.5/2.5/3px strokes, shadows ON).
//
// Both register the `AppColorScheme` ThemeExtension (.dark()/.light()) so a
// widget reading `context.colors.*` resolves the right value per theme with no
// call-site branching. The static `AppColors` class stays in place and stays
// dark-correct (§8.20.6 migration strategy); a screen still on `AppColors.*`
// renders dark values in both themes until it is swept.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_color_scheme.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  /// §8.3 keyboard focus ring color — lime in dark (#A1CC3A, 9.3:1), and the
  /// darkened-lime foreground substitute #5A7A1C in light (§8.20.2 / §8.20.3-B:
  /// brand lime fails as a thin foreground on white, so the ring goes darker).
  static const Color _focusRingDark = AppColors.primary;
  static const Color _focusRingLight = Color(0xFF5A7A1C);

  /// §8.3 / §8.20.3-B focus-ring width. Dark = 2px (lime at 9.3:1 already pops);
  /// light = 3px (the darkened-lime ring sits at 4.8:1, half the dark margin, so
  /// it needs the extra px to read at distance — 3px is the §8.20.3-B punch
  /// ceiling, never exceeded).
  static double _focusRingWidth(Brightness b) =>
      b == Brightness.light ? 3 : 2;

  static BorderSide _focusRingSide(Brightness b) => BorderSide(
        color: b == Brightness.light ? _focusRingLight : _focusRingDark,
        width: _focusRingWidth(b),
      );

  /// Shared chip border resolver, brightness-aware. Drops into a
  /// `ChoiceChip`/`FilterChip`'s `side:` so every chip carries the §8.3 / §8.20.3
  /// treatment: focused → the focus ring; disabled → disabledFill; selected →
  /// the primary/foreground-accent boundary; idle → borderStrong.
  static WidgetStateBorderSide chipSide([Brightness b = Brightness.dark]) {
    final AppColorScheme c =
        b == Brightness.light ? AppColorScheme.light() : AppColorScheme.dark();
    final bool light = b == Brightness.light;
    return WidgetStateBorderSide.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.focused)) return _focusRingSide(b);
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: c.disabledFill, width: light ? 1.5 : 1);
      }
      if (states.contains(WidgetState.selected)) {
        // Selected chip carries the lime fill; the boundary matches it (lime in
        // dark, darkened-lime foreground in light per §8.20.2).
        return BorderSide(
          color: light ? c.textAccent : c.primary,
          width: light ? 2 : 1,
        );
      }
      return BorderSide(color: c.borderStrong, width: light ? 1.5 : 1);
    });
  }

  /// The dark theme — §8.1–§8.13. Apply to `MaterialApp.darkTheme`.
  static ThemeData dark() => _build(Brightness.dark);

  /// The light theme — §8.20. Apply to `MaterialApp.theme`.
  static ThemeData light() => _build(Brightness.light);

  /// Builds the `ThemeData` for the given [brightness]. One body, two themes —
  /// the §8.20.3 light punch (heavier weights, thicker strokes, shadows ON) is
  /// applied through the `light` branches below; structure is shared so the two
  /// themes never drift.
  static ThemeData _build(Brightness brightness) {
    final bool light = brightness == Brightness.light;
    final AppColorScheme c =
        light ? AppColorScheme.light() : AppColorScheme.dark();
    final TextTheme textTheme = buildAppTextTheme(brightness);
    final AppMonoText monoExtension = AppMonoText.defaults(brightness);

    // §8.20.3-B border widths. Light biases thicker (read-at-distance);
    // dark keeps its §8.3/§8.4 line widths.
    final double cardBorderW = light ? 1.5 : 1;
    final double inputBorderW = light ? 1.5 : 1;
    final double inputFocusW = light ? 2.5 : 2;

    // §8.10 — Material 3 ColorScheme mapping. Dark reproduces the EXACT original
    // `ColorScheme.dark(...)` named-constructor call (so the dark render — and
    // every dark golden — is byte-identical); light builds the parallel
    // `ColorScheme.light(...)` per §8.20.6. The two are constructed separately
    // rather than via a shared `.copyWith`, because the `.dark()`/`.light()`
    // named constructors derive their UNSET fields differently and a copyWith
    // over one base would silently shift unset slots.
    final ColorScheme colorScheme = light
        ? ColorScheme.light(
            primary: c.primary,
            onPrimary: c.onPrimary, // #30302F on lime
            secondary: c.primary, // lime is the only accent
            onSecondary: c.onPrimary,
            tertiary: c.accent,
            onTertiary: AppColors.neutral0,
            surface: c.surface0,
            onSurface: c.textPrimary,
            surfaceContainerLowest: c.surface0,
            surfaceContainerLow: c.surface1,
            surfaceContainer: c.surface1,
            surfaceContainerHigh: c.surface2,
            surfaceContainerHighest: c.surface3,
            onSurfaceVariant: c.textSecondary,
            outline: c.borderStrong,
            outlineVariant: c.border,
            error: c.statusDanger,
            onError: AppColors.neutral0,
            scrim: Colors.black,
            shadow: Colors.black,
          )
        : ColorScheme.dark(
            primary: c.primary,
            onPrimary: c.onPrimary, // dark text on lime
            secondary: c.primary, // lime is the only accent
            onSecondary: c.onPrimary,
            tertiary: c.accent,
            onTertiary: AppColors.neutral0,
            surface: c.surface0,
            onSurface: c.textPrimary,
            surfaceContainerLowest: c.surface0,
            surfaceContainerLow: c.surface1,
            surfaceContainer: c.surface1,
            surfaceContainerHigh: c.surface2,
            surfaceContainerHighest: c.surface3,
            onSurfaceVariant: c.textSecondary,
            // §8.10 — `outline` carries the interactive boundary (3:1+);
            // `outlineVariant` is the decorative divider.
            outline: c.borderStrong,
            outlineVariant: c.border,
            // §8.4 / §8.13 — input error resolves to the status danger token.
            error: c.statusDanger,
            onError: AppColors.secondary,
            scrim: Colors.black,
            shadow: Colors.black,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.surface0,
      canvasColor: c.surface0,

      // §8.3 — disabled field/control text resolves to textDisabled, not the
      // Material 3 0.38-opacity default.
      disabledColor: c.textDisabled,

      textTheme: textTheme,
      primaryTextTheme: textTheme,

      // Register BOTH theme extensions: the mono text and the semantic color
      // scheme. `context.colors` resolves the right AppColorScheme per theme.
      extensions: <ThemeExtension<dynamic>>[monoExtension, c],

      // App bar — flat on canvas, no tonal elevation.
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface0,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
            .copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
        ),
        titleTextStyle: textTheme.headlineMedium,
        iconTheme: IconThemeData(
          color: c.textPrimary,
          size: 24, // §8.6 — nav icon size
        ),
      ),

      // Cards — surface1. Dark: hairline border, NO shadow (shadow invisible on
      // dark, §8.20.2). Light: 1.5px hairline + a resting drop shadow that does
      // the elevation work (§8.20.2 — gray canvas + white card + shadow).
      cardTheme: CardThemeData(
        color: c.surface1,
        surfaceTintColor: Colors.transparent,
        // §8.20.2 surface1 = hairline only / no shadow even in light; shadow
        // scales up for surface2/3 (sheets/dialogs/modals) where it does the
        // load-bearing elevation work.
        elevation: 0,
        shadowColor: Colors.black,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: c.border, width: cardBorderW),
        ),
      ),

      // Dialogs / sheets — surface2 (white + shadow in light, §8.20.2).
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface2,
        surfaceTintColor: Colors.transparent,
        // §8.20.2 surface2 shadow scale: y2 / blur8 / 0.08 → Material elevation
        // ~3 in light; dark leaves it flat (shadow invisible on dark).
        elevation: light ? 3 : 0,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: light ? 3 : 0,
        shadowColor: Colors.black,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: light ? 3 : 0,
        shadowColor: Colors.black,
      ),

      // Inputs — recessed within cards (§8.4). Borders use borderStrong. Light
      // thickens idle to 1.5px and focus to 2.5px (§8.20.3-B); the light focus
      // border is the darkened-lime foreground substitute (#5A7A1C), since brand
      // lime fails as a thin foreground on white (§8.20.2).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.disabledFill;
          return c.inputFill;
        }),
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 12,
        ),
        labelStyle: WidgetStateTextStyle.resolveWith((states) {
          final TextStyle base = textTheme.labelMedium ?? const TextStyle();
          if (states.contains(WidgetState.disabled)) {
            return base.copyWith(color: c.textDisabled);
          }
          return base;
        }),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: c.textAccent),
        hintStyle: textTheme.bodyLarge?.copyWith(color: c.textTertiary),
        helperStyle: textTheme.labelSmall,
        errorStyle: textTheme.labelSmall?.copyWith(color: c.statusDanger),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: c.borderStrong, width: inputBorderW),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: c.borderStrong, width: inputBorderW),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
          // Light: darkened-lime #5A7A1C 2.5px; dark: brand lime 2px.
          borderSide: BorderSide(
            color: light ? c.textAccent : c.primary,
            width: inputFocusW,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: c.statusDanger, width: inputFocusW),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: c.statusDanger, width: inputFocusW),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
          borderSide: BorderSide(color: c.borderStrong, width: inputBorderW),
        ),
      ),

      // Primary filled button — lime fill, dark text (§8.3). Light bumps the
      // label to 700 (§8.20.3-A) — dark text on lime, maximizing the punch of
      // the one lime element.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.disabledFill;
            if (states.contains(WidgetState.pressed)) return c.pressed;
            if (states.contains(WidgetState.hovered)) return c.accent;
            return c.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.textDisabled;
            return c.onPrimary;
          }),
          minimumSize: WidgetStateProperty.all(
            const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(
              fontWeight: light ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return _focusRingSide(brightness);
            }
            return null;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),

      // Secondary outline button — foreground-accent border + text. Light uses
      // the darkened-lime foreground substitute (#5A7A1C) for both border and
      // text (§8.20.2) and thickens the idle border to 1.5px (§8.20.3-B).
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.textDisabled;
            return c.textAccent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: c.disabledFill, width: light ? 1.5 : 1);
            }
            if (states.contains(WidgetState.focused)) {
              return _focusRingSide(brightness);
            }
            return BorderSide(color: c.textAccent, width: 1.5);
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return c.primary.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return c.primary.withValues(alpha: 0.08);
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
            if (states.contains(WidgetState.disabled)) return c.textDisabled;
            return c.textAccent;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return c.primary.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.hovered)) {
              return c.primary.withValues(alpha: 0.08);
            }
            return null;
          }),
          minimumSize: WidgetStateProperty.all(
            const Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget),
          ),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return _focusRingSide(brightness);
            }
            return null;
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),

      // Icon-only buttons — §8.3 global focus ring (no at-rest change).
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return _focusRingSide(brightness);
            }
            return null;
          }),
        ),
      ),

      // Chips — selected = lime fill / dark text; unselected = surface2 /
      // secondary text. The §8.3 focus ring rides the per-chip `side` resolver
      // (`AppTheme.chipSide(brightness)`) at the widget site.
      chipTheme: ChipThemeData(
        backgroundColor: c.surface2,
        selectedColor: c.primary,
        disabledColor: c.disabledFill,
        side: chipSide(brightness),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: c.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: c.onPrimary,
          fontWeight: FontWeight.w500,
        ),
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),

      // Dividers — §8.1 / §8.20.3-B held thin (decorative; meant to recede).
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(
        color: c.textPrimary,
        size: 20, // §8.6 — content icon default
      ),

      // Focus / overlays — keep focusColor transparent so the ring isn't muddied.
      focusColor: Colors.transparent,
      hoverColor: c.primary.withValues(alpha: 0.08),
      splashColor: c.primary.withValues(alpha: 0.16),
      highlightColor: c.primary.withValues(alpha: 0.08),

      // List tiles — rows on surface1.
      listTileTheme: ListTileThemeData(
        tileColor: c.surface1,
        iconColor: c.textPrimary,
        textColor: c.textPrimary,
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
