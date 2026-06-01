// Network Quality "About these metrics" help sheet.
//
// Surfaces the Penn-approved help copy (source of truth:
// Deliverables/2026-05-31-network-quality-help-content/network-quality-help.md)
// in the app. Wired to the AppBar help-affordance idiom established by
// wifi_info_screen ("How to install the Shortcut" -> Icons.help_outline ->
// showModalBottomSheet), and built from the same scrollable-sheet shell as
// install_shortcut_sheet (surface2 sheet, drag handle, ConstrainedBox 560,
// SingleChildScrollView).
//
// HONESTY (GL-005): this screen explains that these are the app's OWN
// measurements (not an Orb/Ookla score), that there is no single composite
// score on purpose, that latency/loss stand in over a port-443 TCP connect
// because the iOS/macOS security model forbids raw pings, and that
// Responsiveness is a simplified single-stream figure inspired by RFC 9097 /
// Apple networkQuality, not the full multi-flow standard. The copy below is the
// approved wording; it must not gain new claims.
//
// Styling is GL-003: surface2 sheet, surface1 cards with a §8.2 hairline border,
// IBM Plex Sans body, textSecondary supporting copy, textTertiary captions. No
// hardcoded colors/spacing/radius. The grade bands render as per-metric blocks
// (label + four band chips) rather than a fixed 5-column table, so the content
// reflows instead of clipping at 320px (§8.9). The chips are neutral category
// labels (Excellent/Good/Fair/Poor as headings), NOT computed verdicts, so per
// §8.13 rule 6 they take neutral surface/text tokens — never a status hue.
//
// States: this is static reference content. It has one state (presented) plus
// the interactive Close affordance; there is no loading/empty/error/data axis.

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';

/// Opens the Network Quality help sheet. Matches [WifiInfoScreen]'s
/// `_openInstallSheet` modal idiom (scroll-controlled, drag handle, surface2).
Future<void> showNetQualityHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface2,
    builder: (_) => const NetQualityHelpSheet(),
  );
}

/// "About these metrics" content for the Network Quality tool. Stateless,
/// scrollable, capped at 560 like the other network sheets.
class NetQualityHelpSheet extends StatelessWidget {
  const NetQualityHelpSheet({super.key});

  // ---- The six metrics (label, what it is, how we measure it). Taken verbatim
  // in spirit from the approved help copy; numbers come straight from the
  // net_quality engine. ----
  static const List<_Metric> _metrics = <_Metric>[
    _Metric(
      name: 'Latency',
      whatItIs: 'How long a round trip to a server takes. Lower is better.',
      howWeMeasure:
          'We open a connection to a server on the secure web port (443) and '
          'time the handshake, then repeat it 10 times and report the average. '
          'We time the connection rather than sending a classic ping, because '
          'the iPhone and Mac security model does not let an app send raw '
          'pings. A timed connection on port 443 stands in for the ping we '
          'cannot send.',
    ),
    _Metric(
      name: 'Jitter',
      whatItIs:
          'How much the latency varies from one moment to the next. A steady '
          'connection has low jitter. Lots of jitter makes calls and video '
          'stutter even when the average latency looks fine.',
      howWeMeasure:
          'Across those same 10 round trips, we average how much each one '
          'differs from the one before it.',
    ),
    _Metric(
      name: 'Loss',
      whatItIs:
          'The share of attempts that failed to get through. Lower is better; '
          'zero is ideal.',
      howWeMeasure:
          'Of the 10 connection attempts, we report the percentage that failed '
          'or timed out. Because we time a connection rather than a raw ping, '
          'this is really a connection-failure rate. It tracks closely with '
          'packet loss for everyday purposes.',
    ),
    _Metric(
      name: 'Responsiveness',
      whatItIs:
          'How quickly your connection still answers while it is busy. This is '
          'the metric that catches "bufferbloat," the lag that shows up only '
          'when something is downloading in the background. It is reported in '
          'round trips per minute (RPM), and higher is better.',
      howWeMeasure:
          'We start a download and, while it is running and loading the '
          'connection, we measure the round-trip time five times. We convert '
          'the average loaded round trip into round trips per minute. A '
          'connection that stays quick under load scores high; one that bogs '
          'down when busy scores low.',
      note:
          'This is a simplified, single-stream estimate inspired by Apple\'s '
          'networkQuality tool and the industry RPM work (RFC 9097). The full '
          'standard pushes many streams at once across several layers. Ours '
          'uses one. Treat the RPM here as a reliable direction, not a '
          'lab-grade figure.',
    ),
    _Metric(
      name: 'Download',
      whatItIs:
          'How fast you can pull data down, in megabits per second (Mbps). '
          'Higher is better.',
      howWeMeasure:
          'We download roughly 25 MB from Cloudflare\'s public speed servers '
          'and divide the data moved by the time it took. It is a real '
          'transfer, not an estimate.',
    ),
    _Metric(
      name: 'Upload',
      whatItIs:
          'How fast you can push data up, in Mbps. Higher is better, and it '
          'often matters more than download for video calls, backups, and '
          'sharing files.',
      howWeMeasure:
          'We upload roughly 10 MB to the same Cloudflare speed servers and '
          'divide the data sent by the time it took.',
    ),
  ];

  // ---- Grade bands (label + the four thresholds), per the approved table. ----
  static const List<_GradeBand> _bands = <_GradeBand>[
    _GradeBand('Latency', 'under 20 ms', 'under 50 ms', 'under 100 ms',
        '100 ms or more'),
    _GradeBand('Jitter', 'under 5 ms', 'under 15 ms', 'under 30 ms',
        '30 ms or more'),
    _GradeBand('Loss', '0%', 'under 1%', 'under 2.5%', '2.5% or more'),
    _GradeBand('Responsiveness', '1000+ RPM', '500+ RPM', '100+ RPM',
        'under 100 RPM'),
    _GradeBand('Download', '100+ Mbps', '25+ Mbps', '5+ Mbps', 'under 5 Mbps'),
    _GradeBand('Upload', '20+ Mbps', '5+ Mbps', '1+ Mbps', 'under 1 Mbps'),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Title is the sheet's heading node for screen readers.
              Semantics(
                header: true,
                child: Text(
                  'About Network Quality',
                  style: text.headlineSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Network Quality measures six things about your connection and '
                'grades each one on its own. There is no single overall score, '
                'on purpose: a connection can be great for video calls and poor '
                'for large uploads at the same time, and one headline number '
                'would hide that. Each metric below stands alone.',
                style:
                    text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Anything the device or operating system will not let us '
                'measure is shown as Unavailable. We never fill that gap with a '
                'guess.',
                style:
                    text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),

              const SizedBox(height: AppSpacing.md),
              _SectionHeading('The six metrics'),
              const SizedBox(height: AppSpacing.xs),
              for (final _Metric m in _metrics) ...<Widget>[
                _MetricCard(metric: m),
                const SizedBox(height: AppSpacing.sm),
              ],

              const SizedBox(height: AppSpacing.xs),
              _SectionHeading('What the grades mean'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Each metric is rated Excellent, Good, Fair, or Poor against the '
                'bands below. Where an industry standard exists, it guides the '
                'direction; the exact cut points are ours.',
                style:
                    text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final _GradeBand b in _bands) ...<Widget>[
                _GradeBandCard(band: b),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                'The latency, jitter, and loss thresholds are guided by '
                'long-standing voice and video quality guidance (ITU-T G.114 '
                'and common VoIP practice). The download and upload thresholds '
                'are our own practical bands, mapped to common broadband tiers '
                'and everyday needs, not a published standard.',
                style:
                    text.bodyMedium?.copyWith(color: AppColors.textTertiary),
              ),

              const SizedBox(height: AppSpacing.md),
              const _HonestyCard(),

              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Close help',
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}

/// One metric explained: name, what it is, how we measure it, optional caveat.
/// The whole card is one semantic container so a screen reader reads it as a
/// single passage ("Latency. What it is: … How we measure it: …").
class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

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
            metric.name,
            style: text.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _LabeledBlock(label: 'What it is', body: metric.whatItIs),
          const SizedBox(height: AppSpacing.xs),
          _LabeledBlock(
            label: 'How we measure it',
            body: metric.howWeMeasure,
          ),
          if (metric.note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              metric.note!,
              style: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small caption-label over a body paragraph. The label is textTertiary so it
/// reads as a quiet rubric, not a heading.
class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// One metric's grade bands as four stacked label/value rows. Stacking (rather
/// than a 5-column table) keeps the threshold text from clipping at 320px
/// (§8.9). The band names are neutral category headings, not computed verdicts,
/// so they use neutral text tokens — never a §8.13 status hue (§8.13 rule 6).
class _GradeBandCard extends StatelessWidget {
  const _GradeBandCard({required this.band});

  final _GradeBand band;

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
            band.metric,
            style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _BandRow(grade: 'Excellent', threshold: band.excellent),
          _BandRow(grade: 'Good', threshold: band.good),
          _BandRow(grade: 'Fair', threshold: band.fair),
          _BandRow(grade: 'Poor', threshold: band.poor),
        ],
      ),
    );
  }
}

/// One grade -> threshold row. A single semantic node ("Excellent, under 20
/// ms"). The grade name and threshold reflow on a narrow column because the
/// threshold side is Flexible and wraps rather than overflowing.
class _BandRow extends StatelessWidget {
  const _BandRow({required this.grade, required this.threshold});

  final String grade;
  final String threshold;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$grade, $threshold',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Text(
                grade,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                threshold,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The standing honesty caveats, given a card of their own so they cannot be
/// missed. Same claims as the screen's inline honesty caption, expanded.
class _HonestyCard extends StatelessWidget {
  const _HonestyCard();

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Reassurance/information, not a computed verdict -> textSecondary
              // (§8.13 rule 6: status hues are verdict-only, never decorative).
              const Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'How to read these results',
                  style: text.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These are this app\'s own measurements, not an Orb or Ookla score. '
            'There is no single composite score on purpose; each dimension is '
            'graded on its own. Latency and loss use a timed connection on port '
            '443 rather than a raw ping, because sandboxed iPhone and Mac apps '
            'cannot send one. The Responsiveness grade is a simplified '
            'single-stream figure inspired by RFC 9097 and Apple\'s '
            'networkQuality tool, not the full multi-stream standard.',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---- Plain data holders for the static help content ----

class _Metric {
  const _Metric({
    required this.name,
    required this.whatItIs,
    required this.howWeMeasure,
    this.note,
  });

  final String name;
  final String whatItIs;
  final String howWeMeasure;
  final String? note;
}

class _GradeBand {
  const _GradeBand(
    this.metric,
    this.excellent,
    this.good,
    this.fair,
    this.poor,
  );

  final String metric;
  final String excellent;
  final String good;
  final String fair;
  final String poor;
}
