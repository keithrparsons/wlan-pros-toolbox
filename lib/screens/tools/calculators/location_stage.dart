// LocationStage: the pictures half of the "Where Am I?" tool.
//
// The floor seen from above with its APs, the device (true position), a
// circle around each AP at the distance the chosen method estimated, the
// least-squares position, and the 50 repeated estimates that show the spread.
// In Both, the two methods' floors sit side by side (stacked on a narrow
// screen) so their scatters compare at one glance. Takes the shared
// LocationController and nothing else, so a phone layout can stack it with
// LocationControls and a presenter layout can put the two side by side.
//
// A tap or a drag on a floor moves the device; the device position sliders
// in LocationControls do the same for keyboard users.
//
// PRESENTER (spec 00): the floors fill the stage height with no scroll, and a
// strip over them carries the numbers the lesson is about: the one-sigma
// distance factor, each method's position error and spread radius. Painters
// read PresenterMode.scaleOf.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/location_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'location_controller.dart';
import 'location_painters.dart';
import 'location_parts.dart';

class LocationStage extends StatelessWidget {
  const LocationStage({super.key, required this.controller});

  final LocationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final LocationController c = controller;
        final bool present = PresenterMode.isActive(context);
        final List<LocMethod> methods = c.view.methods;
        if (present) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NowStrip(controller: c),
              if (c.lesson != LocLessonStep.off) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                LocLessonBanner(controller: c),
              ],
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < methods.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _FloorCard(
                          controller: c,
                          method: methods[i],
                          fill: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              _Legend(methods: methods),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (c.lesson != LocLessonStep.off) ...<Widget>[
              LocLessonBanner(controller: c),
              const SizedBox(height: AppSpacing.sm),
            ],
            for (int i = 0; i < methods.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _FloorCard(controller: c, method: methods[i]),
            ],
            const SizedBox(height: AppSpacing.xs),
            _Legend(methods: methods),
          ],
        );
      },
    );
  }
}

/// A method's name as a floor heading.
String locMethodHeading(LocMethod m) => switch (m) {
  LocMethod.signal => 'Signal strength: distance from the level heard',
  LocMethod.ftm =>
    'Fine timing measurement (FTM): distance from the round trip',
};

/// A method's short name.
String locMethodShort(LocMethod m) => switch (m) {
  LocMethod.signal => 'Signal strength',
  LocMethod.ftm => 'Round-trip timing',
};

// ── Now strip (presenter) ───────────────────────────────────────────────────

class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.controller});

  final LocationController controller;

  @override
  Widget build(BuildContext context) {
    final LocationController c = controller;
    final List<LocMethod> methods = c.view.methods;
    return LocCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (methods.contains(LocMethod.signal))
            Expanded(
              flex: 2,
              child: _Tile(
                label: 'One-sigma distance factor',
                value: 'x${c.errorFactor.toStringAsFixed(2)}',
              ),
            ),
          for (final LocMethod m in methods) ...<Widget>[
            Expanded(
              flex: 2,
              child: _Tile(
                label: '${locMethodShort(m)}: position error',
                value: c.run.result(m).positionErrorM == null
                    ? 'no fix'
                    : fmtM(
                        c.run.result(m).positionErrorM!,
                        UnitSystemScope.systemOf(context),
                      ),
                headline: true,
              ),
            ),
            Expanded(
              flex: 2,
              child: _Tile(
                label: '${locMethodShort(m)}: spread radius',
                value: fmtM(
                  c.run.result(m).spreadRadiusM,
                  UnitSystemScope.systemOf(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.headline = false,
  });

  final String label;
  final String value;
  final bool headline;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final TextStyle base = mono.outputMedium.copyWith(
      color: headline ? colors.textAccent : colors.textPrimary,
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 2,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            Text(
              value,
              maxLines: 1,
              style: headline ? sc.headlineStyle(base) : base,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lesson banner ───────────────────────────────────────────────────────────

/// The lesson's words at [c]'s current settings.
String locLessonText(LocationController c) {
  final LocSettings s = c.settings;
  final double d = c.lessonDistanceM;
  final (double lo, double hi) = locOneSigmaRange(d, s.sigmaDb, s.exponent);
  switch (c.lesson) {
    case LocLessonStep.off:
      return '';
    case LocLessonStep.predict:
      return 'Predict: your phone sees an AP at '
          '${kLocLessonRssiDbm.toStringAsFixed(0)} dBm. How far away is it? '
          'Say a number before the reveal.';
    case LocLessonStep.revealed:
      return 'Reveal: the model (n = ${s.exponent.toStringAsFixed(1)}, AP '
          'radiating ${kLocApPowerDbm.toStringAsFixed(0)} dBm, both '
          'illustrative) says ${fmtM(d, c.units)}. But ${s.sigmaDb.toStringAsFixed(1)} '
          'dB of shadowing, one sigma, puts it anywhere from ${fmtM(lo, c.units)} to '
          '${fmtM(hi, c.units)}. Timing would read within about '
          '${fmtM(s.ftmErrorM, c.units)} either way.';
  }
}

class LocLessonBanner extends StatelessWidget {
  const LocLessonBanner({super.key, required this.controller});

  final LocationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border(left: BorderSide(color: colors.primary, width: 4)),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          locLessonText(controller),
          style: text.bodyLarge?.copyWith(color: colors.textPrimary),
        ),
      ),
    );
  }
}

// ── A floor ─────────────────────────────────────────────────────────────────

class _FloorCard extends StatefulWidget {
  const _FloorCard({
    required this.controller,
    required this.method,
    this.fill = false,
  });

  final LocationController controller;
  final LocMethod method;

  /// Presenter: fill a bounded box.
  final bool fill;

  @override
  State<_FloorCard> createState() => _FloorCardState();
}

class _FloorCardState extends State<_FloorCard> {
  Size _size = Size.zero;

  LocationController get c => widget.controller;

  void _moveTo(Offset local) {
    c.device = LocFloorMapping(_size).toFloor(local);
  }

  String _semantic() {
    final LocMethodResult r = c.run.result(widget.method);
    final LocPoint d = c.device;
    final LengthFormat f = LengthFormat(c.units);
    final StringBuffer b = StringBuffer(
      'Floor, ${f.distNumber(kLocFloorWidthM, decimals: 0)} by '
      '${f.distNumber(kLocFloorDepthM, decimals: 0)} ${f.distUnitSpoken}, '
      'seen from above, '
      '${locMethodShort(widget.method)}. ${c.apCount} APs, each with a circle '
      'at its estimated distance. The device is at '
      '${f.distNumber(d.x, decimals: 1, keepZeros: true)}, '
      '${f.distSpoken(d.y, decimals: 1)}. ',
    );
    final LocFix? fix = r.fix;
    if (fix == null) {
      b.write('No position fix. ');
    } else {
      b.write(
        'The estimate is at '
        '${f.distNumber(fix.position.x, decimals: 1, keepZeros: true)}, '
        '${f.distSpoken(fix.position.y, decimals: 1)}, '
        '${f.distSpoken(r.positionErrorM!, decimals: 1)} off. ',
      );
    }
    b.write(
      '$kLocTrials repeated estimates spread over a radius of '
      '${f.distSpoken(r.spreadRadiusM, decimals: 1)}. ',
    );
    if (r.nonMeetingPairs.isNotEmpty) {
      b.write('Some circles cannot meet. ');
    }
    b.write('Drag or tap to move the device.');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final TextTheme text = Theme.of(context).textTheme;
    final LocMethodResult r = c.run.result(widget.method);
    final LocFloorStyle style = LocFloorStyle(
      sc: sc,
      floor: colors.surface2,
      margin: colors.surface1,
      grid: colors.border,
      outline: colors.borderStrong,
      ap: colors.textPrimary,
      apText: colors.textSecondary,
      circle: colors.textSecondary,
      device: colors.textPrimary,
      estimate: colors.textAccent,
      casing: colors.surface0,
      label: colors.textSecondary,
      font: text.labelSmall ?? const TextStyle(),
    );
    final Widget plan = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        _size = Size(bc.maxWidth, bc.maxHeight);
        return MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (TapUpDetails d) => _moveTo(d.localPosition),
            onPanStart: (DragStartDetails d) => _moveTo(d.localPosition),
            onPanUpdate: (DragUpdateDetails d) => _moveTo(d.localPosition),
            child: CustomPaint(
              size: _size,
              painter: LocFloorPainter(
                run: c.run,
                method: widget.method,
                style: style,
                units: c.units,
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
        child: widget.fill
            ? plan
            : AspectRatio(
                aspectRatio:
                    (kLocFloorWidthM + 2 * kLocMarginM) /
                    (kLocFloorDepthM + 2 * kLocMarginM),
                child: plan,
              ),
      ),
    );
    final String pairs = r.nonMeetingPairs
        .map(((int, int) p) => '${p.$1 + 1} and ${p.$2 + 1}')
        .join(', ');
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: AppSpacing.sm,
                height: AppSpacing.sm,
                child: CustomPaint(
                  painter: LocLegendPainter(
                    mark: widget.method == LocMethod.signal
                        ? LocLegendMark.signal
                        : LocLegendMark.ftm,
                    color: colors.textAccent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: LocSectionLabel(locMethodHeading(widget.method))),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (widget.fill) Expanded(child: floor) else floor,
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            liveRegion: true,
            child: Text(
              r.fix == null
                  ? 'No position fix: the APs give no single answer.'
                  : 'Position error ${fmtM(r.positionErrorM!, UnitSystemScope.systemOf(context))}. Spread radius '
                        'over $kLocTrials repeats ${fmtM(r.spreadRadiusM, UnitSystemScope.systemOf(context))}.',
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
          if (r.nonMeetingPairs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: AppSpacing.sm + AppSpacing.xxs,
                    color: colors.statusWarning,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      'Impossible: circles of APs $pairs cannot meet. No '
                      'point fits every distance; the marker is the best '
                      'compromise.',
                      maxLines: widget.fill ? 2 : null,
                      overflow: widget.fill ? TextOverflow.ellipsis : null,
                      style: text.bodySmall?.copyWith(
                        color: colors.statusWarning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Legend ──────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.methods});

  final List<LocMethod> methods;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? small = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary);
    Widget item(LocLegendMark mark, Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: AppSpacing.sm + AppSpacing.xxs,
          height: AppSpacing.sm + AppSpacing.xxs,
          child: CustomPaint(
            painter: LocLegendPainter(mark: mark, color: color),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: small),
      ],
    );
    return Semantics(
      label:
          'Legend: ring with a crosshair, the true device position. Square, '
          'an AP. '
          '${methods.contains(LocMethod.signal) ? 'Diamond, the signal-strength estimate. ' : ''}'
          '${methods.contains(LocMethod.ftm) ? 'Triangle, the round-trip timing estimate. ' : ''}'
          'Small marks, $kLocTrials repeated estimates. Circles, each AP\'s '
          'estimated distance; dashed where the direct path is blocked.',
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          item(LocLegendMark.device, colors.textPrimary, 'True position'),
          item(LocLegendMark.ap, colors.textPrimary, 'AP'),
          if (methods.contains(LocMethod.signal))
            item(
              LocLegendMark.signal,
              colors.textAccent,
              'Signal-strength estimate',
            ),
          if (methods.contains(LocMethod.ftm))
            item(LocLegendMark.ftm, colors.textAccent, 'Timing estimate'),
          Text(
            'Small marks: $kLocTrials repeats. Circles: estimated distances '
            '(dashed: blocked).',
            style: small,
          ),
        ],
      ),
    );
  }
}
