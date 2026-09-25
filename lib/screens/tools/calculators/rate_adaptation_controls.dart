// Controls, readouts and explainer for the Wi-Fi Lab Rate Adaptation tool.
//
// RateAdaptationControls: transport (Play, Step one frame, Restart, speed)
// and the settings (path, SNR offset, sampling share, EWMA weight, retry
// chain, retry limit, ACK timeout). RateAdaptationReadouts: delivered
// throughput, retries per frame, airtime on retries, the best rate and its
// estimate. RateAdaptationExplainer: the four lessons and the formulas.
// Each takes a RateAdaptationController and none knows about the stage.
//
// THEME: context.colors (dark §8 / light §8.20). No status hues here: a rate
// is a description, not a verdict (§8.13). ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/rate_adaptation_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'rate_adaptation_controller.dart';
import 'rate_adaptation_parts.dart';

// ── Controls ────────────────────────────────────────────────────────────────

class RateAdaptationControls extends StatelessWidget {
  const RateAdaptationControls({super.key, required this.controller});
  final RateAdaptationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Transport(c: controller),
          const SizedBox(height: AppSpacing.sm),
          _Settings(c: controller),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.c});
  final RateAdaptationController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            label: c.playing ? 'Pause the link' : 'Play the link',
            excludeSemantics: true,
            child: FilledButton.icon(
              onPressed: c.togglePlay,
              icon: Icon(
                c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(c.playing ? 'Pause' : 'Play'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                textStyle: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: RaOutlineButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Step',
                  semanticLabel: 'Step one frame, with all its retries',
                  onPressed: c.stepFrame,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: RaOutlineButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'Restart',
                  semanticLabel:
                      'Restart: a fresh link that has learned nothing yet',
                  onPressed: c.atStart ? null : c.restart,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Speed (air time per second)',
            semanticLabel: 'Speed',
            field: AppSelect<RaSpeed>(
              value: c.speed,
              semanticLabel: 'Speed',
              items: <AppSelectItem<RaSpeed>>[
                for (final RaSpeed s in RaSpeed.values) (s, s.label),
              ],
              onChanged: (RaSpeed s) => c.speed = s,
            ),
          ),
          if (reducedMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const RaNote(
              'Reduced motion is on. Nothing moves until you press Play or '
              'Step.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.c});
  final RateAdaptationController c;

  @override
  Widget build(BuildContext context) {
    final RaSettings s = c.settings;
    final String Function(double, [int]) n = RaFormat.n;
    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<RaPath>(
            label: 'Path',
            value: s.path,
            expand: true,
            items: <AppToggleItem<RaPath>>[
              (RaPath.walk, 'Walk'),
              (RaPath.steady, 'Steady'),
              (RaPath.fading, 'Fading'),
            ],
            onChanged: (RaPath p) => c.path = p,
          ),
          const SizedBox(height: AppSpacing.xxs),
          RaNote(switch (s.path) {
            RaPath.walk =>
              'The client walks from 2 m to 60 m and back every 20 s.',
            RaPath.steady => 'The client stays 4 m from the AP.',
            RaPath.fading =>
              'The client stays 12 m away while the signal swells and fades '
                  'by up to about 8 dB (illustrative).',
          }),
          RaSlider(
            label: 'SNR offset',
            valueText:
                '${s.snrOffsetDb > 0 ? '+' : ''}${n(s.snrOffsetDb, 0)} dB',
            value: s.snrOffsetDb,
            min: -20,
            max: 20,
            divisions: 40,
            onChanged: (double v) => c.snrOffsetDb = v.roundToDouble(),
            semanticValue: (double v) => '${v.round()} dB',
          ),
          RaSlider(
            label: 'Sampling share',
            valueText: RaFormat.pct(s.samplingShare),
            value: s.samplingShare * 100,
            min: 0,
            max: 30,
            divisions: 30,
            onChanged: (double v) => c.samplingShare = v.round() / 100,
            semanticValue: (double v) => '${v.round()} percent of frames',
          ),
          RaSlider(
            label: 'EWMA weight on history',
            valueText: RaFormat.pct(s.ewmaHistory),
            value: s.ewmaHistory * 100,
            min: 50,
            max: 95,
            divisions: 9,
            onChanged: (double v) => c.ewmaHistory = v.round() / 100,
            semanticValue: (double v) => '${v.round()} percent',
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<bool>(
            label: 'Retry chain',
            value: s.retryChain,
            expand: true,
            items: const <AppToggleItem<bool>>[
              (true, 'On'),
              (false, 'Off, same rate'),
            ],
            onChanged: (bool v) => c.retryChain = v,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<RaRetryLimit>(
            label: 'Retry limit (attempts)',
            value: s.retryLimit,
            expand: true,
            items: <AppToggleItem<RaRetryLimit>>[
              for (final RaRetryLimit l in RaRetryLimit.values) (l, l.label),
            ],
            onChanged: (RaRetryLimit l) => c.retryLimit = l,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<double>(
            label: 'ACK timeout',
            value: s.ackTimeoutUs,
            expand: true,
            items: const <AppToggleItem<double>>[
              (RateAdaptationMath.ackTimeoutMinUs, '45 µs'),
              (RateAdaptationMath.ackTimeoutMaxUs, '50 µs'),
            ],
            onChanged: (double v) => c.ackTimeoutUs = v,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const RaNote(
            'ACK timeout = SIFS + slot + about 20 to 25 µs, so 45 to 50 µs at '
            '5 GHz. The sources do not settle one constant, so pick either '
            'end. Settings apply to the running link; Restart starts a link '
            'that has learned nothing.',
          ),
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class RateAdaptationReadouts extends StatelessWidget {
  const RateAdaptationReadouts({super.key, required this.controller});
  final RateAdaptationController controller;

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
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RateAdaptationEngine e = controller.engine;
    final RaWindowStats w = e.window;
    final int best = e.ranking.bestThroughput;
    final double est = e.stats[best].throughputEstimateMbps;
    final double snr = e.snrNowDb;
    final int? sup = RateAdaptationMath.supportedMcs(snr);
    final bool fresh = e.nowUs == 0;

    Widget value(String label, String v, {bool strong = false}) => Semantics(
      label: '$label: $v',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          // One line each, so a changing value never reflows the card and
          // moves the controls below it.
          Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono.inlineCode.copyWith(
              color: strong ? colors.textAccent : colors.textPrimary,
              fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );

    Widget pair(Widget a, Widget b) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: a),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: b),
        ],
      ),
    );

    final String where = '${RaFormat.n(e.distanceNowM)} m from the AP';

    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RaSectionLabel(
            fresh
                ? 'Readouts (press Play or Step)'
                : 'At ${RaFormat.clock(e.nowUs)}, $where',
          ),
          const SizedBox(height: AppSpacing.xs),
          value('Best rate', RaFormat.rate(best), strong: true),
          pair(
            value(
              'Its estimate',
              est == 0 ? 'no data yet' : RaFormat.mbps(est),
              strong: true,
            ),
            value(
              'Delivered, last second',
              fresh ? '-' : RaFormat.mbps(w.deliveredMbps),
            ),
          ),
          pair(
            value(
              'Retries per frame',
              fresh ? '-' : RaFormat.n(w.retriesPerFrame, 2),
            ),
            value(
              'Airtime on retries',
              fresh ? '-' : RaFormat.pct(w.retryAirtimeShare),
            ),
          ),
          pair(
            value('Dropped, last second', fresh ? '-' : '${w.dropped}'),
            value('SNR now', '${RaFormat.n(snr)} dB'),
          ),
          pair(
            value('SNR supports', sup == null ? 'no MCS' : RaFormat.mcs(sup)),
            const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.xs),
          const RaNote(
            'Delivered throughput is far below the PHY rate because every '
            '1500-byte frame waits, sends a preamble and waits for its ACK '
            'on its own (no aggregation here).',
          ),
        ],
      ),
    );
  }
}

// ── Explainer ───────────────────────────────────────────────────────────────

class RateAdaptationExplainer extends StatelessWidget {
  const RateAdaptationExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle formula() =>
        mono.inlineCode.copyWith(color: colors.textSecondary);
    return RaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RaSectionLabel('What to watch for'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '1. The radio does not know the best rate. It learns it by trying '
            'rates and keeping statistics. Restart and watch the table fill '
            'in.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '2. Every 50 ms each rate\'s success folds into a running average '
            '(75% old, 25% new). About 1 frame in 10 is a sample at another '
            'rate. Each frame carries a retry chain: best throughput, second '
            'best, best probability, lowest rate.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '3. A retry costs more airtime than the first try. The contention '
            'window doubles (mean backoff 67.5, then 139.5, then 283.5 µs), '
            'and a retry at a lower rate takes longer to send.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '4. As the client walks away the chosen rate steps down. As it '
            'comes back, sampling finds the higher rates again. Set sampling '
            'to 0% and Restart: the link never climbs.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('EWMA = 0.75 x old + 0.25 x this interval', style: formula()),
          Text(
            'Estimate = min(P, 90%) x 12000 bits / one attempt',
            style: formula(),
          ),
          Text(
            'Attempt = AIFS + CW/2 x 9 µs + TXTIME + (SIFS + ACK or timeout)',
            style: formula(),
          ),
          Text('CW = 15, 31, 63 ... up to 1023', style: formula()),
          const SizedBox(height: AppSpacing.xs),
          const RaNote(
            'Link: 5 GHz, 802.11ax, 20 MHz, one stream, 0.8 µs guard '
            'interval, 1500-byte frames, best effort, ACK at 24 Mbps. SNR '
            'each MCS needs = its minimum sensitivity minus a -94 dBm noise '
            'floor, as in Rate vs Range. Rate control follows the published '
            'outline of Minstrel, the Linux rate-control algorithm. Attempts '
            'are split over the chain as evenly as they go (7 = 2, 2, 2, 1), '
            'backoff is the mean, and there is one station, so no '
            'collisions.',
          ),
        ],
      ),
    );
  }
}
