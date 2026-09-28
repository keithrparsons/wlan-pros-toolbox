// The stage for Band Steering (Wi-Fi Classroom): which band the client is on
// and why, the top-down floor (AP, both rings, the walk, the beacons, the
// association line and the probe arrows), an RSSI gauge per band with the
// client's thresholds, and the frames at this point of the walk. Reads a
// [BandSteeringController]; owns no state, so a presenter layout can place it
// beside [BandSteeringControls].
//
// COLOR (GL-003 §8.15.2 / §8.13). The two band hues come from
// band_steering_parts.dart and never carry the band alone (pattern and
// words). The one status hue is the warning, used for a refused
// authentication and for a deauthentication, always with the words beside
// it ("Refused", "Deauthentication", "No traffic"). Everything else is the
// neutral stack.
//
// MOTION (§8.8). The walk and the beacon pulse move only while playing. With
// reduced motion on, nothing moves by itself; Reveal jumps to the end.
//
// ACCESSIBILITY. The floor and gauges are pictures: each has a worded
// Semantics label, and every number they show is also in text (SC 1.4.1).
// The position slider moves the client for keyboard and screen-reader users.
//
// PRESENTER (PresenterMode.isActive): the floor fills the stage's height;
// the band, the reason, the gauges and the frames stand beside it.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/band_steering_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'band_steering_controller.dart';
import 'band_steering_painters.dart';
import 'band_steering_parts.dart';

/// The thresholds drawn on [band]'s gauge for [p].
List<BsGaugeMark> bsGaugeMarks(ClientProfile p, BsBand band) {
  final double? entry = entryThresholdDbm(p, band);
  final double? look = lookThresholdDbm(p, band);
  return <BsGaugeMark>[
    const BsGaugeMark(kBsHearFloorDbm, 'floor'),
    if (entry != null) BsGaugeMark(entry, 'join'),
    if (look != null) BsGaugeMark(look, 'look'),
  ];
}

BsStageStyle bsStageStyle(BuildContext context) {
  final AppColorScheme colors = context.colors;
  final TextTheme text = Theme.of(context).textTheme;
  final AppMonoText mono =
      Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
  // Painted text does not see MediaQuery's text scale; the presenter scale
  // reaches it here (1.0 outside presenter mode).
  final PresenterScale scale = PresenterMode.scaleOf(context);
  TextStyle up(TextStyle t) =>
      t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
  return BsStageStyle(
    scale: scale,
    surface: colors.surface2,
    grid: colors.textTertiary,
    ink: colors.textPrimary,
    muted: colors.textSecondary,
    band24: bsBandColor(BsBand.ghz24, colors),
    band5: bsBandColor(BsBand.ghz5, colors),
    refused: colors.statusWarning,
    gridLabel: up(
      mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textSecondary,
      ),
    ),
    label: up(
      text.labelSmall!.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class BandSteeringStage extends StatelessWidget {
  const BandSteeringStage({
    super.key,
    required this.controller,
    this.floorHeight = 300,
  });

  final BandSteeringController controller;

  /// Height of the floor view on the normal screen. Ignored in presenter
  /// mode, where the floor fills the stage.
  final double floorHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = BsHeadline(controller: controller);
        final Widget floor = _FloorCard(
          controller: controller,
          fill: presenting,
          height: floorHeight,
        );
        final Widget gauges = _Gauges(controller: controller);
        final Widget frames = _Frames(controller: controller);
        if (!presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.sm),
              floor,
              const SizedBox(height: AppSpacing.sm),
              gauges,
              const SizedBox(height: AppSpacing.sm),
              frames,
            ],
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double side = (box.maxWidth * 0.38).clamp(320.0, 500.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: floor),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          headline,
                          const SizedBox(height: AppSpacing.xs),
                          gauges,
                          const SizedBox(height: AppSpacing.xs),
                          frames,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Headline: the band and why ──────────────────────────────────────────────

class BsHeadline extends StatelessWidget {
  const BsHeadline({super.key, required this.controller});

  final BandSteeringController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final BsStep s = controller.step;
    final BsBand? band = s.band;
    final String who = controller.config.profile.label;
    final String value = band?.label ?? 'Not connected';
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            label:
                '$who, ${_bsLenSpoken(context, s.distanceM)} from the AP: '
                '${band == null ? 'not connected' : 'on ${band.label}'}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$who is on',
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                Row(
                  children: <Widget>[
                    if (band != null) ...<Widget>[
                      BsBandSwatch(band: band),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    // Never wraps mid-word: shrinks to fit a narrow panel.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: scale.headlineStyle(
                            mono.outputLarge.copyWith(
                              color: band == null
                                  ? colors.textSecondary
                                  : bsBandColor(band, colors),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${_bsLen(context, s.distanceM)} from the AP',
                  style: mono.inlineCode.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            s.why,
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
          ),
          if (controller.config.mode == SteeringMode.deauthentication) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Deauthentications: ${s.deauthsTotal}. Back on 2.4 GHz: '
              '${s.returnsTo24}. Time without traffic: ${s.outageS} s '
              '(illustrative).',
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── The floor ───────────────────────────────────────────────────────────────

class _FloorCard extends StatelessWidget {
  const _FloorCard({
    required this.controller,
    required this.fill,
    required this.height,
  });

  final BandSteeringController controller;
  final bool fill;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final BsWalk w = controller.walk;
    final BsStep s = controller.step;
    final BsConfig c = controller.config;
    final double ring24 = w.ringM(BsBand.ghz24);
    final double ring5 = w.ringM(BsBand.ghz5);
    final List<double> pos = c.positionsM;

    final Widget view = Semantics(
      label:
          'Top-down floor. The AP is at the left; the client walks '
          '${c.path == WalkPath.edgeToAp ? 'from the edge toward the AP' : 'from the AP out to the edge'}. '
          '2.4 GHz can be heard out to ${_bsLenSpoken(context, ring24)}, '
          '5 GHz out to ${_bsLenSpoken(context, ring5)}. Beacons go out '
          'on both bands. The client is '
          '${_bsLenSpoken(context, s.distanceM)} away, '
          '${s.band == null ? 'not connected' : 'on ${s.band!.label}'}.',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: CustomPaint(
          painter: BsFloorPainter(
            rangeM: bsViewRangeM,
            ring24M: ring24,
            ring5M: ring5,
            step: s,
            walkFrom: pos.first,
            walkTo: pos.last,
            clientLetter: c.profile.letter,
            style: bsStageStyle(context),
            pulse: controller.pulse,
            units: UnitSystemScope.systemOf(context),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );

    final Widget slider = Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'Walked',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: controller.index.toDouble(),
            min: 0,
            max: (controller.stepCount - 1).toDouble(),
            divisions: controller.stepCount - 1,
            onChanged: (double v) => controller.index = v.round(),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: (double v) =>
                'Client ${_bsLenSpoken(context, pos[v.round()])} from the AP',
          ),
        ),
        ExcludeSemantics(
          child: Text(
            _bsLen(context, s.distanceM),
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );

    TextStyle? legendStyle() =>
        text.bodySmall?.copyWith(color: colors.textSecondary);
    Widget legendRow(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        swatch,
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: legendStyle())),
      ],
    );
    final Widget legend = ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          legendRow(
            const BsBandSwatch(band: BsBand.ghz24),
            'Solid: 2.4 GHz, heard to ${_bsLen(context, ring24)}',
          ),
          legendRow(
            const BsBandSwatch(band: BsBand.ghz5),
            'Dashed: 5 GHz, heard to ${_bsLen(context, ring5)}',
          ),
          Text(
            'Probe arrows: two heads when answered, a cross when not',
            style: legendStyle(),
          ),
        ],
      ),
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Top-down view. Each ring is where the client can still hear '
            'that band (${kBsHearFloorDbm.toStringAsFixed(0)} dBm, '
            'illustrative).',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (fill)
            Expanded(child: view)
          else
            SizedBox(height: height, child: view),
          const SizedBox(height: AppSpacing.xxs),
          slider,
          legend,
        ],
      ),
    );
  }
}

/// Meters the floor view spans to the right of the AP: past the edge of the
/// walk, and past the 2.4 GHz ring when it fits.
double get bsViewRangeM => kBsEdgeM + 8;

// ── Gauges ──────────────────────────────────────────────────────────────────

class _Gauges extends StatelessWidget {
  const _Gauges({required this.controller});

  final BandSteeringController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final BsStep s = controller.step;
    final ClientProfile p = controller.config.profile;
    final BsStageStyle style = bsStageStyle(context);

    Widget gauge(BsBand b) {
      final double rssi = s.rssi(b);
      final List<BsGaugeMark> marks = bsGaugeMarks(p, b);
      return Semantics(
        label:
            '${b.label} signal ${bsDbm(rssi)}. Lines at '
            '${marks.map((BsGaugeMark m) => '${m.dbm.toStringAsFixed(0)} dBm ${m.label}').join(', ')}.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                BsBandSwatch(band: b),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    b.label,
                    style: text.labelLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
                Text(
                  bsHears(rssi) ? bsDbm(rssi) : '${bsDbm(rssi)}, not heard',
                  style: mono.inlineCode.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              height: 50 * scale.marker,
              child: CustomPaint(
                painter: BsGaugePainter(
                  band: b,
                  rssiDbm: rssi,
                  marks: marks,
                  style: style,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Text(
              'Lines: '
              '${marks.map((BsGaugeMark m) => '${m.label} ${m.dbm.toStringAsFixed(0)}').join(', ')} dBm',
              style: mono.inlineCode.copyWith(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Signal on each band'),
          const SizedBox(height: AppSpacing.xs),
          gauge(BsBand.ghz24),
          const SizedBox(height: AppSpacing.xs),
          gauge(BsBand.ghz5),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            p == ClientProfile.c
                ? 'Floor: below it nothing is heard (illustrative). '
                      '${p.label} publishes no join or look levels.'
                : 'Floor: below it nothing is heard (illustrative). '
                      '${p == ClientProfile.b ? 'Join: the lowest level ${p.label} will join. ' : ''}'
                      'Look: below it ${p.label} looks for another network.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Frames at this point of the walk ────────────────────────────────────────

class _Frames extends StatelessWidget {
  const _Frames({required this.controller});

  final BandSteeringController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final BsStep s = controller.step;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final List<BsFrame> frames = s.frames;

    Widget row(BsFrame f) {
      final bool deauth = f.kind == BsFrameKind.deauthentication;
      final bool refused = f.outcome == BsOutcome.refused;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              refused
                  ? Icons.block_rounded
                  : deauth
                  ? Icons.link_off_rounded
                  : f.fromAp
                  ? Icons.west_rounded
                  : Icons.east_rounded,
              size: 16,
              color: refused || deauth
                  ? colors.statusWarning
                  : colors.textSecondary,
              semanticLabel: refused
                  ? 'refused'
                  : deauth
                  ? 'deauthentication, AP to client'
                  : f.fromAp
                  ? 'AP to client'
                  : 'client to AP',
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(f.text, style: body)),
          ],
        ),
      );
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Frames at this point'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Beacons on 2.4 GHz and 5 GHz: sent in every steering mode.',
            style: body.copyWith(color: colors.textSecondary),
          ),
          if (frames.isEmpty && s.inOutage)
            Text(
              'No other frames: the client was deauthenticated and is '
              'rescanning, so it sends no traffic.',
              style: body.copyWith(color: colors.textSecondary),
            )
          else if (frames.isEmpty)
            Text(
              'No other frames: the client is not looking and the AP has '
              'nothing to ask.',
              style: body.copyWith(color: colors.textSecondary),
            )
          else
            for (final BsFrame f in frames) row(f),
        ],
      ),
    );
  }
}

/// A walk distance, whole metres or whole feet.
String _bsLen(BuildContext context, double m) =>
    LengthFormat(UnitSystemScope.systemOf(context)).dist(m, decimals: 0);

/// [_bsLen] spoken: "12 meters" / "39 feet".
String _bsLenSpoken(BuildContext context, double m) =>
    LengthFormat(UnitSystemScope.systemOf(context)).distSpoken(m, decimals: 0);
