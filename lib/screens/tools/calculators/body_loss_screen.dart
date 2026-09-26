// Body Loss: Wi-Fi Classroom tool (body-loss).
//
// What the human body costs a Wi-Fi link. The lessons (spec 34): a person
// between the device and the AP costs decibels, and the one holding the
// device often costs the most; the loss depends on which way the holder
// faces; crowds add up, which is why the empty-building survey reads better
// than the occupied building; and higher bands generally lose more to the
// body. Every loss value is an illustrative, adjustable setting.
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/34-body-loss.md.
// Model in lib/services/wifi_lab/body_loss_model.dart, which reuses
// RateVsRangeMath (log-distance path loss over FsplMath.logDistanceDb, and
// the MCS lookup) without modifying it.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - BodyLossController (body_loss_controller.dart)
//   - BodyLossStage      (body_loss_stage.dart)     floor, gauge, legend
//   - BodyLossControls, BodyLossExplainer
//                        (body_loss_controls.dart)
//   - BodyLossReadouts, BodyLossPredict
//                        (body_loss_readouts.dart)
//   - BlStagePainter     (body_loss_painter.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> the empty building (the crowd toggled off) and a crowd
//                    of zero are both first-class states, said in words on
//                    the floor, in the legend and in the readouts; nobody on
//                    the line says so and suggests dragging a person onto it
//   - error       -> none reachable: every input is a bounded slider, toggle
//                    or button, and the model clamps and rejects non-finite
//                    values; a level below MCS 0 reads "Below MCS 0"
//   - success     -> floor, gauge, readouts, prediction
//   - disabled    -> the crowd-size slider and Scatter while the building is
//                    empty (with the reason in words); Scatter with no crowd
//   - interactive -> drag the holder or a person, tap to turn the holder;
//                    the holder-position and facing sliders do the same from
//                    the keyboard; themed Material controls with the global
//                    focus ring
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'body_loss_controller.dart';
import 'body_loss_controls.dart';
import 'body_loss_parts.dart';
import 'body_loss_readouts.dart';
import 'body_loss_stage.dart';

export '../../../services/wifi_lab/body_loss_model.dart' show kBodyLossToolId;

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class BodyLossScreen extends StatefulWidget {
  const BodyLossScreen({super.key});

  @override
  State<BodyLossScreen> createState() => _BodyLossScreenState();
}

class _BodyLossScreenState extends State<BodyLossScreen> {
  final BodyLossController _controller = BodyLossController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied). The readouts and the prediction are on the stage.
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'Body Loss',
    stage: BodyLossStage(controller: _controller, stageHeight: 0),
    controls: BodyLossControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Body Loss'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.bodyLoss, builder: _presenter),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double stageH = ((c.maxWidth - 2 * AppSpacing.lg) * 0.62)
                .clamp(200.0, 360.0);
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
          BodyLossStage(controller: _controller, stageHeight: stageHeight),
          const SizedBox(height: AppSpacing.sm),
          BodyLossReadouts(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          BodyLossPredict(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            BlCard(child: BodyLossControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const BodyLossExplainer(),
          const ToolHelpFooter(toolId: kBodyLossToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double stageH = (c.maxHeight * 0.55).clamp(300.0, 520.0);
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
                child: BodyLossControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
