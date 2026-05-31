// Per-metric live sparkline for the Network Quality screen.
//
// Renders one metric's in-memory history as a lime line over four shaded
// Excellent / Good / Fair / Poor bands. The bands give a glance-readable sense
// of which zone the line is sitting in; the grade CHIP in the row still carries
// the true engine grade (the band is a visual reference only — spec §3).
//
// Visual language is borrowed from the Ping screen's `_Sparkline`: a lime
// (`AppColors.primary`) polyline on a `surface2` panel, a single-point dot, and
// token-only sizing. The new part is the four shaded bands behind the line and
// a fixed per-metric y-domain so the bands are stable run to run.
//
// COLOR (spec §4 + GL-003 §8.13.1): the bands reuse the EXISTING grade palette —
// no new colors. Excellent and Good both map to `statusSuccess` (the existing
// `_gradeColors` collapses them too), Fair to `statusWarning`, Poor to
// `statusDanger`. Bands are 0.30-alpha tints of those hues (the §8.13.1
// band-stack floor), separated from each other by a 1px `borderStrong`
// (#808080) hairline at every internal edge so adjacent bands stay legibly
// distinct. The line and the chip — not the band hue — carry the verdict, so
// WCAG 1.4.1 is satisfied (no information by color alone). The whole painter is
// `excludeSemantics`; the parent supplies a worded `Semantics` label.
//
// States (SOP-007 §5):
//   - 0–1 points: caller shows a hint instead of this widget (a 1-point line is
//     misleading). This widget asserts >= 2 points for a line, but renders a
//     single dot gracefully if handed exactly one (defensive).
//   - dense (latency trio): a continuous polyline.
//   - sparse (download/upload/responsiveness): dots, no connecting line, since
//     the points are minutes/runs apart and a line between them would imply
//     continuity that was never measured.

import 'package:flutter/material.dart';
import 'package:net_quality/net_quality.dart';

import '../../../theme/app_tokens.dart';
import 'live_quality_monitor.dart';

/// Direction of "better" for a metric, which fixes how the bands stack.
enum BetterWhen {
  /// Lower is better (latency, jitter, loss): Excellent band at the bottom.
  lower,

  /// Higher is better (download, upload, responsiveness): Excellent band at
  /// the top.
  higher,
}

/// Fixed display domain + band edges for one metric (spec §3 table). The three
/// [edges] split the [min]..[max] domain into the four grade bands.
@immutable
class SparklineDomain {
  /// Bottom of the y-axis (metric's native unit).
  final double min;

  /// Top of the y-axis (metric's native unit).
  final double max;

  /// The three internal band boundaries, ascending, between [min] and [max].
  final List<double> edges;

  /// Which direction counts as better — sets band stacking.
  final BetterWhen betterWhen;

  /// Creates a domain. [edges] must hold exactly three ascending values.
  const SparklineDomain({
    required this.min,
    required this.max,
    required this.edges,
    required this.betterWhen,
  });

  /// Per-metric domains from the spec §3 table. Returns null for an unknown id.
  static SparklineDomain? forMetric(String id) => _domains[id];

  static const Map<String, SparklineDomain> _domains = <String, SparklineDomain>{
    MetricIds.latency: SparklineDomain(
      min: 0,
      max: 150,
      edges: <double>[20, 50, 100],
      betterWhen: BetterWhen.lower,
    ),
    MetricIds.jitter: SparklineDomain(
      min: 0,
      max: 40,
      edges: <double>[5, 15, 30],
      betterWhen: BetterWhen.lower,
    ),
    MetricIds.loss: SparklineDomain(
      min: 0,
      max: 5,
      edges: <double>[0, 1, 2.5],
      betterWhen: BetterWhen.lower,
    ),
    MetricIds.responsiveness: SparklineDomain(
      min: 0,
      max: 1200,
      edges: <double>[100, 500, 1000],
      betterWhen: BetterWhen.higher,
    ),
    MetricIds.download: SparklineDomain(
      min: 0,
      max: 120,
      edges: <double>[5, 25, 100],
      betterWhen: BetterWhen.higher,
    ),
    MetricIds.upload: SparklineDomain(
      min: 0,
      max: 25,
      edges: <double>[1, 5, 20],
      betterWhen: BetterWhen.higher,
    ),
  };
}

/// A small token-only sparkline with shaded grade bands behind a metric's
/// live history. Decorative for AT (the parent row carries the worded summary).
class MetricSparkline extends StatelessWidget {
  /// Creates a sparkline.
  ///
  /// [samples] is the metric's history (oldest first). [domain] fixes the
  /// y-axis and bands. [dotsOnly] renders points without a connecting line —
  /// used for the sparse expensive trio whose points are runs apart.
  const MetricSparkline({
    super.key,
    required this.samples,
    required this.domain,
    this.dotsOnly = false,
  });

  /// The metric's history, oldest first.
  final List<MetricSample> samples;

  /// Fixed y-domain and band edges for this metric.
  final SparklineDomain domain;

  /// When true, plot dots only (no line). For the sparse expensive trio.
  final bool dotsOnly;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: 40,
          width: double.infinity,
          color: AppColors.surface2,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 6,
          ),
          child: CustomPaint(
            painter: _BandSparklinePainter(
              samples: samples,
              domain: domain,
              dotsOnly: dotsOnly,
            ),
          ),
        ),
      ),
    );
  }
}

class _BandSparklinePainter extends CustomPainter {
  _BandSparklinePainter({
    required this.samples,
    required this.domain,
    required this.dotsOnly,
  });

  final List<MetricSample> samples;
  final SparklineDomain domain;
  final bool dotsOnly;

  // GL-003 §8.13.1 band-stack floor: grade-band tints sit at 0.30 alpha so the
  // deepest band still clears WCAG SC 1.4.11 against the data line.
  static const double _bandAlpha = 0.30;

  /// Band fill colors top-to-bottom in VALUE space (min..max ascending), as
  /// [value-range]→color pairs. The four ranges are
  /// [min..e0], [e0..e1], [e1..e2], [e2..max].
  List<Color> _bandColorsByValueRange() {
    // In value order (low value first): for "lower is better" the lowest band
    // is Excellent; for "higher is better" the lowest band is Poor.
    final Color exc = AppColors.statusSuccess.withValues(alpha: _bandAlpha);
    final Color good = AppColors.statusSuccess.withValues(alpha: _bandAlpha);
    final Color fair = AppColors.statusWarning.withValues(alpha: _bandAlpha);
    final Color poor = AppColors.statusDanger.withValues(alpha: _bandAlpha);
    if (domain.betterWhen == BetterWhen.lower) {
      // low value = good end
      return <Color>[exc, good, fair, poor];
    }
    // higher is better: low value = poor end
    return <Color>[poor, fair, good, exc];
  }

  double _yFor(double value, Size size) {
    final double span = (domain.max - domain.min);
    final double clamped = value.clamp(domain.min, domain.max);
    final double norm = span <= 0 ? 0 : (clamped - domain.min) / span;
    // Higher value → higher on the chart (smaller y).
    return size.height - norm * size.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) {
      // No-samples / neutral state: a flat `surface3` fill, no grade hue, so an
      // empty sparkline never implies a verdict (GL-003 §8.13.1).
      canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, size.height),
        Paint()..color = AppColors.surface3,
      );
      return;
    }
    _paintBands(canvas, size);
    _paintBandEdges(canvas, size);
    _paintData(canvas, size);
  }

  void _paintBands(Canvas canvas, Size size) {
    // Band boundaries in value space: min, e0, e1, e2, max.
    final List<double> bounds = <double>[
      domain.min,
      ...domain.edges,
      domain.max,
    ];
    final List<Color> colors = _bandColorsByValueRange();
    for (int i = 0; i < 4; i++) {
      final double yTop = _yFor(bounds[i + 1], size); // higher value = top
      final double yBottom = _yFor(bounds[i], size);
      final Rect rect = Rect.fromLTRB(0, yTop, size.width, yBottom);
      canvas.drawRect(rect, Paint()..color = colors[i]);
    }
  }

  // GL-003 §8.13.1: a 1px `borderStrong` (#808080) hairline at each of the
  // three INTERNAL band edges so adjacent grade tints stay distinct. The outer
  // frame is owned by the ClipRRect/Container, not painted here. Drawn after the
  // band fills and before the data line, so the line stays on top.
  void _paintBandEdges(Canvas canvas, Size size) {
    final Paint hairline = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final double edge in domain.edges) {
      final double y = _yFor(edge, size);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hairline);
    }
  }

  void _paintData(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final int n = samples.length;
    final double dx = n == 1 ? 0 : size.width / (n - 1);

    final Paint dotPaint = Paint()..color = AppColors.primary;

    // Single point → one dot (defensive; the caller normally shows a hint).
    if (n == 1) {
      final double x = size.width / 2;
      final double y = _yFor(samples.first.value, size);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      return;
    }

    if (dotsOnly) {
      for (int i = 0; i < n; i++) {
        final double x = i * dx;
        final double y = _yFor(samples[i].value, size);
        canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      }
      return;
    }

    final Path path = Path();
    for (int i = 0; i < n; i++) {
      final double x = i * dx;
      final double y = _yFor(samples[i].value, size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final Paint line = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);

    // Mark the latest point so "now" is locatable on a dense line.
    final double lastX = (n - 1) * dx;
    final double lastY = _yFor(samples.last.value, size);
    canvas.drawCircle(Offset(lastX, lastY), 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(_BandSparklinePainter old) =>
      old.samples.length != samples.length ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.value != samples.last.value) ||
      old.dotsOnly != dotsOnly ||
      old.domain != domain;
}
