// Cloud Apps reachability panel — the named-app reachability surface (Feature 1,
// Felix 2026-06-13, per Pax's gap brief Deliverables/2026-06-13-toolbox-gap-
// feasibility/feasibility-brief.md).
//
// REUSE, no new measurement: it drives the SAME shared [ReachabilityProbe] the
// Network Quality tool runs, over the recurated [kCloudApps] named-service list.
// The probe times a TCP-connect to each service edge on :443 (sandboxed iOS /
// macOS apps cannot open raw ICMP sockets — GL-008), concurrently.
//
// HONESTY (GL-005): a successful connect proves the service EDGE / CDN is
// reachable and times THAT hop; it is NOT a measure of in-app call or stream
// quality. The caption says so verbatim. An unreachable host renders an explicit
// "unreachable" word + glyph (never color alone — WCAG 2.2 SC 1.4.1), never a
// fabricated latency.
//
// STATES (all explicit): loading (probe in flight → skeleton rows), success
// (per-service rows), partial (some unreachable — same row, honest word), error
// (probe threw → recoverable retry), empty/all-unreachable (honest "couldn't
// reach any" + retry). Disabled is N/A (the only control is Retry, disabled
// while a probe is in flight).
//
// LAYOUT: a surface1 card with the §8.1 hairline border, matching the sibling
// result cards on Test My Connection. Drop it as a child of the result column.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:net_quality/net_quality.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// The lifecycle of the cloud-apps reachability probe.
enum _PanelPhase { loading, ready, error }

/// A self-contained panel that probes the recurated [kCloudApps] named services
/// for reachability + latency and renders the result, reusing the shared
/// [ReachabilityProbe] engine. All states (loading / success / partial / error /
/// all-unreachable) are handled explicitly.
class CloudAppsPanel extends StatefulWidget {
  const CloudAppsPanel({
    super.key,
    this.probe,
    this.autoStart = true,
    this.onResults,
  });

  /// Injectable reachability probe (tests pass a fake prober). Defaults to a
  /// real [ReachabilityProbe] over [kCloudApps].
  final ReachabilityProbe? probe;

  /// When true (production default) the probe runs on first mount. Tests that
  /// drive the probe manually can disable it.
  final bool autoStart;

  /// Fired whenever a probe completes with the latest per-service reachability
  /// rows (Keith ISP/comprehensive-copy ask). The host screen reads it so the
  /// "Copy these details" payload can carry the cloud-apps reachability summary
  /// alongside the Wi-Fi / internet / ISP sections. Honest by construction: it
  /// only ever carries the rows the probe actually produced — never a fabricated
  /// reachability claim. Optional; null in tests that do not exercise the copy.
  final ValueChanged<List<SiteReachability>>? onResults;

  @override
  State<CloudAppsPanel> createState() => _CloudAppsPanelState();
}

class _CloudAppsPanelState extends State<CloudAppsPanel> {
  late final ReachabilityProbe _probe;

  _PanelPhase _phase = _PanelPhase.loading;
  List<SiteReachability> _results = const <SiteReachability>[];

  /// Guards setState after an in-flight probe completes post-dispose.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _probe = widget.probe ?? ReachabilityProbe(sites: kCloudApps);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_run());
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Runs the reachability probe. Never throws to the framework: a probe failure
  /// lands on the honest [_PanelPhase.error] retry state.
  Future<void> _run() async {
    if (!mounted) return;
    setState(() {
      _phase = _PanelPhase.loading;
      _results = const <SiteReachability>[];
    });
    try {
      final List<SiteReachability> results = await _probe.measure();
      if (_disposed || !mounted) return;
      setState(() {
        _results = results;
        _phase = _PanelPhase.ready;
      });
      // Surface the rows to the host screen for the comprehensive copy payload.
      widget.onResults?.call(results);
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Cloud app reachability check complete',
        TextDirection.ltr,
      );
    } catch (_) {
      if (_disposed || !mounted) return;
      setState(() => _phase = _PanelPhase.error);
    }
  }

  /// Number of services that answered, for the honest summary line.
  int get _reachableCount => _results.where((SiteReachability s) => s.reachable).length;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

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
          // Header — SR heading so heading-rotor nav can land here.
          Semantics(
            header: true,
            child: Text(
              'Cloud apps reachable?',
              style: text.labelMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // HONESTY caption (GL-005) — what a green check does and does NOT mean.
          Text(
            'Can your device reach these services right now? This times a connect '
            'to each service edge. It is not a measure of in-app call or stream '
            'quality.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _content(context),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (_phase) {
      case _PanelPhase.loading:
        return _LoadingRows(sites: _probe.sites);
      case _PanelPhase.error:
        return _ErrorState(onRetry: _run);
      case _PanelPhase.ready:
        if (_results.isEmpty) {
          // The probe returned no rows at all (an empty target list) — honest
          // empty state, not a blank card.
          return _EmptyState(onRetry: _run);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Summary line — how many of N answered. Lives above the rows so the
            // user reads the verdict first.
            _SummaryLine(
              reachable: _reachableCount,
              total: _results.length,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final SiteReachability s in _results) _CloudAppRow(result: s),
            const SizedBox(height: AppSpacing.xs),
            // Keith #7: scope the label so it is unmistakable that this button
            // ONLY re-runs the cloud-apps reachability probe — NOT the whole
            // Wi-Fi/internet test (which is the AppBar "Run again" affordance).
            _RetryButton(onRetry: _run, label: 'Re-check cloud apps'),
          ],
        );
    }
  }
}

/// The "N of M reachable" summary, an SR live region so a re-run is announced.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.reachable, required this.total});

  final int reachable;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool allOk = reachable == total;
    final bool noneOk = reachable == 0;
    final String line = noneOk
        ? "Couldn't reach any of these services. Your connection may be down."
        : allOk
            ? 'All $total services are reachable.'
            : '$reachable of $total services are reachable.';
    return Text(
      line,
      style: text.bodyMedium?.copyWith(
        color: noneOk ? colors.textSecondary : colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// One service row: name (left), status WORD (never color alone), latency (mono,
/// right). The whole row is one SR node.
class _CloudAppRow extends StatelessWidget {
  const _CloudAppRow({required this.result});

  final SiteReachability result;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool ok = result.reachable;
    // WCAG 2.2 SC 1.4.1 — outcome carried by icon SHAPE and a text WORD, never
    // by color alone. The hue only reinforces.
    final IconData icon = ok ? Icons.check_circle : Icons.cancel;
    final Color iconColor = ok ? colors.statusSuccess : colors.statusDanger;
    final String status = ok ? 'reachable' : 'unreachable';
    final String rtt = ok && result.latencyMs != null
        ? '${result.latencyMs!.round()} ms'
        : 'n/a';

    return Semantics(
      container: true,
      label: '${result.site.name}, $status'
          '${ok && result.latencyMs != null ? ', ${result.latencyMs!.round()} milliseconds' : ''}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Icon nudged onto the text baseline of a possibly-wrapped row.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Keith #3 (320px mid-word wrap): the name column gets the larger
              // flex AND word-boundary wrapping (softWrap: true,
              // wordSpacing-default), so service names break at spaces — never
              // mid-character ("Faceboo-k"). The status word is the flexible one
              // that yields room and wraps on its own word boundary, so it can
              // never squeeze the name box below a single word's width at 320px
              // or under scaled dynamic type.
              Expanded(
                flex: 3,
                child: Text(
                  result.site.name,
                  softWrap: true,
                  style: text.bodyLarge?.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                flex: 2,
                child: Text(
                  status,
                  softWrap: true,
                  textAlign: TextAlign.right,
                  style: text.labelMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 56,
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
}

/// Loading state — one shimmer-less skeleton row per target so the card holds
/// its shape while the concurrent probe is in flight (no layout jump on land).
class _LoadingRows extends StatelessWidget {
  const _LoadingRows({required this.sites});

  final List<PopularSite> sites;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // Track tone: on light, surface2 is white and vanishes on the white card, so
    // the placeholder bar uses the gray canvas instead.
    final Color barColor = colors.isLight ? colors.surface0 : colors.surface2;
    return Semantics(
      liveRegion: true,
      label: 'Checking cloud app reachability',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Checking…',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final PopularSite s in sites)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.radio_button_unchecked,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        s.name,
                        style: text.bodyLarge?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 10,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Error state — the probe threw. Honest message + a recoverable retry.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          "Couldn't run the cloud-app check. Please try again.",
          style: text.bodyMedium?.copyWith(color: colors.statusDanger),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Keith #7: match the scoped label used in the success / empty states so
        // it is unmistakable this only re-runs the cloud-apps probe, never the
        // whole Wi-Fi/internet test.
        _RetryButton(onRetry: onRetry, label: 'Re-check cloud apps'),
      ],
    );
  }
}

/// Empty state — the probe returned no rows (no targets). Honest, with a retry.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'No services to check right now.',
          style: text.bodyMedium?.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.sm),
        _RetryButton(onRetry: onRetry, label: 'Re-check cloud apps'),
      ],
    );
  }
}

/// Shared retry/refresh control. Left-aligned, outlined, keyboard-operable, with
/// the framework's default §8.3 focus ring.
class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry, required this.label});

  final Future<void> Function() onRetry;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: label,
        child: OutlinedButton.icon(
          onPressed: () => unawaited(onRetry()),
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}
