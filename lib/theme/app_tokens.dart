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
  static const Color primary = Color(0xFFA1CC3A); // Brand green — only app accent.
  static const Color secondary = Color(
    0xFF1A1A1A,
  ); // Charcoal (also surface-0).
  static const Color accent = Color(0xFF7A9E26); // Hover / pressed companion.
  static const Color pressed = Color(
    0xFF6B8C20,
  ); // §8.3 — primary button pressed.

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

  // §8.13 — semantic status palette (added 2026-05-29). Verdict colors only:
  // pass / marginal / fail / info. NOT decorative accents — lime `primary`
  // remains the only interactive/computed accent. Every value passes WCAG 2.2
  // SC 1.4.3 AA for NORMAL text (4.5:1) on both surface1 (#222222) and
  // surface0 (#1A1A1A), so a status word reads at body size. Ratios per §8.12.
  // Always pair with text/icon — never color alone (SC 1.4.1).

  /// Pass / good verdict. 8.66:1 on surface1 / 9.26:1 on surface0. A cool
  /// mint-green deliberately distinct from the lime brand `primary` so
  /// "this answer passes" never reads as "this is the computed value."
  static const Color statusSuccess = Color(0xFF5BD68A);

  /// Marginal / caution verdict. 7.12:1 on surface1 / 7.62:1 on surface0.
  static const Color statusWarning = Color(0xFFE0A23A);

  /// Fail / bad verdict; also the input error-border color (§8.4). 5.48:1 on
  /// surface1 / 5.86:1 on surface0. Lightened from the retired v1.1 #E04646
  /// (3.89:1 — failed normal-text AA) so status words read at body size.
  static const Color statusDanger = Color(0xFFF26E6E);

  /// Neutral informational note. 6.06:1 on surface1 / 6.49:1 on surface0.
  /// Use only where a true non-verdict info role exists; do not default to it.
  static const Color statusInfo = Color(0xFF4EA8E0);
}

/// 8px spacing scale — §4.
class AppSpacing {
  AppSpacing._();

  /// §4 — `--space-xxs`: the single sanctioned sub-8px gap (half-step). Use for
  /// tight inline pairings inside one logical unit (value↔unit symbol,
  /// number↔suffix) and dense single-line data-row top/bottom insets where 8px
  /// would over-space the row. The smallest gap in the system; nothing finer is
  /// permitted. Added 2026-06-01 (Vera calculator-gate finding #2): replaces the
  /// off-grid `SizedBox(width: 6)` value→unit gaps and `vertical: 4` row insets.
  /// Do not introduce 2px, 6px, or any other sub-grid value.
  static const double xxs = 4;

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

  /// Shared content-column cap for EVERY app surface — the home category grid,
  /// the category tool list, every calculator, and every reference table all
  /// center their content at this width so navigating from a list into a tool
  /// no longer changes the content-column width (Vera web-demo gate, 2026-06-02,
  /// "inconsistent content width"). 680 lets calculators breathe wider than the
  /// old 480 cap on desktop while keeping tables and lists feeling intentional
  /// rather than full-bleed. TUNABLE — Keith may adjust this single value to
  /// widen or tighten every surface at once. Apply it via [CenteredContent]
  /// (lib/widgets/centered_content.dart), not a fresh ConstrainedBox per screen.
  static const double contentMaxWidth = 680;

  /// Calculator content cap. Folded into [contentMaxWidth] on 2026-06-02 so the
  /// app no longer carries two competing content widths (calculators were 480,
  /// home/category were full-bleed). Retained as a named alias only so the ~50
  /// tool screens that reference it keep compiling; new code uses
  /// [contentMaxWidth] (or [CenteredContent]) directly.
  static const double calculatorMaxWidth = contentMaxWidth;

  /// Wider content cap for the category/tool TILE GRIDS only — the home category
  /// grid (`home_screen.dart`) and any future tile grid. Reading surfaces (guide
  /// reader, educational-resource detail, single-column calculators/forms, and
  /// the category tool LIST) stay at [contentMaxWidth] (680) so prose holds a
  /// readable measure; a tile grid is scanned, not read, so it may stretch wider
  /// to use a desktop window's width instead of stranding ~2 centered columns in
  /// big side margins (Kjetil desktop beta finding, 2026-06-07).
  ///
  /// 1280 lets the width-based breakpoints in `_crossAxisCountFor` actually
  /// reach their 3-column (≥720) and 4-column (≥1100) paths — which the old 680
  /// cap made unreachable — while still capping the grid before tiles grow
  /// absurdly wide on an ultrawide display (a 5th column would need ≥1480, above
  /// this cap, so the grid tops out at 4 columns by design). TUNABLE — adjust
  /// here and both tile grids widen together. Maps to GL-003 §8.7
  /// `--app-grid-max-width` (proposed to Iris alongside this fix).
  ///
  /// Width-based, NOT platform-based: a Mac window resized narrow reflows back
  /// down to 2 or 1 column exactly like a phone, which platform detection would
  /// get wrong.
  static const double gridMaxWidth = 1280;

  /// Width at and above which the tile grid shows 4 columns.
  static const double gridFourColBreakpoint = 1100;

  /// Width at and above which the tile grid shows 3 columns.
  static const double gridThreeColBreakpoint = 720;

  /// Width below which the tile grid drops from 2 columns to a single column
  /// (phone). Above it (and below [gridThreeColBreakpoint]) the grid is 2-up.
  static const double gridTwoColBreakpoint = 440;

  /// Tile cross-axis count for a given AVAILABLE grid width (post screen-edge
  /// padding is applied by the grid delegate's spacing, so pass the raw capped
  /// grid width here). Shared by the home grid and any future tile grid so the
  /// breakpoints live in one place. Width-based by design — see [gridMaxWidth].
  static int gridCrossAxisCountFor(double width) {
    if (width >= gridFourColBreakpoint) return 4;
    if (width >= gridThreeColBreakpoint) return 3;
    if (width >= gridTwoColBreakpoint) return 2;
    return 1;
  }

  /// Short-viewport height threshold for the calculator scroll-column alignment
  /// (see [calculatorVerticalAlignment]). At or below this, the column is
  /// top-aligned so the result readout (GL-003 §8.5 visual climax) reads from
  /// the top with no scroll; above it, the column is vertically centered.
  /// 480 is the iPhone landscape height band (~390–430pt), which is the case
  /// Vera's landscape audit flagged. (Decoupled from the content-width cap on
  /// 2026-06-02 when that widened to 680 — this is a height threshold and must
  /// stay at the landscape band, not track the content width.)
  static const double shortViewportHeight = 480;

  /// Vertical alignment for a calculator screen's capped scroll column.
  ///
  /// In a SHORT viewport (iPhone landscape, ~390pt tall) a vertically centered
  /// column pushes the result readout to or below the fold; the user has to
  /// scroll to see the answer they came for. Top-aligning in that case lets the
  /// layout read inputs-then-result from the top with no scroll. In a TALL
  /// (portrait) viewport the centered layout looks right, so it is preserved.
  ///
  /// Horizontal centering and the [calculatorMaxWidth] cap are unchanged in both
  /// cases — only the vertical axis switches. Returns [Alignment.topCenter] when
  /// short, [Alignment.center] when tall.
  static Alignment calculatorVerticalAlignment(BoxConstraints constraints) {
    return constraints.maxHeight < shortViewportHeight
        ? Alignment.topCenter
        : Alignment.center;
  }

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

  /// §8.5.1 — `--app-text-field-numeric`: the editable numeric *input* value in
  /// calculators and unit converters (the field the user types dBm / Watts /
  /// MHz / distances into). Rendered in DM Mono 500 at line-height 1.4. Sits
  /// between body/16 and h3/22 as the dense-input mono register. NOT for result
  /// readouts (those use h2/h1 per §8.5) and NOT for identifier strings (IP/MAC/
  /// hex use Roboto Mono). Added 2026-06-01: every hardcoded `fontSize: 18`/`20`
  /// on a DM Mono input field resolves to this one token (20). 16px floor
  /// (iOS Safari auto-zoom) is respected.
  static const double fieldNumeric = 20;
}
