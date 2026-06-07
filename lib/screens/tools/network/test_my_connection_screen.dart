// Test My Connection — the ONE merged connection tool (Wave 4, 2026-06-04).
//
// Progressive disclosure: it leads with the plain consumer answer (is this my
// Wi-Fi or my internet?), tucks the full pro "Wi-Fi vs Internet" depth one tap
// away, and runs a live "Wi-Fi signal" sparkline card so the tool doubles as a
// walk-around instrument. It replaces BOTH former screens — the consumer
// `test-my-connection` and the pro `wifi-vs-internet` — so nothing the pro tool
// showed is lost; it moves into the expandable technical section.
//
// REUSE (zero new measurement / verdict / sampling code):
//   * the connected-AP link read — the SAME per-platform path wifi-info uses
//     (MacWifiInfoAdapter on macOS / WiFiDetailsBridge on iOS);
//   * a net_quality FULL run via the QualityClient seam;
//   * the duplicated engine glue, now in ONE shared [ConnectionCheck] service;
//   * [ConsumerVerdictMapper] as the consumer "brain" (untouched);
//   * the live RF feed + sparklines via the shared [WifiSignalSampler] (the same
//     MacWifiInfoAdapter poll / WifiMonitorController stream wifi-info ships),
//     windowed to 30s for this tool; rendered with the shared [Sparkline].
//
// HONESTY (GL-005 / GL-008): a Wi-Fi link the platform cannot read (wired, or
// iOS without the companion Shortcut) lands on the engine's honest internet-only
// path — Outcome D — with a soft optional Shortcut offer on iOS only. Any datum
// the platform never exposes (macOS public CoreWLAN never reports Rx rate)
// renders "Unavailable" on screen AND in the copy text, never fabricated.
//
// LAYOUT: SafeArea + centered ConstrainedBox(maxWidth 560) + scroll; surface1
// cards with a §8.1 hairline border; overflow-safe at 320px. Per-tool help is a
// bottom ToolHelpFooter (§8.16.1); copy stays the trailing AppBar action (§8.16).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:net_quality/net_quality.dart';

import '../../../services/network/connected_ap.dart';
import '../../../services/network/connection_check.dart';
import '../../../services/network/consumer_verdict.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_grading.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_signal_sampler.dart';
import '../../../services/network/wifi_time_series.dart';
import '../../../services/network/wifi_vs_internet.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/sparkline.dart';
import '../../../widgets/tool_help_footer.dart';
import 'install_shortcut_sheet.dart';
import 'network_unavailable_view.dart';

/// The footnote method-disclosure, VERBATIM from the pro screen's spec. Kept as
/// a named constant so the test asserts the exact string and the technical
/// section renders it unchanged after the merge.
const String kWifiVsInternetFootnote =
    '* Usable Wi-Fi capacity is estimated at 55% of the average negotiated '
    'Tx/Rx data rate (real-world Wi-Fi throughput runs about 50 to 60 percent '
    'of the PHY rate). Internet throughput is the average of the measured '
    'download and upload speeds. The verdict compares the two: internet within '
    '70% of usable Wi-Fi capacity points to the Wi-Fi link as the limiter; '
    'below 40% points upstream to the internet. RSSI and SNR are shown as '
    'supporting context; the negotiated data rate drives the verdict.';

/// The merged "is it my Wi-Fi or my internet?" screen.
class TestMyConnectionScreen extends StatefulWidget {
  const TestMyConnectionScreen({
    super.key,
    this.sourceOverride,
    this.macAdapter,
    this.iosBridge,
    this.qualityClient,
    this.nowOverride,
    this.autoStart = false,
    this.startExpanded = false,
    this.sampler,
    this.enableLiveSampling = true,
  });

  /// When true, the check runs automatically on first mount instead of waiting
  /// for the user to tap "Check My Connection". Used by the home consumer hero
  /// card so its one tap goes straight into the test.
  final bool autoStart;

  /// Retained no-op since v1.1 (2026-06-05). The "See the details" disclosure was
  /// removed and the full technical detail is now ALWAYS rendered, so there is no
  /// collapsed state to pre-expand. The old `/tools/wifi-vs-internet` deep link
  /// still passes `startExpanded: true`; it now lands on the same always-detailed
  /// view. Kept so existing call sites compile unchanged.
  final bool startExpanded;

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver].
  final WifiInfoSource? sourceOverride;

  /// Injectable macOS CoreWLAN adapter (tests). Defaults to the real adapter.
  final WifiInfoAdapter? macAdapter;

  /// Injectable iOS Shortcuts bridge (tests + the optional install sheet).
  final WiFiDetailsBridge? iosBridge;

  /// Injectable net_quality backend (tests use a [MockQualityClient]).
  final QualityClient? qualityClient;

  /// Injectable clock for the "Tested:" timestamp (tests).
  final DateTime Function()? nowOverride;

  /// Injectable live sampler (tests). Defaults to a real [WifiSignalSampler] on
  /// the resolved platform.
  final WifiSignalSampler? sampler;

  /// When false, the live sampler is never started (tests that do not exercise
  /// the live card disable it so no poll timer ticks). Production leaves it on.
  final bool enableLiveSampling;

  @override
  State<TestMyConnectionScreen> createState() => _TestMyConnectionScreenState();
}

class _TestMyConnectionScreenState extends State<TestMyConnectionScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;
  WifiInfoAdapter? _macAdapter;
  WiFiDetailsBridge? _iosBridge;
  late final QualityClient _quality;

  /// The shared live-RF sampler that feeds the "Wi-Fi signal" sparkline card.
  /// Continuous while the screen is open (macOS auto-polls; iOS streams via the
  /// companion Shortcut). Null on web / unsupported.
  WifiSignalSampler? _sampler;

  bool _running = false;
  String? _error;

  // Internet progress.
  QualityPhase _phase = QualityPhase.idle;
  double _fraction = 0;

  // Results, populated when the run completes.
  ConnectedAp? _ap;
  QualityResult? _internet;
  ConsumerVerdict? _verdict;
  WifiVsInternetResult? _engine;
  DateTime? _testedAt;

  StreamSubscription<QualityProgress>? _sub;

  /// True only on iOS (the companion-Shortcut source).
  bool get _isIos => _source == WifiInfoSource.iosShortcuts;

  /// Plain platform word for the "Tested … on `<platform>`" fact (GL-005).
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

    // Live "Wi-Fi signal" sampler — the same per-platform feed wifi-info uses,
    // windowed to 30s for this tool (the sampler sets its own capacity; it does
    // not touch wifi-info's defaults). Only built where a live feed exists.
    if (widget.enableLiveSampling &&
        (_source == WifiInfoSource.macosCoreWlan ||
            _source == WifiInfoSource.iosShortcuts)) {
      _sampler = widget.sampler ??
          WifiSignalSampler(
            source: _source,
            macAdapter: _macAdapter,
            iosBridge: _iosBridge,
          );
      WidgetsBinding.instance.addObserver(this);
      _sampler!.load();
      // AUTO-START THE LIVE CAPTURE (item #8).
      //
      // macOS sources its live feed from NATIVE polling (CoreWLAN snapshots on a
      // timer, no app switch), so it auto-starts cleanly on screen entry — the
      // sparklines begin filling as soon as the first sample lands, with no tap.
      // This holds whether the screen was reached by tapping "Check My
      // Connection" or via the home hero's auto-run argument.
      //
      // iOS sources its live feed from the Shortcuts bridge: start() fires the
      // companion "WLAN Pros Live" Shortcut, which SWITCHES to the Shortcuts app.
      // Auto-firing that on screen entry would bounce the user straight out of
      // the app — a jarring auto-bounce. So iOS keeps the single explicit Start
      // kickoff in the live card; we do not auto-fire the bridge. The comparison
      // test still auto-runs on the home-hero path; only the iOS RF stream waits
      // for the one deliberate tap (GL-008: build to the platform, no fabricated
      // auto-behavior that the bridge cannot honor).
      if (_source == WifiInfoSource.macosCoreWlan) {
        _sampler!.start();
      }
    }

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final WifiSignalSampler? sampler = _sampler;
    if (sampler == null) return;
    if (state == AppLifecycleState.resumed) {
      sampler.load();
      sampler.resumeMac();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      sampler.pauseMac();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_sampler != null) {
      WidgetsBinding.instance.removeObserver(this);
      // Only dispose a sampler we created; an injected one is the test's.
      if (widget.sampler == null) _sampler!.dispose();
    }
    super.dispose();
  }

  /// Reads the connected-AP link via the SAME per-platform path as wifi-info.
  /// Returns null when the link cannot be read — the engine then takes its
  /// honest wifiUnknown path (Outcome D). Never throws to the caller.
  Future<ConnectedAp?> _readLink() async {
    try {
      switch (_source) {
        case WifiInfoSource.macosCoreWlan:
          final WifiInfoAdapter? adapter = _macAdapter;
          if (adapter == null) return null;
          // A consumer check must never pop a Location prompt mid-test (the link
          // RATE — hence the verdict — resolves WITHOUT Location; only the NAME
          // needs it). Read the snapshot directly, bounded so a stalled channel
          // can never hang the check.
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
      return null;
    }
  }

  /// Runs the internet measurement and the link read from one tap, then computes
  /// the engine verdict (shared [ConnectionCheck]) and translates it for the
  /// consumer ([ConsumerVerdictMapper]).
  void _run() {
    setState(() {
      _error = null;
      _running = true;
      _phase = QualityPhase.idle;
      _fraction = 0;
      _ap = null;
      _internet = null;
      _verdict = null;
      _engine = null;
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
        final ConnectedAp? ap = await linkFuture.timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
        if (!mounted) return;
        final WifiVsInternetResult engine = ConnectionCheck.compute(
          ap,
          internet,
        );
        setState(() {
          _ap = ap;
          _internet = internet;
          _engine = engine;
          _verdict = ConsumerVerdictMapper.map(
            engine,
            internetHealthy:
                ConnectionCheck.internetHealth(internet) ==
                InternetHealth.good,
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

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test My Connection'),
        toolbarHeight: 64,
        // §8.16: copy LEADS, the Refresh action trails. Help is the bottom
        // footer (§8.16.1), not an AppBar glyph.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ..._refreshAction(),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// The AppBar "Refresh" action — re-runs the SAME check via [_run()]. Returns
  /// an empty list until a result exists.
  List<Widget> _refreshAction() {
    if (_verdict == null && !_running) return const <Widget>[];
    if (_running) {
      // The spinner is a thin foreground graphic on the canvas → darkened-lime
      // in light (brand lime would vanish on white), brand lime in dark.
      final Color spinner = context.colors.isLight
          ? context.colors.textAccent
          : context.colors.primary;
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: spinner,
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
    // route web (and any no-socket platform) to the shared fallback.
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
                    // (A) VERDICT HERO — the H1/36px plain-language sentence +
                    //     the two axis status chips side by side (§2.A / §2.A2).
                    _HeroVerdict(
                      verdict: verdict,
                      heroSentence: _heroSentence(verdict),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // VERDICT LINE — a plain, state-driven sentence that names the
                    // limiter, plus the direct % comparison answer. Both ALWAYS
                    // shown, prominent (no disclosure). The v1.1 "show more" pass
                    // walked back the over-simplified reshape (Keith, 2026-06-05).
                    _VerdictLine(
                      verdict: _verdictLine(verdict),
                      comparison: _comparisonLine(verdict),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // DETAILS — the Mbps / bars / live signal / pro readout, now
                    // ALWAYS rendered (the "See the details" disclosure was
                    // removed in v1.1 to return to showing more information).
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // Core comparison — usable Wi-Fi vs internet bars.
                        _ComparisonCard(result: _engine!),
                        const SizedBox(height: AppSpacing.sm),
                        // Live "Wi-Fi signal" sparkline card.
                        if (_sampler != null) ...[
                          _LiveSignalCard(sampler: _sampler!),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        // "What to tell support".
                        _HelpDeskCard(
                          facts: _facts(),
                          onCopy: _copyDetails,
                          copied: _detailsCopied,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // The absorbed pro "Wi-Fi vs Internet" readout.
                        _TechnicalSection(
                          ap: _ap,
                          internet: _internet,
                          result: _engine!,
                        ),
                      ],
                    ),
                    // iOS-only soft optional Shortcut offer on the D1 path only.
                    if (_isIos &&
                        verdict.outcome ==
                            ConsumerOutcome.couldntCheckWifi) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ShortcutOfferCard(onOpen: _openShortcutSheet),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    _poweredBy(context),
                  ],
                  ToolHelpFooter(toolId: 'test-my-connection'),
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
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        "Not sure if it's your Wi-Fi or your internet? Tap below and find out "
        'in about a minute.',
        style: text.bodyLarge?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _actionCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_error != null) ...[
          Container(
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: colors.border,
                width: colors.isLight ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              _error!,
              style: text.bodyMedium?.copyWith(color: colors.statusDanger),
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
    final AppColorScheme colors = context.colors;
    final int pct = (_fraction * 100).round();
    final String caption = _friendlyPhase(_phase);
    // The progress fill is a FILL (a bar), so brand lime is sanctioned in both
    // themes (§8.20.2 lime-may-be-a-fill). The track sits below it; on light,
    // surface2 is white and would be invisible against the white card, so the
    // track uses the gray canvas tone instead.
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Semantics(
                liveRegion: true,
                child: Text(
                  caption,
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0.4,
                    fontWeight:
                        colors.isLight ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$pct%',
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: '$caption, $pct percent complete',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _fraction),
                duration: AppMotion.base,
                curve: AppMotion.standardEase,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: _fraction == 0 ? null : value,
                    minHeight: 6,
                    backgroundColor:
                        colors.isLight ? colors.surface0 : colors.surface2,
                    // Progress fill: a 6px bar is a vivid AREA, so it carries
                    // full brand lime in both themes (§8.20.3-B/C).
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Testing your Wi-Fi and your internet connection.',
            style: text.bodyMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Friendly, jargon-free phase captions. The user never sees
  /// "latency / download / upload".
  static String _friendlyPhase(QualityPhase phase) {
    switch (phase) {
      case QualityPhase.idle:
        return 'Starting…';
      case QualityPhase.latency:
      case QualityPhase.download:
        return 'Testing your internet speed…';
      case QualityPhase.upload:
        return 'Checking your Wi-Fi…';
      case QualityPhase.responsiveness:
      case QualityPhase.complete:
        return 'Working out the answer…';
      case QualityPhase.failed:
        return 'Something went wrong…';
    }
  }

  // ---- v1.1 readability copy (§2–§4) ----
  //
  // Every string below is authored to Flesch-Kincaid grade ≤ 8.0 PER STRING
  // (§4). The hero sentence, the "what this means" line, the D1 number anchor,
  // and the self-help steps are all measured; the worst is 6.7. The D1 path is
  // the only one that surfaces a raw number — it carries a use-case ANCHOR (§3),
  // never a bare figure at the verdict level.

  /// (A) The plain-language VERDICT HERO sentence (§2.A), one per outcome. Short,
  /// active, second person, most-important-first — FK ≤ 8.0 each.
  String _heroSentence(ConsumerVerdict verdict) {
    switch (verdict.outcome) {
      case ConsumerOutcome.wifi:
        return 'Your Wi-Fi is the slow part.';
      case ConsumerOutcome.wifiLead:
        return 'Your Wi-Fi is mostly the slow part.';
      case ConsumerOutcome.internet:
        return 'Your internet is the slow part.';
      case ConsumerOutcome.bothFine:
        return 'Your Wi-Fi and internet both look fine.';
      case ConsumerOutcome.couldntCheckWifi:
        return 'We checked your internet, but not your Wi-Fi.';
      case ConsumerOutcome.couldntComplete:
        return 'We could not finish the check.';
    }
  }

  /// The plain, state-driven VERDICT LINE that names the limiter (item #4). It
  /// maps off the SAME verdict classification the engine produced — the line and
  /// the comparison bars always agree. The "could not check one side" rows keep
  /// an honest neutral line and never assert a verdict we do not have (GL-005).
  String _verdictLine(ConsumerVerdict verdict) {
    switch (verdict.outcome) {
      case ConsumerOutcome.wifi:
      case ConsumerOutcome.wifiLead:
        // Usable Wi-Fi is clearly below the measured internet — Wi-Fi limits.
        return 'Your Wi-Fi is the weak link right now.';
      case ConsumerOutcome.internet:
        // Usable Wi-Fi clearly exceeds the measured internet — internet limits.
        return 'Your internet is the limit right now, not your Wi-Fi.';
      case ConsumerOutcome.bothFine:
        // Both strong / about even.
        return 'Both your Wi-Fi and your internet are keeping up.';
      case ConsumerOutcome.couldntCheckWifi:
        // Internet measured, Wi-Fi not — honest, no verdict on the missing side.
        return 'We measured your internet, but could not read your Wi-Fi on '
            'this device.';
      case ConsumerOutcome.couldntComplete:
        // Neither side read — honest neutral line.
        return 'We could not read your Wi-Fi or your internet. Make sure you '
            'are on Wi-Fi, then try again.';
    }
  }

  /// The DIRECT COMPARISON sentence (item #5): a single headline answer comparing
  /// the SAME two quantities the verdict already compares — the usable Wi-Fi data
  /// rate vs the measured internet rate. N = round(100 * (usableWifi - internet)
  /// / internet). Faster when usable > internet, slower when below, "about the
  /// same" within +/-10%. Returns null (the line is suppressed) when the internet
  /// side could not be measured or is ~0 — the honest neutral verdict line then
  /// carries the result on its own (GL-005: the % is only ever shown from real
  /// measured numbers, never fabricated).
  String? _comparisonLine(ConsumerVerdict verdict) {
    final double? usable = _engine?.usableWifiMbps;
    final double? internet = _engine?.internetAvgMbps;
    // Suppress when either side is missing or the internet rate is ~0 (no truthful
    // denominator). The verdict line already states the honest couldn't-check.
    if (usable == null || internet == null || internet < 0.5) return null;

    final double deltaPct = 100 * (usable - internet) / internet;
    final int n = deltaPct.abs().round();
    // Within +/-10% reads as "about the same speed" rather than a near-zero %.
    if (deltaPct.abs() <= 10) {
      return 'Your Wi-Fi link and your internet connection are running at about '
          'the same speed.';
    }
    final String direction = deltaPct > 0 ? 'faster' : 'slower';
    return 'Your Wi-Fi link is $n% $direction than your internet connection.';
  }

  // ---- Result: the plain help-desk facts ----

  /// The plain facts, as label/value rows. Any field not measured prints
  /// "Not measured" — never blank, never invented (GL-005).
  List<_Fact> _facts() {
    final QualityResult? net = _internet;
    final ConnectedAp? ap = _ap;

    final double? down = ConnectionCheck.metricValue(net, MetricIds.download);
    final double? up = ConnectionCheck.metricValue(net, MetricIds.upload);
    final double? latency =
        ConnectionCheck.metricValue(net, MetricIds.latency);
    final double? loss = ConnectionCheck.metricValue(net, MetricIds.loss);

    final String? wifiName = _consumerWifiName(ap);

    return <_Fact>[
      _Fact('Internet Down', _mbps(down)),
      _Fact('Internet Up', _mbps(up)),
      _Fact(
        'Delay / dropped data',
        '${latency != null ? '${latency.round()} ms' : 'Not measured'} · '
            '${loss != null ? '${loss.round()}%' : 'Not measured'}',
      ),
      if (wifiName != null) _Fact('Wi-Fi network', wifiName),
      _Fact('Tested', '${_formatTimestamp(_testedAt)} on $_platformLabel'),
    ];
  }

  /// The Wi-Fi network NAME for the consumer flow, or null when not available.
  String? _consumerWifiName(ConnectedAp? ap) {
    final String? ssid = ap?.ssid;
    if (ssid != null && ssid.trim().isNotEmpty) return ssid;
    return null;
  }

  /// RSSI alone, for the copy line. "Unavailable" when the NIC omits it.
  static String _rssiOnly(ConnectedAp? ap) {
    final int? rssi = ap?.rssiDbm;
    return rssi != null ? '$rssi dBm' : 'Unavailable';
  }

  /// SNR alone, for the copy line. "Unavailable" when the NIC omits it.
  static String _snrOnly(ConnectedAp? ap) {
    final int? snr = ap?.snrDb;
    return snr != null ? '$snr dB' : 'Unavailable';
  }

  /// Wi-Fi Down — the NIC's average Rx data rate. "Unavailable" when omitted.
  static String _rxRate(ConnectedAp? ap) {
    final double? rx = ap?.rxRateMbps;
    return rx != null ? '${rx.round()} Mbps' : 'Unavailable';
  }

  /// Wi-Fi Up — the NIC's average Tx data rate. "Unavailable" when omitted.
  static String _txRate(ConnectedAp? ap) {
    final double? tx = ap?.txRateMbps;
    return tx != null ? '${tx.round()} Mbps' : 'Unavailable';
  }

  /// Mbps rounded to a whole number for a consumer, or "Not measured".
  static String _mbps(double? v) =>
      v == null ? 'Not measured' : '${v.round()} Mbps';

  /// "Jun 1, 2:14 PM" — month-day + 12-hour clock, no intl dependency.
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
    final double? down = ConnectionCheck.metricValue(net, MetricIds.download);
    final double? up = ConnectionCheck.metricValue(net, MetricIds.upload);
    final double? latency =
        ConnectionCheck.metricValue(net, MetricIds.latency);
    final double? loss = ConnectionCheck.metricValue(net, MetricIds.loss);

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
      ..writeln('Internet Down: ${_mbps(down)}')
      ..writeln('Internet Up: ${_mbps(up)}')
      ..writeln(
        'Delay: ${latency != null ? '${latency.round()} ms' : 'Not measured'}   '
        'Dropped data: ${loss != null ? '${loss.round()}%' : 'Not measured'}',
      );
    if (wifiName != null) {
      buf.writeln('Wi-Fi network: $wifiName');
    }
    buf
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

  // ---- iOS optional Shortcut offer (D1 path) ----

  Future<void> _openShortcutSheet() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    await showInstallShortcutSheet(
      context: context,
      openUrl: bridge.openUrl,
      onInstalled: () async {
        if (mounted) _run();
      },
    );
  }

  Widget _poweredBy(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Text(
        'Powered by the WLAN Pros Toolbox',
        style: text.labelSmall?.copyWith(color: context.colors.textTertiary),
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
// (A) VERDICT HERO — the H1/36px plain-language sentence (the visual climax)
// + the two axis status chips SIDE BY SIDE (§2.A / §2.A2).
// ===========================================================================

/// The verdict hero: a single result card holding the plain-language verdict
/// SENTENCE at `headlineLarge` (H1/36px, §8.5.2 scope extension), then the two
/// labeled axis status chips on one row. The sentence is the comprehension
/// climax — the screen opens on the answer, not the numbers (§2.A). The chips
/// teach the two-things model; each carries WORD + GLYPH + color (§1.3), never
/// color alone. In light, the card takes the §8.20.3-C status accent treatment.
class _HeroVerdict extends StatelessWidget {
  const _HeroVerdict({required this.verdict, required this.heroSentence});

  final ConsumerVerdict verdict;
  final String heroSentence;

  /// §8.20.3-C #2 — the status tone that colors the result card's accent bar.
  /// "Both fine" reads as success; any slow side is a warning; an unreadable
  /// side is neutral info. The headline + chips carry the precise verdict; the
  /// bar is a projector-visible reinforcement of the overall tone.
  StatusTone get _tone {
    switch (verdict.outcome) {
      case ConsumerOutcome.bothFine:
        return StatusTone.success;
      case ConsumerOutcome.wifi:
      case ConsumerOutcome.wifiLead:
      case ConsumerOutcome.internet:
        return StatusTone.warning;
      case ConsumerOutcome.couldntCheckWifi:
      case ConsumerOutcome.couldntComplete:
        return StatusTone.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String semanticsLabel =
        '$heroSentence '
        'Wi-Fi ${_TwoAxisChips.word(verdict.wifiStatus)}. '
        'Internet ${_TwoAxisChips.word(verdict.internetStatus)}.';

    final Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // §2.A — the plain-language verdict SENTENCE at H1/36px
          // (`headlineLarge`, §8.5.2 scope extension). The largest in-app
          // headline; the comprehension climax. Wraps (never clips) under
          // dynamic type, §8.9.
          Text(
            heroSentence,
            style: text.headlineLarge?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          // §2.A2 — the two axis chips, side by side, teaching the two-things
          // model.
          _TwoAxisChips(
            wifiStatus: verdict.wifiStatus,
            internetStatus: verdict.internetStatus,
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        // §8.20.3-C #2 — in light, the status-bearing result card carries a 6px
        // full-saturation status-hue left-accent bar plus a 4px top strip in the
        // same hue (a small AREA, not a thin line, so full saturation). No bars
        // in dark.
        child: colors.isLight
            ? _StatusAccentFrame(tone: _tone, child: card)
            : card,
      ),
    );
  }
}

/// Wraps a result card with the §8.20.3-C #2 status accent treatment (light
/// only): a 6px full-saturation status-hue bar down the left edge and a 4px
/// strip across the top, both in the relevant status hue. The bars are small
/// AREAS (≥3:1 vs the white card), so they carry the hue at full saturation; the
/// card's headline + chips carry the precise meaning.
class _StatusAccentFrame extends StatelessWidget {
  const _StatusAccentFrame({required this.tone, required this.child});

  final StatusTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color hue = colors.statusToneColor(tone);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Stack(
        children: <Widget>[
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 4, color: hue), // top strip
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 6, color: hue), // left accent bar
          ),
        ],
      ),
    );
  }
}

/// The two labeled axis chips, laid out side by side (Item B) and wrapping to a
/// second row at the smallest width. Each carries an aligned plain label + a
/// status chip; the WORD always carries the verdict (never color alone).
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
    // Wrap, not Row: the two labeled chips sit side by side on a wide card and
    // reflow to two rows on a narrow one (320px / large type) without clipping.
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _AxisRow(label: 'Wi-Fi', status: wifiStatus),
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          '$label:',
          style: text.bodyLarge?.copyWith(color: context.colors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.xs),
        _StatusChip(status: status),
      ],
    );
  }
}

/// A single status chip: icon + WORD + §8.13/§8.20.4 color. The WORD always
/// carries meaning (WCAG 2.2 SC 1.4.1).
///
/// LIGHT (§8.20.4 Style A) renders the SOLID-FILL pill — the full-strength
/// status hue as a solid fill carrying a WHITE 700 label and a WHITE Material
/// status glyph (white-on-fill 5.4–5.9:1). DARK keeps the §8.13 outline chip
/// (surface2 fill + thin colored border + colored label/glyph). The "couldn't
/// check" neutral state has no status hue, so light fills it with the neutral
/// textSecondary #4A4A4A (white-on-fill 8.86:1) for the same solid + white
/// look, matching the _GradeChip no-hue fills.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AxisStatus status;

  /// The full-strength status hue, theme-aware. In dark this colors the label,
  /// glyph and border; in light it is the §8.20.4 solid pill fill.
  Color _color(AppColorScheme colors) {
    switch (status) {
      case AxisStatus.fine:
        return colors.statusSuccess;
      case AxisStatus.slow:
        return colors.statusWarning;
      case AxisStatus.unknown:
        // Light: neutral textSecondary #4A4A4A fill, matching the _GradeChip
        // no-hue fills across TMC / wifi_info / net_quality. Dark stays on
        // textTertiary so the dark render is byte-identical.
        return colors.isLight ? colors.textSecondary : colors.textTertiary;
    }
  }

  /// The Material status glyph. Light uses the FILLED variant (a solid white
  /// knockout on the solid pill, §8.20.4); dark keeps the original OUTLINED
  /// variant so the dark render is byte-identical.
  IconData _icon(bool light) {
    switch (status) {
      case AxisStatus.fine:
        return light ? Icons.check_circle : Icons.check_circle_outline;
      case AxisStatus.slow:
        return light ? Icons.warning_amber : Icons.warning_amber_outlined;
      case AxisStatus.unknown:
        // §1.1 — the "couldn't check" glyph is `help_outline`, NOT error /
        // cancel / block / remove. Those carry "fault"; this reads "unknown /
        // not determined", which is the truth. Same outlined glyph the footer
        // uses, so it reads familiar and non-threatening.
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Color hue = _color(colors);

    // §8.20.4 Style A (light): solid hue fill, white label + white glyph, no
    // border. §8.13 (dark): surface2 fill, thin colored border, colored content.
    final Color fill = colors.isLight ? hue : colors.surface2;
    final Color content = colors.isLight ? const Color(0xFFFFFFFF) : hue;
    final BoxBorder? border =
        colors.isLight ? null : Border.all(color: hue, width: 1);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon(colors.isLight), size: 18, color: content),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            _TwoAxisChips.word(status),
            style: text.labelLarge?.copyWith(
              color: content,
              fontWeight: FontWeight.w700, // §8.20.4 / §8.20.3-A verdict word
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// VERDICT LINE — the plain, state-driven verdict that names the limiter, plus
// the direct % comparison answer. ALWAYS visible (no disclosure), prominent.
// Added in the v1.1 "show more" pass (Keith, 2026-06-05) walking back the
// over-simplified reshape toward MORE information.
// ===========================================================================

/// The verdict block beneath the hero: a plain sentence naming the limiter
/// ([verdict], item #4) and the single direct-comparison sentence ([comparison],
/// item #5). The verdict line sits at `bodyLarge`/textPrimary; the comparison
/// sentence is the headline answer, bumped to `titleMedium` weight so it reads
/// as the prominent takeaway. The comparison line is omitted entirely when null
/// (internet not measured / ~0) — the honest verdict line then stands alone
/// (GL-005). The two lines read as one container for screen readers.
class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.verdict, required this.comparison});

  final String verdict;

  /// The direct % comparison sentence, or null when it must be suppressed
  /// (internet side unmeasured / ~0). Never fabricated.
  final String? comparison;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String? cmp = comparison;
    return Semantics(
      container: true,
      label: cmp == null ? verdict : '$verdict $cmp',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              verdict,
              style: text.bodyLarge?.copyWith(color: colors.textPrimary),
            ),
            if (cmp != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                cmp,
                style: text.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 2. Core comparison — usable Wi-Fi capacity vs internet throughput on a
// shared scale. Wi-Fi is the lime accent bar; internet is a NEUTRAL bar
// (surface3 fill + borderStrong outline, NOT a status hue, per Vera §8.13).
// Always rendered in the result detail (the "See the details" disclosure was
// removed in v1.1; the detail no longer collapses).
// ===========================================================================

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.result});

  final WifiVsInternetResult result;

  /// The plain reading line beneath the bars, derived from the engine verdict so
  /// the words and the bar heights agree. No new verdict math — it reads the
  /// already-computed verdict and reuses the engine's usable-capacity figure.
  String _readingLine() {
    switch (result.verdict) {
      case WifiVsInternetVerdict.wifiLimiter:
        return 'Your internet can carry more than your Wi-Fi link is passing. '
            'Boost the Wi-Fi signal to raise the ceiling.';
      case WifiVsInternetVerdict.bothContributing:
        return 'Your internet is using almost all the headroom your Wi-Fi link '
            'can carry. Boost the Wi-Fi signal to raise the ceiling.';
      case WifiVsInternetVerdict.upstream:
        return 'Your Wi-Fi link has room to spare. The internet coming into '
            'your home is the slower part right now.';
      case WifiVsInternetVerdict.bothHealthy:
        return 'Both your Wi-Fi and your internet are keeping up. Neither side '
            'is holding you back right now.';
      case WifiVsInternetVerdict.wifiUnknown:
        return result.internetAvgMbps == null
            ? 'We could not read your Wi-Fi link, so there is nothing to '
                'compare the internet against yet.'
            : 'We could not read your Wi-Fi link, so only the internet side is '
                'shown.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double? usable = result.usableWifiMbps;
    final double? internet = result.internetAvgMbps;

    // Shared scale: the larger of the two figures is full width, so the bars are
    // directly comparable. When one side is unknown, the other still draws.
    final double scaleMax = <double>[
      usable ?? 0,
      internet ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final double safeMax = scaleMax <= 0 ? 1 : scaleMax;

    final String wifiValue =
        usable != null ? '${usable.round()} Mbps' : 'Unavailable';
    final String internetValue =
        internet != null ? '${internet.round()} Mbps' : 'Unavailable';

    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      // §1.3.1 — mark the comparison card as an SR heading node so heading-rotor
      // navigation can land on it (previously the card carried no heading
      // semantic at all). SR-only: the visible bar label "Wi-Fi usable capacity"
      // is the de-facto card title and is unchanged. No layout shift.
      header: true,
      label:
          'Wi-Fi usable capacity $wifiValue. Internet throughput '
          '$internetValue. ${_readingLine()}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colors.border,
              width: colors.isLight ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CompareBar(
                label: 'Wi-Fi usable capacity',
                value: wifiValue,
                fraction: usable == null ? null : (usable / safeMax),
                accent: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              _CompareBar(
                label: 'Internet throughput',
                value: internetValue,
                fraction: internet == null ? null : (internet / safeMax),
                accent: false,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _readingLine(),
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labeled bar in the comparison. The lime [accent] bar is the Wi-Fi usable
/// capacity (the single semantic accent); the non-accent bar is the NEUTRAL
/// internet bar (surface3 fill + borderStrong outline, never a status hue).
class _CompareBar extends StatelessWidget {
  const _CompareBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.accent,
  });

  final String label;
  final String value;

  /// 0..1 of the shared scale, or null when the figure is unavailable (the bar
  /// track shows empty and the value reads "Unavailable").
  final double? fraction;
  final bool accent;

  static const double _barHeight = 10;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AppColorScheme colors = context.colors;
    final double f = (fraction ?? 0).clamp(0.0, 1.0);

    // On light, surface2/surface3 are both white and would vanish against the
    // white card: the empty track uses the gray canvas, and the neutral
    // (internet) fill uses the gray canvas + borderStrong so it reads as a
    // bordered neutral bar, not an invisible one.
    final Color trackColor = colors.isLight ? colors.surface0 : colors.surface2;
    final Color neutralFill = colors.isLight ? colors.surface0 : colors.surface3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: mono.robotoMono.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        // The shared-scale track. §8.20.3-B/C — the Wi-Fi capacity fill is a bar
        // AREA, not a thin foreground, so it carries FULL-saturation brand lime
        // #A1CC3A in both themes (a vivid fill reads at distance; the olive
        // substitute is only for thin foregrounds, §8.20.2). The internet bar is
        // the neutral fill + borderStrong outline.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            height: _barHeight,
            child: Stack(
              children: <Widget>[
                Container(color: trackColor),
                FractionallySizedBox(
                  widthFactor: f == 0 ? 0.0 : f,
                  child: accent
                      ? Container(color: colors.primary)
                      : Container(
                          decoration: BoxDecoration(
                            color: neutralFill,
                            border: Border.all(
                              color: colors.borderStrong,
                              width: 1,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// 3. Live "Wi-Fi signal" sparkline card — REUSES the shared WifiSignalSampler
// and the shared Sparkline. Three rows: Wi-Fi data rate, SNR, RSSI, each with a
// current value (mono), a trend arrow, and an inline sparkline. macOS auto-polls
// continuously; iOS streams via the companion Shortcut (Start/Stop), degrading
// honestly when the Shortcut is absent.
// ===========================================================================

class _LiveSignalCard extends StatelessWidget {
  const _LiveSignalCard({required this.sampler});

  final WifiSignalSampler sampler;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sampler,
      builder: (context, _) {
        final ConnectedAp? latest = sampler.latest;
        final WifiTimeSeries series = sampler.series;
        final TextTheme text = Theme.of(context).textTheme;
        final AppColorScheme colors = context.colors;
        // LIVE label is a thin foreground → darkened-lime in light, lime in dark.
        final Color liveColor =
            colors.isLight ? colors.textAccent : colors.primary;

        return Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: colors.border,
              width: colors.isLight ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header: title + LIVE indicator (lime dot — NOT a status hue),
              // or, on iOS while paused, a Start affordance.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Wi-Fi signal',
                        style: text.titleSmall?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (sampler.isIos && !sampler.isStreaming)
                    Semantics(
                      button: true,
                      label: 'Start live Wi-Fi signal',
                      child: OutlinedButton.icon(
                        onPressed: sampler.start,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Start'),
                      ),
                    )
                  else if (sampler.isIos && sampler.isStreaming)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _LiveDot(color: liveColor),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'LIVE',
                          style: text.labelMedium?.copyWith(
                            color: liveColor,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Semantics(
                          button: true,
                          label: 'Stop live Wi-Fi signal',
                          child: IconButton(
                            icon: const Icon(Icons.stop, size: 20),
                            tooltip: 'Stop',
                            visualDensity: VisualDensity.compact,
                            onPressed: sampler.stop,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _LiveDot(color: liveColor),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'LIVE',
                          style: text.labelMedium?.copyWith(
                            color: liveColor,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // Walk-around tip (item #6) — invites the user to move while the
              // live feed runs so they see the signal change spot to spot.
              Text(
                'Walk around while this runs to see how your Wi-Fi signal '
                'changes from spot to spot.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (sampler.isIos &&
                  sampler.triggerError) ...<Widget>[
                _LiveUnavailableNote(
                  message:
                      'Could not start the live Wi-Fi feed. The companion '
                      '"WLAN Pros Live" Shortcut may not be installed. Install '
                      'it, then tap Start.',
                ),
              ] else if (series.isEmpty) ...<Widget>[
                _LiveUnavailableNote(
                  // iOS, not yet started → invite the deliberate Start tap.
                  // iOS, started but the first sample has not landed yet →
                  // an HONEST "waiting" indicator (the Shortcut WAS fired; we
                  // are genuinely waiting on it, never a fake "LIVE" with
                  // nothing behind it). macOS auto-polls, so it is simply
                  // reading the link.
                  message: sampler.isIos
                      ? (sampler.isStreaming
                          ? 'Starting the live Wi-Fi feed from the companion '
                              'Shortcut. The first reading should arrive in a '
                              'moment…'
                          : 'Tap Start to begin live Wi-Fi signal readings from '
                              'the companion Shortcut.')
                      : 'Reading the Wi-Fi link…',
                ),
              ] else ...<Widget>[
                // Wi-Fi data rate (Tx — the rate macOS reliably exposes; iOS
                // carries both). Trend arrow + lime sparkline (not graded).
                _SignalRow(
                  label: 'Wi-Fi data rate',
                  unit: 'Mbps',
                  value: _rate(latest?.txRateMbps),
                  window: series.txRate,
                  // Thin sparkline line → darkened-lime in light, lime in dark.
                  lineColor: liveColor,
                ),
                const SizedBox(height: AppSpacing.xs),
                // SNR — graded line color reinforces the trend (word still leads
                // via the value; the line tint is reinforcement only).
                _SignalRow(
                  label: 'SNR',
                  unit: 'dB',
                  value: latest?.snrDb?.toString(),
                  window: series.snr,
                  lineColor: _gradeColor(
                    colors,
                    WifiGrading.gradeSnr(latest?.snrDb),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // RSSI.
                _SignalRow(
                  label: 'RSSI',
                  unit: 'dBm',
                  value: latest?.rssiDbm?.toString(),
                  window: series.rssi,
                  lineColor: _gradeColor(
                    colors,
                    WifiGrading.gradeRssi(latest?.rssiDbm),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String? _rate(double? mbps) {
    if (mbps == null) return null;
    if (mbps == mbps.roundToDouble()) return mbps.toStringAsFixed(0);
    return mbps.toStringAsFixed(1);
  }

  /// Tints a sparkline to its grade (reinforcement only; the unavailable case
  /// stays neutral so it never reads as a verdict). Theme-aware — status hues
  /// re-derive darker in light (§8.20.1).
  static Color _gradeColor(AppColorScheme colors, QualityGrade grade) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return colors.statusSuccess;
      case QualityGrade.fair:
        return colors.statusWarning;
      case QualityGrade.poor:
        return colors.statusDanger;
      case QualityGrade.unavailable:
        return colors.textTertiary;
    }
  }
}

/// One live-signal row: label, current value (mono), a trend arrow derived from
/// the window's last two PRESENT samples, and an inline sparkline.
class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.label,
    required this.unit,
    required this.value,
    required this.window,
    required this.lineColor,
  });

  final String label;
  final String unit;
  final String? value;
  final List<double?> window;
  final Color lineColor;

  static const double _sparklineHeight = 28;

  /// −1 falling, 0 steady, +1 rising — from the last two present samples.
  int get _trend {
    double? prev;
    double? last;
    for (final double? v in window) {
      if (v == null) continue;
      prev = last;
      last = v;
    }
    if (prev == null || last == null) return 0;
    if (last > prev) return 1;
    if (last < prev) return -1;
    return 0;
  }

  IconData get _trendIcon {
    switch (_trend) {
      case 1:
        return Icons.trending_up;
      case -1:
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  String get _trendWord {
    switch (_trend) {
      case 1:
        return 'rising';
      case -1:
        return 'falling';
      default:
        return 'steady';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AppColorScheme colors = context.colors;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue ? '$value $unit' : 'Unavailable';

    return Semantics(
      container: true,
      label: '$label, $shown, $_trendWord',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Label + value stack (left).
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hasValue
                              ? mono.robotoMono.copyWith(
                                  color: colors.textPrimary,
                                )
                              : text.bodyMedium?.copyWith(
                                  color: colors.textSecondary,
                                ),
                        ),
                      ),
                      if (hasValue) ...<Widget>[
                        const SizedBox(width: AppSpacing.xxs),
                        Icon(
                          _trendIcon,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Sparkline (right, fills).
            Expanded(
              child: Sparkline(
                values: window,
                lineColor: lineColor,
                semanticLabel: '$label trend',
                height: _sparklineHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "LIVE" dot. Lime is the §8.3 active-state accent, not a verdict, so it is
/// off-limits for status color (§8.13). [color] is the foreground-accent (lime
/// in dark, darkened-lime in light) resolved by the parent so a small dot stays
/// visible on white (§8.20.2 — lime as a thin foreground fails on light).
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Honest note inside the live card when no samples exist yet or the iOS feed
/// could not start (GL-005 — no fabricated trend).
class _LiveUnavailableNote extends StatelessWidget {
  const _LiveUnavailableNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      message,
      style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
    );
  }
}

// ===========================================================================
// 4. "What to tell support" — plain measured facts + inline copy button.
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
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'What to tell support',
              style: text.titleSmall?.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
                color: copied ? colors.statusSuccess : colors.textSecondary,
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
/// node. Value wraps before overflowing at 320px.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
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
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                fact.value,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// The absorbed pro "Wi-Fi vs Internet" readout — the technical layer, now
// ALWAYS rendered in the result detail (the "See the details" disclosure was
// removed in v1.1; this section no longer collapses).
// Nothing the pro tool showed is lost; it just no longer leads the screen.
// ===========================================================================

class _TechnicalSection extends StatelessWidget {
  const _TechnicalSection({
    required this.ap,
    required this.internet,
    required this.result,
  });

  final ConnectedAp? ap;
  final QualityResult? internet;
  final WifiVsInternetResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Section heading — the named concept "Wi-Fi vs Internet" survives.
        // Marked as an SR heading so heading-rotor navigation can land on it.
        Semantics(
          header: true,
          child: Text(
            'Wi-Fi vs Internet',
            style: text.titleMedium?.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _ProVerdictCard(result: result),
        const SizedBox(height: AppSpacing.sm),
        _WifiLinkSection(ap: ap, result: result),
        const SizedBox(height: AppSpacing.sm),
        _InternetSection(result: internet),
        const SizedBox(height: AppSpacing.sm),
        Text(
          kWifiVsInternetFootnote,
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// The pro verdict card (absorbed from wifi_vs_internet_screen): the engineer
/// verdict word + explanation + supporting SNR context, in the §8.13 status hue.
class _ProVerdictCard extends StatelessWidget {
  const _ProVerdictCard({required this.result});

  final WifiVsInternetResult result;

  static Color _statusColor(AppColorScheme colors, WifiVsInternetVerdict v) {
    switch (v) {
      case WifiVsInternetVerdict.bothHealthy:
        return colors.statusSuccess;
      case WifiVsInternetVerdict.wifiLimiter:
      case WifiVsInternetVerdict.upstream:
      case WifiVsInternetVerdict.bothContributing:
        return colors.statusWarning;
      case WifiVsInternetVerdict.wifiUnknown:
        return colors.statusInfo;
    }
  }

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
    final AppColorScheme colors = context.colors;
    final Color status = _statusColor(colors, result.verdict);

    final Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      // §8.20.3-C #1 — pad the left edge in light so the 4px accent bar (added
      // below) clears the content.
      padding: EdgeInsets.fromLTRB(
        colors.isLight ? AppSpacing.sm + 4 : AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(_icon(result.verdict), size: 24, color: status),
              const SizedBox(width: AppSpacing.xs),
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
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
          ),
          if (result.snrContext.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              result.snrContext,
              style: text.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      label:
          'Verdict: ${result.headline}. ${result.explanation}'
          '${result.snrContext.isNotEmpty ? ' ${result.snrContext}' : ''}',
      child: ExcludeSemantics(
        // §8.20.3-C #1 — a status-bearing result card gets a 4px colored
        // left-accent bar in light (clears the 3:1 SC 1.4.11 floor). Dark keeps
        // the plain card (no accent bar in §8.13).
        child: colors.isLight
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Stack(
                  children: <Widget>[
                    card,
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      child: Container(width: 4, color: status),
                    ),
                  ],
                ),
              )
            : card,
      ),
    );
  }
}

/// "Your Wi-Fi link" sub-card (absorbed verbatim from wifi_vs_internet_screen).
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

/// "Your internet" sub-card (absorbed verbatim from wifi_vs_internet_screen).
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

/// The §8.13 grade chip (absorbed from wifi_vs_internet_screen).
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final QualityGrade grade;

  /// DARK (§8.13): solid status fill + dark text. LIGHT (§8.20.4 Style A): the
  /// SOLID full-strength status hue fill + WHITE 700 label + WHITE glyph, no
  /// border. Returns (fill, border, label) per theme. The "unavailable" grade
  /// has no status hue, so it stays neutral in both themes.
  static (Color, Color?, Color) _colors(AppColorScheme c, QualityGrade grade) {
    if (c.isLight) {
      const Color white = Color(0xFFFFFFFF);
      switch (grade) {
        case QualityGrade.excellent:
        case QualityGrade.good:
          return (c.statusSuccess, null, white);
        case QualityGrade.fair:
          return (c.statusWarning, null, white);
        case QualityGrade.poor:
          return (c.statusDanger, null, white);
        case QualityGrade.unavailable:
          // Neutral solid fill (textSecondary #4A4A4A, white-on-fill 9.0:1).
          return (c.textSecondary, null, white);
      }
    }
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (c.statusSuccess, null, c.onPrimary);
      case QualityGrade.fair:
        return (c.statusWarning, null, c.onPrimary);
      case QualityGrade.poor:
        return (c.statusDanger, null, c.onPrimary);
      case QualityGrade.unavailable:
        return (c.surface2, c.borderStrong, c.textSecondary);
    }
  }

  /// §8.20.4 — the Material status glyph that reinforces the verdict word
  /// (so meaning is never carried by color alone).
  static IconData _glyph(QualityGrade grade) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return Icons.check_circle;
      case QualityGrade.fair:
        return Icons.warning_amber_rounded;
      case QualityGrade.poor:
        return Icons.error;
      case QualityGrade.unavailable:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final (Color bg, Color? borderColor, Color fg) =
        _colors(colors, grade);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        // §8.20.4 Style A — light is a borderless solid-fill PILL; dark keeps its
        // control-radius solid fill (only dark "unavailable" carries a 1px
        // boundary off borderColor).
        borderRadius: BorderRadius.circular(
          colors.isLight ? AppRadius.pill : AppRadius.control,
        ),
        border:
            borderColor == null ? null : Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // §8.20.4 Style A — the solid-fill light pill carries a 16px WHITE
          // Material status glyph, so the verdict is reinforced by shape + word,
          // not color alone. Dark keeps its solid-fill chip with no glyph.
          if (colors.isLight) ...<Widget>[
            Icon(_glyph(grade), size: 16, color: fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              grade.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(
                color: fg,
                // §8.20.4 / §8.20.3-A verdict word bumps to 700 in light.
                fontWeight: colors.isLight ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled surface1 card with a §8.1 hairline border (absorbed shell).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // §1.3.1 — the section heading is marked as an SR heading so VoiceOver
          // / TalkBack heading-rotor navigation can land on it. SR-only; no
          // layout change. Applied once here so every _SectionCard ("Your Wi-Fi
          // link", "Your internet") inherits the heading semantic.
          Semantics(
            header: true,
            child: Text(
              title,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          // §8.20.3-C #3 — a 4px vivid lime #A1CC3A FILL underline bar under the
          // section heading, on the white card surface. Decorative brand area
          // (the bold label above carries the meaning); the bar reads vivid as a
          // fill. Light only — no underline in dark (lime is the dark accent
          // already and the section label needs no extra bar there).
          if (colors.isLight) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

/// One label → value data row (absorbed verbatim from wifi_vs_internet_screen):
/// a null value renders "Unavailable", each row is one semantic node, mono for
/// numerics, an optional trailing grade chip ellipsizes before overflow.
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
    final AppColorScheme colors = context.colors;

    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue
        ? (unit == null ? value! : '${value!} $unit')
        : 'Unavailable';
    final Color valueColor =
        hasValue ? colors.textPrimary : colors.textSecondary;
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
                          color: colors.textSecondary,
                        ),
                      ),
                      if (derived)
                        Text(
                          'derived',
                          style: text.labelSmall?.copyWith(
                            color: colors.textTertiary,
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
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// iOS-only optional Shortcut offer (D1 path) — soft, secondary, post-answer.
// ===========================================================================

class _ShortcutOfferCard extends StatelessWidget {
  const _ShortcutOfferCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Want a deeper Wi-Fi check?',
            style: text.titleSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add the companion Shortcut to let this app read your Wi-Fi '
            'details next time. Optional, and it only takes a minute.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
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
