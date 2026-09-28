// The stage of the guest-discovery walk-through: the phone's question, every
// device on its path, where it stops, and what the phone's list shows.
// Controls live in guest_discovery_controls.dart so this widget only draws.
//
// States (SOP-007 §5): all three steps of all three modes render here; the
// model is compiled in, so there is no loading, empty or error state. The
// empty result ("Nothing found") is a teaching state, drawn in words. Each hop
// carries its outcome as words and an icon, never color alone (GL-003 §8.13).
//
// THEME: `context.colors` only.
//
// ACCESSIBILITY: the step heading is a live region; each hop is one merged
// semantics node ("The TV, Main network: Never heard it").

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/guest_discovery_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

class GuestDiscoveryStage extends StatelessWidget {
  const GuestDiscoveryStage({
    super.key,
    required this.scenario,
    required this.stage,
  });

  final DiscoveryScenario scenario;
  final DiscoveryStage stage;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final int n = DiscoveryStage.values.length;
    final List<DiscoveryHop> hops = scenario.hops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(
            'Step ${stage.index + 1} of $n: ${kStageTitles[stage]}',
            style: (t.titleSmall ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _Query(),
        const SizedBox(height: AppSpacing.sm),
        for (int i = 0; i < hops.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xxs),
          _HopRow(hop: hops[i], stage: stage),
          if (stage != DiscoveryStage.ask &&
              hops[i].outcome == HopOutcome.stopped)
            const _StopMarker(),
        ],
        if (stage == DiscoveryStage.result) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _Result(scenario: scenario),
        ],
        if (stage != DiscoveryStage.ask) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            scenario.why,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _Query extends StatelessWidget {
  const _Query();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(
                Icons.record_voice_over_outlined,
                size: 20,
                color: colors.textAccent,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'The phone asks',
                    style: t.labelMedium?.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xxs / 2),
                  Text(
                    kQueryPlain,
                    style: t.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    kQueryAddressed,
                    style: t.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
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

IconData _iconFor(String label) => switch (label) {
  'This phone' => Icons.smartphone_outlined,
  'Access point' => Icons.wifi,
  'Router' => Icons.router_outlined,
  'The TV' => Icons.tv_outlined,
  'The printer' => Icons.print_outlined,
  _ => Icons.devices_other_outlined,
};

/// The words for a hop's outcome at [stage]. Before the question travels,
/// everyone but the phone is waiting.
String outcomeWords(HopOutcome o, DiscoveryStage stage) {
  if (stage == DiscoveryStage.ask) {
    return o == HopOutcome.sender ? 'Asks' : 'Waiting';
  }
  return switch (o) {
    HopOutcome.sender => 'Asked',
    HopOutcome.passed => 'Passed it on',
    HopOutcome.stopped => 'Stops it here',
    HopOutcome.heard =>
      stage == DiscoveryStage.result ? 'Heard it and answered' : 'Heard it',
    HopOutcome.missed => 'Never heard it',
  };
}

class _HopRow extends StatelessWidget {
  const _HopRow({required this.hop, required this.stage});

  final DiscoveryHop hop;
  final DiscoveryStage stage;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool asked = stage != DiscoveryStage.ask;
    final (IconData mark, Color tone) = !asked
        ? (Icons.more_horiz, colors.textTertiary)
        : switch (hop.outcome) {
            HopOutcome.sender => (Icons.campaign_outlined, colors.textAccent),
            HopOutcome.passed => (Icons.arrow_downward, colors.textAccent),
            HopOutcome.stopped => (Icons.block, colors.statusWarning),
            HopOutcome.heard => (
              Icons.check_circle_outline,
              colors.statusSuccess,
            ),
            HopOutcome.missed => (
              Icons.remove_circle_outline,
              colors.textTertiary,
            ),
          };
    final String words = outcomeWords(hop.outcome, stage);
    return Semantics(
      container: true,
      label: '${hop.label}, ${hop.segment}: $words',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: asked && hop.outcome == HopOutcome.stopped
                ? colors.statusWarning
                : colors.borderStrong,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(_iconFor(hop.label), size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hop.label,
                    style: t.labelLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    hop.segment,
                    style: t.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(mark, size: 18, color: tone),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                words,
                textAlign: TextAlign.end,
                style: t.labelMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopMarker extends StatelessWidget {
  const _StopMarker();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          Expanded(child: Divider(color: colors.statusWarning, thickness: 2)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'The question stops here',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Divider(color: colors.statusWarning, thickness: 2)),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.scenario});

  final DiscoveryScenario scenario;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final List<String> found = scenario.found;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            "The phone's list",
            style: t.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (found.isEmpty)
            Text(
              'Nothing found',
              style: t.titleSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            for (final String f in found)
              Row(
                children: <Widget>[
                  ExcludeSemantics(
                    child: Icon(
                      _iconFor(f),
                      size: 18,
                      color: colors.textAccent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    f,
                    style: t.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            scenario.internetWorks
                ? 'The internet works on this phone either way.'
                : '',
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
