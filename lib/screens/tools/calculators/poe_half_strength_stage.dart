// PoeHalfStrengthStage: the picture half of the Wi-Fi Classroom tool "PoE:
// Why the New AP Runs at Half Strength" (poe-half-strength).
//
// The drawing (PhStagePainter), its caption, and in presenter mode the
// readouts and the prediction beside it. It takes the controller and knows
// nothing about the controls.
//
// PoeHalfStrengthReadouts: streams live of 12, radios live of 3, the power
// that reaches the AP against what it needs, and the power light (on in
// every case). PoeHalfStrengthPredict: the new AP on last year's 802.3at
// switch.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'poe_half_strength_controller.dart';
import 'poe_half_strength_painter.dart';
import 'poe_half_strength_parts.dart';

/// The whole drawing in words, for a screen reader.
String phStageSemantics(PhConfig c) {
  final String radios = <String>[
    for (final PhRadio r in PhRadio.values) '${r.label} ${c.radioState(r)}',
  ].join(', ');
  return 'A switch with an ${c.port.standard} port sends '
      '${PhFormat.watts(c.port.pseWatts)}; ${PhFormat.watts(c.port.pdWatts)} '
      'reaches the AP, which needs about ${PhAp.fullFunctionWatts.round()} W '
      'for full function. The power light is on. Radios: $radios. '
      '${c.streamsLive} of ${PhAp.maxStreams} streams live.';
}

class PoeHalfStrengthStage extends StatelessWidget {
  const PoeHalfStrengthStage({
    super.key,
    required this.controller,
    required this.stageHeight,
  });

  final PoeHalfStrengthController controller;

  /// Height of the drawing. Ignored in presenter mode, where it fills.
  final double stageHeight;

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
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final bool presenter = PresenterMode.isActive(context);
    final PhConfig c = controller.config;

    final Widget drawing = Semantics(
      label: phStageSemantics(c),
      liveRegion: presenter,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: CustomPaint(
            size: Size.infinite,
            painter: PhStagePainter(
              config: c,
              scale: scale,
              palette: PhPalette(
                ink: colors.textPrimary,
                muted: colors.textSecondary,
                faint: colors.textTertiary,
                fill: colors.primary,
                surface: colors.surface1,
                boxBorder: colors.borderStrong,
                track: colors.disabledFill,
                fontFamily: text.bodySmall?.fontFamily,
              ),
            ),
          ),
        ),
      ),
    );

    final Widget card = PhCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${PhLabels.genericAp}, on an ${c.port.label} switch port. A '
            'filled mark is a live spatial stream; a dashed mark is a stream '
            'the AP has turned off.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: drawing)
          else
            SizedBox(height: stageHeight, child: drawing),
          if (c.illustrative) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const PhNote(Icons.info_outline, PhLabels.afIllustrative),
          ],
        ],
      ),
    );
    if (!presenter) return card;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.38).clamp(320.0, 480.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: card),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: side,
              // Shrinks as one piece rather than clip in a short window.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: side,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      PoeHalfStrengthReadouts(
                        controller: controller,
                        compact: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      PoeHalfStrengthPredict(controller: controller),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Readouts ─────────────────────────────────────────────────────────────

/// One sentence on the state, from the model.
String phSummary(PhConfig c) {
  if (c.fullFunction) {
    return '${PhFormat.watts(c.port.pdWatts)} reaches the AP, more than the '
        'about ${PhAp.fullFunctionWatts.round()} W it needs: every radio '
        'runs at full strength.';
  }
  if (c.port == PhPort.at) {
    return '${PhFormat.watts(c.port.pdWatts)} reaches the AP, '
        '${PhFormat.watts(c.shortfallWatts)} short of what it needs, so it '
        'runs ${c.atMode.phrase}: ${c.streamsLive} of ${PhAp.maxStreams} '
        'streams. The power light does not tell you.';
  }
  return '${PhFormat.watts(c.port.pdWatts)} reaches the AP, less than half '
      'of what it needs. In this illustrative example it still boots with '
      'less: ${c.streamsLive} of ${PhAp.maxStreams} streams, one band off, '
      'lower transmit power, and the USB port and second Ethernet port off. '
      'The power light is on.';
}

class PoeHalfStrengthReadouts extends StatelessWidget {
  const PoeHalfStrengthReadouts({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final PoeHalfStrengthController controller;

  /// The presenter-stage form: no footnotes.
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
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final PhConfig c = controller.config;

    return PhCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PhSectionLabel('On an ${c.port.label} port'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${c.streamsLive} of ${PhAp.maxStreams}',
              style: scale
                  .headlineStyle(mono.outputLarge)
                  .copyWith(color: colors.textPrimary),
            ),
            Text(
              'spatial streams live (${PhFormat.percent(c.streamShare)})',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            PhFigure(
              label: 'Radios live',
              value: '${c.radiosLive} of ${PhRadio.values.length}',
            ),
            PhFigure(
              label:
                  'Power at the AP (needs about '
                  '${PhAp.fullFunctionWatts.round()} W)',
              value: PhFormat.watts(c.port.pdWatts),
            ),
            PhFigure(label: 'Power light', value: 'On'),
            if (c.otherReductions.isNotEmpty)
              PhFigure(
                label: 'Also cut (illustrative)',
                value: c.otherReductions.join(', '),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              phSummary(c),
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              const PhNote(
                Icons.info_outline,
                'A 2x2 client uses at most two streams, so one phone alone '
                'may notice little. The AP loses the streams it could share '
                'among many clients at once and, with a radio off, a whole '
                'band.',
              ),
              const SizedBox(height: AppSpacing.xxs),
              const PhNote(Icons.info_outline, PhLabels.vendorsDiffer),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Predict, then reveal ─────────────────────────────────────────────────

class PoeHalfStrengthPredict extends StatelessWidget {
  const PoeHalfStrengthPredict({super.key, required this.controller});
  final PoeHalfStrengthController controller;

  static const String question =
      'The new Wi-Fi 7 AP goes on last year\'s 802.3at switch. Its power '
      'light comes on. Is it running at full strength?';

  static String answer(PhAtMode m) {
    final PhConfig at = PhConfig(atMode: m);
    return 'No. An 802.3at port guarantees ${PhFormat.watts(PhPort.at.pdWatts)} '
        'at the AP, short of the about ${PhAp.fullFunctionWatts.round()} W '
        'this AP needs, so it runs ${m.phrase}: ${at.streamsLive} of '
        '${PhAp.maxStreams} streams. The power light is on either way. Check '
        'the AP\'s own power status, or give it an 802.3bt port.';
  }

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
    final bool presenter = PresenterMode.isActive(context);
    final bool open = controller.revealed;

    return PhCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PhSectionLabel('Predict, then reveal'),
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
                answer(controller.config.atMode),
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => controller.setPort(PhPort.at),
                icon: const Icon(Icons.power_outlined),
                label: const Text('Show it on 802.3at'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
