// Readouts and the predict-then-reveal card for the Wi-Fi Classroom Uplink vs
// Downlink tool.
//
// UplinkDownlinkReadouts: both directions at the client (level, MCS, SNR),
// the imbalance in dB, the asymmetry zone in meters, and what "turn AP down
// to match" changed when it is in effect. `compact` is the presenter-stage
// form: the numbers and the two sentences that matter, no footnotes.
//
// UplinkDownlinkPredict: "The client shows four bars. Can the AP hear it?"
// (spec 28), with the answer hidden until Reveal (or P in presenter mode).
//
// Both take the controller and know nothing about the stage or the controls.
// No status hues: a level or an MCS is a description, not a verdict
// (GL-003 §8.13 rule 6). ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/unit_system.dart';
import 'uplink_downlink_controller.dart';
import 'uplink_downlink_parts.dart';

/// One sentence on the imbalance, true at every distance.
String udImbalanceSentence(UdConfig c) {
  final double d = c.imbalanceDb;
  final String v = UdFormat.n(d.abs());
  if (d.abs() < 0.05) {
    return 'Both directions arrive at the same level: the AP and the client '
        'transmit the same power.';
  }
  return d > 0
      ? 'The downlink arrives $v dB stronger than the uplink at every '
            'distance, because the AP transmits $v dB more than the client. '
            'Each antenna\'s gain counts in both directions.'
      : 'The uplink arrives $v dB stronger than the downlink at every '
            'distance, because the client transmits $v dB more than the AP. '
            'Each antenna\'s gain counts in both directions.';
}

/// The presenter-stage form of [udZoneSentence].
String udZoneShort(UdConfig c, [UnitSystem u = UnitSystem.metric]) {
  if (c.zoneMiddleM == null) return 'The rings are the same size.';
  final bool down = c.downlinkRingM >= c.uplinkRingM;
  final double lo = down ? c.uplinkRingM : c.downlinkRingM;
  final double hi = down ? c.downlinkRingM : c.uplinkRingM;
  return 'From ${UdFormat.dist(lo, u)} to ${UdFormat.dist(hi, u)}: only '
      '${down ? 'the client' : 'the AP'} decodes.';
}

/// The presenter-stage form of udMatchSummary.
String udMatchShort(
  UdConfig before,
  UdConfig after, [
  UnitSystem u = UnitSystem.metric,
]) =>
    'AP turned down to ${UdFormat.n(after.apTxDbm)} dBm. Downlink ring '
    '${UdFormat.dist(before.downlinkRingM, u)} to '
    '${UdFormat.dist(after.downlinkRingM, u)}. Uplink unchanged.';

/// One sentence on the asymmetry zone.
String udZoneSentence(UdConfig c, [UnitSystem u = UnitSystem.metric]) {
  if (c.zoneMiddleM == null) {
    return 'No asymmetry zone: both rings are the same size.';
  }
  final bool down = c.downlinkRingM >= c.uplinkRingM;
  final double lo = down ? c.uplinkRingM : c.downlinkRingM;
  final double hi = down ? c.downlinkRingM : c.uplinkRingM;
  return 'Asymmetry zone: ${UdFormat.dist(c.asymmetryZoneM, u)} wide, from '
      '${UdFormat.dist(lo, u)} to ${UdFormat.dist(hi, u)}. There '
      '${down ? 'the client still decodes the AP, but the AP cannot decode the client' : 'the AP still decodes the client, but the client cannot decode the AP'}.';
}

class UplinkDownlinkReadouts extends StatelessWidget {
  const UplinkDownlinkReadouts({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final UplinkDownlinkController controller;

  /// The presenter-stage form: numbers and two sentences.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final UdConfig c = controller.config;
    final UdConfig? before = controller.beforeMatch;
    final UnitSystem u = controller.units;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return UdCard(
      child: Semantics(
        container: true,
        liveRegion: compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            UdSectionLabel('Client at ${UdFormat.dist(c.clientDistanceM, u)}'),
            Text(
              'Each way: level, MCS and signal-to-noise ratio (SNR)',
              style: small(),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _DirectionBlock(
                    dir: UdDir.downlink,
                    title: 'Downlink, AP to client',
                    reading: c.downlink,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DirectionBlock(
                    dir: UdDir.uplink,
                    title: 'Uplink, client to AP',
                    reading: c.uplink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _Figure(
              label: 'Imbalance',
              value: '${UdFormat.n(c.imbalanceDb.abs())} dB',
            ),
            Text(
              compact
                  ? 'AP transmit power minus client transmit power, the same '
                        'at every distance.'
                  : udImbalanceSentence(c),
              style: compact ? small() : body(),
            ),
            const SizedBox(height: AppSpacing.xs),
            _Figure(
              label: 'Asymmetry zone',
              value: c.zoneMiddleM == null
                  ? 'none'
                  : '${UdFormat.dist(c.asymmetryZoneM, u)} wide',
            ),
            Text(
              compact ? udZoneShort(c, u) : udZoneSentence(c, u),
              style: compact ? small() : body(),
            ),
            if (before != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              UdNote(
                Icons.compare_arrows,
                compact
                    ? udMatchShort(before, c, u)
                    : udMatchSummary(before, c, u),
              ),
            ],
            if (!compact) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'SNR is the level minus a '
                '${UdFormat.dbm(c.noiseFloorDbm)} noise floor at '
                '${c.widthMHz} MHz (the same 7 dB noise figure at both ends). '
                'Equivalent isotropically radiated power (EIRP): AP '
                '${UdFormat.dbm(c.apEirpDbm)}, client '
                '${UdFormat.dbm(c.clientEirpDbm)}.',
                style: small(),
              ),
              if (c.preset.isRegulated) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                const UdNote(
                  Icons.info_outline,
                  'Under this rule the client is set to the most it may '
                  'transmit. The rule is a ceiling: many clients transmit '
                  'less, which widens the gap.',
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              const UdNote(
                Icons.info_outline,
                'Both ends use the same receiver floors (the conformance '
                'minimums for each MCS). Real radios do better than the '
                'floors, and many APs gain more on receive from extra '
                'antennas and receive chains, which this model leaves out.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          '$label  ',
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
        Text(
          value,
          style: mono.outputMedium.copyWith(color: colors.textAccent),
        ),
      ],
    );
  }
}

class _DirectionBlock extends StatelessWidget {
  const _DirectionBlock({
    required this.dir,
    required this.title,
    required this.reading,
  });

  final UdDir dir;
  final String title;
  final UdDirection reading;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            UdLineSwatch(dir: dir),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                title,
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            UdFormat.dbm(reading.rssiDbm),
            style: scale
                .headlineStyle(mono.outputLarge)
                .copyWith(color: colors.textPrimary),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            reading.mcs == null ? 'Below MCS 0' : 'MCS ${reading.mcs}',
            style: mono.outputMedium.copyWith(color: colors.textAccent),
          ),
        ),
        Text(
          'SNR ${UdFormat.n(reading.snrDb)} dB',
          style: mono.inlineCode.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ── Predict, then reveal ──────────────────────────────────────────────────

class UplinkDownlinkPredict extends StatelessWidget {
  const UplinkDownlinkPredict({super.key, required this.controller});
  final UplinkDownlinkController controller;

  static const String question =
      'The client shows four bars. Can the AP hear it?';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final UdConfig c = controller.config;
    final bool presenter = PresenterMode.isActive(context);
    final bool open = controller.revealed;
    final UdDirection ul = c.uplink;
    final bool zone = c.zoneMiddleM != null;
    final bool downBigger = c.downlinkRingM >= c.uplinkRingM;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);

    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const UdSectionLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            question,
            style: text.titleMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: controller.toggleReveal,
              icon: Icon(open ? Icons.visibility_off : Icons.visibility),
              label: Text(
                '${open ? 'Hide the answer' : 'Reveal the answer'}'
                '${presenter ? ' (P)' : ''}',
              ),
            ),
          ),
          if (open) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: true,
              child: Text(
                presenter
                    ? 'Not necessarily. Bars come from the downlink only.'
                    : 'Not necessarily. The bars come from what the client '
                          'hears, the downlink. Nothing in them measures the '
                          'uplink, what the AP hears from the client, and how '
                          'many bars a level earns differs from device to '
                          'device.',
                style: body(),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Here the AP hears the client at ${UdFormat.dbm(ul.rssiDbm)}: '
              '${ul.mcs == null ? 'below MCS 0, so it cannot decode it.' : 'MCS ${ul.mcs}, so it can.'}',
              style: body(),
            ),
            if (zone && downBigger && !presenter) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'In the shaded zone the client still decodes the AP while the '
                'AP cannot decode the client.',
                style: body(),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: zone ? controller.moveClientIntoZone : null,
                icon: const Icon(Icons.place_outlined),
                label: Text(
                  zone
                      ? 'Put the client in the zone'
                      : 'No zone at these settings',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
