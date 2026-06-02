// Per-metric live sparkline for the Network Quality screen.
//
// Renders one metric's in-memory history as a lime line on a plain `surface2`
// panel. The grade CHIP in each row carries the true engine grade; the
// sparkline is a visual trend reference only (spec §3).
//
// Visual language is borrowed from the Ping screen's `_Sparkline`: a lime
// (`AppColors.primary`) polyline on a `surface2` panel, a single-point dot, and
// token-only sizing. A fixed per-metric y-domain keeps the line's vertical
// placement stable run to run.
//
// COLORED GRADE BANDS REMOVED 2026-06-02 (Keith): the four shaded
// Excellent / Good / Fair / Poor zone tints that used to sit behind the line
// interfered with reading the trend, so they are gone — the line now stands on
// the same neutral `surface2` surface as the rest of the card. No information
// is lost: the grade was never carried by the band hue. The row's grade CHIP
// (a worded label) carries the verdict, and the row's `Semantics` label speaks
// the value + grade + trend, so WCAG 1.4.1 (no information by color alone)
// holds. The `domain` is retained solely to fix the y-axis scale. The whole
// painter is `excludeSemantics`; the parent supplies a worded `Semantics`
// label.
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

/// A small token-only sparkline of a metric's live history on a plain
/// `surface2` panel (no grade-zone bands). Decorative for AT (the parent row
/// carries the worded summary).
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
      // No-samples / neutral state: leave the plain `surface2` panel (owned by
      // the Container) showing — no grade hue, so an empty sparkline never
      // implies a verdict.
      return;
    }
    // Grade-zone bands removed 2026-06-02 (Keith): the line now renders on the
    // plain `surface2` panel. Only the data line + latest-point dot are painted.
    _paintData(canvas, size);
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
