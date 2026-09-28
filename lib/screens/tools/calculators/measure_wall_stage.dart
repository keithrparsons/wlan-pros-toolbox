// MeasureWallStage: the picture half of How to Measure Wall Attenuation
// (measure-wall).
//
// The side view (source, wall, the person with the laptop, the wave), the
// locked channel, and the Take new readings button, which belong to reading
// the picture. It takes a MeasureWallController and knows nothing about the
// controls, so a screen can place it above the controls (phone), beside them
// (desktop) or full screen (the presenter layout).
//
// POINTER: drag the person (or tap anywhere in the room) to move the laptop,
// on either side of the wall; drag the RF source to move it. The view's
// scale holds still during a drag and refits when the finger lifts. The
// sliders in the controls do the same from the keyboard.
//
// PRESENTER: the view fills the stage's height, and the readouts and the
// prediction stand beside it. Strokes, markers and painted labels follow
// PresenterMode.scaleOf.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'measure_wall_controller.dart';
import 'measure_wall_format.dart';
import 'measure_wall_painter.dart';
import 'measure_wall_readouts.dart';
import 'wifi_through_a_wall_parts.dart' show WallCard;

/// The locked-channel line, shown on the stage and in the readouts.
String mwChannelLine(MwConfig c) =>
    'Laptop locked to channel ${c.channel} (${c.freqMHz} MHz, '
    '${c.band.label})';

/// What a screen reader hears for the view.
String mwStageSemantics(MwConfig c, MwFormat f) {
  final String where = c.side == MwSide.near
      ? '${f.gapSpoken(c.nearGapM)} in front of the wall, on the source side'
      : '${f.gapSpoken(c.farGapM)} behind the wall';
  final double? m = c.measuredDb;
  return 'Side view. The RF source stands ${f.distSpoken(c.sourceToWallM)} '
      'from a ${c.material.label.toLowerCase()} wall. The laptop is $where. '
      'Near readings average ${MwFormat.dbm(c.nearSeries.averageDbm)}; '
      '${c.farBelowFloor ? 'far readings are below the noise floor' : 'far readings average ${MwFormat.dbm(c.farSeries.averageDbm)}'}. '
      '${m == null ? 'The wall cannot be measured here.' : 'Measured wall attenuation ${MwFormat.db(m)}, true ${MwFormat.wallDb(c.trueWallDb)}.'}';
}

class MeasureWallStage extends StatelessWidget {
  const MeasureWallStage({
    super.key,
    required this.controller,
    required this.stageHeight,
  });

  final MeasureWallController controller;

  /// Height of the view itself; the caption and buttons add to it. Ignored
  /// in presenter mode, where the view fills the stage.
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
    final MwConfig c = controller.config;
    final MwFormat f = MwFormat(controller.units);
    final bool presenter = PresenterMode.isActive(context);

    final Widget view = Semantics(
      label: mwStageSemantics(c, f),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: _MwRoom(controller: controller),
        ),
      ),
    );
    final Widget card = WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            presenter
                ? 'Drag the person or the RF source.'
                : 'Side view. Drag the person with the laptop to either side '
                      'of the wall, or drag the RF (radio frequency) source. '
                      'The wave\'s height is the level in dB, and the thin '
                      'line over its crests traces it; the spacing never '
                      'changes.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: view)
          else
            SizedBox(height: stageHeight, child: view),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: controller.retake,
                icon: const Icon(Icons.refresh),
                label: Text(
                  'Take new readings, ${c.side == MwSide.near ? 'near' : 'far'} '
                  'side${presenter ? ' (Space)' : ''}',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.toggleSide,
                icon: const Icon(Icons.swap_horiz),
                label: Text(
                  'Go to the ${c.side == MwSide.near ? 'far' : 'near'} side'
                  '${presenter ? ' (S)' : ''}',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          _ChannelLock(config: c),
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
                      MeasureWallReadouts(
                        controller: controller,
                        compact: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MeasureWallPredict(controller: controller),
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

class _ChannelLock extends StatelessWidget {
  const _ChannelLock({required this.config});
  final MwConfig config;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      children: <Widget>[
        Icon(Icons.lock_outline, size: 16, color: colors.textSecondary),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            mwChannelLine(config),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// What a drag holds.
enum _Grab { laptop, source }

class _MwRoom extends StatefulWidget {
  const _MwRoom({required this.controller});
  final MeasureWallController controller;

  @override
  State<_MwRoom> createState() => _MwRoomState();
}

class _MwRoomState extends State<_MwRoom> {
  /// The view held still during a drag; null between drags.
  MwView? _held;
  _Grab _grab = _Grab.laptop;

  MeasureWallController get _k => widget.controller;

  MwView get _view => _held ?? MwView.forConfig(_k.config);

  _Grab _hit(MwStageGeometry g, Offset p) {
    final PresenterScale s = PresenterMode.scaleOf(context);
    final double dx = (p.dx - g.sourceX).abs();
    final double laptopX = g.xFor(_k.config.laptopDistM);
    if (dx <= 22 * s.marker && dx < (p.dx - laptopX).abs()) {
      return _Grab.source;
    }
    return _Grab.laptop;
  }

  void _apply(MwStageGeometry g, Offset p) {
    switch (_grab) {
      case _Grab.laptop:
        _k.laptopAt(g.fromSourceAt(p.dx));
      case _Grab.source:
        // The wall stays put; the source moves to the finger.
        final double d = (g.wallLeft - p.dx) / g.pxPerM;
        _k.setSourceToWall(
          d.clamp(MwConfig.minSourceM, _view.nearSpanM - 0.05),
        );
    }
  }

  void _end() => setState(() => _held = null);

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    final MwStageStyle style = MwStageStyle(
      scale: scale,
      surface: colors.surface2,
      ink: colors.textPrimary,
      muted: colors.textTertiary,
      wave: colors.textAccent,
      wallFill: colors.disabledFill,
      accentFill: colors.primary,
      label: up(
        text.labelSmall!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      small: up(
        text.labelSmall!.copyWith(
          color: colors.textSecondary,
          fontSize: AppTextSize.caption - 1,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, box.maxHeight);
        final MwStageGeometry g = MwStageGeometry(
          size,
          _k.config,
          _view,
          scale,
        );
        void start(Offset p) {
          _held = _view;
          _grab = _hit(g, p);
          _apply(g, p);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (TapUpDetails d) {
            // A tap places the laptop; it never moves the source.
            _grab = _Grab.laptop;
            _apply(g, d.localPosition);
          },
          // Horizontal drags only: the room is a line, and a vertical swipe
          // is left to the page scroll on a phone.
          onHorizontalDragStart: (DragStartDetails d) => start(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              _apply(g, d.localPosition),
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          child: CustomPaint(
            size: size,
            painter: MwStagePainter(
              config: _k.config,
              view: _view,
              style: style,
              format: MwFormat(_k.units),
              revision: _k.revision,
            ),
          ),
        );
      },
    );
  }
}
