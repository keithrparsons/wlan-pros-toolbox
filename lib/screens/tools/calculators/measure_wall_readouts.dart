// Readouts and the predict-then-reveal card for How to Measure Wall
// Attenuation (measure-wall).
//
// MeasureWallReadouts: the live measured wall attenuation, and the three
// things it is made of, shown apart: the true wall loss, the free-space error
// from the geometry, and what the fading left in the averages. Then the two
// averages. `compact` is the presenter-stage form.
//
// MeasureWallPredict: "Source 2 m from the wall, readings 1 m either side of
// it. Is the measured wall loss too high, too low, or right?" (Larry's
// correction to the brief, 2026-09-27). Answer: too high, by 20 log10(3/1) =
// 9.5 dB of free-space loss on top of the wall, plus the wall's own
// thickness.
//
// No status hues: an error is a description, not a verdict (GL-003 §8.13
// rule 6). ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'measure_wall_controller.dart';
import 'measure_wall_format.dart';
import 'wifi_through_a_wall_parts.dart'
    show WallCard, WallNote, WallRow, WallSectionLabel, fmtRate;

/// Source distances for the "same readings, other sources" comparison.
const List<double> kMwCompareSourcesM = <double>[1, 2, 4, 8, 15];

/// One sentence on where the measurement stands.
String mwVerdict(MwConfig c) {
  final double? total = c.totalErrorDb;
  if (total == null) {
    return 'The far side is below the noise floor, so the laptop hears '
        'nothing there and the wall cannot be measured from here. Choose a '
        'thinner wall, a lower band, or move the source closer.';
  }
  final String dir = total >= 0 ? 'high' : 'low';
  return 'The measurement reads ${MwFormat.db(total.abs())} $dir: '
      '${MwFormat.signedDb(c.geometryErrorDb)} from the geometry and '
      '${MwFormat.signedDb(c.fadingResidualDb)} from the fading left in the '
      'averages.';
}

/// The formula line for the geometry error.
String mwErrorFormula(MwConfig c, MwFormat f) =>
    '20 log10(far / near) = 20 log10(${f.dist(c.farDistM, decimals: 2)} / '
    '${f.dist(c.nearDistM, decimals: 2)})';

class MeasureWallReadouts extends StatelessWidget {
  const MeasureWallReadouts({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final MeasureWallController controller;

  /// The presenter-stage form: the numbers and one line each.
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
    final MwConfig c = controller.config;
    final MwFormat f = MwFormat(controller.units);
    final double? m = c.measuredDb;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);

    String side(MwSeries s) => s.belowFloor
        ? 'below the noise floor'
        : compact
        ? MwFormat.dbm(s.averageDbm)
        : '${MwFormat.dbm(s.averageDbm)} '
              '(${MwFormat.n(s.minDbm)} to ${MwFormat.n(s.maxDbm)})';

    return WallCard(
      child: Semantics(
        container: true,
        liveRegion: compact,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const WallSectionLabel('Measured wall attenuation'),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                m == null ? 'Cannot measure' : MwFormat.db(m),
                style: scale
                    .headlineStyle(mono.outputLarge)
                    .copyWith(color: colors.textPrimary),
              ),
            ),
            Text(
              compact
                  ? 'Near average - far average'
                  : 'Near average - far average, updated as you move the '
                        'laptop or the source',
              style: small(),
            ),
            const SizedBox(height: AppSpacing.xs),
            WallRow(
              label: 'True wall loss',
              value: MwFormat.wallDb(c.trueWallDb),
              emphasize: true,
            ),
            WallRow(
              label: 'Free-space error',
              value: MwFormat.signedDb(c.geometryErrorDb),
            ),
            if (!compact)
              Text(
                mwErrorFormula(c, f),
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            WallRow(
              label: 'Fading residual',
              value: c.farBelowFloor
                  ? 'none, no far reading'
                  : MwFormat.signedDb(c.fadingResidualDb),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(mwVerdict(c), style: compact ? small() : body()),
            const SizedBox(height: AppSpacing.xs),
            WallRow(
              label: 'Near, ${f.gap(c.nearGapM)} in front',
              value: side(c.nearSeries),
            ),
            MwSeriesStrip(series: c.nearSeries),
            WallRow(
              label: 'Far, ${f.gap(c.farGapM)} behind',
              value: side(c.farSeries),
            ),
            MwSeriesStrip(series: c.farSeries),
            Text(
              '${c.samplesPerSide} '
              '${c.samplesPerSide == 1 ? 'reading' : 'readings'} per side, '
              'illustrative spread ${MwFormat.n(c.spreadDb)} dB. Dots: '
              'readings; bar: their average; ring: the level with no fading.',
              style: small(),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              WallSectionLabel(
                'Same readings (${f.gap(c.nearGapM)} and ${f.gap(c.farGapM)} '
                'from the wall), other source distances',
              ),
              const SizedBox(height: AppSpacing.xxs),
              for (final double d in kMwCompareSourcesM)
                _compareRow(context, c, f, d),
              const SizedBox(height: AppSpacing.xs),
              WallNote(
                icon: Icons.info_outline,
                message:
                    'The free-space curve is steep near the source: it '
                    'falls ${fmtRate(MwMath.fsplSlopeDbPerM(1), controller.units)} '
                    'at ${f.dist(1)} and '
                    '${fmtRate(MwMath.fsplSlopeDbPerM(4), controller.units)} '
                    'at ${f.dist(4)}. Every step between the two readings adds '
                    'free-space loss that is not the wall, and it adds the '
                    'most when the source is close.',
              ),
              const SizedBox(height: AppSpacing.xxs),
              const WallNote(
                icon: Icons.info_outline,
                message:
                    'The fading spread is an illustrative setting, not a '
                    'measurement: each reading is the model level plus a '
                    'random draw with that standard deviation.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _compareRow(BuildContext context, MwConfig c, MwFormat f, double d) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool fits = d - c.nearGapM >= MwConfig.minFromSourceM - 1e-9;
    final bool current = (d - c.sourceToWallM).abs() < 1e-9;
    final String v = fits
        ? MwFormat.signedDb(
            MwMath.geometryErrorDb(
              sourceToWallM: d,
              nearGapM: c.nearGapM,
              farGapM: c.farGapM,
              thicknessM: c.thicknessM,
            ),
          )
        : 'the near spot would be behind the source';
    return Text(
      'Source ${f.dist(d)}: $v${current ? '  (now)' : ''}',
      style: mono.inlineCode.copyWith(
        color: current ? colors.textPrimary : colors.textSecondary,
        fontWeight: current ? FontWeight.w700 : null,
      ),
    );
  }
}

// ── Predict, then reveal ──────────────────────────────────────────────────

/// The answer, with the current wall's thickness added in.
String mwPredictAnswer(MwConfig c, MwFormat f) {
  const double d = MwPredict.sourceToWallM;
  const double a = MwPredict.gapM;
  final double withWall = MwMath.geometryErrorDb(
    sourceToWallM: d,
    nearGapM: a,
    farGapM: a,
    thicknessM: c.thicknessM,
  );
  return 'Too high. The near readings are ${f.dist(d - a)} from the source '
      'and the far readings ${f.dist(d + a)} (plus the wall), so the far side '
      'carries 20 log10(3 / 1) = ${MwFormat.db(MwPredict.thinWallErrorDb)} '
      'more free-space loss that is not the wall. Add this wall\'s '
      '${f.thickness(c.thicknessM)} and it is ${MwFormat.db(withWall)}. Move '
      'the source to ${f.dist(4)} or more and bring both readings close to '
      'the wall, and the error falls under half a decibel.';
}

class MeasureWallPredict extends StatelessWidget {
  const MeasureWallPredict({super.key, required this.controller});
  final MeasureWallController controller;

  static String question(MwFormat f) =>
      'Source ${f.dist(MwPredict.sourceToWallM)} from the wall, readings '
      '${f.dist(MwPredict.gapM)} either side of it. Is the measured wall '
      'loss too high, too low, or right?';

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
    final MwConfig c = controller.config;
    final MwFormat f = MwFormat(controller.units);
    final bool presenter = PresenterMode.isActive(context);
    final bool open = controller.revealed;
    final bool showing = controller.activePreset == MwPreset.predict;

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Predict, then reveal'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            question(f),
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
                mwPredictAnswer(c, f),
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: showing
                    ? null
                    : () => controller.applyPreset(MwPreset.predict),
                icon: const Icon(Icons.straighten),
                label: Text(
                  showing ? 'This is the scene on the stage' : 'Show it',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── One series, drawn ─────────────────────────────────────────────────────

/// One side's readings on a local dB scale (the average +/- 8 dB, wider if
/// the readings spread further): a dot per reading, a bar at the average and
/// a ring at the model level, so the scatter and what averaging does with it
/// are visible. Marks differ by shape, never by color alone.
class MwSeriesStrip extends StatelessWidget {
  const MwSeriesStrip({super.key, required this.series});
  final MwSeries series;

  @override
  Widget build(BuildContext context) {
    if (series.belowFloor) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final PresenterScale s = PresenterMode.scaleOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 20 * s.marker,
        child: CustomPaint(
          size: Size.infinite,
          painter: _StripPainter(
            series: series,
            ink: colors.textPrimary,
            track: colors.disabledFill,
            stroke: s.strokeWidth(1.5),
            dot: s.markerSize(3),
          ),
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.series,
    required this.ink,
    required this.track,
    required this.stroke,
    required this.dot,
  });

  final MwSeries series;
  final Color ink;
  final Color track;
  final double stroke;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final double avg = series.averageDbm;
    double half = 8;
    for (final double v in series.samplesDbm) {
      half = math.max(half, (v - avg).abs() + 1);
    }
    final double y = size.height / 2;
    final double x0 = dot * 2, x1 = size.width - dot * 2;
    double xOf(double v) => x0 + (v - (avg - half)) / (2 * half) * (x1 - x0);
    canvas.drawLine(
      Offset(x0, y),
      Offset(x1, y),
      Paint()
        ..strokeWidth = stroke
        ..color = track,
    );
    for (final double v in series.samplesDbm) {
      canvas.drawCircle(Offset(xOf(v), y), dot, Paint()..color = ink);
    }
    canvas.drawCircle(
      Offset(xOf(series.modelDbm), y),
      dot * 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ink,
    );
    final double xa = xOf(avg);
    canvas.drawLine(
      Offset(xa, y - size.height * 0.45),
      Offset(xa, y + size.height * 0.45),
      Paint()
        ..strokeWidth = stroke * 2
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.series != series ||
      old.ink != ink ||
      old.track != track ||
      old.stroke != stroke ||
      old.dot != dot;
}
