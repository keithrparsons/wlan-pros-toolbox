// AdjacentChannelStage: the picture half of the Wi-Fi Classroom Adjacent
// Channels and AP Stacking tool.
//
// The spectrum strip (your channel, the wanted signal, the neighbor's mask
// skirt reaching into your 20 MHz, shaded), its legend, the floor line with
// the three radios, and the neighbor-distance slider, which is the lesson's
// main control and so lives with the picture. It takes an
// AdjacentChannelController and knows nothing about the controls, so a screen
// can place it above them (phone), beside them (desktop) or full screen (the
// presenter layout).
//
// PRESENTER: the strip and floor fill the stage's height, and the verdicts
// stand beside them in headline type: highest MCS without and with the
// neighbor, SINR, leakage, and energy detect.
//
// THEME: context.colors (dark §8 / light §8.20) plus AciPalette (§8.15.2).
// Status hues only on the two computed verdicts, always with their words.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/adjacent_channel_model.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'adjacent_channel_controller.dart';
import 'adjacent_channel_painters.dart';
import 'adjacent_channel_parts.dart';
import 'rate_vs_range_parts.dart';

class AdjacentChannelStage extends StatelessWidget {
  const AdjacentChannelStage({super.key, required this.controller});

  final AdjacentChannelController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final bool presenter = PresenterMode.isActive(context);
    final AciResult r = controller.result;
    final AciPaintStyle style = _style(context);

    final Widget spectrum = Semantics(
      label: _spectrumSemantics(r),
      excludeSemantics: true,
      child: _surface(
        context,
        CustomPaint(
          painter: AciSpectrumPainter(
            result: r,
            neighborName: 'Neighbor',
            receiverName: r.config.listener.receiverName,
            style: style,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final Widget floor = Semantics(
      label: _floorSemantics(r),
      excludeSemantics: true,
      child: _surface(
        context,
        CustomPaint(
          painter: AciFloorPainter(
            result: r,
            receiverName: r.config.listener.receiverName,
            wantedName: r.config.listener.wantedName,
            style: style,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );

    final Widget card = RvrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RvrSectionLabel(
            'Power at the receiver, across frequency (dBm per MHz)',
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(flex: 3, child: spectrum)
          else
            SizedBox(height: 280, child: spectrum),
          const SizedBox(height: AppSpacing.xxs),
          _legend(context, r),
          const SizedBox(height: AppSpacing.xs),
          if (presenter)
            Expanded(flex: 1, child: floor)
          else
            SizedBox(height: 130, child: floor),
          _distanceSlider(context),
        ],
      ),
    );
    if (!presenter) return card;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.32).clamp(280.0, 440.0);
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
                  child: AciHeadline(controller: controller),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    final AppColorScheme colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: ColoredBox(color: colors.surface2, child: child),
    );
  }

  AciPaintStyle _style(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    final Color neighbor = AciPalette.neighbor(colors);
    final Color yours = AciPalette.yours(colors);
    return AciPaintStyle(
      scale: scale,
      surface: colors.surface2,
      grid: colors.textTertiary,
      axis: colors.textPrimary,
      neighbor: neighbor,
      yours: yours,
      noise: colors.textTertiary,
      threshold: colors.textPrimary,
      label: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textSecondary,
        ),
      ),
      strongLabel: up(
        text.labelSmall!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      neighborLabel: up(
        text.labelSmall!.copyWith(color: neighbor, fontWeight: FontWeight.w600),
      ),
      yoursLabel: up(
        text.labelSmall!.copyWith(color: yours, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _legend(BuildContext context, AciResult r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double k = PresenterMode.scaleOf(context).marker;
    final TextStyle small =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    Widget swatch(Color c, {double alpha = 1}) => Container(
      width: 14 * k,
      height: 10 * k,
      decoration: BoxDecoration(
        color: c.withValues(alpha: alpha),
        border: Border.all(color: c),
      ),
    );
    Widget item(Widget sw, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        sw,
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: small)),
      ],
    );
    final AciChannelPlan p = r.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: <Widget>[
            item(
              swatch(AciPalette.yours(colors)),
              'Yours, ${p.receiverLabel}, 20 MHz',
            ),
            item(
              swatch(AciPalette.neighbor(colors)),
              'Neighbor, ${p.neighborLabel}, ${p.neighborWidthMHz} MHz',
            ),
            item(
              swatch(AciPalette.neighbor(colors), alpha: 0.35),
              'Neighbor energy inside your 20 MHz',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Dashed across your channel: the clear channel assessment (CCA) '
          'energy-detect threshold. The solid bar is the interference: the '
          'leakage plus what of the neighbor\'s own channel gets past your '
          'receiver\'s filter. Both are spread over your 20 MHz, so they '
          'compare directly. Moving a radio '
          'changes heights only; channel centers never move.',
          style: small,
        ),
      ],
    );
  }

  Widget _distanceSlider(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double lo = FsplMath.log10(AciLimits.neighborDistanceMin);
    final double hi = FsplMath.log10(AciLimits.neighborDistanceMax);
    final double d = controller.config.neighborDistanceM;
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'Neighbor distance',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: FsplMath.log10(d).clamp(lo, hi),
            min: lo,
            max: hi,
            divisions: 200,
            onChanged: (double v) =>
                controller.neighborDistanceM = math.pow(10, v).toDouble(),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: AciFormat.dist(d),
            semanticFormatterCallback: (double v) =>
                'Neighbor distance '
                '${AciFormat.dist(math.pow(10, v).toDouble())}',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 64 * PresenterMode.scaleOf(context).text,
            child: Text(
              AciFormat.dist(d),
              textAlign: TextAlign.right,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }

  String _spectrumSemantics(AciResult r) {
    final AciChannelPlan p = r.plan;
    return 'Spectrum at the receiver. Neighbor on ${p.neighborLabel}, '
        '${p.neighborWidthMHz} MHz wide, received at '
        '${AciFormat.dbm(r.neighborDbm)} in its own channel. Your channel '
        '${p.receiverLabel}, wanted signal ${AciFormat.dbm(r.wantedDbm)}. '
        'Leakage into your 20 MHz ${AciFormat.dbm(r.leakageDbm)}; '
        'interference ${AciFormat.dbm(r.effectiveInterferenceDbm)}, against a '
        'CCA threshold of ${r.config.ccaThresholdDbm.round()} dBm: '
        '${r.ccaBusy ? 'busy' : 'clear'}.';
  }

  String _floorSemantics(AciResult r) {
    final AciConfig c = r.config;
    return '${c.listener.receiverName} listens. ${c.listener.wantedName} is '
        '${AciFormat.dist(c.wantedDistanceM)} away; the neighbor is '
        '${AciFormat.dist(c.neighborDistanceM)} away.';
  }
}

/// The verdicts in headline type: highest MCS without and with the neighbor,
/// SINR and SIR at the rate the link would otherwise run, leakage, and energy
/// detect. On the presenter stage, and on the phone as the readouts card.
class AciHeadline extends StatelessWidget {
  const AciHeadline({super.key, required this.controller});

  final AdjacentChannelController controller;

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
    final AciResult r = controller.result;

    Widget value(String label, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        Text(v, style: mono.inlineCode.copyWith(color: colors.textPrimary)),
      ],
    );

    return RvrCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const RvrSectionLabel('Highest MCS (modulation and coding scheme)'),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${AciFormat.mcsHeadline(r.mcsWithout)} to '
                '${AciFormat.mcs(r.mcsWith)}',
                style: scale
                    .headlineStyle(mono.outputLarge)
                    .copyWith(color: colors.textAccent),
              ),
            ),
            Text(
              'without the neighbor, then with it',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            AciVerdictText(linkVerdict(r, colors)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'SINR (signal to interference plus noise ratio)',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
            Text(
              AciFormat.db(r.sinrDb),
              style: mono.outputMedium.copyWith(color: colors.textAccent),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                value(
                  'SIR (signal to interference ratio)',
                  AciFormat.db(r.sirDb),
                ),
                value('Signal to noise, no neighbor', AciFormat.db(r.snrDb)),
                value('Wanted signal', AciFormat.dbm(r.wantedDbm)),
                value('Leakage in your 20 MHz', AciFormat.dbm(r.leakageDbm)),
                value(
                  'Interference',
                  AciFormat.dbm(r.effectiveInterferenceDbm),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The mask at your center is not the leakage. dBr: decibels '
              'relative to the neighbor\'s in-channel level.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                value(
                  'Mask at your center',
                  AciFormat.dbr(r.maskAtReceiverCenterDbr),
                ),
                value('Across your 20 MHz', AciFormat.dbr(r.leakageDbr)),
                value('Neighbor in its channel', AciFormat.dbm(r.neighborDbm)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'CCA energy detect at ${r.config.ccaThresholdDbm.round()} dBm',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
            AciVerdictText(ccaVerdict(r, colors)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Selectivity ${AciFormat.n(r.selectivityDb, 0)} dB '
              '(${r.config.separation.isAdjacent ? 'next channel' : 'one gap or more'}): '
              'illustrative.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
