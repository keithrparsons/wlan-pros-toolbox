// Ping Plotter — a sustained ping that CHARTS latency over time, instead of the
// single-shot result the Ping / ICMP Ping tools give. Closes the "live
// performance graphs" competitor gap (NetXi research). Wave B, 2026-06-04.
//
// ENGINE (reuse, never rebuild — brief §16): driven by the shipped
// PingService TCP-handshake engine via PingPlotController. PingService is the
// ONE ping engine that runs on both shipping targets — iOS AND the macOS App
// Sandbox (real ICMP needs a subprocess the sandbox blocks, GL-008) — so it is
// the right primitive for a continuous, device-verifiable latency trend. No new
// transport, no new entitlement.
//
// HONESTY NOTE (GL-005, brief §10): this is a TCP round-trip probe, not ICMP
// echo. The form exposes the probe port and the metric is labelled "TCP RTT" so
// the user is never misled. Dropped probes are drawn as visible gap markers on
// the chart and counted in loss% — never faked as 0 ms.
//
// CHART: fl_chart LineChart (RTT on Y, elapsed seconds on X) over the
// controller's bounded rolling window; lost probes are overlaid as
// status-danger scatter dots on the X axis so a gap is unmistakable. The canvas
// is decorative for assistive tech — the numeric current/min/avg/max/jitter/loss
// readout beside it is the accessible text summary, in a DEBOUNCED live region
// (brief §31: announce at most ~1/sec so a screen reader isn't spammed every
// sample — the IPv6-fix lesson).
//
// States (SOP-007 §5):
//  - idle        → form only.
//  - loading     → live chart + running readout streaming; Stop button.
//  - success     → run stopped with samples; chart + final readout persist.
//  - empty/error → host blank → inline validation; all probes lost → an honest
//                  "no replies" readout (loss 100%), never a crash or a bare 0.
//  - web         → NetworkUnavailableView (network category is native-only).

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/ping_plot_controller.dart';
import '../../../services/network/ping_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class PingPlotterScreen extends StatefulWidget {
  const PingPlotterScreen({super.key, this.controller});

  /// Injected in tests with a stubbed ping stream so the screen renders, runs,
  /// and tears down without opening a socket. In production this is null and the
  /// screen builds a controller over the real PingService.
  final PingPlotController? controller;

  @override
  State<PingPlotterScreen> createState() => _PingPlotterScreenState();
}

class _PingPlotterScreenState extends State<PingPlotterScreen> {
  late final PingPlotController _controller;
  final TextEditingController _hostCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  int _port = PingService.defaultPort;

  /// Probe interval in milliseconds. Presets a network pro reaches for.
  int _intervalMs = 1000;
  static const List<int> _intervalPresets = <int>[500, 1000, 2000, 5000];

  bool _running = false;
  String? _error;
  PingPlotState _state = PingPlotState.empty;
  StreamSubscription<PingPlotState>? _sub;

  // Debounced a11y: hold the last announced time so the live region updates at
  // most ~1/sec regardless of sample cadence (brief §31, the IPv6 lesson).
  DateTime _lastAnnounced = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _announceEvery = Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PingPlotController();
    _sub = _controller.states.listen(
      (PingPlotState s) {
        if (!mounted) return;
        setState(() => _state = s);
        _maybeAnnounce(s);
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error = 'Ping error: $e';
        });
      },
    );
  }

  @override
  void dispose() {
    // Order matters: drop our listener first, then dispose the controller so it
    // signals the engine cancel and closes its stream — no leaked timer/socket
    // and no setState after unmount (brief §27, the main correctness risk).
    _sub?.cancel();
    _controller.dispose();
    _hostCtrl.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  void _start() {
    final String host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'Enter a host or IP to plot.');
      return;
    }
    _hostFocus.unfocus();
    setState(() {
      _error = null;
      _running = true;
      _state = PingPlotState.empty;
      _lastAnnounced = DateTime.fromMillisecondsSinceEpoch(0);
    });
    _controller.start(
      host: host,
      port: _port,
      interval: Duration(milliseconds: _intervalMs),
    );
  }

  void _stop() {
    _controller.stop();
    setState(() => _running = false);
    // Final summary announcement (WCAG 4.1.3) — bypasses the debounce so the
    // stopped-run summary always lands.
    final String avg = _state.avgMs == null
        ? 'no replies'
        : 'average ${_state.avgMs!.toStringAsFixed(1)} milliseconds';
    _announce(
      'Plot stopped, ${_state.totalReceived} of ${_state.totalSent} replies, '
      '$avg',
    );
  }

  void _maybeAnnounce(PingPlotState s) {
    final DateTime now = DateTime.now();
    if (now.difference(_lastAnnounced) < _announceEvery) return;
    _lastAnnounced = now;
    final String last = s.lastMs == null
        ? 'last probe lost'
        : 'current ${s.lastMs!.toStringAsFixed(0)} milliseconds';
    final String avg = s.avgMs == null
        ? 'no replies yet'
        : 'average ${s.avgMs!.toStringAsFixed(0)}';
    final String loss = '${(s.totalLossFraction * 100).toStringAsFixed(0)} '
        'percent loss';
    _announce('Plotting, $last, $avg, $loss');
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ping Plotter'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a run has
        // produced samples; copies the summary stats + a per-sample TSV.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (!NetworkSupport.pingSupported) {
      return NetworkUnavailableView(
        toolName: 'Ping Plotter',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConceptGraphicBand(
                    toolId: 'ping-plotter',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ping-plotter'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  if (_state.totalSent > 0 || _running) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _readoutCard(context),
                    const SizedBox(height: AppSpacing.sm),
                    _chartCard(context),
                  ],
                  ToolHelpFooter(toolId: 'ping-plotter'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledField(
            label: 'Host or IP',
            field: TextField(
              controller: _hostCtrl,
              focusNode: _hostFocus,
              enabled: !_running,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _running ? null : _start(),
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '1.1.1.1'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _chipGroupLabel(context, 'TCP port'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: PingService.commonPorts
                .map((int p) => _choice(
                      context,
                      label: '$p',
                      selected: _port == p,
                      onSelected: () => setState(() => _port = p),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _chipGroupLabel(context, 'Interval'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: _intervalPresets
                .map((int ms) => _choice(
                      context,
                      label: _intervalLabel(ms),
                      selected: _intervalMs == ms,
                      onSelected: () => setState(() => _intervalMs = ms),
                    ))
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Plots TCP handshake round-trip time to port $_port over time, a '
              'reachability and latency trend, not ICMP echo. Runs until you '
              'stop it; the chart keeps the most recent '
              '${_controller.windowSize} samples.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: colors.statusDanger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_running)
            OutlinedButton(onPressed: _stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: _start, child: const Text('Start plot')),
        ],
      ),
    );
  }

  Widget _chipGroupLabel(BuildContext context, String label) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      label,
      style: text.labelMedium?.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? colors.onPrimary : colors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: colors.primary,
      backgroundColor: colors.surface2,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      side: AppTheme.chipSide(Theme.of(context).brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _running ? null : (_) => onSelected(),
    );
  }

  String _intervalLabel(int ms) =>
      ms % 1000 == 0 ? '${ms ~/ 1000}s' : '${ms}ms';

  // ── Live readout (the accessible text summary) ─────────────────────────────

  Widget _readoutCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String lossPct =
        (_state.totalLossFraction * 100).toStringAsFixed(0);
    String ms(double? v) => v == null ? '—' : v.toStringAsFixed(1);

    final bool finished = !_running && _state.totalSent > 0;
    final bool noReplies = finished && _state.totalReceived == 0;

    final String liveLabel = _running
        ? 'Plotting, ${_state.totalReceived} of ${_state.totalSent} replies, '
              '$lossPct percent loss, current ${ms(_state.lastMs)} '
              'milliseconds, average ${ms(_state.avgMs)} milliseconds'
        : 'Plot ${finished ? 'stopped' : 'idle'}, '
              '${_state.totalReceived} of ${_state.totalSent} replies, '
              '$lossPct percent loss, average ${ms(_state.avgMs)} '
              'milliseconds';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _running ? 'Plotting…' : 'Summary',
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '${_state.totalReceived} / ${_state.totalSent} · $lossPct% loss',
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // WCAG 4.1.3 — the numeric grid is visual; this Semantics label
          // carries the same facts to AT so the readout is legible on demand
          // when focused. Spoken updates come solely from the throttled
          // _maybeAnnounce / _announce path (SemanticsService.sendAnnouncement),
          // so liveRegion is intentionally omitted: a liveRegion label that
          // rebuilds every sample would drive the SR ~2/sec and defeat the
          // ~1/sec throttle (matches the Network Quality pattern).
          Semantics(
            label: liveLabel,
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _metric(context, mono, 'current', ms(_state.lastMs)),
                _metric(context, mono, 'min', ms(_state.minMs)),
                _metric(context, mono, 'avg', ms(_state.avgMs)),
                _metric(context, mono, 'max', ms(_state.maxMs)),
                _metric(context, mono, 'jitter', ms(_state.jitterMs)),
              ],
            ),
          ),
          if (noReplies) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No replies. The host did not answer on TCP $_port. It may be '
              'down, the port may be filtered, or ICMP-only.',
              style: text.bodyLarge?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    AppMonoText mono,
    String label,
    String value,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: mono.outputMedium.copyWith(color: colors.textAccent),
            ),
            if (value != '—') ...[
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'ms',
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── Latency-trend chart (fl_chart) ─────────────────────────────────────────

  Widget _chartCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<PingSample> samples = _state.samples;
    final List<double> landed = _state.landedRttsMs;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Latency trend',
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                'ms over time',
                style: text.labelSmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (landed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text(
                  samples.isEmpty
                      ? 'Waiting for the first reply…'
                      : 'No replies yet. Every probe so far was lost.',
                  style:
                      text.bodyLarge?.copyWith(color: colors.textTertiary),
                ),
              ),
            )
          else
            // The chart canvas is decorative for AT — the numeric readout above
            // is the screen-reader-legible summary (brief §29).
            Semantics(
              excludeSemantics: true,
              child: SizedBox(
                height: 180,
                child: _LatencyChart(samples: samples),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          // Legend — color is never the only cue (SC 1.4.1): each swatch carries
          // a text label.
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _legend(context, colors.textAccent, 'RTT'),
              _legend(context, colors.statusDanger, 'Lost probe'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  // ── Copy payload (§8.16) ───────────────────────────────────────────────────

  /// Returns null (→ disabled affordance) until a run has sent at least one
  /// probe. Copies a labeled summary plus a per-sample TSV in send order. A lost
  /// sample carries its honest reason word (GL-005) and a blank time, never a 0.
  String? _buildCopyText() {
    if (_state.totalSent == 0) return null;

    final String host = _hostCtrl.text.trim();
    final String lossPct =
        (_state.totalLossFraction * 100).toStringAsFixed(0);
    String ms(double? v) => v == null ? '—' : v.toStringAsFixed(1);

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ping Plotter: TCP handshake RTT over time (not ICMP echo)')
      ..writeln('Target: ${host.isEmpty ? '(unknown)' : host}  port $_port  '
          'interval ${_intervalLabel(_intervalMs)}')
      ..writeln(
        'Summary: ${_state.totalReceived}/${_state.totalSent} replies, '
        '$lossPct% loss · min ${ms(_state.minMs)} ms / '
        'avg ${ms(_state.avgMs)} ms / max ${ms(_state.maxMs)} ms / '
        'jitter ${ms(_state.jitterMs)} ms',
      )
      ..writeln('Showing the most recent ${_state.samples.length} of '
          '${_state.totalSent} samples.')
      ..writeln()
      ..writeln(<String>['Seq', 't (s)', 'Result', 'RTT (ms)'].join(tab));

    for (final PingSample s in _state.samples) {
      final String t = (s.elapsed.inMilliseconds / 1000.0).toStringAsFixed(1);
      final String result = s.lost ? (s.errorLabel ?? 'lost') : 'reply';
      final String rtt = s.lost ? '' : ms(s.rttMs);
      buf.writeln(<String>['${s.sequence}', t, result, rtt].join(tab));
    }

    return buf.toString().trimRight();
  }
}

/// The latency line chart: landed RTTs as a lime line, lost probes as
/// status-danger dots pinned to the X axis so a gap reads at a glance.
/// Token-only; no literal hex. Decorative for AT (wrapped by the caller).
class _LatencyChart extends StatelessWidget {
  const _LatencyChart({required this.samples});

  final List<PingSample> samples;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // X = elapsed seconds; Y = RTT ms. Build the landed line and the lost-dot
    // overlay from the same sample list so they share one axis.
    final List<FlSpot> line = <FlSpot>[];
    final List<FlSpot> lost = <FlSpot>[];
    double maxRtt = 1;
    double maxX = 0;
    for (final PingSample s in samples) {
      final double x = s.elapsed.inMilliseconds / 1000.0;
      if (x > maxX) maxX = x;
      if (!s.lost && s.rttMs != null) {
        line.add(FlSpot(x, s.rttMs!));
        if (s.rttMs! > maxRtt) maxRtt = s.rttMs!;
      } else {
        lost.add(FlSpot(x, 0));
      }
    }

    // Round the Y ceiling up to a friendly headroom value.
    final double yMax = _niceCeiling(maxRtt);
    final double xMax = maxX <= 0 ? 1 : maxX;

    final TextStyle axisStyle =
        (text.labelSmall ?? const TextStyle()).copyWith(
      color: colors.textTertiary,
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: xMax,
        minY: 0,
        maxY: yMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yMax / 4,
          getDrawingHorizontalLine: (double _) => FlLine(
            color: colors.border,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: yMax / 2,
              getTitlesWidget: (double value, TitleMeta meta) => Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xxs),
                child: Text(value.toStringAsFixed(0), style: axisStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: _xInterval(xMax),
              getTitlesWidget: (double value, TitleMeta meta) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text('${value.toStringAsFixed(0)}s', style: axisStyle),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: <LineChartBarData>[
          // Landed RTT line.
          LineChartBarData(
            spots: line,
            isCurved: false,
            // Data line is a colored LINE (foreground) → darkened-lime on light
            // so it reads on white (§8.20.2).
            color: colors.textAccent,
            barWidth: 2,
            dotData: FlDotData(
              show: line.length <= 40,
              getDotPainter: (FlSpot spot, double _, LineChartBarData _,
                      int _) =>
                  FlDotCirclePainter(
                radius: 2,
                color: colors.textAccent,
                strokeWidth: 0,
                strokeColor: colors.textAccent,
              ),
            ),
          ),
          // Lost-probe markers pinned to the X axis.
          LineChartBarData(
            spots: lost,
            color: colors.statusDanger.withValues(alpha: 0),
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (FlSpot spot, double _, LineChartBarData _,
                      int _) =>
                  FlDotCirclePainter(
                radius: 3,
                color: colors.statusDanger,
                strokeWidth: 0,
                strokeColor: colors.statusDanger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Round a max RTT up to a clean chart ceiling so the Y axis reads tidily.
  static double _niceCeiling(double v) {
    if (v <= 10) return 10;
    if (v <= 25) return 25;
    if (v <= 50) return 50;
    if (v <= 100) return 100;
    if (v <= 250) return 250;
    if (v <= 500) return 500;
    if (v <= 1000) return 1000;
    // Above 1s, round up to the next 500.
    return (v / 500).ceil() * 500;
  }

  /// Choose a readable X tick spacing for the elapsed-seconds axis.
  static double _xInterval(double xMax) {
    if (xMax <= 10) return 2;
    if (xMax <= 30) return 5;
    if (xMax <= 60) return 10;
    if (xMax <= 180) return 30;
    return 60;
  }
}
