// Wi-Fi Live Trend — the full charted RSSI + Tx-rate trend over time for the
// connected link (competitor-study item H2). This is the genuine feature gap
// the competitor scan found: the existing `_LiveCharts` sparklines in
// wifi_info_screen carry a current value + grade glyph, but no axes and no
// min/avg/max — they read the *direction*, not the *shape*. This section adds a
// proper fl_chart LineChart per field with a screen-reader-legible
// current/min/avg/max readout beside it, matching the Ping Plotter treatment.
//
// ENGINE (reuse, never rebuild): driven entirely by the already-shipped rolling
// [WifiTimeSeries] the screen already fills — macOS CoreWLAN auto-poll on one
// path, the iOS companion-Shortcut stream on the other. This widget reads that
// window; it opens no socket, fires no Shortcut, and adds no measurement. It is
// a presentation layer over data the screen already has.
//
// HONESTY (GL-005, load-bearing):
//   * RSSI (dBm) and Tx rate (Mbps) plot confidently wherever the platform
//     supplies them.
//   * A field absent from a sample is a null in the window → the line BREAKS at
//     that gap; it is never drawn through a fabricated 0.
//   * Rx rate degrades GRACEFULLY: when the platform never exposes it (macOS
//     public CoreWLAN) or this reading lacks it, the card shows an honest
//     "Not reported" state with the precise per-platform reason — never a fake
//     flat line, never a zero series.
//   * The whole window being null for a field → an honest "Waiting / not
//     reported" panel, not an empty axis implying a reading of nothing.
//
// ACCESSIBILITY (matches Ping Plotter §29): the LineChart canvas is decorative
// for assistive tech — it is wrapped in ExcludeSemantics. The numeric
// current/min/avg/max readout beside each chart is the screen-reader-legible
// summary, carried on a Semantics node that speaks the same facts the pixels
// show. Color is never the only cue: every line carries its field label, and
// the readout speaks values in words.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../services/network/connected_ap.dart';
import '../../../services/network/wifi_time_series.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// Summary statistics over the present (non-null) samples in a rolling window.
///
/// Pure and side-effect free so it is trivially unit-testable. Gaps (nulls) are
/// skipped entirely — they never pull an average toward 0 (GL-005). When the
/// window holds no present sample, [hasData] is false and the consumer renders
/// an honest "not reported" / "waiting" state instead of zeroes.
@immutable
class TrendStats {
  const TrendStats._({
    required this.current,
    required this.min,
    required this.avg,
    required this.max,
    required this.sampleCount,
  });

  /// The most recent PRESENT value in the window, or null when the latest
  /// sample is a gap (or the window is empty).
  final double? current;

  /// Smallest present value, or null when no present sample exists.
  final double? min;

  /// Mean of the present values, or null when no present sample exists.
  final double? avg;

  /// Largest present value, or null when no present sample exists.
  final double? max;

  /// How many present (non-null) samples contributed.
  final int sampleCount;

  /// True when at least one present sample exists.
  bool get hasData => sampleCount > 0;

  /// Computes the stats over [window] (oldest → newest). Nulls are skipped.
  factory TrendStats.fromWindow(List<double?> window) {
    double? min;
    double? max;
    double sum = 0;
    int count = 0;
    double? current;
    for (final double? v in window) {
      if (v == null) continue;
      current = v; // keep advancing; ends on the last present sample
      sum += v;
      count++;
      if (min == null || v < min) min = v;
      if (max == null || v > max) max = v;
    }
    // "current" must reflect NOW: if the most recent sample is a gap, there is
    // no current reading even though earlier samples were present.
    final double? latest = window.isEmpty ? null : window.last;
    return TrendStats._(
      current: latest == null ? null : current,
      min: min,
      avg: count == 0 ? null : sum / count,
      max: max,
      sampleCount: count,
    );
  }
}

/// The Live trend section: a full charted RSSI + Tx-rate trend over the rolling
/// window, each with a current/min/avg/max readout. Stateless and cheap to
/// rebuild on each streamed/polled sample.
class WifiLiveTrend extends StatelessWidget {
  const WifiLiveTrend({
    super.key,
    required this.series,
    required this.latest,
    required this.platformLabel,
  });

  /// The rolling window the screen already fills (macOS poll / iOS stream).
  final WifiTimeSeries series;

  /// The latest reading, for the Rx-rate availability reason. May be null
  /// briefly between Start and the first payload.
  final ConnectedAp? latest;

  /// Honest per-platform label for the "not reported" reasons, matching the
  /// metric cards — e.g. 'macOS CoreWLAN', 'iOS Live', 'Android'.
  final String platformLabel;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // Rx availability: rxRateAvailable false → the platform NEVER exposes it
    // (macOS public CoreWLAN). True-but-null → a per-reading miss. Phrased to
    // match the static Rate card so the surfaces never disagree (GL-005).
    final bool rxAvailable = latest?.rxRateAvailable ?? false;
    final String? rxReason = !rxAvailable
        ? 'Rx rate is not reported by $platformLabel.'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Live trend',
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                'last ${series.capacity} samples',
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _TrendChartRow(
            label: 'RSSI',
            unit: 'dBm',
            window: series.rssi,
            // RSSI is negative and "less negative is better"; a fixed-ish
            // headroom keeps the line readable rather than hugging an edge.
            niceBounds: _rssiBounds,
            decimals: 0,
          ),
          const SizedBox(height: AppSpacing.md),
          _TrendChartRow(
            label: 'Tx rate',
            unit: 'Mbps',
            window: series.txRate,
            niceBounds: _rateBounds,
            decimals: 0,
          ),
          const SizedBox(height: AppSpacing.md),
          _TrendChartRow(
            label: 'Rx rate',
            unit: 'Mbps',
            window: series.rxRate,
            niceBounds: _rateBounds,
            decimals: 0,
            // Graceful degradation: when the platform can never report Rx, the
            // row shows the honest reason instead of an axis of nothing.
            unavailableReason: rxReason,
          ),
        ],
      ),
    );
  }

  /// RSSI axis: pad 3 dBm beyond the present min/max, floored to a sane window
  /// so a flat strong link does not render as a jittery full-height line.
  static ({double min, double max}) _rssiBounds(double dataMin, double dataMax) {
    double lo = (dataMin - 3).floorToDouble();
    double hi = (dataMax + 3).ceilToDouble();
    if (hi - lo < 6) {
      // Flat series: open a readable 6 dB window centered on the value.
      final double mid = (lo + hi) / 2;
      lo = mid - 3;
      hi = mid + 3;
    }
    return (min: lo, max: hi);
  }

  /// Rate axis: 0-based with a friendly ceiling rounded up past the max.
  static ({double min, double max}) _rateBounds(double dataMin, double dataMax) {
    return (min: 0, max: _niceCeiling(dataMax));
  }

  static double _niceCeiling(double v) {
    if (v <= 0) return 1;
    if (v <= 10) return 10;
    if (v <= 25) return 25;
    if (v <= 50) return 50;
    if (v <= 100) return 100;
    if (v <= 250) return 250;
    if (v <= 500) return 500;
    if (v <= 1000) return 1000;
    if (v <= 2500) return 2500;
    return (v / 1000).ceil() * 1000;
  }
}

/// One field's trend: the accessible current/min/avg/max readout above a
/// decorative fl_chart line over the rolling window. Renders an honest
/// "not reported" / "waiting" panel when no present sample exists.
class _TrendChartRow extends StatelessWidget {
  const _TrendChartRow({
    required this.label,
    required this.unit,
    required this.window,
    required this.niceBounds,
    required this.decimals,
    this.unavailableReason,
  });

  final String label;
  final String unit;
  final List<double?> window;
  final int decimals;

  /// Maps the present-sample (min, max) to a friendly axis (min, max).
  final ({double min, double max}) Function(double dataMin, double dataMax)
      niceBounds;

  /// When non-null, the platform cannot report this field — show the reason in
  /// place of a chart (graceful degradation, never a fake line).
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final TrendStats stats = TrendStats.fromWindow(window);

    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(decimals);

    // The accessible summary the screen reader speaks. Matches Ping Plotter's
    // approach: the chart is decorative; this carries the facts in words.
    final String summary;
    if (unavailableReason != null) {
      summary = '$label, $unavailableReason';
    } else if (!stats.hasData) {
      summary = '$label, waiting for the first reading';
    } else {
      summary = '$label trend over ${stats.sampleCount} samples, '
          'current ${fmt(stats.current)} $unit, '
          'minimum ${fmt(stats.min)} $unit, '
          'average ${fmt(stats.avg)} $unit, '
          'maximum ${fmt(stats.max)} $unit';
    }

    return Semantics(
      container: true,
      label: summary,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  unit,
                  style: text.labelSmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (unavailableReason != null)
              _ReasonPanel(text: unavailableReason!)
            else if (!stats.hasData)
              _ReasonPanel(
                text: 'Waiting for the first reading…',
              )
            else ...<Widget>[
              // current / min / avg / max — the text summary beside the chart.
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  _Stat(mono: mono, label: 'current', value: fmt(stats.current)),
                  _Stat(mono: mono, label: 'min', value: fmt(stats.min)),
                  _Stat(mono: mono, label: 'avg', value: fmt(stats.avg)),
                  _Stat(mono: mono, label: 'max', value: fmt(stats.max)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 120,
                child: _TrendLineChart(
                  window: window,
                  bounds: niceBounds,
                  decimals: decimals,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One labeled current/min/avg/max statistic, mono value + unit-less label.
class _Stat extends StatelessWidget {
  const _Stat({required this.mono, required this.label, required this.value});

  final AppMonoText mono;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: mono.outputMedium.copyWith(color: colors.textAccent),
        ),
      ],
    );
  }
}

/// Honest no-data / not-reported panel: a neutral surface with a reason, never
/// an empty axis (which would imply a reading of nothing).
class _ReasonPanel extends StatelessWidget {
  const _ReasonPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        text,
        style: textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// The decorative line chart for one field over the rolling window. Wrapped in
/// ExcludeSemantics by the caller — the numeric readout carries the facts to
/// AT. Nulls break the line (GL-005: a gap is a gap, never a fabricated 0).
/// Token-only; no literal hex.
class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({
    required this.window,
    required this.bounds,
    required this.decimals,
  });

  final List<double?> window;
  final ({double min, double max}) Function(double dataMin, double dataMax)
      bounds;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // X = sample index (0 .. n-1). Y = the field value. Gaps split the line
    // into separate bars so a missing sample reads as a break, not a zero.
    final int n = window.length;
    double dataMin = double.infinity;
    double dataMax = double.negativeInfinity;
    for (final double? v in window) {
      if (v == null) continue;
      if (v < dataMin) dataMin = v;
      if (v > dataMax) dataMax = v;
    }
    // No present sample is handled by the caller (_ReasonPanel); guard anyway.
    if (dataMin == double.infinity) {
      dataMin = 0;
      dataMax = 1;
    }
    final ({double min, double max}) yb = bounds(dataMin, dataMax);
    final double yMin = yb.min;
    final double yMax = yb.max <= yb.min ? yb.min + 1 : yb.max;

    // Build contiguous present-run segments; each becomes its own line bar so
    // the polyline never bridges a gap.
    final List<List<FlSpot>> segments = <List<FlSpot>>[];
    List<FlSpot> current = <FlSpot>[];
    for (int i = 0; i < n; i++) {
      final double? v = window[i];
      if (v == null) {
        if (current.isNotEmpty) {
          segments.add(current);
          current = <FlSpot>[];
        }
        continue;
      }
      current.add(FlSpot(i.toDouble(), v));
    }
    if (current.isNotEmpty) segments.add(current);

    final TextStyle axisStyle =
        (text.labelSmall ?? const TextStyle()).copyWith(
      color: colors.textTertiary,
    );

    final double xMax = n <= 1 ? 1 : (n - 1).toDouble();
    final double yInterval = (yMax - yMin) / 2;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: xMax,
        minY: yMin,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval <= 0 ? 1 : yInterval,
          getDrawingHorizontalLine: (double _) =>
              FlLine(color: colors.border, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: yInterval <= 0 ? 1 : yInterval,
              getTitlesWidget: (double value, TitleMeta meta) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xxs),
                child: Text(
                  value.toStringAsFixed(decimals),
                  style: axisStyle,
                ),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: <LineChartBarData>[
          for (final List<FlSpot> seg in segments)
            LineChartBarData(
              spots: seg,
              isCurved: false,
              // Data LINE (foreground) → darkened-lime on light (§8.20.2).
              color: colors.textAccent,
              barWidth: 2,
              dotData: FlDotData(
                // Lone present sample → a dot so a single reading is visible.
                show: seg.length == 1,
                getDotPainter:
                    (FlSpot spot, double _, LineChartBarData _, int _) =>
                        FlDotCirclePainter(
                  radius: 2.5,
                  color: colors.textAccent,
                  strokeWidth: 0,
                  strokeColor: colors.textAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
