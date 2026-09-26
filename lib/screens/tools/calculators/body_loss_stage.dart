// BodyLossStage: the picture half of the Wi-Fi Classroom Body Loss tool.
//
// The top-down auditorium and everything that belongs to reading it: the
// caption, the floor (AP, holder with facing arrow and device, crowd, the
// line to the AP with each person on it numbered), a holder-position slider
// for keyboard and screen-reader users, the received-level gauge and the
// legend. It takes a BodyLossController and knows nothing about the
// controls, so a screen can place it above the controls (phone), beside them
// (desktop) or full screen (the presenter layout).
//
// POINTER: drag the holder to move them; drag a person to place them; tap or
// drag anywhere else to turn the holder toward that point.
//
// PRESENTER (lib/widgets/presenter/): the floor fills the stage's height, and
// the readouts and the predict-then-reveal card stand beside it. Strokes,
// markers and painted labels follow PresenterMode.scaleOf.
//
// THEME: context.colors only (dark §8 / light §8.20). ASCII copy, no em
// dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'body_loss_controller.dart';
import 'body_loss_painter.dart';
import 'body_loss_parts.dart';
import 'body_loss_readouts.dart';

/// The holder's label on the floor.
String blHolderLabel(BlConfig c) => c.holderLossAppliedDb > 0.05
    ? 'Holder, body in the path: ${BlFormat.db(c.holderLossAppliedDb)}'
    : 'Holder';

class BodyLossStage extends StatelessWidget {
  const BodyLossStage({
    super.key,
    required this.controller,
    required this.stageHeight,
  });

  final BodyLossController controller;

  /// Height of the floor view itself. The caption, slider, gauge and legend
  /// add to it. Ignored in presenter mode, where the floor fills the stage.
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
    final BlConfig c = controller.config;
    final bool presenter = PresenterMode.isActive(context);

    final Widget view = Semantics(
      label: blStageSemantics(c),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: _BlFloor(controller: controller),
        ),
      ),
    );
    final Widget card = BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Top-down view of an auditorium, ${c.band.label}. Drag the holder '
            'or a person; tap elsewhere to turn the holder toward that spot. '
            'The gauge gives the received level and the MCS (modulation and '
            'coding scheme) it supports.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: view)
          else
            SizedBox(height: stageHeight, child: view),
          const SizedBox(height: AppSpacing.xxs),
          _positionSlider(context, c),
          const SizedBox(height: AppSpacing.xxs),
          BlGauge(config: c),
          const SizedBox(height: AppSpacing.xs),
          _legend(context, c),
        ],
      ),
    );
    if (!presenter) return card;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.36).clamp(320.0, 480.0);
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      BodyLossReadouts(controller: controller, compact: true),
                      const SizedBox(height: AppSpacing.sm),
                      BodyLossPredict(controller: controller),
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

  Widget _positionSlider(BuildContext context, BlConfig c) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'Holder',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: c.holder.x.clamp(0.3, BlConfig.floorWidthM - 0.3),
            min: 0.3,
            max: BlConfig.floorWidthM - 0.3,
            divisions: 97,
            onChanged: controller.setHolderX,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${BlFormat.dist(c.distanceM)} from the AP',
            semanticFormatterCallback: (double v) =>
                'Holder position, ${v.toStringAsFixed(1)} m from the front '
                'wall',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: 104 * PresenterMode.scaleOf(context).text,
            child: Text(
              '${BlFormat.dist(c.distanceM)} to AP',
              textAlign: TextAlign.right,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, BlConfig c) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle? st() => text.bodySmall?.copyWith(color: colors.textSecondary);
    Widget row(BlSwatchKind k, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BlSwatch(kind: k),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: st())),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          row(BlSwatchKind.line, 'Straight line, AP to device'),
          row(
            BlSwatchKind.holder,
            'Holder, arrow shows facing, device in front',
          ),
          if (c.occupied) ...<Widget>[
            row(BlSwatchKind.person, 'Person'),
            row(
              BlSwatchKind.onLine,
              'Numbered: on the line, '
              '${BlFormat.people(c.crossingCount)}',
            ),
          ] else
            Text('Empty building: no crowd', style: st()),
        ],
      ),
    );
  }
}

/// What a screen reader hears for the floor.
String blStageSemantics(BlConfig c) {
  final String crowd = c.occupied
      ? '${c.crowdSize} people in the room, '
            '${BlFormat.people(c.crossingCount)} on the line to the AP'
      : 'The building is empty';
  return 'Top-down view. The device is ${BlFormat.dist(c.distanceM)} from the '
      'AP. The holder faces ${BlFormat.deg(c.facingDeg)}, '
      '${BlFormat.deg(c.offAxisDeg)} away from the AP, and the body costs '
      '${BlFormat.db(c.holderLossAppliedDb)}. $crowd, costing '
      '${BlFormat.db(c.crowdLossDb)}. Received '
      '${BlFormat.dbm(c.receivedDbm)}, ${BlFormat.mcs(c.mcs)}.';
}

/// What a drag started on.
sealed class _DragTarget {
  const _DragTarget();
}

class _HolderTarget extends _DragTarget {
  const _HolderTarget();
}

class _PersonTarget extends _DragTarget {
  const _PersonTarget(this.index);
  final int index;
}

class _TurnTarget extends _DragTarget {
  const _TurnTarget();
}

class _BlFloor extends StatefulWidget {
  const _BlFloor({required this.controller});
  final BodyLossController controller;

  @override
  State<_BlFloor> createState() => _BlFloorState();
}

class _BlFloorState extends State<_BlFloor> {
  _DragTarget _target = const _TurnTarget();

  BodyLossController get _k => widget.controller;

  _DragTarget _hit(BlFloorGeometry g, Offset local) {
    final BlConfig c = _k.config;
    final PresenterScale s = PresenterMode.scaleOf(context);
    final Offset holder = g.toPx(c.holder);
    if ((local - holder).distance <= math.max(0.8 * g.pxPerM, 22 * s.marker)) {
      return const _HolderTarget();
    }
    if (c.occupied) {
      final double reach = math.max(0.45 * g.pxPerM, 14 * s.marker);
      int? best;
      double bestD = double.infinity;
      for (int i = 0; i < c.crowdSize; i++) {
        final double d = (local - g.toPx(c.people[i])).distance;
        if (d <= reach && d < bestD) {
          best = i;
          bestD = d;
        }
      }
      if (best != null) return _PersonTarget(best);
    }
    return const _TurnTarget();
  }

  void _apply(BlFloorGeometry g, Offset local) {
    final BlPoint p = g.toM(local);
    switch (_target) {
      case _HolderTarget():
        _k.moveHolder(p);
      case _PersonTarget(:final int index):
        _k.movePerson(index, p);
      case _TurnTarget():
        _k.faceToward(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    final BlStageStyle style = BlStageStyle(
      scale: scale,
      surface: colors.surface2,
      grid: colors.textTertiary,
      ink: colors.textPrimary,
      crowd: colors.textTertiary,
      accent: colors.primary,
      accentStroke: colors.textAccent,
      onAccent: colors.onPrimary,
      gridLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
        ),
      ),
      label: up(
        text.labelSmall!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      badge: up(
        text.labelSmall!.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final BlConfig c = _k.config;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, box.maxHeight);
        final BlFloorGeometry g = BlFloorGeometry(size);
        void start(Offset local) {
          _target = _hit(g, local);
          _apply(g, local);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // A drag decides what it holds from where the finger went down,
          // not from where it had moved to when the drag was recognized.
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (TapDownDetails d) {
            // A tap turns the holder; it never moves anyone.
            final _DragTarget t = _hit(g, d.localPosition);
            if (t is _TurnTarget) {
              _target = t;
              _apply(g, d.localPosition);
            }
          },
          // Vertical and horizontal drag recognizers, not pan: pan needs
          // twice the touch slop, so a page scroll would win on a phone.
          onVerticalDragStart: (DragStartDetails d) => start(d.localPosition),
          onVerticalDragUpdate: (DragUpdateDetails d) =>
              _apply(g, d.localPosition),
          onHorizontalDragStart: (DragStartDetails d) => start(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              _apply(g, d.localPosition),
          child: CustomPaint(
            size: size,
            painter: BlStagePainter(
              config: c,
              style: style,
              revision: _k.revision,
              holderLabel: blHolderLabel(c),
              emptyLabel: c.occupied ? null : 'Empty building',
            ),
          ),
        );
      },
    );
  }
}
