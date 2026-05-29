// Design tokens — direct ports of GL-003 §2 and §8.
//
// Source of truth: Team Knowledge/Guidelines/GL-003-design-system.md
// (App Mode / Dark Theme: §8.1–§8.9; Spacing: §4; Type scale: §3).
//
// Touch nothing here without first updating GL-003 via Iris.

import 'package:flutter/material.dart';

/// Brand palette — §2.
class AppColors {
  AppColors._();

  // §2 — brand palette.
  static const Color primary = Color(0xFFA2CC3A); // Lime — only app accent.
  static const Color secondary = Color(0xFF1A1A1A); // Charcoal (also surface-0).
  static const Color accent = Color(0xFF7A9E26); // Hover / pressed companion.
  static const Color pressed = Color(0xFF6B8C20); // §8.3 — primary button pressed.

  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral2 = Color(0xFFE5E5E5);
  static const Color neutral3 = Color(0xFF9C9C9C);

  // §8.1 — dark surface stack.
  static const Color surface0 = Color(0xFF1A1A1A); // canvas
  static const Color surface1 = Color(0xFF222222); // cards, list rows
  static const Color surface2 = Color(0xFF2A2A2A); // sheets, dialogs
  static const Color surface3 = Color(0xFF333333); // top of stack

  /// Decorative-only divider. 1.4–1.5:1 against surface0/1 — never use as the
  /// boundary of an interactive component. Use `borderStrong` for inputs and
  /// any other UI-component boundary. (GL-003 §8.1.)
  static const Color border = Color(0xFF3A3A3A);

  /// Required for UI-component boundaries (input outlines, focusable cards,
  /// outlined-button borders). 3.83:1 on inputFill / 3.63:1 on surface2 /
  /// 4.41:1 on surface0 — passes SC 1.4.11 across every dark surface it sits
  /// on. Corrected 2026-05-29 (Iris §8.1 republish closing Vera F-NEW-01);
  /// the previous #5A5A5A regression measured 2.19–2.52:1 and failed 1.4.11.
  static const Color borderStrong = Color(0xFF808080);

  static const Color inputFill = Color(0xFF262626);

  /// Fill for disabled buttons / chips / toggles. Paired with
  /// `textDisabled` (#7F7F7F) for 3.58:1 — passes SC 1.4.11.
  /// Added 2026-05-29 per Iris's §8.1 update closing Vera F-02.
  static const Color disabledFill = Color(0xFF2A2A2A);

  static const Color scrim = Color(0x99000000); // rgba(0,0,0,0.6)

  // §8.2 — text on dark (all WCAG 2.2 AA on surface0 / surface1).
  static const Color textPrimary = neutral0; // 17.4:1
  static const Color textSecondary = neutral2; // 13.8:1
  static const Color textTertiary = neutral3; // 6.3:1

  /// Disabled text/icon foreground. 4.3:1 on surface0; 3.58:1 on disabledFill —
  /// passes SC 1.4.11. Bumped from #6B6B6B to #7F7F7F on 2026-05-29 per Iris's
  /// §8.2 update closing Vera F-02.
  static const Color textDisabled = Color(0xFF7F7F7F);

  static const Color textAccent = primary; // 9.3:1
}

/// 8px spacing scale — §4.
class AppSpacing {
  AppSpacing._();

  static const double xs = 8;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 48;
  static const double xxl = 64;

  /// §8.7 — screen edge padding (mobile vs tablet+ desktop).
  static const double screenEdgeMobile = sm;
  static const double screenEdgeDesktop = md;

  /// §8.7 — `--app-row-padding`: vertical (top + bottom) inset for tool-result
  /// rows, list rows, and any single-line data row inside a card. 1.5× `xs`
  /// (8px base) = 12px — denser than card padding without crowding. Use this
  /// token wherever a row's top/bottom inset is set; never hardcode 12px.
  /// Horizontal row inset follows card padding (`sm`, 16px).
  static const double rowPadding = 12;

  /// Calculator content cap so desktop doesn't stretch a 2000px form field.
  static const double calculatorMaxWidth = 480;

  /// §8.3 — minimum touch target. iOS 44pt / Android 48dp; we render at 48.
  static const double minTouchTarget = 48;
}

/// Corner radii — §8.11.
///
/// Two-step scale: containers (cards/sheets/tiles) take `card`, controls
/// (buttons/inputs/chips) take `control`. `pill` is reserved for fully-rounded
/// chips and badges and is optional. Never mix radii within one composite
/// control.
class AppRadius {
  AppRadius._();

  /// Cards, tiles, sheets, dialogs, popovers — any container surface.
  static const double card = 12;

  /// Buttons, text inputs, selects, chips, toggles, small interactive surfaces.
  static const double control = 8;

  /// Fully-rounded chips and badges. Use only when the pill shape carries
  /// meaning (status badge, filter chip). Do not apply to inputs or buttons.
  static const double pill = 999;
}

/// Motion durations — §8.8.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve standardEase = Cubic(0.2, 0, 0, 1);
}

/// Type-scale sizes in logical px — §3.
class AppTextSize {
  AppTextSize._();

  static const double display = 48;
  static const double h1 = 36;
  static const double h2 = 28;
  static const double h3 = 22;
  static const double body = 16;
  static const double caption = 13;
}
