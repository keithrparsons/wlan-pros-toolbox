// Wi-Fi vs Internet — the diagnostic screen.
//
// One "Run Check" orchestrates TWO already-shipped engines (this screen adds NO
// measurement backend, per the spec):
//   * the connected-AP link read — the SAME per-platform path wifi_info_screen
//     uses (WifiInfoSourceResolver → MacWifiInfoAdapter on macOS / the
//     WiFiDetailsBridge → ConnectedAp.fromWifiDetails on iOS), and
//   * a net_quality run via the QualityClient seam (the same seam
//     net_quality_screen consumes), read for download/upload + the per-dimension
//     QualityGrades.
// It feeds both into the pure [WifiVsInternetEngine] and renders the verdict.
//
// CORE PRINCIPLE (Keith): data RATE is the verdict truth; RSSI/SNR are
// supporting context. That lives in the engine; this screen only displays it.
//
// HONESTY (GL-005 / GL-008): a Wi-Fi link the platform cannot read (wired, or
// iOS without the companion Shortcut) yields the engine's wifiUnknown path —
// an internet-only read with an explicit caveat and, on iOS, a prompt to install
// the Shortcut. Nothing is fabricated to paper over a platform limit.
//
// LAYOUT matches net_quality_screen / wifi_info_screen: SafeArea + LayoutBuilder
// + centered ConstrainedBox(maxWidth 560) + scroll; surface1 cards with a §8.1
// hairline border; identifiers/numerics in mono; overflow-safe at 320px.
//
// STATES (SOP-007 §5): web/unsupported → NetworkUnavailableView/coming-soon ·
// idle (intro + Run) · loading (progress card, Run disabled, announced) ·
// success (verdict card + two data sections + footnote) · per-field unavailable
// (honest "not reported on this platform" rows) · error (in-card message + Run
// re-enabled to retry).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:net_quality/net_quality.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_vs_internet.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';

/// The footnote method-disclosure, VERBATIM from the spec (§Footnote text). Kept
/// as a named constant so the test asserts the exact string and a future edit is
/// a single, deliberate change.
const String kWifiVsInternetFootnote =
    '* Usable Wi-Fi capacity is estimated at 55% of the average negotiated '
    'Tx/Rx data rate (real-world Wi-Fi throughput runs about 50 to 60 percent '
    'of the PHY rate). Internet throughput is the average of the measured '
    'download and upload speeds. The verdict compares the two: internet within '
    '70% of usable Wi-Fi capacity points to the Wi-Fi link as the limiter; '
    'below 40% points upstream to the internet. RSSI and SNR are shown as '
    'supporting context; the negotiated data rate drives the verdict.';

/// Wi-Fi vs Internet diagnostic screen.
class WifiVsInternetScreen extends StatefulWidget {
  const WifiVsInternetScreen({
    super.key,
    this.sourceOverride,
    this.macAdapter,
    this.iosBridge,
    this.qualityClient,
  });

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver] — the same resolver wifi_info_screen uses.
  final WifiInfoSource? sourceOverride;

  /// Injectable macOS CoreWLAN adapter (tests). Defaults to the real adapter.
  final WifiInfoAdapter? macAdapter;

  /// Injectable iOS Shortcuts bridge (tests). Defaults to the real bridge.
  final WiFiDetailsBridge? iosBridge;

  /// Injectable net_quality backend (tests use a [MockQualityClient] with no
  /// network); null in production, where a real [OwnEngineQualityClient] runs.
  final QualityClient? qualityClient;

  @override
  State<WifiVsInternetScreen> createState() => _WifiVsInternetScreenState();
}

class _WifiVsInternetScreenState extends State<WifiVsInternetScreen> {
  late final WifiInfoSource _source;
  WifiInfoAdapter? _macAdapter;
  WiFiDetailsBridge? _iosBridge;
  late final QualityClient _quality;

  bool _running = false;
  String? _error;

  // Internet progress.
  QualityPhase _phase = QualityPhase.idle;
  double _fraction = 0;

  // Results, populated when the run completes.
  ConnectedAp? _ap;
  QualityResult? _internet;
  WifiVsInternetResult? _verdict;

  StreamSubscription<QualityProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        _macAdapter = widget.macAdapter ?? MacWifiInfoAdapter();
      case WifiInfoSource.iosShortcuts:
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
    _quality =
        widget.qualityClient ??
        OwnEngineQualityClient.forHost('one.one.one.one');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Reads the connected-AP link via the SAME per-platform path as
  /// wifi_info_screen. Returns null when the link cannot be read (no reading,
  /// no Shortcut payload, or an unsupported source) — the engine then takes its
  /// honest wifiUnknown path. Never throws to the caller.
  Future<ConnectedAp?> _readLink() async {
    try {
      switch (_source) {
        case WifiInfoSource.macosCoreWlan:
          final WifiInfoAdapter? adapter = _macAdapter;
          if (adapter == null) return null;
          // Bound the native CoreWLAN snapshot read so a stalled channel can
          // never hang the check. This screen does NOT call
          // requestNamePermission() (it reads the link rate, which never needs
          // Location), so the adapter-level permission timeout does not cover
          // this path — fetch() is bounded here directly, mirroring Test My
          // Connection. On timeout the link reads as unread (null) and the
          // verdict degrades to the honest internet-only wifiUnknown path.
          return await adapter.fetch().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw TimeoutException('Wi-Fi link read timed out'),
          );
        case WifiInfoSource.iosShortcuts:
          final WiFiDetailsBridge? bridge = _iosBridge;
          if (bridge == null) return null;
          final details = await bridge.readLatest();
          return details == null ? null : ConnectedAp.fromWifiDetails(details);
        case WifiInfoSource.unsupported:
        case WifiInfoSource.web:
          return null;
      }
    } catch (_) {
      // A link-read failure is non-fatal: the verdict degrades to the
      // internet-only wifiUnknown path rather than blocking the whole check.
      return null;
    }
  }

  /// Runs the internet measurement and the link read from one action, then
  /// computes the verdict. The link read starts immediately and resolves while
  /// the internet stream runs.
  void _run() {
    setState(() {
      _error = null;
      _running = true;
      _phase = QualityPhase.idle;
      _fraction = 0;
      _ap = null;
      _internet = null;
      _verdict = null;
    });

    final Future<ConnectedAp?> linkFuture = _readLink();

    _sub = _quality.measure().listen(
      (QualityProgress p) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
        });
      },
      onDone: () async {
        final QualityResult? internet = _quality.lastResult;
        // Safety net: the link read is already bounded inside _readLink (the
        // fetch() timeout), but guard this final await too so the verdict
        // ALWAYS computes even if the link future stalls for any reason. A
        // timeout yields ap = null → the honest internet-only wifiUnknown path.
        final ConnectedAp? ap = await linkFuture.timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
        if (!mounted) return;
        setState(() {
          _ap = ap;
          _internet = internet;
          _verdict = _compute(ap, internet);
          _running = false;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Wi-Fi versus internet check complete',
          TextDirection.ltr,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error = 'Could not complete the check: $e';
        });
      },
    );
  }

  /// Bridges the two engines into the pure [WifiVsInternetEngine]: translates
  /// the net_quality grades into the engine's [InternetHealth] flag at the
  /// boundary (keeping the engine Flutter-free) and forwards the link rates.
  WifiVsInternetResult _compute(ConnectedAp? ap, QualityResult? internet) {
    final double? down = _metricValue(internet, MetricIds.download);
    final double? up = _metricValue(internet, MetricIds.upload);

    return WifiVsInternetEngine.evaluate(
      txRateMbps: ap?.txRateMbps,
      rxRateMbps: ap?.rxRateMbps,
      rxRateAvailable: ap?.rxRateAvailable ?? false,
      snrDb: ap?.snrDb,
      rssiDbm: ap?.rssiDbm,
      internetDownMbps: down,
      internetUpMbps: up,
      internetHealth: _internetHealth(internet),
    );
  }

  /// Grade gate input: GOOD only when throughput (download AND upload), latency,
  /// and loss ALL grade good/excellent. A missing/unavailable grade on any of
  /// the gating dimensions counts as NOT good, so the ratio gets to diagnose.
  static InternetHealth _internetHealth(QualityResult? r) {
    if (r == null) return InternetHealth.marginal;
    bool ok(String id) {
      final QualityMetric? m = r.metric(id);
      return m != null &&
          (m.grade == QualityGrade.good || m.grade == QualityGrade.excellent);
    }

    final bool throughputGood = ok(MetricIds.download) && ok(MetricIds.upload);
    final bool latencyGood = ok(MetricIds.latency);
    final bool lossGood = ok(MetricIds.loss);
    return (throughputGood && latencyGood && lossGood)
        ? InternetHealth.good
        : InternetHealth.marginal;
  }

  static double? _metricValue(QualityResult? r, String id) {
    final QualityMetric? m = r?.metric(id);
    return (m != null && m.isAvailable) ? m.value : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi vs Internet'),
        toolbarHeight: 64,
        // §8.16 order: copy LEADS, the Refresh action trails. Copy is disabled
        // until a check has been run; copies the verdict + Wi-Fi link +
        // internet figures as a labeled text block. Refresh re-runs the SAME
        // check in place via _run() — it appears only once a verdict exists
        // (before that, the in-card "Run Check" button is the affordance) and
        // swaps to the in-progress spinner while a re-run is underway so the
        // check can't be double-fired. Help trails copy + refresh (§8.16).
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ..._refreshAction(),
          const ToolHelpAction(toolId: 'wifi-vs-internet'),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// The AppBar "Refresh" action — re-runs the SAME check via [_run()] (no
  /// duplicated logic). Matches the Wi-Fi Information and Test My Connection
  /// screens' affordance: a circular-arrow [IconButton] that swaps to a small
  /// in-progress spinner while a run is underway. Returns an empty list until a
  /// verdict exists, so the affordance only appears once there is something to
  /// re-run (the in-card "Run Check" button is the first-run affordance). The
  /// spinner + the run guard in [_run]/onPressed prevent a double-run.
  List<Widget> _refreshAction() {
    // Nothing to re-run before the first verdict lands.
    if (_verdict == null && !_running) return const <Widget>[];
    if (_running) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ];
    }
    return <Widget>[
      Semantics(
        button: true,
        label: 'Run the test again',
        child: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _run,
        ),
      ),
    ];
  }

  /// §8.16 copy payload — the whole check as a labeled plain-text block.
  ///
  /// Returns null (→ disabled affordance) until a check has produced a verdict.
  /// Per the §8.16 content contract, every on-screen VERDICT WORD travels to
  /// the clipboard: the headline verdict word, and each internet dimension's
  /// grade WORD (Excellent / Good / Fair / Poor / Unavailable) appended to its
  /// line — color was the on-screen carrier, the word is the clipboard carrier.
  /// Unavailable figures are written as "Unavailable" (never blank/fabricated,
  /// matching the on-screen `_DataRow` treatment, GL-005).
  String? _buildCopyText() {
    final WifiVsInternetResult? v = _verdict;
    if (_running || v == null) return null;

    final ConnectedAp? ap = _ap;
    final QualityResult? net = _internet;
    final StringBuffer buf = StringBuffer();

    // --- Verdict (the WORD always leads; §8.13 / §8.16) ---
    buf
      ..writeln('Wi-Fi vs Internet')
      ..writeln('Verdict: ${v.headline}')
      ..writeln(v.explanation);
    if (v.snrContext.isNotEmpty) buf.writeln(v.snrContext);

    // --- Wi-Fi link figures ---
    buf
      ..writeln()
      ..writeln('Your Wi-Fi link')
      ..writeln('  Tx rate: ${_copyVal(_copyRate(ap?.txRateMbps), 'Mbps')}');
    final bool rxUnavailable =
        ap != null && !ap.rxRateAvailable && ap.rxRateMbps == null;
    buf.writeln(
      '  Rx rate: ${rxUnavailable ? 'Not reported on this platform' : _copyVal(_copyRate(ap?.rxRateMbps), 'Mbps')}',
    );
    buf.writeln(
      '  Usable capacity: ${_copyVal(_copyRate(v.usableWifiMbps), 'Mbps')} '
      '(55% of ${WifiVsInternetEngine.rateBasisCaption(v.rateBasis)})',
    );
    buf
      ..writeln(
        '  SNR: ${_copyVal(ap?.snrDb?.toString(), 'dB')}'
        '${(ap?.snrDerived ?? false) ? ' (derived)' : ''}',
      )
      ..writeln('  RSSI: ${_copyVal(ap?.rssiDbm?.toString(), 'dBm')}')
      ..writeln('  Channel: ${_copyVal(ap?.channel?.toString(), null)}')
      ..writeln('  Standard: ${_copyVal(ap?.standard, null)}');

    // --- Internet figures, each with its grade WORD ---
    final double? down = _copyMetricValue(net, MetricIds.download);
    final double? up = _copyMetricValue(net, MetricIds.upload);
    final double? avg = (down != null && up != null)
        ? (down + up) / 2
        : (down ?? up);
    buf
      ..writeln()
      ..writeln('Your internet')
      ..writeln(
        '  Download: ${_copyVal(down?.toStringAsFixed(1), 'Mbps')} — ${_copyGrade(net, MetricIds.download)}',
      )
      ..writeln(
        '  Upload: ${_copyVal(up?.toStringAsFixed(1), 'Mbps')} — ${_copyGrade(net, MetricIds.upload)}',
      )
      ..writeln(
        '  Averaged: ${_copyVal(avg?.toStringAsFixed(1), 'Mbps')} '
        '(average of download and upload)',
      )
      ..writeln(
        '  Latency: ${_copyVal(_copyMetricValue(net, MetricIds.latency)?.round().toString(), 'ms')} — ${_copyGrade(net, MetricIds.latency)}',
      )
      ..writeln(
        '  Jitter: ${_copyVal(_copyMetricValue(net, MetricIds.jitter)?.round().toString(), 'ms')} — ${_copyGrade(net, MetricIds.jitter)}',
      )
      ..writeln(
        '  Loss: ${_copyVal(_copyMetricValue(net, MetricIds.loss)?.round().toString(), '%')} — ${_copyGrade(net, MetricIds.loss)}',
      );

    // --- Method footnote ---
    buf
      ..writeln()
      ..writeln(kWifiVsInternetFootnote);

    return buf.toString().trimRight();
  }

  /// Formats "value unit", or "Unavailable" when the value is missing — the
  /// clipboard analog of the on-screen `_DataRow` (GL-005 honest blanks).
  static String _copyVal(String? value, String? unit) {
    if (value == null || value.trim().isEmpty) return 'Unavailable';
    return unit == null ? value : '$value $unit';
  }

  /// Same rate rounding as the on-screen `_WifiLinkSection._rate`.
  static String? _copyRate(double? mbps) {
    if (mbps == null) return null;
    final double r = (mbps * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }

  static double? _copyMetricValue(QualityResult? r, String id) {
    final QualityMetric? m = r?.metric(id);
    return (m != null && m.isAvailable) ? m.value : null;
  }

  /// The grade WORD for a dimension — the §8.16 verdict-word carrier for the
  /// internet figures. Falls back to "Unavailable" when no grade exists.
  static String _copyGrade(QualityResult? r, String id) =>
      (r?.metric(id)?.grade ?? QualityGrade.unavailable).label;

  Widget _body() {
    // The internet measurement needs dart:io sockets the browser does not have;
    // route web (and any no-socket platform) to the shared download-the-app
    // fallback — never crash, never a broken screen.
    if (!NetworkSupport.activeNetworkSupported) {
      return NetworkUnavailableView(
        toolName: 'Wi-Fi vs Internet',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }
    if (_source == WifiInfoSource.web) {
      return const NetworkUnavailableView(
        toolName: 'Wi-Fi vs Internet',
        reason: NetworkUnavailableReason.web,
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
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: 'wifi-vs-internet',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('wifi-vs-internet'))
                    const SizedBox(height: AppSpacing.md),
                  _runCard(context),
                  if (_running) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  if (_verdict != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _VerdictCard(result: _verdict!),
                    const SizedBox(height: AppSpacing.sm),
                    _WifiLinkSection(ap: _ap, result: _verdict!),
                    const SizedBox(height: AppSpacing.sm),
                    _InternetSection(result: _internet),
                    const SizedBox(height: AppSpacing.sm),
                    _footnote(context),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _runCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Measures your internet throughput, reads your Wi-Fi link rate, and '
            "tells you which one is the bottleneck. The negotiated data rate "
            'drives the verdict; RSSI and SNR explain why the rate is what it is.',
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: AppColors.statusDanger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Semantics(
            button: true,
            enabled: !_running,
            label: _running
                ? 'Running the Wi-Fi versus internet check'
                : 'Run the Wi-Fi versus internet check',
            child: FilledButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? 'Running…' : 'Run Check'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int pct = (_fraction * 100).round();
    final String caption = _phaseCaption(_phase);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // Sole liveRegion for the run so AT announces each phase once.
              Semantics(
                liveRegion: true,
                child: Text(
                  caption,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: '$caption, $pct percent complete',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: LinearProgressIndicator(
                value: _fraction == 0 ? null : _fraction,
                minHeight: 6,
                backgroundColor: AppColors.surface2,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _phaseCaption(QualityPhase phase) {
    switch (phase) {
      case QualityPhase.idle:
        return 'Starting…';
      case QualityPhase.latency:
        return 'Measuring latency…';
      case QualityPhase.download:
        return 'Measuring download…';
      case QualityPhase.upload:
        return 'Measuring upload…';
      case QualityPhase.complete:
        return 'Computing the verdict…';
      case QualityPhase.failed:
        return 'Failed';
    }
  }

  Widget _footnote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      kWifiVsInternetFootnote,
      style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}

// ===========================================================================
// Verdict card — status color (§8.13) + the verdict WORD (never color-only).
// ===========================================================================

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.result});

  final WifiVsInternetResult result;

  /// Maps each verdict to its §8.13 status token. The COLOR only reinforces the
  /// word in [WifiVsInternetResult.headline]; the word always carries the
  /// verdict (WCAG 2.2 SC 1.4.1).
  ///   wifiLimiter / upstream / bothContributing → a found-fault verdict
  ///     (warning amber — there is a bottleneck to act on, but it is advisory).
  ///   bothHealthy → success mint.
  ///   wifiUnknown → info sky-blue (a neutral "could not localize" state, not a
  ///     pass/fail verdict).
  static Color _statusColor(WifiVsInternetVerdict v) {
    switch (v) {
      case WifiVsInternetVerdict.bothHealthy:
        return AppColors.statusSuccess;
      case WifiVsInternetVerdict.wifiLimiter:
      case WifiVsInternetVerdict.upstream:
      case WifiVsInternetVerdict.bothContributing:
        return AppColors.statusWarning;
      case WifiVsInternetVerdict.wifiUnknown:
        return AppColors.statusInfo;
    }
  }

  /// Leading glyph reinforcing the verdict word by SHAPE (never color alone).
  static IconData _icon(WifiVsInternetVerdict v) {
    switch (v) {
      case WifiVsInternetVerdict.bothHealthy:
        return Icons.check_circle_outline;
      case WifiVsInternetVerdict.wifiLimiter:
        return Icons.wifi_outlined;
      case WifiVsInternetVerdict.upstream:
        return Icons.cloud_off_outlined;
      case WifiVsInternetVerdict.bothContributing:
        return Icons.compare_arrows;
      case WifiVsInternetVerdict.wifiUnknown:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color status = _statusColor(result.verdict);

    return Semantics(
      container: true,
      label:
          'Verdict: ${result.headline}. ${result.explanation}'
          '${result.snrContext.isNotEmpty ? ' ${result.snrContext}' : ''}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(_icon(result.verdict), size: 24, color: status),
                  const SizedBox(width: AppSpacing.xs),
                  // The verdict WORD, in the status hue. Flexible so a long
                  // headline wraps instead of overflowing at 320px.
                  Expanded(
                    child: Text(
                      result.headline,
                      style: text.titleMedium?.copyWith(
                        color: status,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                result.explanation,
                style: text.bodyLarge?.copyWith(color: AppColors.textPrimary),
              ),
              if (result.snrContext.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  result.snrContext,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// "Your Wi-Fi link" section.
// ===========================================================================

class _WifiLinkSection extends StatelessWidget {
  const _WifiLinkSection({required this.ap, required this.result});

  final ConnectedAp? ap;
  final WifiVsInternetResult result;

  @override
  Widget build(BuildContext context) {
    final ConnectedAp? a = ap;
    return _SectionCard(
      title: 'Your Wi-Fi link',
      children: <Widget>[
        _DataRow(
          label: 'Tx rate',
          value: _rate(a?.txRateMbps),
          unit: 'Mbps',
          mono: true,
        ),
        _DataRow(
          label: 'Rx rate',
          value: _rate(a?.rxRateMbps),
          unit: 'Mbps',
          mono: true,
          // Honest per-platform reason when Rx is never exposed (macOS public
          // CoreWLAN) vs simply absent this read.
          note: (a != null && !a.rxRateAvailable && a.rxRateMbps == null)
              ? 'Not reported on this platform'
              : null,
        ),
        _DataRow(
          label: 'Usable capacity',
          value: _rate(result.usableWifiMbps),
          unit: 'Mbps',
          mono: true,
          note:
              '55% of ${WifiVsInternetEngine.rateBasisCaption(result.rateBasis)}',
        ),
        _DataRow(
          label: 'SNR',
          value: a?.snrDb?.toString(),
          unit: 'dB',
          mono: true,
          derived: a?.snrDerived ?? false,
        ),
        _DataRow(
          label: 'RSSI',
          value: a?.rssiDbm?.toString(),
          unit: 'dBm',
          mono: true,
        ),
        _DataRow(label: 'Channel', value: a?.channel?.toString(), mono: true),
        _DataRow(label: 'Standard', value: a?.standard),
      ],
    );
  }

  static String? _rate(double? mbps) {
    if (mbps == null) return null;
    final double r = (mbps * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }
}

// ===========================================================================
// "Your internet" section.
// ===========================================================================

class _InternetSection extends StatelessWidget {
  const _InternetSection({required this.result});

  final QualityResult? result;

  @override
  Widget build(BuildContext context) {
    final QualityResult? r = result;
    final double? down = _value(r, MetricIds.download);
    final double? up = _value(r, MetricIds.upload);
    final double? avg = (down != null && up != null)
        ? (down + up) / 2
        : (down ?? up);

    return _SectionCard(
      title: 'Your internet',
      children: <Widget>[
        _DataRow(
          label: 'Download',
          value: _fmt(down),
          unit: 'Mbps',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.download)),
        ),
        _DataRow(
          label: 'Upload',
          value: _fmt(up),
          unit: 'Mbps',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.upload)),
        ),
        _DataRow(
          label: 'Averaged',
          value: _fmt(avg),
          unit: 'Mbps',
          mono: true,
          note: 'average of download and upload',
        ),
        _DataRow(
          label: 'Latency',
          value: _fmtMs(_value(r, MetricIds.latency)),
          unit: 'ms',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.latency)),
        ),
        _DataRow(
          label: 'Jitter',
          value: _fmtMs(_value(r, MetricIds.jitter)),
          unit: 'ms',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.jitter)),
        ),
        _DataRow(
          label: 'Loss',
          value: _fmtMs(_value(r, MetricIds.loss)),
          unit: '%',
          mono: true,
          trailing: _GradeChip(grade: _grade(r, MetricIds.loss)),
        ),
      ],
    );
  }

  static double? _value(QualityResult? r, String id) {
    final QualityMetric? m = r?.metric(id);
    return (m != null && m.isAvailable) ? m.value : null;
  }

  static QualityGrade _grade(QualityResult? r, String id) =>
      r?.metric(id)?.grade ?? QualityGrade.unavailable;

  static String? _fmt(double? mbps) => mbps?.toStringAsFixed(1);

  static String? _fmtMs(double? v) => v?.round().toString();
}

/// The §8.13 grade chip, ported from net_quality_screen so the two internet
/// surfaces grade identically. The grade WORD always carries the meaning; the
/// color only reinforces it (WCAG 2.2 SC 1.4.1).
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final QualityGrade grade;

  static (Color, Color) _colors(QualityGrade grade) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (AppColors.statusSuccess, AppColors.secondary);
      case QualityGrade.fair:
        return (AppColors.statusWarning, AppColors.secondary);
      case QualityGrade.poor:
        return (AppColors.statusDanger, AppColors.secondary);
      case QualityGrade.unavailable:
        return (AppColors.surface2, AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final (Color bg, Color fg) = _colors(grade);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: grade == QualityGrade.unavailable
            ? Border.all(color: AppColors.borderStrong, width: 1)
            : null,
      ),
      child: Text(
        grade.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ===========================================================================
// Shared presentation widgets.
// ===========================================================================

/// A titled surface1 card with a §8.1 hairline border, matching the other
/// network screens' card shell.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

/// One label → value data row, modeled on wifi_info_screen._MetricRow: a null
/// value renders "Unavailable" in textSecondary (muted but AA), each row is one
/// semantic node, identifiers/numerics render mono. Adds an optional trailing
/// widget (the grade chip) that ellipsizes the value before overflowing at
/// 320px.
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.label,
    required this.value,
    this.unit,
    this.mono = false,
    this.note,
    this.derived = false,
    this.trailing,
  });

  final String label;
  final String? value;
  final String? unit;
  final bool mono;
  final String? note;
  final bool derived;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue
        ? (unit == null ? value! : '${value!} $unit')
        : 'Unavailable';
    final Color valueColor = hasValue
        ? AppColors.textPrimary
        : AppColors.textSecondary;
    final TextStyle? valueStyle = (mono && hasValue)
        ? monoText.robotoMono.copyWith(color: valueColor)
        : text.bodyMedium?.copyWith(color: valueColor);

    final String labelSpoken = derived ? '$label, derived' : label;
    final String semanticLabel = note == null
        ? '$labelSpoken, $shown'
        : '$labelSpoken, $shown, $note';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (derived)
                        Text(
                          'derived',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                            letterSpacing: 0.4,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          shown,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: valueStyle,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                note!,
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
