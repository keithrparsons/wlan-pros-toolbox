// SurveyWalkStage: the pictures half of the Survey Walk.
//
// The floor (corridor and rooms, APs, the path, the walker, the samples of
// the shown channel with their ghosts and the white no-data stretches), the
// channel strip (which channel each NIC is on right now) and, when the
// signal layer is on, the level of the shown channel's APs along the path.
// Takes the shared SurveyWalkController and nothing else, so a phone layout
// can stack it with SurveyWalkControls and a presenter layout can put the
// two side by side.
//
// PRESENTER (spec 00): inside a PresenterLayout the floor, the strip and the
// signal plot share the stage height with no scroll, the phone prose is
// dropped, and a strip over the floor carries the number the lesson is
// about: the shown channel's sample spacing against the guess range, with
// the Rule 4 verdict in words.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/survey_walk_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'roaming_walk_painters.dart' show FloorMapping;
import 'roaming_walk_palette.dart';
import 'roaming_walk_parts.dart';
import 'survey_walk_controller.dart';
import 'survey_walk_controls.dart' show SurveyActiveLimitsCard;
import 'survey_walk_painters.dart';

class SurveyWalkStage extends StatelessWidget {
  const SurveyWalkStage({super.key, required this.controller});

  final SurveyWalkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final SurveyPaintStyle style = _paintStyle(context);
        final bool signal =
            controller.showSignal && controller.shownIndex != null;
        if (PresenterMode.isActive(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NowStrip(controller: controller),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                flex: 5,
                child: _FloorCard(
                  controller: controller,
                  style: style,
                  fill: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Active: one radio, one AP; the lesson is its limits.
              if (controller.config.effectiveType == SurveyType.active)
                const SurveyActiveLimitsCard(compact: true)
              else
                _StripCard(controller: controller, style: style, fill: true),
              if (signal) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Expanded(
                  flex: 3,
                  child: _SignalCard(
                    controller: controller,
                    style: style,
                    fill: true,
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _FloorCard(controller: controller, style: style),
            const SizedBox(height: AppSpacing.sm),
            _StripCard(controller: controller, style: style),
            if (signal) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _SignalCard(controller: controller, style: style),
            ],
          ],
        );
      },
    );
  }

  static SurveyPaintStyle _paintStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    return SurveyPaintStyle(
      sc: sc,
      apColors: <Color>[
        for (int i = 0; i < kSurveyAps.length; i++)
          roamApColor(i, isLight: colors.isLight),
      ],
      accent: colors.textAccent,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      halo: colors.surface2,
      // Light: the floor sits on the grey canvas so white (no data) stands
      // out; dark: the floor is surface 2 and no data is text white.
      floor: colors.isLight ? colors.surface0 : colors.surface2,
      noData: colors.isLight ? colors.surface1 : colors.textPrimary,
      disabled: colors.textDisabled,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: sc.paintFont(AppTextSize.caption - 2),
        color: colors.textSecondary,
      ),
    );
  }
}

// ── Floor ───────────────────────────────────────────────────────────────────

class _FloorCard extends StatelessWidget {
  const _FloorCard({
    required this.controller,
    required this.style,
    this.fill = false,
  });

  final SurveyWalkController controller;
  final SurveyPaintStyle style;
  final bool fill;

  String _semantic() {
    final SurveyWalkController c = controller;
    final SurveyWalkResult r = c.result;
    final SurveyWalkConfig cfg = c.config;
    final StringBuffer b = StringBuffer(
      'Floor plan, ${LengthFormat(c.units).distNumber(kFloorWidthM, decimals: 0)} '
      'by ${LengthFormat(c.units).distSpoken(kFloorDepthM, decimals: 0)}, a '
      'corridor with rooms either side. ',
    );
    if (c.drawing) {
      b.write(
        'Drawing a path: ${c.drawnPoints.length} points so far. Tap the '
        'floor to add a point.',
      );
      return b.toString();
    }
    b.write(
      'Path ${c.pathPreset.label.toLowerCase()}, '
      '${LengthFormat(c.units).distSpoken(r.plan.lengthM, decimals: 0)}. '
      'Walker at '
      '${LengthFormat(c.units).distSpoken(c.walkerS, decimals: 1)}. ',
    );
    if (cfg.effectiveType == SurveyType.active) {
      final int? s = r.servingApAt(c.timeS);
      if (s != null) {
        b.write(
          'Active survey: associated with ${cfg.aps[s].label}; every '
          'other AP is greyed out. ',
        );
      }
    }
    final int? ch = c.shownIndex;
    if (ch == null) {
      b.write('Showing samples of every channel, shaped by band. ');
    } else {
      final int n = r
          .samplesOf(ch)
          .where((SurveySample s) => s.measuredAtS <= c.timeS)
          .length;
      b.write(
        'Showing ${r.channels[ch].label}: $n samples so far. White '
        'stretches mean no data. ',
      );
    }
    if (cfg.doorPause) {
      b.write(
        'The walker pauses ${cfg.doorPauseS.toStringAsFixed(0)} seconds at '
        'the door. ',
      );
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SurveyWalkController c = controller;
    final bool wide = MediaQuery.sizeOf(context).width >= 720;
    final Widget plan = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        final Size size = Size(bc.maxWidth, bc.maxHeight);
        return MouseRegion(
          cursor: c.drawing
              ? SystemMouseCursors.precise
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: c.drawing
                ? (TapUpDetails d) =>
                      c.addWaypoint(FloorMapping(size).toFloor(d.localPosition))
                : null,
            child: CustomPaint(
              size: size,
              painter: SurveyFloorPainter(
                result: c.result,
                timeS: c.timeS,
                shown: c.shownIndex,
                style: style,
                drawnPoints: List<FloorPoint>.of(c.drawnPoints),
                drawing: c.drawing,
              ),
            ),
          ),
        );
      },
    );
    final Widget floor = Semantics(
      label: _semantic(),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: fill
              ? plan
              : AspectRatio(aspectRatio: wide ? 2.6 : 2.2, child: plan),
        ),
      ),
    );
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RwSectionLabel(
            'Floor plan, seen from above '
            '(${LengthFormat(UnitSystemScope.systemOf(context)).dist(kFloorWidthM, decimals: 0)} x '
            '${LengthFormat(UnitSystemScope.systemOf(context)).dist(kFloorDepthM, decimals: 0)})',
          ),
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The walls are drawn for orientation; the signal model has none. '
              'A dot is placed where the survey app thinks it was taken; a '
              'ring joined to it marks where it really was.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (fill) Expanded(child: floor) else floor,
          const SizedBox(height: AppSpacing.xs),
          if (c.drawing)
            _DrawBar(controller: c)
          else
            _FloorLegend(style: style, allChannels: c.shownIndex == null),
        ],
      ),
    );
  }
}

class _DrawBar extends StatelessWidget {
  const _DrawBar({required this.controller});

  final SurveyWalkController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final SurveyWalkController c = controller;
    final int n = c.drawnPoints.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(
            n == 0
                ? 'Drawing a path: tap the floor where the walk starts, then '
                      'tap each turn. The door is halfway along the first '
                      'leg.'
                : n == 1
                ? '1 point. Tap the next one.'
                : '$n points, ${pathLengthM(c.drawnPoints).toStringAsFixed(0)} '
                      'm. Tap to add more, or Use this path.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            SizedBox(
              width: 160,
              child: FilledButton(
                onPressed: c.canFinishDrawing ? c.finishDrawing : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  disabledBackgroundColor: colors.disabledFill,
                  disabledForegroundColor: colors.textDisabled,
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                ),
                child: const Text('Use this path'),
              ),
            ),
            SizedBox(
              width: 120,
              child: RwOutlineButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                semanticLabel: 'Remove the last point',
                onPressed: n > 0 ? c.undoWaypoint : null,
              ),
            ),
            SizedBox(
              width: 120,
              child: RwOutlineButton(
                icon: Icons.close_rounded,
                label: 'Cancel',
                semanticLabel: 'Stop drawing and keep the old path',
                onPressed: c.cancelDrawing,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FloorLegend extends StatelessWidget {
  const _FloorLegend({required this.style, required this.allChannels});

  final SurveyPaintStyle style;
  final bool allChannels;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle t =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    Widget item(CustomPainter swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CustomPaint(size: const Size(18, 14), painter: swatch),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: t),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          if (allChannels) ...<Widget>[
            item(_Marker(RoamBand.b24, style.secondary), '2.4 GHz'),
            item(_Marker(RoamBand.b5, style.secondary), '5 GHz'),
            item(_Marker(RoamBand.b6, style.secondary), '6 GHz'),
          ] else ...<Widget>[
            item(_Marker(RoamBand.b24, style.accent), 'Sample'),
            item(_Swatch(style.noData, style.axis), 'No data (white)'),
          ],
          item(
            _Marker(RoamBand.b24, style.tertiary, hollow: true),
            'Where it was really taken',
          ),
          item(
            _Marker(RoamBand.b24, style.secondary, hollow: true),
            'Measured, not placed yet',
          ),
          item(_Active(style.accent), 'Active test'),
        ],
      ),
    );
  }
}

class _Marker extends CustomPainter {
  _Marker(this.band, this.color, {this.hollow = false});

  final RoamBand band;
  final Color color;
  final bool hollow;

  @override
  void paint(Canvas canvas, Size size) {
    drawBandMarker(
      canvas,
      size.center(Offset.zero),
      4.5,
      band,
      Paint()
        ..color = color
        ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_Marker old) =>
      old.color != color || old.band != band || old.hollow != hollow;
}

class _Active extends CustomPainter {
  _Active(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    canvas.drawCircle(
      c,
      4.5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(c, 1.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Active old) => old.color != color;
}

class _Swatch extends CustomPainter {
  _Swatch(this.fill, this.edge);

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = fill);
    canvas.drawRect(
      r,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_Swatch old) => old.fill != fill || old.edge != edge;
}

// ── Channel strip ───────────────────────────────────────────────────────────

class _StripCard extends StatelessWidget {
  const _StripCard({
    required this.controller,
    required this.style,
    this.fill = false,
  });

  final SurveyWalkController controller;
  final SurveyPaintStyle style;
  final bool fill;

  static String nowText(SurveyWalkController c) {
    final SurveyWalkResult r = c.result;
    final List<RadioNow> now = r.radiosAt(c.timeS);
    if (now.isEmpty) return 'No radio is scanning.';
    final List<String> parts = <String>[
      for (final RadioNow n in now)
        'NIC ${n.radio + 1}'
            '${n.active ? ' (active)' : ''}: '
            '${n.channel == null ? (c.config.capture == CaptureMethod.stopAndGo && !n.active ? 'idle, walking to the next stop' : 'idle') : r.channels[n.channel!].label}'
            '${n.channel != null && !n.recording ? ', not recording' : ''}',
    ];
    return '${parts.join('. ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SurveyWalkController c = controller;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final String now = nowText(c);
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel(
            'Channel strip: where each network interface card (NIC) is now',
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: 'Channel strip. $now',
            excludeSemantics: true,
            child: SizedBox(
              height: sc.markerSize(64),
              child: CustomPaint(
                size: Size.infinite,
                painter: SurveyChannelStripPainter(
                  result: c.result,
                  timeS: c.timeS,
                  shown: c.shownIndex,
                  style: style,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ExcludeSemantics(
            child: Text(
              now,
              maxLines: fill ? 1 : 3,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          if (!fill && (c.result.schedule?.isPriority ?? false))
            Text(
              'A bar under a channel marks it as a priority channel.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

// ── Signal ──────────────────────────────────────────────────────────────────

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.controller,
    required this.style,
    this.fill = false,
  });

  final SurveyWalkController controller;
  final SurveyPaintStyle style;
  final bool fill;

  String _semantic(int ch) {
    final SurveyWalkController c = controller;
    final SurveyWalkResult r = c.result;
    final List<SurveySample> s = r
        .samplesOf(ch)
        .where((SurveySample x) => x.measuredAtS <= c.timeS)
        .toList();
    final StringBuffer b = StringBuffer(
      'Signal along the path on ${r.channels[ch].label}. ',
    );
    if (s.isEmpty || s.last.heard.isEmpty) {
      b.write('No sample of an AP on this channel yet.');
    } else {
      final HeardAp h = s.last.heard.first;
      b.write(
        'Latest sample: ${fmtDbm(h.rssiDbm)} against an average of '
        '${fmtDbm(h.meanDbm)}, a fade of ${h.fadeDb.toStringAsFixed(1)} dB.',
      );
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SurveyWalkController c = controller;
    final int ch = c.shownIndex!;
    final Widget plot = Semantics(
      label: _semantic(ch),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: fill ? null : 200,
          color: colors.surface2,
          child: CustomPaint(
            size: Size.infinite,
            painter: SurveySignalPainter(
              result: c.result,
              timeS: c.timeS,
              shown: ch,
              style: style,
              units: c.units,
            ),
          ),
        ),
      ),
    );
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RwSectionLabel(
            'Signal along the path (dBm), ${c.result.channels[ch].label}',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fill) Expanded(child: plot) else plot,
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Line: the average level (log-distance). Dots: each sample with '
              'small-scale fading. A moving scanner draws a new fade every '
              'sample; standing still repeats one fade.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Presenter strip ─────────────────────────────────────────────────────────

/// Presenter only: the shown channel's spacing against the guess range (the
/// headline), the Rule 4 verdict in words, the walk time and the error.
class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.controller});

  final SurveyWalkController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final SurveyWalkController c = controller;
    final SurveyWalkResult r = c.result;
    final SurveyWalkConfig cfg = c.config;
    final int? ch = c.shownIndex;
    // Active: one radio tests on whatever AP it is associated with, so the
    // spacing is the test interval, not a channel's revisit.
    final bool active = cfg.effectiveType == SurveyType.active;
    final double spacing = active || ch == null
        ? sampleSpacingM(cfg.paceMps, r.ruleRevisitS)
        : r.stats[ch].spacingM;
    final String headLabel = active
        ? 'Spacing, active tests'
        : ch == null
        ? 'Worst spacing'
        : 'Spacing, ch ${r.channels[ch].shortLabel}';

    Widget stat(String label, String value, {Color? color}) => MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: mono.outputMedium.copyWith(
              color: color ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );

    final bool pass = r.rule4Pass;
    return RwCard(
      child: Semantics(
        liveRegion: true,
        child: Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: <Widget>[
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    headLabel,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    '${fmtM(spacing, UnitSystemScope.systemOf(context))} vs ${fmtM(cfg.guessRangeM, UnitSystemScope.systemOf(context))}',
                    style: sc
                        .headlineStyle(mono.outputLarge)
                        .copyWith(color: colors.textAccent),
                  ),
                ],
              ),
            ),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Rule 4',
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        pass
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        color: pass
                            ? colors.statusSuccess
                            : colors.statusDanger,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        '${pass ? 'Pass' : 'Fail'}: ${fmtS(r.ruleRevisitS)} '
                        'revisit, ${fmtS(r.maxAllowedRevisit)} allowed',
                        style: mono.outputMedium.copyWith(
                          color: pass
                              ? colors.statusSuccess
                              : colors.statusDanger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            stat(
              'Walk',
              '${c.timeS.toStringAsFixed(1)} of '
                  '${r.durationS.toStringAsFixed(1)} s',
            ),
            stat(
              'Largest position error',
              fmtM(r.maxErrorM, UnitSystemScope.systemOf(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "-70.4 dBm".
String fmtDbm(double v) => '${v.toStringAsFixed(1)} dBm';
