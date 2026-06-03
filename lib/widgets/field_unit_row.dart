// FieldUnitRow — the shared "value field + unit selector" layout primitive.
//
// Every RF/distance calculator pairs a numeric field with a unit selector
// (AppToggle / AppSelect): GHz·MHz, km·mi·m, dBm·W·mW, and so on. The
// established layout was a hand-rolled
//   Row(children: [Expanded(field), SizedBox(gap), unit])
// repeated across ~12 calculators.
//
// Why this widget exists (Vera web-demo gate, 2026-06-02 — "sub-440px
// horizontal clip"): on narrow widths (~390px) the field + 3-segment toggle
// could not both fit on one line, so the toggle's right edge clipped off the
// card. The fix is a single shared primitive that REFLOWS below a breakpoint:
// above it the field and unit sit side-by-side (the familiar layout); at or
// below it the unit selector drops onto its own line UNDER the field, full
// width, so nothing clips at phone widths. One widget, applied at every
// field+unit site, keeps the reflow behavior identical everywhere.

import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';

/// Lays out a numeric [field] beside a [unit] selector, reflowing the unit
/// below the field at narrow widths.
///
/// - Wide (row width ≥ [reflowBreakpoint]): `Row` with `Expanded(field)`, a
///   [gap], then the intrinsic-width [unit] — the familiar side-by-side layout.
/// - Narrow (row width < [reflowBreakpoint]): `Column` with the [field] on top
///   and the [unit] beneath it on its own full-width line — no horizontal clip.
///
/// [gap] is the spacing token between the two in either axis (horizontal gap in
/// row mode, vertical gap in column mode); defaults to `--space-sm` (16px).
class FieldUnitRow extends StatelessWidget {
  const FieldUnitRow({
    super.key,
    required this.field,
    required this.unit,
    this.gap = AppSpacing.sm,
    this.reflowBreakpoint = kFieldUnitReflowBreakpoint,
  });

  /// The numeric input. Rendered inside an `Expanded` in row mode and full
  /// width in column mode.
  final Widget field;

  /// The unit selector (AppToggle / AppSelect). Keeps its intrinsic width
  /// beside the field in row mode; spans the line beneath the field in column
  /// mode.
  final Widget unit;

  /// Spacing token between field and unit (horizontal in row mode, vertical in
  /// column mode). Defaults to `--space-sm`.
  final double gap;

  /// Row width at/below which the unit reflows beneath the field. Defaults to
  /// [kFieldUnitReflowBreakpoint] (440), matching the home-grid single-column
  /// breakpoint so both narrow-width fixes trip at the same point.
  final double reflowBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool narrow = constraints.maxWidth < reflowBreakpoint;

        if (narrow) {
          // Stacked: field, then the unit selector on its own full-width line.
          // crossAxisAlignment.stretch so the unit track spans the column —
          // a full-width segmented track reads intentionally, not clipped.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              field,
              SizedBox(height: gap),
              unit,
            ],
          );
        }

        // Side-by-side: the familiar layout. Baseline-friendly bottom alignment
        // so the unit selector lines up with the field's lower edge.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(child: field),
            SizedBox(width: gap),
            unit,
          ],
        );
      },
    );
  }
}

/// Shared reflow breakpoint (440) for the field+unit layout. Matches the home
/// grid's single-column breakpoint so every narrow-width reflow in the app
/// trips at the same width. (Vera web-demo gate, 2026-06-02.)
const double kFieldUnitReflowBreakpoint = 440;
