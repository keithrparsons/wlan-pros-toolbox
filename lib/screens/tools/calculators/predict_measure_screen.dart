// Predict, Then Measure: Wi-Fi Classroom tool (predict-then-measure).
//
// A predictive design is a model: walls with assumed losses, an AP, a
// computed heat map. An AP-on-a-stick survey (a temporary AP placed where
// the design says, measured on site) tests those assumptions. What the
// student should see (spec 32):
//   1. Every wall loss in a predictive design is a claim.
//   2. Where predicted and measured disagree, the wall is not what the model
//      assumed.
//   3. You only learn a wall's real loss by measuring on both sides of it
//      (Keith's Rule 5). A walk that stays on one side cannot find it.
//   4. After correcting the model, the design may need an AP moved, added
//      or removed.
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/32-predict-then-measure.md. All math lives in
// lib/services/wifi_lab/predict_measure_engine.dart, which reuses Heat Map
// Builder's floor, wall crossing, sampling and IDW. Every wall loss is an
// illustrative, adjustable value; no product is named or implied.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets over one PredictMeasureController.
//   - PredictMeasureStage    (predict_measure_stage.dart): prompt, floor,
//                            maps, walk, legend.
//   - PredictMeasureControls (predict_measure_controls.dart): walk,
//                            readouts, update and reveal, wall losses, AP,
//                            scenario, instructor truth.
// This screen only composes them. The Present button (desktop and tablet
// windows) puts the stage beside the controls over the SAME controller
// (lib/widgets/presenter/, spec 00).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The floor is the
// GL-003 §8.22 brand-green heat map on the dark coverage viewport in both
// themes (lib/theme/app_coverage_ramp.dart, as Heat Map Builder), with its
// legend; white with a hatch is reserved for no data. Lime marks the walk
// and its samples, the measured quantity.
//
// MOTION (§8.8): nothing animates. Every change is a redraw in answer to the
// user's own drag, tap or control, so reduced motion needs no special path.
//
// States (SOP-007 §5):
//   - empty       -> no walk: the Measured and Difference maps are white (no
//                    data), every wall reads "untested", the readouts say
//                    "no data", Undo and Clear are disabled, and a note says
//                    how to walk
//   - success     -> the maps, the wall badges, the readouts, the prompt
//   - full        -> at kPmMaxSamples the walk stops growing and says so
//   - disabled    -> Update model until a tested wall disagrees with the
//                    design; the material-default button when the wall is
//                    already at its default
//   - loading / error -> not reachable: the engine is synchronous and pure,
//                    and every input is a bounded slider, toggle, select or
//                    button
//   - interactive -> themed Material controls with the global focus ring;
//                    the floor and legend carry worded screen-reader labels;
//                    every drag on the floor has a button or slider
//                    equivalent (preset walks, AP sliders)

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'heat_map_builder_parts.dart';
import 'predict_measure_controller.dart';
import 'predict_measure_controls.dart';
import 'predict_measure_stage.dart';

export 'predict_measure_controller.dart' show kPredictMeasureToolId;

const String _kTitle = 'Predict, Then Measure';

class PredictMeasureScreen extends StatefulWidget {
  const PredictMeasureScreen({super.key, this.controller});

  /// Test seam: drive the screen from a given controller (not disposed here).
  final PredictMeasureController? controller;

  @override
  State<PredictMeasureScreen> createState() => _PredictMeasureScreenState();
}

class _PredictMeasureScreenState extends State<PredictMeasureScreen>
    with UnitSystemFollower<PredictMeasureScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  late final PredictMeasureController _controller =
      widget.controller ?? PredictMeasureController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: PredictMeasureStage(controller: _controller),
    controls: PredictMeasureControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          const UnitSystemSwitch(),
          PresentButton(
            toolRoute: AppRouter.predictThenMeasure,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      PredictMeasureStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      PredictMeasureControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kPredictMeasureToolId),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return HmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const HmSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A teaching model. Signal is a log-distance path-loss model '
            'plus the loss of every wall on the straight line from the AP. '
            'Wall losses, the material defaults, the scenarios and the '
            'noise are all illustrative, adjustable values, not measured '
            'material data. Doors, reflections and floors above and below '
            'are left out.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A wall counts as tested when two neighboring samples on one '
            'walk leg sit on either side of it. Its measured loss is the '
            'drop between them, corrected for the extra distance with the '
            'design\'s path-loss exponent.',
            style: body,
          ),
        ],
      ),
    );
  }
}
