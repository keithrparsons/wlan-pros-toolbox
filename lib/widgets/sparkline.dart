// Sparkline — a small inline time-series chart for App Mode (TICKET-01).
//
// Built for Wi-Fi Live mode: one compact line chart per streamed RF field
// (RSSI, SNR, Tx rate, Rx rate), rendered beside the field's current value and
// grade. It is deliberately small — a trend sparkline, NOT a full dashboard
// chart with gridlines and axes. Latest sample sits at the right edge; the
// window scrolls left as new samples arrive.
//
// Design-system fidelity (GL-003 §8): the line is `--color-primary` lime (the
// only app accent), and both the line and the latest-point dot are tinted via
// the single [lineColor] prop (the dot reuses [lineColor]; there is no separate
// dotColor) so a graded chart can tint its line to match its grade chip when
// the caller wants that reinforcement (color is never the only signal — the
// value text and grade word always carry the meaning). The
// surface is transparent so the chart sits on its host card's `surface1`. No
// literal hex, no magic numbers that are not local layout constants.
//
// Accessibility: the painter output is decorative — a screen reader gets the
// numeric value + grade from the surrounding row, not from the pixels — so the
// chart is wrapped in [ExcludeSemantics] with a caller-supplied [semanticLabel]
// on an outer node describing the series in words (e.g. "RSSI trend, 12
// samples, currently -54 dBm"). Nulls (gaps where the field was unavailable in
// a sample) break the line rather than being drawn as zero (GL-005 honesty: a
// gap is a gap, never a fabricated 0).

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A compact inline time-series chart. Stateless and cheap to rebuild on each
/// streamed sample. Pass the rolling window oldest→newest; nulls render as gaps.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.semanticLabel,
    this.lineColor = AppColors.primary,
    this.height = _defaultHeight,
  });

  /// The rolling window of samples, ordered oldest → newest. A null entry is a
  /// gap (the field was unavailable in that sample) and breaks the line; it is
  /// never substituted with 0.
  final List<double?> values;

  /// A words description of the series for the a11y tree (the pixels are
  /// decorative). E.g. "RSSI trend, currently -54 dBm".
  final String semanticLabel;

  /// Line + latest-dot color. Defaults to the §8.3 lime accent. A graded caller
  /// may pass the matching §8.13 status color so the line reinforces the grade
  /// (the grade word still carries the meaning; SC 1.4.1).
  final Color lineColor;

  /// Chart height. Width fills the parent; the painter scales the window to fit.
  final double height;

  static const double _defaultHeight = 40;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(values: values, lineColor: lineColor),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.lineColor});

  final List<double?> values;
  final Color lineColor;

  // Local layout constants (not design tokens — painter geometry).
  static const double _strokeWidth = 1.5;
  static const double _dotRadius = 2.5;
  static const double _verticalInset = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final List<double?> v = values;
    if (v.isEmpty) return;

    // Range across the PRESENT samples only — gaps do not pull the scale.
    final List<double> present = v.whereType<double>().toList(growable: false);
    if (present.isEmpty) return;

    double minV = present.first;
    double maxV = present.first;
    for (final double d in present) {
      if (d < minV) minV = d;
      if (d > maxV) maxV = d;
    }
    // Flat series → center the line vertically (avoid divide-by-zero).
    final double span = (maxV - minV).abs();
    final double range = span == 0 ? 1 : span;

    final double usableH = size.height - _verticalInset * 2;
    // A single present sample cannot define a horizontal step; pin it to the
    // right edge as a lone dot.
    final int n = v.length;
    final double stepX = n <= 1 ? 0 : size.width / (n - 1);

    double xFor(int i) => n <= 1 ? size.width : stepX * i;
    double yFor(double value) {
      final double t = (value - minV) / range; // 0 (min) .. 1 (max)
      // Higher value → higher on screen (smaller y).
      return _verticalInset + (1 - t) * usableH;
    }

    final Paint linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Build the polyline, breaking at gaps (nulls) so a missing sample shows as
    // a break, not a line drawn through a fabricated 0.
    Path? path;
    Offset? lastPoint;
    for (int i = 0; i < n; i++) {
      final double? value = v[i];
      if (value == null) {
        // Gap: end the current segment.
        if (path != null) {
          canvas.drawPath(path, linePaint);
          path = null;
        }
        continue;
      }
      final Offset p = Offset(xFor(i), yFor(value));
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      lastPoint = p;
    }
    if (path != null) canvas.drawPath(path, linePaint);

    // Latest-sample dot at the most recent present point.
    if (lastPoint != null) {
      // Only draw the dot if the LAST sample is the one that is present (so the
      // dot tracks "now"); otherwise the most recent reading is a gap and we
      // leave the head undotted to signal the current absence.
      if (v.last != null) {
        final Paint dotPaint = Paint()
          ..color = lineColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(lastPoint, _dotRadius, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      !_listEquals(oldDelegate.values, values);

  static bool _listEquals(List<double?> a, List<double?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
