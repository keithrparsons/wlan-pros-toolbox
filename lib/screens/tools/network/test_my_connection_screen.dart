// Test My Connection — the consumer companion to the pro `wifi-vs-internet`
// tool. Same backends, same verdict engine, plain-English re-skin.
//
// It answers ONE question for a non-technical person — is this my Wi-Fi or my
// internet? — gives the handful of facts a help desk will ask for, and lists a
// few safe, FCC-sourced things to try. The pro tool does not change; this is a
// presentation layer over engines that already ship.
//
// REUSE (zero new measurement code):
//   * the connected-AP link read — the SAME per-platform path the pro screen
//     uses (WifiInfoSourceResolver → MacWifiInfoAdapter on macOS / the
//     WiFiDetailsBridge → ConnectedAp.fromWifiDetails on iOS);
//   * a net_quality FULL run via the QualityClient seam (Keith's decision 2 —
//     no trimmed engine in v1);
//   * the same `_compute()` / `_internetHealth()` glue the pro screen carries,
//     lifted wholesale; then
//   * [ConsumerVerdictMapper] translates the engine's 5 enums → 4 consumer
//     outcomes (the only new "brain", pure-Dart + unit-tested).
//
// HONESTY (GL-005 / GL-008): a Wi-Fi link the platform cannot read (wired, or
// iOS without the companion Shortcut) lands on Outcome D1 — the internet result
// it DID measure, plainly told, with a soft optional Shortcut offer on iOS only
// (decision 4). Nothing is fabricated. The user gets their answer FIRST; the
// Shortcut offer is secondary and never blocks or nags.
//
// LAYOUT reuses the pro screen's shell: SafeArea + centered
// ConstrainedBox(maxWidth 560) + scroll + surface1 cards with a §8.1 hairline
// border; overflow-safe at 320px.
//
// STATES (SOP-007 §5): web/unsupported → NetworkUnavailableView · idle (intro +
// one big button) · running (friendly progress card, button disabled) · result
// (verdict + Wi-Fi details + help-desk facts + self-help cards) · error (in-card
// message + the button re-enabled to retry).
//
// Wi-Fi details (RSSI / SNR, Wi-Fi Down = avg Rx rate, Wi-Fi Up = avg Tx rate)
// come from the single connected-NIC read [ConnectedAp]; this tool does not
// sample the rate over the test window, so "average" is the NIC's reported
// average at read time. Any datum the platform does not expose (macOS public
// CoreWLAN never reports Rx rate) renders "Unavailable" on screen AND in the
// copy text — never fabricated or zero-filled (GL-005 / GL-008).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:net_quality/net_quality.dart';

import '../../../services/network/connected_ap.dart';
import '../../../services/network/consumer_verdict.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_vs_internet.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import 'install_shortcut_sheet.dart';
import 'network_unavailable_view.dart';

/// Consumer "is it my Wi-Fi or my internet?" screen.
class TestMyConnectionScreen extends StatefulWidget {
  const TestMyConnectionScreen({
    super.key,
    this.sourceOverride,
    this.macAdapter,
    this.iosBridge,
    this.qualityClient,
    this.nowOverride,
  });

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver] — the same resolver the pro screen uses.
  final WifiInfoSource? sourceOverride;

  /// Injectable macOS CoreWLAN adapter (tests). Defaults to the real adapter.
  final WifiInfoAdapter? macAdapter;

  /// Injectable iOS Shortcuts bridge (tests + the optional install sheet).
  /// Defaults to the real bridge.
  final WiFiDetailsBridge? iosBridge;

  /// Injectable net_quality backend (tests use a [MockQualityClient] with no
  /// network); null in production, where a real [OwnEngineQualityClient] runs.
  final QualityClient? qualityClient;

  /// Injectable clock for the "Tested:" timestamp (tests). Defaults to now.
  final DateTime Function()? nowOverride;

  @override
  State<TestMyConnectionScreen> createState() => _TestMyConnectionScreenState();
}

class _TestMyConnectionScreenState extends State<TestMyConnectionScreen> {
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
  ConsumerVerdict? _verdict;
  DateTime? _testedAt;

  StreamSubscription<QualityProgress>? _sub;

  /// True only on iOS (the companion-Shortcut source). macOS never shows the
  /// optional Shortcut offer and always produces a real verdict (decision 4).
  bool get _isIos => _source == WifiInfoSource.iosShortcuts;

  /// Plain platform word for the "Tested … on `<platform>`" fact (GL-005: the
  /// real platform, never invented).
  String get _platformLabel {
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        return 'macOS';
      case WifiInfoSource.iosShortcuts:
        return 'iOS';
      case WifiInfoSource.unsupported:
        return 'this device';
      case WifiInfoSource.web:
        return 'this browser';
    }
  }

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

  /// Reads the connected-AP link via the SAME per-platform path as the pro
  /// screen. Returns null when the link cannot be read (no reading, no Shortcut
  /// payload, or an unsupported source) — the engine then takes its honest
  /// wifiUnknown path (consumer Outcome D). Never throws to the caller.
  Future<ConnectedAp?> _readLink() async {
    try {
      switch (_source) {
        case WifiInfoSource.macosCoreWlan:
          final WifiInfoAdapter? adapter = _macAdapter;
          if (adapter == null) return null;
          // macOS gates the network NAME (SSID/BSSID) behind Location Services.
          // A consumer connection check must NEVER pop a Location prompt
          // mid-test (that is the pro Wi-Fi Information tool's job, via its
          // explicit "grant Location" button), and it never surfaces a
          // permission message either — the name is cosmetic here and the
          // facts row omits it gracefully when absent. So we do NOT touch the
          // authorization status at all; we just read the snapshot. The link
          // RATE — hence the Wi-Fi Fine/Slow chip and the verdict — resolves
          // WITHOUT Location; only the human-readable NAME depends on it.
          //
          // Bound the snapshot read: a stalled native channel must not hang the
          // check. On timeout the link reads as unread (null) and the verdict
          // degrades to the honest internet-only path (Outcome D).
          return await adapter.fetch().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
              'Wi-Fi link read timed out',
            ),
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
      // internet-only Outcome D rather than blocking the whole check.
      return null;
    }
  }

  /// Runs the internet measurement and the link read from one tap, then
  /// computes the engine verdict and translates it for the consumer.
  void _run() {
    setState(() {
      _error = null;
      _running = true;
      _phase = QualityPhase.idle;
      _fraction = 0;
      _ap = null;
      _internet = null;
      _verdict = null;
      _testedAt = null;
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
        // permission request at the adapter and the snapshot fetch here), but
        // guard this final await as well so the verdict ALWAYS computes even if
        // the link future stalls for any reason. A timeout yields ap = null →
        // the honest internet-only / wifiUnknown path (Outcome D).
        final ConnectedAp? ap = await linkFuture.timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
        if (!mounted) return;
        final WifiVsInternetResult engine = _compute(ap, internet);
        setState(() {
          _ap = ap;
          _internet = internet;
          _verdict = ConsumerVerdictMapper.map(
            engine,
            internetHealthy:
                _internetHealth(internet) == InternetHealth.good,
          );
          _testedAt = (widget.nowOverride ?? DateTime.now)();
          _running = false;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Connection check complete',
          TextDirection.ltr,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error =
              "Something went wrong and we couldn't finish the check. "
              'Please try again.';
        });
      },
    );
  }

  // ---- Backend glue, lifted wholesale from the pro screen ----

  /// Bridges the two engines into the pure [WifiVsInternetEngine]: translates
  /// the net_quality grades into the engine's [InternetHealth] flag at the
  /// boundary and forwards the link rates. Identical to the pro screen.
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

  /// Grade gate input — identical to the pro screen: GOOD only when throughput
  /// (download AND upload), latency, and loss ALL grade good/excellent.
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

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test My Connection'),
        toolbarHeight: 64,
        // §8.16 order: copy LEADS, the Refresh action trails. Copy is disabled
        // until a check has run (same payload as the inline "Copy these
        // details" button). Refresh re-runs the SAME check in place via _run()
        // — it appears only once a result exists (before that, the big "Check
        // My Connection" button is the affordance) and shows the in-progress
        // spinner while a re-run is underway so the test can't be double-fired.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ..._refreshAction(),
          // Help trails copy + refresh (§8.16).
          const ToolHelpAction(toolId: 'test-my-connection'),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// The AppBar "Refresh" action — re-runs the SAME check via [_run()] (no
  /// duplicated logic). Matches the Wi-Fi Information screen's affordance: a
  /// circular-arrow [IconButton] that swaps to a small in-progress spinner
  /// while a run is underway. Returns an empty list until a result exists, so
  /// the affordance only appears once there is something to re-run (the big
  /// "Check My Connection" button is the first-run affordance). The spinner +
  /// the run guard in [_run]/onPressed prevent a double-run.
  List<Widget> _refreshAction() {
    // Nothing to re-run before the first result lands.
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

  Widget _body() {
    // The internet measurement needs dart:io sockets the browser does not have;
    // route web (and any no-socket platform) to the shared download-the-app
    // fallback — never crash, never a broken screen.
    if (!NetworkSupport.activeNetworkSupported) {
      return NetworkUnavailableView(
        toolName: 'Test My Connection',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }
    if (_source == WifiInfoSource.web) {
      return const NetworkUnavailableView(
        toolName: 'Test My Connection',
        reason: NetworkUnavailableReason.web,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        final ConsumerVerdict? verdict = _verdict;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.md,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (verdict == null && !_running) _introCard(context),
                  if (verdict == null) _actionCard(context),
                  if (_running) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  if (verdict != null) ...[
                    _VerdictCard(verdict: verdict),
                    const SizedBox(height: AppSpacing.sm),
                    _WifiDetailsCard(details: _wifiDetails()),
                    const SizedBox(height: AppSpacing.sm),
                    _HelpDeskCard(
                      facts: _facts(),
                      onCopy: _copyDetails,
                      copied: _detailsCopied,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _SelfHelpCard(topic: verdict.selfHelp),
                    // iOS-only, decision 4: a soft optional Shortcut offer on
                    // the D1 path only, BELOW the self-help card, after the
                    // answer. macOS never shows it.
                    if (_isIos &&
                        verdict.outcome ==
                            ConsumerOutcome.couldntCheckWifi) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ShortcutOfferCard(onOpen: _openShortcutSheet),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _poweredBy(context),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Idle ----

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        "Not sure if it's your Wi-Fi or your internet? Tap below and find out "
        'in about a minute.',
        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _actionCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_error != null) ...[
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: AppColors.statusDanger),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Semantics(
          button: true,
          enabled: !_running,
          label: _running
              ? 'Checking your connection'
              : 'Check my connection',
          child: FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Checking…' : 'Check My Connection'),
          ),
        ),
      ],
    );
  }

  // ---- Running ----

  Widget _progressCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int pct = (_fraction * 100).round();
    final String caption = _friendlyPhase(_phase);
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            "This won't change any of your settings.",
            style: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Friendly, jargon-free phase captions (spec State 2). The user never sees
  /// "latency / download / upload". The spec sequence is
  /// "Starting…" → "Testing your internet speed…" → "Checking your Wi-Fi…" →
  /// "Working out the answer…" — latency/download read as the speed test, upload
  /// as the Wi-Fi check, complete as the answer.
  static String _friendlyPhase(QualityPhase phase) {
    switch (phase) {
      case QualityPhase.idle:
        return 'Starting…';
      case QualityPhase.latency:
      case QualityPhase.download:
        return 'Testing your internet speed…';
      case QualityPhase.upload:
        return 'Checking your Wi-Fi…';
      case QualityPhase.complete:
        return 'Working out the answer…';
      case QualityPhase.failed:
        return 'Something went wrong…';
    }
  }

  // ---- Result: the plain help-desk facts ----

  /// The plain facts, as label/value rows. Any field not measured prints
  /// "Not measured" — never blank, never invented (GL-005).
  List<_Fact> _facts() {
    final QualityResult? net = _internet;
    final ConnectedAp? ap = _ap;

    final double? down = _metricValue(net, MetricIds.download);
    final double? up = _metricValue(net, MetricIds.upload);
    final double? latency = _metricValue(net, MetricIds.latency);
    final double? loss = _metricValue(net, MetricIds.loss);

    final String? wifiName = _consumerWifiName(ap);

    return <_Fact>[
      // Each speed value on its own labeled row so it can never wrap mid-value
      // (e.g. "60" / "Mbps" splitting across lines). Parallels the Wi-Fi
      // Down/Up rows. "Not measured" stands in for any value the run did not
      // produce (GL-005) — never blank, never invented.
      _Fact('Internet Down', _mbps(down)),
      _Fact('Internet Up', _mbps(up)),
      _Fact(
        'Delay / dropped data',
        '${latency != null ? '${latency.round()} ms' : 'Not measured'} · '
            '${loss != null ? '${loss.round()}%' : 'Not measured'}',
      ),
      // Consumer flow: the network NAME is cosmetic. When it is unavailable
      // (macOS Location off, or simply not read) the row is OMITTED entirely
      // rather than surfacing a technical "enable Location Services" error that
      // makes a perfectly good connection test look broken. The Wi-Fi Fine/Slow
      // verdict and the link-detail rows never depend on the name.
      if (wifiName != null) _Fact('Wi-Fi network', wifiName),
      _Fact('Tested', '${_formatTimestamp(_testedAt)} on $_platformLabel'),
    ];
  }

  /// The Wi-Fi link detail rows: RSSI / SNR, Wi-Fi Down (avg Rx rate), and
  /// Wi-Fi Up (avg Tx rate), read from the connected NIC ([ConnectedAp]). Each
  /// value is taken from the single link read this tool performs; where the NIC
  /// does not expose a datum (e.g. macOS public CoreWLAN never reports the Rx
  /// rate) the value is "Unavailable" — never fabricated or zero-filled
  /// (GL-005 / GL-008). The same four rows feed the copy text.
  List<_Fact> _wifiDetails() {
    final ConnectedAp? ap = _ap;
    return <_Fact>[
      _Fact('RSSI / SNR', _rssiSnr(ap)),
      _Fact('Wi-Fi Down', _rxRate(ap)),
      _Fact('Wi-Fi Up', _txRate(ap)),
    ];
  }

  /// "RSSI / SNR" as e.g. "-58 dBm / 32 dB". Each half degrades to
  /// "Unavailable" on its own when the NIC omits it (GL-005).
  static String _rssiSnr(ConnectedAp? ap) {
    final int? rssi = ap?.rssiDbm;
    final int? snr = ap?.snrDb;
    final String rssiStr = rssi != null ? '$rssi dBm' : 'Unavailable';
    final String snrStr = snr != null ? '$snr dB' : 'Unavailable';
    return '$rssiStr / $snrStr';
  }

  /// Wi-Fi Down — the NIC's average Rx data rate. "Unavailable" when the
  /// platform never exposes Rx (macOS public CoreWLAN) or the read omitted it.
  static String _rxRate(ConnectedAp? ap) {
    final double? rx = ap?.rxRateMbps;
    return rx != null ? '${rx.round()} Mbps' : 'Unavailable';
  }

  /// Wi-Fi Up — the NIC's average Tx data rate. "Unavailable" when omitted.
  static String _txRate(ConnectedAp? ap) {
    final double? tx = ap?.txRateMbps;
    return tx != null ? '${tx.round()} Mbps' : 'Unavailable';
  }

  /// RSSI alone, for the separately-labeled copy line. "Unavailable" when the
  /// NIC omits it.
  static String _rssiOnly(ConnectedAp? ap) {
    final int? rssi = ap?.rssiDbm;
    return rssi != null ? '$rssi dBm' : 'Unavailable';
  }

  /// SNR alone, for the separately-labeled copy line. "Unavailable" when the
  /// NIC omits it (SNR is null unless both RSSI and noise are present).
  static String _snrOnly(ConnectedAp? ap) {
    final int? snr = ap?.snrDb;
    return snr != null ? '$snr dB' : 'Unavailable';
  }

  /// The Wi-Fi network NAME for the consumer flow, or null when it is not
  /// available. The name is purely cosmetic here — the Wi-Fi Fine/Slow verdict
  /// and every link-detail row resolve WITHOUT it. So when the platform can not
  /// give us a real name (macOS gates the SSID behind Location Services per
  /// Apple's rule, or the link was simply not read) we return null and the
  /// caller OMITS the row, rather than surfacing a technical
  /// "enable Location Services" error that makes a healthy connection test read
  /// as broken. Never fabricates a name (GL-005). The PRO Wi-Fi Information tool
  /// keeps its explicit Location messaging; this graceful degrade is scoped to
  /// the consumer experience.
  String? _consumerWifiName(ConnectedAp? ap) {
    final String? ssid = ap?.ssid;
    if (ssid != null && ssid.trim().isNotEmpty) return ssid;
    return null;
  }

  /// Mbps rounded to a whole number for a consumer, or "Not measured".
  static String _mbps(double? v) =>
      v == null ? 'Not measured' : '${v.round()} Mbps';

  /// "Jun 1, 2:14 PM" — month-day + 12-hour clock, no dependency on intl.
  static String _formatTimestamp(DateTime? at) {
    if (at == null) return 'Not measured';
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String month = months[at.month - 1];
    final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String minute = at.minute.toString().padLeft(2, '0');
    final String meridiem = at.hour < 12 ? 'AM' : 'PM';
    return '$month ${at.day}, $hour12:$minute $meridiem';
  }

  // ---- §8.16 copy payload (shared by toolbar + inline button) ----

  bool _detailsCopied = false;

  /// The clipboard format VERBATIM from the spec. The verdict WORD always leads
  /// (§8.16 / §8.13); unmeasured fields print "Not measured" (GL-005).
  String? _buildCopyText() {
    if (_running || _verdict == null) return null;
    final List<_Fact> facts = _facts();
    String fact(String label) =>
        facts.firstWhere((f) => f.label == label).value;

    final QualityResult? net = _internet;
    final double? down = _metricValue(net, MetricIds.download);
    final double? up = _metricValue(net, MetricIds.upload);
    final double? latency = _metricValue(net, MetricIds.latency);
    final double? loss = _metricValue(net, MetricIds.loss);

    // R1-A — the two-axis status line, reinforcing the Wi-Fi vs Internet model
    // in the help-desk paste (e.g. "Wi-Fi: Fine · Internet: Slow").
    final ConsumerVerdict? v = _verdict;
    final StringBuffer buf = StringBuffer()
      ..writeln('Test My Connection (WLAN Pros Toolbox)');
    if (v != null) {
      buf.writeln(
        'Wi-Fi: ${_TwoAxisChips.word(v.wifiStatus)} · '
        'Internet: ${_TwoAxisChips.word(v.internetStatus)}',
      );
    }
    final String? wifiName = _consumerWifiName(_ap);
    buf
      // Internet down and up on their own labeled lines — one value per line,
      // parallel to the Wi-Fi Down / Wi-Fi Up lines below.
      ..writeln('Internet Down: ${_mbps(down)}')
      ..writeln('Internet Up: ${_mbps(up)}')
      ..writeln(
        'Delay: ${latency != null ? '${latency.round()} ms' : 'Not measured'}   '
        'Dropped data: ${loss != null ? '${loss.round()}%' : 'Not measured'}',
      );
    // Consumer copy: include the network NAME line only when we actually have a
    // name — never paste a "enable Location Services" error into a help-desk
    // ticket (it reads as a fault, and the name is cosmetic here).
    if (wifiName != null) {
      buf.writeln('Wi-Fi network: $wifiName');
    }
    buf
      // Wi-Fi link details from the connected NIC — "Unavailable" where the
      // platform does not expose a datum (GL-005 / GL-008), never fabricated.
      ..writeln('RSSI: ${_rssiOnly(_ap)}')
      ..writeln('SNR: ${_snrOnly(_ap)}')
      ..writeln('Wi-Fi Down: ${_rxRate(_ap)}')
      ..writeln('Wi-Fi Up: ${_txRate(_ap)}')
      ..writeln('Tested: ${fact('Tested')}');
    return buf.toString().trimRight();
  }

  Future<void> _copyDetails() async {
    final String? text = _buildCopyText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Details copied',
      TextDirection.ltr,
    );
    setState(() => _detailsCopied = true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _detailsCopied = false);
    });
  }

  // ---- iOS optional Shortcut offer (decision 4) ----

  Future<void> _openShortcutSheet() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface2,
      isScrollControlled: true,
      builder: (_) => InstallShortcutSheet(
        bridge: bridge,
        // The consumer flow does not re-stream; "installed" simply re-runs the
        // check so the next pass can read the link.
        onInstalled: () async {
          if (mounted) _run();
        },
      ),
    );
  }

  Widget _poweredBy(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Text(
        'Powered by the WLAN Pros Toolbox',
        style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

// ===========================================================================
// A single help-desk fact (label → value).
// ===========================================================================

class _Fact {
  const _Fact(this.label, this.value);
  final String label;
  final String value;
}

// ===========================================================================
// Verdict card — status color (§8.13) + the verdict WORD (never color-only).
// ===========================================================================

/// R1-A — the result verdict card. The card itself is NEUTRAL (surface1 +
/// hairline, no full-card tint); the COLOR lives in the two status chips.
///
/// Layout: two labeled chips ("Wi-Fi:" / "Internet:"). The chips ARE the
/// verdict — they teach the non-technical reader that Wi-Fi and Internet are
/// two separate things, and each axis carries its OWN explicit status so a
/// missing Wi-Fi read shows as "Wi-Fi: Couldn't check", never a silent gap.
///
/// The explanatory conclusion sentence was removed 2026-06-02 (Keith) — the
/// status chips and the measured facts below them speak for themselves. The
/// chips render for every outcome, including D2 (both axes "Couldn't check").
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict});

  final ConsumerVerdict verdict;

  @override
  Widget build(BuildContext context) {
    // SR reads the two axis statuses as one container.
    final String semanticsLabel =
        'Wi-Fi ${_TwoAxisChips.word(verdict.wifiStatus)}. '
        'Internet ${_TwoAxisChips.word(verdict.internetStatus)}.';

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _TwoAxisChips(
            wifiStatus: verdict.wifiStatus,
            internetStatus: verdict.internetStatus,
          ),
        ),
      ),
    );
  }
}

/// The two labeled axis rows — "Wi-Fi:" and "Internet:", each with a status
/// chip. Aligned labels keep the two words scannable in under two seconds.
class _TwoAxisChips extends StatelessWidget {
  const _TwoAxisChips({
    required this.wifiStatus,
    required this.internetStatus,
  });

  final AxisStatus wifiStatus;
  final AxisStatus internetStatus;

  /// Plain status WORD — the single source the card, chip, and SR label share.
  static String word(AxisStatus s) {
    switch (s) {
      case AxisStatus.fine:
        return 'Fine';
      case AxisStatus.slow:
        return 'Slow';
      case AxisStatus.unknown:
        return "Couldn't check";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AxisRow(label: 'Wi-Fi', status: wifiStatus),
        const SizedBox(height: AppSpacing.xs),
        _AxisRow(label: 'Internet', status: internetStatus),
      ],
    );
  }
}

/// One axis: an aligned plain label + a status chip.
class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.label, required this.status});

  final String label;
  final AxisStatus status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 84,
          child: Text(
            '$label:',
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: _StatusChip(status: status)),
      ],
    );
  }
}

/// A single status chip: icon + WORD + §8.13 color. The WORD always carries
/// meaning (WCAG 2.2 SC 1.4.1, never color alone). Fine → status-good, Slow →
/// status-warn, "Couldn't check" → a neutral/muted token.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AxisStatus status;

  /// §8.13 token per status. Neutral muted text token for the unknown axis so a
  /// "couldn't check" never reads as an alarm color.
  Color get _color {
    switch (status) {
      case AxisStatus.fine:
        return AppColors.statusSuccess;
      case AxisStatus.slow:
        return AppColors.statusWarning;
      case AxisStatus.unknown:
        return AppColors.textTertiary;
    }
  }

  /// Glyph reinforcing the word by SHAPE (✓ / ⚠ / –), never color alone.
  IconData get _icon {
    switch (status) {
      case AxisStatus.fine:
        return Icons.check_circle_outline;
      case AxisStatus.slow:
        return Icons.warning_amber_outlined;
      case AxisStatus.unknown:
        return Icons.remove_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = _color;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              _TwoAxisChips.word(status),
              style: text.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// "Wi-Fi details" card — the connected-NIC link facts: RSSI / SNR, Wi-Fi Down
// (avg Rx rate), Wi-Fi Up (avg Tx rate). Any datum the platform does not
// expose renders "Unavailable" — never fabricated (GL-005 / GL-008).
// ===========================================================================

class _WifiDetailsCard extends StatelessWidget {
  const _WifiDetailsCard({required this.details});

  final List<_Fact> details;

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
            'Wi-Fi details',
            style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...details.map((f) => _FactRow(fact: f)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Help-desk facts card — plain measured facts + inline copy button. The copy
// button serializes the verdict, these facts, AND the Wi-Fi link details.
// ===========================================================================

class _HelpDeskCard extends StatelessWidget {
  const _HelpDeskCard({
    required this.facts,
    required this.onCopy,
    required this.copied,
  });

  final List<_Fact> facts;
  final Future<void> Function() onCopy;
  final bool copied;

  @override
  Widget build(BuildContext context) {
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
          ...facts.map((f) => _FactRow(fact: f)),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: copied ? 'Details copied' : 'Copy these details',
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: Icon(
                copied ? Icons.check : Icons.copy_outlined,
                size: 20,
                color: copied
                    ? AppColors.statusSuccess
                    : AppColors.textSecondary,
              ),
              label: Text(copied ? 'Copied' : 'Copy these details'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One help-desk fact as a label → value row. The whole row is one semantic
/// node ("`label, value`"). Value wraps before overflowing at 320px.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding / 2),
      child: Semantics(
        container: true,
        label: '${fact.label}, ${fact.value}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Text(
                fact.label,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                fact.value,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// "A few things to try" card — only the relevant vetted self-help list.
// ===========================================================================

class _SelfHelpCard extends StatelessWidget {
  const _SelfHelpCard({required this.topic});

  final SelfHelpTopic topic;

  /// The vetted, FCC-sourced self-help copy (spec §Self-help lists), verbatim.
  /// Easiest-first; all non-destructive.
  static const Map<SelfHelpTopic, List<String>> _items =
      <SelfHelpTopic, List<String>>{
    SelfHelpTopic.wifi: <String>[
      'Move closer to the router, or move the router to a more central, open '
          'spot.',
      'Restart your router: unplug it, wait about 60 seconds, plug it back in, '
          'give it a couple of minutes.',
      'Pause other big downloads or streams competing for the connection.',
    ],
    SelfHelpTopic.internet: <String>[
      "Check for an outage: open your provider's website or app and look for a "
          'reported outage in your area.',
      'Restart your modem (the box from your provider) first, then your router.',
      'Still slow? Contact your provider with the copied details above; '
          'equipment may be outdated or there may be a service issue only they '
          'can see.',
    ],
    SelfHelpTopic.differentApp: <String>[
      'Try the same thing in a different app or website. If only one app is '
          'slow, the problem is on their end, and waiting or contacting that '
          'service is the fix.',
    ],
    SelfHelpTopic.reconnect: <String>[
      "Make sure you're on Wi-Fi and try again.",
    ],
  };

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> items = _items[topic] ?? const <String>[];
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
            'A few things to try',
            style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...items.map((item) => _SelfHelpItem(text: item)),
        ],
      ),
    );
  }
}

class _SelfHelpItem extends StatelessWidget {
  const _SelfHelpItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyLarge?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// iOS-only optional Shortcut offer (decision 4) — soft, secondary, post-answer.
// ===========================================================================

class _ShortcutOfferCard extends StatelessWidget {
  const _ShortcutOfferCard({required this.onOpen});

  final VoidCallback onOpen;

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
            'Want a deeper Wi-Fi check?',
            style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add the companion Shortcut to let this app read your Wi-Fi '
            'details next time. Optional, and it only takes a minute.',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: onOpen,
              child: const Text('Add the companion Shortcut'),
            ),
          ),
        ],
      ),
    );
  }
}
