// Network Quality tool — a one-shot transport-quality measurement plus a
// popular-site reachability table, built on the pure-Dart `net_quality`
// engine (packages/net_quality). The screen depends ONLY on the QualityClient
// seam and ReachabilityProbe, never on a concrete probe, so the backend is
// swappable and the whole screen is testable with a MockQualityClient and no
// real network.
//
// HONESTY (GL-005 + ARCHITECTURE.md): these are this app's OWN measurements,
// not an Orb or Ookla score, and there is deliberately no single composite
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
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';

/// Network Quality screen. Runs one transport measurement and a popular-site
/// reachability pass, then renders six graded metric rows and a reachability
/// table.
class NetQualityScreen extends StatefulWidget {
  const NetQualityScreen({
    super.key,
    this.client,
    this.reachabilityProbe,
  });

  /// Measurement backend. Injected in tests (a [MockQualityClient] with no
  /// network); null in production, where the screen builds a real
  /// [OwnEngineQualityClient] targeting Cloudflare's one.one.one.one.
  final QualityClient? client;

  /// Reachability backend. Injected in tests with a fake [SiteProber] and a
  /// short site list; null in production, where the screen builds a real
  /// [ReachabilityProbe] over the default [kPopularSites].
  final ReachabilityProbe? reachabilityProbe;

  @override
  State<NetQualityScreen> createState() => _NetQualityScreenState();
}

class _NetQualityScreenState extends State<NetQualityScreen> {
  late final QualityClient _client;
  late final ReachabilityProbe _reachability;

  bool _running = false;
  String? _error;

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
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Kicks off both the transport measurement and the reachability pass from a
  /// single Run action. The reachability future resolves independently and
  /// updates its own section when done.
  void _run() {
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
    unawaited(_reachability.measure().then((List<SiteReachability> sites) {
      if (!mounted) return;
      setState(() => _sites = sites);
    }).catchError((Object _) {
      // A reachability failure is non-fatal: leave the section empty rather
      // than surfacing an error over the transport result.
      if (!mounted) return;
      setState(() => _sites = <SiteReachability>[]);
    }));

    _sub = _client.measure().listen(
      (QualityProgress p) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _running = false;
          _result = _client.lastResult;
        });
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
      appBar: AppBar(title: const Text('Network Quality'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body()),
    );
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
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _metricsCard(context),
                  ],
                  if (_result != null || _sites.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _sitesCard(context),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _honestyCaption(context),
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
            'Measures latency, jitter, loss, download, upload, and '
            'responsiveness over a TCP-connect probe and an HTTPS transfer to '
            'Cloudflare, then checks reachability to a list of popular sites. '
            'Each dimension is graded on its own; there is no single score.',
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
          // Full-width primary action, matching the other network screens.
          Semantics(
            button: true,
            enabled: !_running,
            // MINOR 6 (WCAG): the SR button label tracks state — it announces
            // "Running network quality test" while the test runs, and flips
            // back to the actionable label when idle.
            label: _running
                ? 'Running network quality test'
                : 'Run the network quality test',
            child: FilledButton(
              onPressed: _running ? null : _run,
              child: Text(_running ? 'Running…' : 'Run test'),
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
              // MAJOR 4 (WCAG 4.1.3): the phase caption is the live progress
              // status, so it is its own liveRegion — screen readers announce
              // each phase change ("Measuring download…") as it lands.
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
          // WCAG 4.1.3 — a bare bar announces nothing; give it a descriptive
          // label. The live announcement is owned by the caption above (one
          // liveRegion only, so AT does not double-speak the phase change).
          Semantics(
            label: '$caption, $pct percent complete',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: LinearProgressIndicator(
                value: _fraction == 0 ? null : _fraction,
                minHeight: 6,
                backgroundColor: AppColors.surface2,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
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
      case QualityPhase.complete:
        return 'Finishing…';
      case QualityPhase.failed:
        return 'Failed';
    }
  }

  Widget _metricsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final QualityResult result = _result!;
    // Fixed transport order so the card reads the same every run.
    const List<String> order = <String>[
      MetricIds.latency,
      MetricIds.jitter,
      MetricIds.loss,
      MetricIds.download,
      MetricIds.upload,
      MetricIds.responsiveness,
    ];
    final List<QualityMetric> metrics = <QualityMetric>[
      for (final String id in order)
        if (result.metric(id) != null) result.metric(id)!,
    ];

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
            'Transport',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final QualityMetric m in metrics) _metricRow(context, m),
        ],
      ),
    );
  }

  Widget _metricRow(BuildContext context, QualityMetric m) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool available = m.isAvailable;
    final String valueLabel =
        available ? _formatValue(m) : (m.note ?? 'Unavailable');

    // Whole row is one semantic node so AT reads "<label>, <value>, <grade>".
    final String gradePhrase = available
        ? m.grade.label
        : 'unavailable${m.note == null ? '' : ', ${m.note}'}';
    final String semanticValue = available ? _spokenValue(m) : valueLabel;

    return Semantics(
      label: '${m.label}, $semanticValue, $gradePhrase',
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          // §8.7 named row-padding token (12px) — never hardcoded.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      m.label,
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!available && m.note != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        m.note!,
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (available)
                // MAJOR 3 (320px overflow): the value shares one row with an
                // Expanded label and a fixed-width grade chip. Flexible +
                // ellipsis lets a long value give way instead of throwing a
                // RenderFlex overflow in a ~150px 2-column grid cell.
                Flexible(
                  child: Text(
                    valueLabel,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: mono.outputMedium.copyWith(color: AppColors.primary),
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              _gradeChip(context, m.grade),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact graded chip. WCAG 1.4.1 — the grade is ALWAYS carried by the text
  /// label, never by color alone; the color only reinforces it. Backgrounds map
  /// to the GL-003 §8.13 status palette; the unavailable grade takes a neutral
  /// surface so it never reads as a verdict.
  Widget _gradeChip(BuildContext context, QualityGrade grade) {
    final TextTheme text = Theme.of(context).textTheme;
    final (Color bg, Color fg) = _gradeColors(grade);
    // Contrast: dark chip label clears WCAG 4.5:1 on all grade backgrounds;
    // bespoke successStrong/onWarningStrong tokens are an Iris call (GL-003).
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

  /// GL-003 §8.13 status-token mapping for grade chips. Foreground is the dark
  /// `secondary` (#1A1A1A) on every verdict chip — dark text clears WCAG 4.5:1
  /// on all three grade backgrounds, so no per-grade white exception is needed:
  ///   excellent + good → statusSuccess (#5BD68A), dark text (13.79:1)
  ///   fair             → statusWarning (#E0A23A), dark text (9.95:1)
  ///   poor             → statusDanger  (#F26E6E), dark text (7.27:1)
  ///   unavailable      → neutral surface2 + textSecondary (6.30:1, no verdict)
  /// Every pairing clears WCAG 2.2 AA for normal text (see app_tokens.dart).
  static (Color, Color) _gradeColors(QualityGrade grade) {
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

  /// Display value with sensible rounding: integers for ms / % / RPM, one
  /// decimal for throughput, then the unit. Examples: "14 ms", "512.4 Mbps",
  /// "0%", "820 RPM".
  static String _formatValue(QualityMetric m) {
    final double v = m.value!;
    final String number;
    switch (m.id) {
      case MetricIds.download:
      case MetricIds.upload:
        number = v.toStringAsFixed(1);
      default:
        number = v.round().toString();
    }
    // Percent reads "0%" (no space); the rest read "14 ms", "820 RPM".
    if (m.unit == '%') return '$number%';
    return '$number ${m.unit}';
  }

  /// Spoken form of the value for the row's semantic label (units expanded).
  static String _spokenValue(QualityMetric m) {
    final double v = m.value!;
    switch (m.id) {
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
            'Popular sites',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_sites.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No reachability results. The check did not return — your '
                'connection may be down.',
                style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
              ),
            )
          else
            for (final SiteReachability s in _sites) _siteRow(context, s),
        ],
      ),
    );
  }

  Widget _siteRow(BuildContext context, SiteReachability s) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool ok = s.reachable;
    // WCAG 1.4.1 — outcome carried by icon shape AND a text status word, never
    // color alone.
    final IconData icon = ok ? Icons.check_circle : Icons.cancel;
    final Color iconColor =
        ok ? AppColors.statusSuccess : AppColors.statusDanger;
    final String status = ok ? 'reachable' : 'unreachable';
    final String rtt = ok && s.latencyMs != null
        ? '${s.latencyMs!.round()} ms'
        : '—';

    return Semantics(
      label: '${s.site.name}, $status'
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
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                status,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 64,
                child: Text(
                  rtt,
                  textAlign: TextAlign.right,
                  style: mono.inlineCode.copyWith(
                    color: ok ? AppColors.primary : AppColors.textTertiary,
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
    final TextTheme text = Theme.of(context).textTheme;
    // MINOR 5 (legibility): this honesty note reads at the §3 caption size
    // (13px, the next step up from the prior 11px) and stays secondary-toned
    // (textSecondary) so it remains supporting copy without dropping below the
    // 12px floor.
    return Text(
      'These are this app\'s own measurements, not an Orb or Ookla score. '
      'The Responsiveness grade is an indicative figure inspired by RFC 9097, '
      'not the full standard.',
      style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
    );
  }
}
