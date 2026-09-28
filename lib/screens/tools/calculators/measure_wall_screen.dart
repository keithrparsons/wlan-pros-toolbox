// How to Measure Wall Attenuation: Wi-Fi Classroom tool (measure-wall).
//
// Keith's field method, and why it works (Keith, 2026-09-27): lock the
// laptop to one channel, put the RF source 4 m or more from the wall, average
// a series of readings close to the near side, then close to the far side;
// the difference is the wall. Move the person with the laptop and the source,
// and watch the live measured value split into the true wall, the free-space
// error from the geometry, and the fading left in the averages.
//
// Model in lib/services/wifi_lab/measure_wall_model.dart, which reuses
// FsplMath (the FSPL Simulator) and WallSlab (Wi-Fi Through a Wall, ITU-R
// P.2040-4) without modifying either.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - MeasureWallController  (measure_wall_controller.dart)
//   - MeasureWallStage       (measure_wall_stage.dart)    side view, buttons
//   - MeasureWallControls, MeasureWallExplainer
//                            (measure_wall_controls.dart)
//   - MeasureWallReadouts, MeasureWallPredict
//                            (measure_wall_readouts.dart)
//   - MwStagePainter         (measure_wall_painter.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> none: there is always a source, a wall and two series
//   - error       -> the far side below the noise floor: the headline reads
//                    "Cannot measure", the readouts and the stage say why in
//                    words, and the verdict says what to change
//   - success     -> the view, the live measured value and its three parts
//   - disabled    -> the active scene's button (its check mark and "selected"
//                    say why); "Show it" once the prediction is on the stage
//   - interactive -> drag or tap the room, sliders and buttons for all of
//                    it from the keyboard; themed Material controls with the
//                    global focus ring
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/unit_system_switch.dart';
import 'measure_wall_controller.dart';
import 'measure_wall_controls.dart';
import 'measure_wall_readouts.dart';
import 'measure_wall_stage.dart';
import 'wifi_through_a_wall_parts.dart' show WallCard;

export '../../../services/wifi_lab/measure_wall_model.dart'
    show kMeasureWallToolId;

/// The catalog title, used by the app bar and the presenter.
const String kMeasureWallTitle = 'How to Measure Wall Attenuation';

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class MeasureWallScreen extends StatefulWidget {
  const MeasureWallScreen({super.key});

  @override
  State<MeasureWallScreen> createState() => _MeasureWallScreenState();
}

class _MeasureWallScreenState extends State<MeasureWallScreen>
    with UnitSystemFollower<MeasureWallScreen> {
  final MeasureWallController _controller = MeasureWallController();

  @override
  void applyUnitSystem(UnitSystem system) => _controller.setUnits(system);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: kMeasureWallTitle,
    stage: MeasureWallStage(controller: _controller, stageHeight: 0),
    controls: MeasureWallControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kMeasureWallTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          const UnitSystemSwitch(),
          PresentButton(toolRoute: AppRouter.measureWall, builder: _presenter),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double stageH = ((c.maxWidth - 2 * AppSpacing.lg) * 0.7)
                .clamp(240.0, 380.0);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: _main(
                  edge: AppSpacing.screenEdgeMobile,
                  stageHeight: stageH,
                  withControls: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _main({
    required double edge,
    required double stageHeight,
    required bool withControls,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MeasureWallStage(controller: _controller, stageHeight: stageHeight),
          const SizedBox(height: AppSpacing.sm),
          MeasureWallReadouts(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          MeasureWallPredict(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            WallCard(child: MeasureWallControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const MeasureWallExplainer(),
          const ToolHelpFooter(toolId: kMeasureWallToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double stageH = (c.maxHeight * 0.5).clamp(300.0, 460.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _main(
                edge: AppSpacing.screenEdgeDesktop,
                stageHeight: stageH,
                withControls: false,
              ),
            ),
            Container(
              width: _kPanelWidth,
              decoration: BoxDecoration(
                color: colors.surface1,
                border: Border(left: BorderSide(color: colors.border)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: MeasureWallControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
