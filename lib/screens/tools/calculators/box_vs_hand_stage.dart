// BoxVsHandStage: the picture half of the Wi-Fi Classroom tool The Number on
// the Box vs the Number in Your Hand (box-vs-hand).
//
// Three bars on one scale, the box number (18,656 Mbps) at full length:
//   1. On the box: every radio added, split by band. The 6 GHz radio, the
//      one link a client's best case uses, takes the accent; the other two
//      are neutral.
//   2. Best case for this client: one link, its own streams. It starts at
//      the box length and shrinks.
//   3. At a stated distance and width: the estimate. It starts at the best
//      case and shrinks again.
// The step buttons (and Left, Right, Space in presenter mode) walk the steps;
// a bar not yet shown keeps its place so nothing jumps.
//
// It takes a BoxVsHandController and knows nothing about the controls.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'box_vs_hand_controller.dart';
import 'box_vs_hand_parts.dart';

/// Row titles, shared with the tests.
abstract final class BvhLabels {
  static String boxRow() => 'On the box: a ${BoxVsHand.className}-class router';
  static String bestRow(BvhClient c) => 'Best case: ${c.label.toLowerCase()}';
  static const String nextStep = 'Show the next step';
  static const String previous = 'Back a step';
  static const String sameCeiling =
      'A 2x2 laptop and a 2x2 phone reach the same ceiling, because the '
      'number of streams sets it.';
}

class BoxVsHandStage extends StatelessWidget {
  const BoxVsHandStage({super.key, required this.controller});
  final BoxVsHandController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final bool presenter = PresenterMode.isActive(context);
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _rows(context),
    );
    if (!presenter) return BvhCard(child: body);
    // Presenter: the card fills the stage; the content shrinks as one piece
    // rather than clip in a short window.
    return BvhCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(width: box.maxWidth, child: body),
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final BoxVsHandController k = controller;
    final double box = k.boxMbps;
    final double best = k.bestCaseMbps;
    final BvhReading r = k.reading;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return <Widget>[
      Text(
        'Every bar is on the same scale: full length is the number on the '
        'box. Mbps is megabits per second.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.sm),
      _row(
        context,
        index: 0,
        title: BvhLabels.boxRow(),
        value: BvhFormat.mbps(box),
        bar: BvhBar(
          segments: <BvhSegment>[
            for (final BvhRadio x in BoxVsHand.radios)
              BvhSegment(
                share: x.datasheetMbps / box,
                usable: identical(x, BoxVsHand.bestRadio),
              ),
          ],
        ),
        detail:
            '${BoxVsHand.radios.map((BvhRadio x) => '${x.band.label} ${BvhFormat.grouped(x.datasheetMbps.round())}').join(' + ')}. '
            'Every radio added, each at ${BoxVsHand.bestRadio.streams} '
            'streams, its widest channel and its top MCS (modulation and '
            'coding scheme). The class name rounds the sum up.',
      ),
      const SizedBox(height: AppSpacing.md),
      _row(
        context,
        index: 1,
        title: BvhLabels.bestRow(k.client),
        value: BvhFormat.mbps(best),
        share: '${BvhFormat.pct(best, box)} of the box',
        bar: BvhBar(
          segments: <BvhSegment>[BvhSegment(share: best / box, usable: true)],
          fromShare: 1,
        ),
        detail:
            'One link, not three: the 6 GHz radio at '
            '${BoxVsHand.bestRadio.widthMHz} MHz, ${k.client.streams} '
            'streams, MCS ${BoxVsHand.topMcs} (4096-QAM, quadrature amplitude '
            'modulation). Assumes the client supports '
            '${BoxVsHand.bestRadio.widthMHz} MHz and 4096-QAM.'
            '${k.client.streams == 2 ? ' ${BvhLabels.sameCeiling}' : ''}',
      ),
      const SizedBox(height: AppSpacing.md),
      _row(
        context,
        index: 2,
        title: k.distanceHeading,
        value: r.mcs == null ? 'No link' : BvhFormat.mbps(r.estimateMbps),
        share: r.mcs == null
            ? null
            : '${BvhFormat.pct(r.estimateMbps, box)} of the box',
        bar: BvhBar(
          segments: <BvhSegment>[
            BvhSegment(share: r.estimateMbps / box, usable: true),
          ],
          fromShare: best / box,
        ),
        detail: r.mcs == null
            ? 'Received ${BvhFormat.dbm(r.receivedDbm)}: below MCS 0 on a '
                  '${r.widthMHz} MHz channel, so there is no link here. Move '
                  'closer or choose a narrower channel.'
            : 'Received ${BvhFormat.dbm(r.receivedDbm)}, MCS ${r.mcs}. PHY '
                  '(physical layer) rate ${BvhFormat.mbps(r.phyMbps)} x '
                  '${BoxVsHand.efficiency.toStringAsFixed(2)}, the Throughput '
                  'Calculator factor, a favorable estimate. Assumes the '
                  'client keeps '
                  '${k.client.streams == 2 ? 'both' : 'all ${k.client.streams}'} '
                  'streams at this distance.',
      ),
      const SizedBox(height: AppSpacing.sm),
      _legend(context),
      const SizedBox(height: AppSpacing.xs),
      _stepper(context),
    ];
  }

  Widget _row(
    BuildContext context, {
    required int index,
    required String title,
    required String value,
    String? share,
    required Widget bar,
    required String detail,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool shown = controller.step.index >= index;
    final String stepWord = 'Step ${index + 1} of ${BvhStep.values.length}';

    if (!shown) {
      return Semantics(
        label: '$stepWord, not shown yet',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '$stepWord: ${BvhStep.values[index].label.toLowerCase()}',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            const BvhBar(segments: <BvhSegment>[]),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Press ${BvhLabels.nextStep} to see it.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      );
    }

    return Semantics(
      liveRegion: index == controller.step.index,
      label:
          '$stepWord. $title: $value${share == null ? '' : ', $share'}. $detail',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Title and number side by side when they fit, the number on its
          // own line when they do not (a phone, or the desktop's left column).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpacing.xs,
            children: <Widget>[
              Text(
                title,
                style: text.titleSmall?.copyWith(color: colors.textPrimary),
              ),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: value,
                      style: mono.outputMedium.copyWith(
                        color: colors.textAccent,
                      ),
                    ),
                    if (share != null)
                      TextSpan(
                        text: '  $share',
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          // A bar that just appeared animates from the bar above it.
          KeyedSubtree(key: ValueKey<String>('bvh-bar-$index'), child: bar),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            detail,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? t = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BvhSwatch(usable: true),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'The one link a client uses (${WifiBand.band6.label})',
              style: t,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BvhSwatch(usable: false),
            const SizedBox(width: AppSpacing.xxs),
            Text('Radios it does not use', style: t),
          ],
        ),
      ],
    );
  }

  Widget _stepper(BuildContext context) {
    final bool presenter = PresenterMode.isActive(context);
    final BoxVsHandController k = controller;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        FilledButton.icon(
          onPressed: k.canAdvance ? k.nextStep : null,
          icon: const Icon(Icons.arrow_forward),
          label: Text('${BvhLabels.nextStep}${presenter ? ' (Right)' : ''}'),
        ),
        TextButton.icon(
          onPressed: k.canGoBack ? k.previousStep : null,
          icon: const Icon(Icons.arrow_back),
          label: Text('${BvhLabels.previous}${presenter ? ' (Left)' : ''}'),
        ),
      ],
    );
  }
}
