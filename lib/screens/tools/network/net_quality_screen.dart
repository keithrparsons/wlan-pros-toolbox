// Network Quality tool — a one-shot transport-quality measurement plus a
// popular-site reachability table, built on the pure-Dart `net_quality`
// engine (packages/net_quality). The screen depends ONLY on the QualityClient
// seam and ReachabilityProbe, never on a concrete probe, so the backend is
// swappable and the whole screen is testable with a MockQualityClient and no
// real network.
//
// HONESTY (GL-005 + ARCHITECTURE.md): these are this app's OWN measurements,
// not a third-party score, and there is deliberately no single composite
// "score" — each dimension is graded on its own. The Responsiveness grade is a
// simplified single-flow figure inspired by RFC 9097 / Apple networkQuality,
// not the full multi-flow RPM standard. Latency and reachability use a
// TCP-connect RTT, not ICMP, because sandboxed macOS and iOS apps cannot open
// raw sockets (GL-008). A dimension that cannot be measured is shown as
// "Unavailable" with its note, never faked.
//
// PLATFORM MATRIX:
//   - macOS / Windows / Linux / Android / iOS: real run over dart:io sockets
//     and HTTP. Works on desktop and mobile.
//   - web: dart:io is absent and browsers cannot open the sockets this engine
//     needs, so the screen routes to NetworkUnavailableView (the same
//     download-the-native-app fallback the other network tools use) and never
//     crashes the web build.
//
// States (SOP-007 §5): idle · loading (progress + phase caption, Run disabled) ·
// success (six graded metric rows + reachability rows) · per-metric unavailable
// (note instead of a value) · empty/error (failed metrics carry their note,
// reachability empties gracefully) · web-unavailable.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:net_quality/net_quality.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_connection_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'live_quality_monitor.dart';
import 'metric_sparkline.dart';
import 'net_quality_help_sheet.dart';
import 'network_unavailable_view.dart';

/// Network Quality screen. Runs one transport measurement and a popular-site
/// reachability pass, then renders six graded metric rows and a reachability
/// table.
class NetQualityScreen extends StatefulWidget {
  const NetQualityScreen({
    super.key,
    this.client,
    this.reachabilityProbe,
    this.monitor,
    this.connectionService,
  });

  /// Measurement backend. Injected in tests (a [MockQualityClient] with no
  /// network); null in production, where the screen builds a real
  /// [OwnEngineQualityClient] targeting Cloudflare's one.one.one.one.
  final QualityClient? client;

  /// Reachability backend. Injected in tests with a fake [SiteProber] and a
  /// short site list; null in production, where the screen builds a real
  /// [ReachabilityProbe] over the default [kPopularSites].
  final ReachabilityProbe? reachabilityProbe;

  /// Live trend monitor. Injected in tests with a fake latency sampler and a
  /// driven tick; null in production, where the screen builds a real
  /// [LiveQualityMonitor] over the same target host as [client]. The screen
  /// owns its lifecycle: it `start()`s the monitor in `initState` and disposes
  /// it in `dispose()`, which is the "clears on leave" behavior (spec §2).
  final LiveQualityMonitor? monitor;

  /// The honest "is this device on Wi-Fi?" probe, injected in tests. Null in
  /// production, where the screen builds the real one. Drives the cellular-data
  /// consent gate (F-1).
  final WifiConnectionService? connectionService;

  @override
  State<NetQualityScreen> createState() => _NetQualityScreenState();
}

class _NetQualityScreenState extends State<NetQualityScreen> {
  late final QualityClient _client;
  late final ReachabilityProbe _reachability;
  late final LiveQualityMonitor _monitor;

  bool _running = false;
  String? _error;

  /// The honest "is this device on Wi-Fi?" probe (F-1). A POSITIVE not-on-Wi-Fi
  /// verdict is the ONLY thing that raises the cellular-data gate; an ambiguous
  /// read resolves to `unknown` and changes nothing, so a wired desktop is never
  /// nagged about cellular data it is not spending.
  late final WifiConnectionService _connection;

  /// True only on a POSITIVE not-on-Wi-Fi probe. Never set from a failed or
  /// ambiguous read (GL-005).
  bool _notOnWifi = false;

  /// Set when the user taps the cost-labelled Run button. The tap IS the consent:
  /// the button states the data cost, directly under the warning that explains it.
  bool _throughputConsented = false;

  // Transport progress.
  QualityPhase _phase = QualityPhase.idle;
  double _fraction = 0;

  // Results, populated on completion.
  QualityResult? _result;
  List<SiteReachability> _sites = <SiteReachability>[];

  StreamSubscription<QualityProgress>? _sub;

  @override
  void initState() {
    super.initState();
    // Injection seam: real engine + real reachability in production, fakes in
    // tests. Default target is Cloudflare's one.one.one.one on port 443.
    _client =
        widget.client ?? OwnEngineQualityClient.forHost('one.one.one.one');
    _reachability = widget.reachabilityProbe ?? ReachabilityProbe();
    // The live monitor samples the cheap latency trio while the screen is
    // mounted. Built with a real LatencyProbe in production (same host as the
    // one-shot client); injected with a fake sampler in tests. Only started on
    // a platform that can actually run the sockets — never on web.
    _monitor = widget.monitor ?? LiveQualityMonitor(host: 'one.one.one.one');
    _connection = widget.connectionService ?? WifiConnectionService();
    if (NetworkSupport.activeNetworkSupported) {
      _monitor.start();
    }
    // Resolve the connection state on open so the pre-run screen can state the
    // data cost BEFORE the user reaches for Run. Never fires a measurement.
    unawaited(_refreshConnection());
  }

  /// Re-reads the honest Wi-Fi connection state. Only a POSITIVE not-on-Wi-Fi
  /// verdict sets [_notOnWifi]; `unknown` leaves it false (GL-005 — an ambiguous
  /// read must never be presented as proof of cellular).
  Future<void> _refreshConnection() async {
    final WifiConnectionStatus status = await _connection.status();
    if (!mounted) return;
    setState(() {
      _notOnWifi = status == WifiConnectionStatus.notOnWifi;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Disposing the monitor cancels its timer and frees the histories — this IS
    // the "clears on leave" behavior; the trend does not survive leaving the
    // screen (spec §2, Keith's decision).
    _monitor.dispose();
    super.dispose();
  }

  /// Kicks off both the transport measurement and the reachability pass from a
  /// single Run action. The reachability future resolves independently and
  /// updates its own section when done.
  ///
  /// [includeThroughput] CARRIES THE USER'S CELLULAR-DATA CONSENT (round-4 cold
  /// review, F-1, 2026-07-14).
  ///
  /// THIS TOOL HAD NO GATE AT ALL. It called `_client.measure()` bare, riding a
  /// `includeThroughput = true` default on the QualityClient interface. Network
  /// Quality is shipped, routed and iOS-live, so on a cellular iPhone: open it,
  /// tap Run, and it began a full-rate ~30 s download plus the RPM load
  /// generator — 50 to 500 MB of the user's data — with no warning, no decline
  /// path, and nothing to consent to. Test My Connection's gate was never the
  /// whole gate; it was one caller being careful while the door stood open.
  ///
  /// The default is now GONE from the interface, so the compiler forces every
  /// caller to state a decision. This method is where that decision is honored.
  Future<void> _run({required bool includeThroughput}) async {
    // SETTLE THE PROBE BEFORE THE CONSENT DECISION READS IT. Same rule as Test My
    // Connection (F-2): a user can walk out of Wi-Fi range with this screen open,
    // and a decision made from a stale flag spends data they never agreed to.
    await _refreshConnection();
    if (!mounted) return;

    // THE CHOKEPOINT. `includeThroughput` is what the CALLER ASKED FOR;
    // `spendData` is what the USER HAS AGREED TO PAY FOR. Off Wi-Fi the two are
    // the same only after an explicit, cost-labelled tap. On Wi-Fi (or on an
    // AMBIGUOUS probe — a wired desktop, a read we could not make) this is a
    // no-op and the tool behaves exactly as it always has: an ambiguous read is
    // never treated as proof of cellular (GL-005).
    final bool spendData =
        includeThroughput && (!_notOnWifi || _throughputConsented);

    setState(() {
      _error = null;
      _running = true;
      _phase = QualityPhase.idle;
      _fraction = 0;
      _result = null;
      _sites = <SiteReachability>[];
    });

    // Reachability runs concurrently with the transport stream. Its result
    // populates the popular-sites section as soon as it lands.
    unawaited(
      _reachability
          .measure()
          .then((List<SiteReachability> sites) {
            if (!mounted) return;
            setState(() => _sites = sites);
          })
          .catchError((Object _) {
            // A reachability failure is non-fatal: leave the section empty rather
            // than surfacing an error over the transport result.
            if (!mounted) return;
            setState(() => _sites = <SiteReachability>[]);
          }),
    );

    _sub = _client.measure(includeThroughput: spendData).listen(
      (QualityProgress p) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
        });
      },
      onDone: () {
        if (!mounted) return;
        final QualityResult? result = _client.lastResult;
        setState(() {
          _running = false;
          _result = result;
        });
        // Feed all six metric values into the live history. The expensive trio
        // (download/upload/responsiveness) gets points ONLY here, which is why
        // those sparklines are sparse by design (spec §2).
        if (result != null) _monitor.addFullResult(result);
        // WCAG 4.1.3 — announce completion to assistive tech.
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Network quality test complete',
          TextDirection.ltr,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error = 'Network quality test error: $e';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Quality'),
        toolbarHeight: 64,
        // §8.16.1: copy is the ONLY sanctioned AppBar action on a results
        // screen. The per-tool help affordance has moved OUT of the AppBar to
        // the shared ToolHelpFooter at the end of the scroll body (below). The
        // footer is wired via its onTap callback to this screen's bespoke
        // showNetQualityHelpSheet, so the richer per-metric help content is
        // preserved unchanged while the affordance reads identically to every
        // other tool screen. Copy stays here; it is disabled until a one-shot
        // run has produced a result.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the completed run as a labeled plain-text block: the
  /// six transport dimensions then the popular-site reachability table. Each
  /// transport line carries its grade WORD (Excellent / Good / Fair / Poor /
  /// Unavailable) and each site its reachable/unreachable WORD, so every
  /// on-screen verdict the color reinforced survives to the clipboard
  /// (§8.13 / §8.16 content contract). Honesty (GL-005): a dimension that did
  /// not measure is written as "Unavailable" with its note, never faked.
  ///
  /// Returns null (→ disabled affordance) until a one-shot run completes
  /// ([_result] is non-null and the test is not in flight). The live latency
  /// trio alone is not a "result to keep" — copy waits for a full Run.
  String? _buildCopyText() {
    final QualityResult? r = _result;
    if (_running || r == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('Network Quality');

    buf
      ..writeln()
      ..writeln('Transport');
    for (final String id in _metricOrder) {
      final (String label, String unit) = _metricMeta[id]!;
      final QualityMetric? m = r.metric(id);
      final double? v = m?.value;
      final bool available = m != null && m.isAvailable && v != null;
      final String value = available
          ? _formatValueRaw(id, v, unit)
          : 'Unavailable';
      final String grade = (m?.grade ?? QualityGrade.unavailable).label;
      final String note = (!available && m?.note != null)
          ? ' (${m!.note})'
          : '';
      buf.writeln('  $label: $value — $grade$note');
    }

    buf
      ..writeln()
      ..writeln('Cloud apps reachable?');
    if (_sites.isEmpty) {
      buf.writeln('  No reachability results.');
    } else {
      for (final SiteReachability s in _sites) {
        final String status = s.reachable ? 'reachable' : 'unreachable';
        final String rtt = (s.reachable && s.latencyMs != null)
            ? ' (${s.latencyMs!.round()} ms)'
            : '';
        buf.writeln('  ${s.site.name}: $status$rtt');
      }
    }

    buf
      ..writeln()
      ..writeln(
        "These are this app's own measurements, not a third-party score. "
        'The Responsiveness grade is an indicative figure inspired by '
        'RFC 9097, not the full standard.',
      );

    return buf.toString().trimRight();
  }

  Widget _body() {
    // Web (and any platform with no socket stack) → the shared
    // download-the-native-app fallback. The engine needs dart:io sockets/HTTP
    // that browsers do not provide, so the screen never tries to run there.
    if (!NetworkSupport.activeNetworkSupported) {
      return NetworkUnavailableView(
        toolName: 'Network Quality',
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
                    toolId: 'net-quality',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('net-quality'))
                    const SizedBox(height: AppSpacing.md),
                  _runCard(context),
                  if (_running) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  // The metrics card redraws as live samples land, so it is
                  // wrapped in a ListenableBuilder over the monitor. It shows
                  // once there is either a one-shot result OR any live history.
                  ListenableBuilder(
                    listenable: _monitor,
                    builder: (context, _) {
                      final bool hasLive = _monitor
                          .historyFor(MetricIds.latency)
                          .isNotEmpty;
                      if (_result == null && !hasLive) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: _metricsCard(context),
                      );
                    },
                  ),
                  if (_result != null || _sites.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _sitesCard(context),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _honestyCaption(context),
                  ],
                  // §8.16.1 tool-help footer — the LAST element in the scroll
                  // body, inside the content-max-width column. It owns its own
                  // --space-lg gap above and the bottom safe-area inset, so no
                  // SizedBox precedes it here. Wired via onTap to the bespoke
                  // per-metric showNetQualityHelpSheet (richer than the catalog
                  // helpForId sheet), keeping that content unchanged while the
                  // affordance matches every other tool screen.
                  ToolHelpFooter(
                    toolId: 'net-quality',
                    onTap: () => showNetQualityHelpSheet(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _runCard(BuildContext context) {
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
        children: <Widget>[
          Text(
            'Measures latency, jitter, loss, download, upload, and '
            'responsiveness over a TCP-connect probe and HTTPS transfers, then '
            'checks whether your device can reach a set of popular cloud apps '
            'right now. Each dimension is graded on its own; there is no single '
            'score.',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: colors.statusDanger),
            ),
          ],
          // THE CELLULAR-DATA COST, STATED BEFORE THE USER SPENDS IT (F-1).
          // Only on a POSITIVE not-on-Wi-Fi probe — an ambiguous read never nags.
          // The cost is a RANGE and a MECHANISM, not an invented figure: it
          // genuinely depends on link speed and cannot be known before the run
          // (GL-005). Identical wording to Test My Connection, deliberately —
          // the same cost, told the same way, wherever the bytes are spent.
          if (_notOnWifi && !_running) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              "You're on cellular. The speed test is not capped by size: it "
              'downloads at full speed for about 30 seconds, so it uses roughly '
              '50 MB on a slow link and 500 MB or more on fast 5G. Everything '
              'else on this screen is cheap.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Full-width primary action, matching the other network screens.
          Semantics(
            button: true,
            enabled: !_running,
            // MINOR 6 (WCAG): the SR button label tracks state — it announces
            // "Running network quality test" while the test runs, and flips
            // back to the actionable label when idle. Off Wi-Fi the label states
            // the data cost, so the tap is an INFORMED one for a screen-reader
            // user exactly as it is for a sighted one.
            label: _running
                ? 'Running network quality test'
                : (_notOnWifi
                    ? 'Run the full test including the speed test, which uses '
                        'cellular data'
                    : 'Run the network quality test'),
            child: FilledButton(
              onPressed: _running
                  ? null
                  : () {
                      // THE TAP IS THE CONSENT. Off Wi-Fi this button's own label
                      // states the cost, directly under the warning that explains
                      // it, so tapping it IS the informed decision. Record it
                      // before the run so the chokepoint in [_run] honors it.
                      if (_notOnWifi) _throughputConsented = true;
                      unawaited(_run(includeThroughput: true));
                    },
              child: Text(
                _running
                    ? 'Running…'
                    : (_notOnWifi ? 'Run test (uses data)' : 'Run test'),
              ),
            ),
          ),
          // THE DECLINE PATH. Not a dead end: latency, jitter, loss and the
          // reachability table all still run and are all cheap. Only the two
          // data-hungry stages are withheld, and they report their honest
          // unavailable note — never a fabricated zero.
          if (_notOnWifi && !_running) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              button: true,
              label: 'Run without the speed test, using no cellular data',
              child: TextButton(
                onPressed: () => unawaited(_run(includeThroughput: false)),
                child: const Text('Run without the speed test'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progressCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final int pct = (_fraction * 100).round();
    final String caption = _phaseCaption(_phase);

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
              // MAJOR 4 (WCAG 4.1.3): the phase caption is the live progress
              // status, so it is its own liveRegion — screen readers announce
              // each phase change ("Measuring download…") as it lands.
              Semantics(
                liveRegion: true,
                child: Text(
                  caption,
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0.4,
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
          // WCAG 4.1.3 — a bare bar announces nothing; give it a descriptive
          // label. The live announcement is owned by the caption above (one
          // liveRegion only, so AT does not double-speak the phase change).
          //
          // Value-tweening: the engine emits time-weighted fractions, but band
          // pivots and the instant-metrics step can still arrive as discrete
          // jumps. A TweenAnimationBuilder glides the bar from its previous
          // value to each new target over AppMotion.base, so every step eases
          // instead of snapping. The engine guarantees monotonic fractions, so
          // the tween only ever animates forward.
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
                    // Indeterminate only at the very start (before the first
                    // real emit); a tweened zero would read as a stuck bar.
                    value: _fraction == 0 ? null : value,
                    minHeight: 6,
                    backgroundColor: colors.surface2,
                    // §8.20.3-B/C (vivid placement, 2026-06-05) — a 6px progress
                    // bar is an AREA, not a thin line, so the fill carries FULL
                    // brand lime #A1CC3A in both themes. (Reverses the earlier
                    // olive-substitute, now reserved for thin foregrounds only.)
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Human caption for the current phase while running.
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
      case QualityPhase.responsiveness:
        return 'Checking responsiveness…';
      case QualityPhase.complete:
        return 'Finishing…';
      case QualityPhase.failed:
        return 'Failed';
    }
  }

  /// Fixed transport order so the card reads the same every run.
  static const List<String> _metricOrder = <String>[
    MetricIds.latency,
    MetricIds.jitter,
    MetricIds.loss,
    MetricIds.download,
    MetricIds.upload,
    MetricIds.responsiveness,
  ];

  /// The latency trio is sampled live every 30 s; the rest only on a one-shot
  /// run. Used to pick dense-line vs. dots-only rendering and the hint copy.
  static const Set<String> _liveTrio = <String>{
    MetricIds.latency,
    MetricIds.jitter,
    MetricIds.loss,
  };

  /// Static label + unit per metric, so a row can render from live history
  /// alone (before any one-shot run, when there is no [QualityResult] yet).
  static const Map<String, (String, String)> _metricMeta =
      <String, (String, String)>{
        MetricIds.latency: ('Latency', 'ms'),
        MetricIds.jitter: ('Jitter', 'ms'),
        MetricIds.loss: ('Loss', '%'),
        MetricIds.download: ('Download', 'Mbps'),
        MetricIds.upload: ('Upload', 'Mbps'),
        MetricIds.responsiveness: ('Responsiveness', 'RPM'),
      };

  Widget _metricsCard(BuildContext context) {
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
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                'Transport',
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The indicator takes the remaining width so its caption can
              // ellipsize on narrow phones instead of overflowing the row.
              Expanded(child: _liveIndicator(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final String id in _metricOrder) _metricRow(context, id),
        ],
      ),
    );
  }

  /// The quiet, honest live affordance: a status word plus a pause/resume
  /// control. It states exactly what is live (latency, every 30 s) and never
  /// implies the speed metrics are live — they are not (spec §3).
  Widget _liveIndicator(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool running = _monitor.isRunning;
    final String caption = running
        ? 'Live · sampling latency every 30s'
        : 'Paused';
    final Color dotColor = running
        ? colors.statusSuccess
        : colors.textTertiary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        // WCAG 1.4.1 — the dot only reinforces the word "Live"/"Paused", which
        // carries the state. Decorative for AT.
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        Flexible(
          child: Text(
            caption,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        // Stateful SR label like the Run button: announces the ACTION the tap
        // performs, and flips with state.
        Semantics(
          button: true,
          label: running ? 'Pause live sampling' : 'Resume live sampling',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: colors.textSecondary,
            tooltip: running ? 'Pause' : 'Resume',
            onPressed: () => running ? _monitor.pause() : _monitor.resume(),
            icon: Icon(running ? Icons.pause : Icons.play_arrow),
          ),
        ),
      ],
    );
  }

  Widget _metricRow(BuildContext context, String id) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final (String label, String unit) = _metricMeta[id]!;
    final List<MetricSample> history = _monitor.historyFor(id);
    final QualityMetric? oneShot = _result?.metric(id);

    // Current value/grade: prefer the most recent live sample (latency trio),
    // fall back to the one-shot result (the expensive trio, and the trio before
    // the first live tick lands).
    final MetricSample? latest = history.isNotEmpty ? history.last : null;

    final bool available =
        latest != null || (oneShot != null && oneShot.isAvailable);

    final double? currentValue = latest?.value ?? oneShot?.value;
    final QualityGrade grade =
        latest?.grade ?? oneShot?.grade ?? QualityGrade.unavailable;
    final String? note = (latest == null) ? oneShot?.note : null;

    final String valueLabel = available
        ? _formatValueRaw(id, currentValue!, unit)
        : (note ?? 'Unavailable');

    // Whole row is one semantic node so AT reads "<label>, <value>, <grade>".
    final String gradePhrase = available
        ? grade.label
        : 'unavailable${note == null ? '' : ', $note'}';
    final String semanticValue = available
        ? _spokenValueRaw(id, currentValue!)
        : valueLabel;

    // Sparkline / hint state (spec §3): 0–1 points → hint, not a misleading
    // line. The expensive trio is dots-only (points are runs apart).
    final SparklineDomain? domain = SparklineDomain.forMetric(id);
    final bool enoughForLine = history.length >= 2;
    final String trendSemantic = _trendSemantic(
      label,
      unit,
      id,
      history,
      grade,
      available,
    );

    return Semantics(
      label: '$label, $semanticValue, $gradePhrase. $trendSemantic',
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          // §8.7 named row-padding token (12px) — never hardcoded.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          style: text.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!available && note != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            note,
                            style: text.labelSmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (available)
                    // MAJOR 3 (320px overflow): the value shares one row with
                    // an Expanded label and a fixed-width grade chip. Flexible
                    // + ellipsis lets a long value give way instead of throwing
                    // a RenderFlex overflow in a ~150px 2-column grid cell.
                    Flexible(
                      child: Text(
                        valueLabel,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: mono.outputMedium.copyWith(
                          color: colors.textAccent,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  _gradeChip(context, grade),
                ],
              ),
              // Sparkline (>= 2 points) or a hint (0–1 points). The grade chip
              // above always carries the true grade; the sparkline is a visual
              // trend reference only (spec §3 + §4).
              if (domain != null) ...[
                const SizedBox(height: AppSpacing.xs),
                if (enoughForLine)
                  MetricSparkline(
                    samples: history,
                    domain: domain,
                    dotsOnly: !_liveTrio.contains(id),
                  )
                else
                  _trackingHint(context, id),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Hint shown when a metric has 0–1 points — a line would be misleading
  /// (spec §3). The expensive trio is sparse by design, so its hint nudges a
  /// run; the latency trio only shows this for the brief moment before the
  /// first live tick lands.
  Widget _trackingHint(BuildContext context, String id) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String message = _liveTrio.contains(id)
        ? 'Sampling…'
        : 'Run a test to start tracking';
    return Container(
      height: 40,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        message,
        style: text.labelSmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }

  /// Worded trend summary for the row's semantic label (spec §4): e.g.
  /// "Latency trend, 12 samples, range 14 to 41 milliseconds." Kept compact;
  /// the current value + grade are already in the row's primary label, so this
  /// adds the count and range, never color.
  String _trendSemantic(
    String label,
    String unit,
    String id,
    List<MetricSample> history,
    QualityGrade grade,
    bool available,
  ) {
    if (history.length < 2) {
      if (!available) return 'No trend yet';
      return 'Tracking, 1 sample';
    }
    double mn = history.first.value;
    double mx = history.first.value;
    for (final MetricSample s in history) {
      if (s.value < mn) mn = s.value;
      if (s.value > mx) mx = s.value;
    }
    final String unitWord = _spokenUnit(id);
    return '$label trend, ${history.length} samples, '
        'range ${_round(id, mn)} to ${_round(id, mx)} $unitWord';
  }

  static String _round(String id, double v) {
    if (id == MetricIds.download || id == MetricIds.upload) {
      return v.toStringAsFixed(1);
    }
    return v.round().toString();
  }

  static String _spokenUnit(String id) {
    switch (id) {
      case MetricIds.download:
      case MetricIds.upload:
        return 'megabits per second';
      case MetricIds.responsiveness:
        return 'round-trips per minute';
      case MetricIds.loss:
        return 'percent';
      default:
        return 'milliseconds';
    }
  }

  /// Compact graded chip. WCAG 1.4.1 — the grade is ALWAYS carried by the text
  /// label, never by color alone; the color only reinforces it. Backgrounds map
  /// to the GL-003 §8.13 status palette; the unavailable grade takes a neutral
  /// surface so it never reads as a verdict.
  Widget _gradeChip(BuildContext context, QualityGrade grade) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // §8.20.4 Style A — light renders a SOLID-FILL PILL: the full-strength
    // status hue fill carrying a WHITE 700 label + WHITE Material glyph, no
    // border (white-on-fill 5.4–5.9:1). Dark keeps its solid-fill chip with
    // dark text.
    if (colors.isLight) {
      const Color white = Color(0xFFFFFFFF);
      final (Color fill, IconData? glyph) = _lightGradeParts(grade, colors);
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (glyph != null) ...<Widget>[
              Icon(glyph, size: 16, color: white),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Flexible(
              child: Text(
                grade.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: white,
                  fontWeight: FontWeight.w700, // §8.20.3-A verdict words
                ),
              ),
            ),
          ],
        ),
      );
    }

    final (Color bg, Color fg) = _gradeColors(grade, colors);
    // Contrast: dark chip label clears WCAG 4.5:1 on all grade backgrounds.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        // The neutral chip needs a perceivable boundary on its surface.
        border: grade == QualityGrade.unavailable
            ? Border.all(color: colors.borderStrong, width: 1)
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

  /// §8.20.4 Style A light parts: the SOLID full-strength status hue fill and
  /// its matching Material status glyph. Label + glyph render in WHITE on the
  /// fill. Unavailable has no status hue, so it fills with neutral textSecondary.
  static (Color fill, IconData? glyph) _lightGradeParts(
      QualityGrade grade, AppColorScheme c) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (c.statusSuccess, Icons.check_circle);
      case QualityGrade.fair:
        return (c.statusWarning, Icons.warning_amber);
      case QualityGrade.poor:
        return (c.statusDanger, Icons.error);
      case QualityGrade.unavailable:
        // Neutral solid fill (textSecondary #4A4A4A, white-on-fill 9.0:1).
        return (c.textSecondary, Icons.info);
    }
  }

  /// GL-003 §8.13 status-token mapping for grade chips. Foreground is the dark
  /// `secondary` (#1A1A1A) on every verdict chip — dark text clears WCAG 4.5:1
  /// on all three grade backgrounds, so no per-grade white exception is needed:
  ///   excellent + good → statusSuccess (#5BD68A), dark text (9.47:1)
  ///   fair             → statusWarning (#E0A23A), dark text (7.79:1)
  ///   poor             → statusDanger  (#F26E6E), dark text (5.99:1)
  ///   unavailable      → neutral surface2 + textSecondary (11.39:1, no verdict)
  /// Every pairing clears WCAG 2.2 AA for normal text (see app_tokens.dart).
  static (Color, Color) _gradeColors(QualityGrade grade, AppColorScheme colors) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (colors.statusSuccess, colors.onPrimary);
      case QualityGrade.fair:
        return (colors.statusWarning, colors.onPrimary);
      case QualityGrade.poor:
        return (colors.statusDanger, colors.onPrimary);
      case QualityGrade.unavailable:
        return (colors.surface2, colors.textSecondary);
    }
  }

  /// Display value with sensible rounding: integers for ms / % / RPM, one
  /// decimal for throughput, then the unit. Examples: "14 ms", "512.4 Mbps",
  /// "0%", "820 RPM". Works from a raw id+value so it serves both the one-shot
  /// result and a live sample (which has no [QualityMetric] wrapper).
  static String _formatValueRaw(String id, double v, String unit) {
    final String number;
    switch (id) {
      case MetricIds.download:
      case MetricIds.upload:
        number = v.toStringAsFixed(1);
      default:
        number = v.round().toString();
    }
    // Percent reads "0%" (no space); the rest read "14 ms", "820 RPM".
    if (unit == '%') return '$number%';
    return '$number $unit';
  }

  /// Spoken form of the value for the row's semantic label (units expanded).
  static String _spokenValueRaw(String id, double v) {
    switch (id) {
      case MetricIds.download:
      case MetricIds.upload:
        return '${v.toStringAsFixed(1)} megabits per second';
      case MetricIds.responsiveness:
        return '${v.round()} round-trips per minute';
      case MetricIds.loss:
        return '${v.round()} percent';
      default:
        return '${v.round()} milliseconds';
    }
  }

  Widget _sitesCard(BuildContext context) {
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
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Cloud apps reachable?',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // HONESTY (GL-005): a TCP-connect proves the service EDGE answers and
          // times that hop. It is not a measure of in-app call / stream quality.
          Text(
            'Reachability and latency to each service edge. Not a measure of '
            'in-app call or stream quality.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_sites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No reachability results. The check did not return. Your '
                'connection may be down.',
                style: text.bodyLarge?.copyWith(color: colors.textTertiary),
              ),
            )
          else
            for (final SiteReachability s in _sites) _siteRow(context, s),
        ],
      ),
    );
  }

  Widget _siteRow(BuildContext context, SiteReachability s) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool ok = s.reachable;
    // WCAG 1.4.1 — outcome carried by icon shape AND a text status word, never
    // color alone.
    final IconData icon = ok ? Icons.check_circle : Icons.cancel;
    final Color iconColor = ok
        ? colors.statusSuccess
        : colors.statusDanger;
    final String status = ok ? 'reachable' : 'unreachable';
    final String rtt = ok && s.latencyMs != null
        ? '${s.latencyMs!.round()} ms'
        : '—';

    return Semantics(
      label:
          '${s.site.name}, $status'
          '${ok && s.latencyMs != null ? ', ${s.latencyMs!.round()} milliseconds' : ''}',
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  s.site.name,
                  style: text.bodyLarge?.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                status,
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 64,
                child: Text(
                  rtt,
                  textAlign: TextAlign.right,
                  style: mono.inlineCode.copyWith(
                    color: ok ? colors.textAccent : colors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _honestyCaption(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // MINOR 5 (legibility): this honesty note reads at the §3 caption size
    // (13px, the next step up from the prior 11px) and stays secondary-toned
    // (textSecondary) so it remains supporting copy without dropping below the
    // 12px floor.
    return Text(
      'These are this app\'s own measurements, not a third-party score. '
      'The Responsiveness grade is an indicative figure inspired by RFC 9097, '
      'not the full standard.',
      style: text.labelMedium?.copyWith(color: colors.textSecondary),
    );
  }
}
