// Heat Map Builder: Wi-Fi Classroom tool (heat-map-builder).
//
// The student places survey samples on a floor and watches a heat map get
// built from them. What they should see (spec 27):
//   1. A heat map is mostly guesses. Only the dots are measurements.
//   2. Inverse distance weighting (IDW) fills each cell with a weighted
//      average of nearby samples; the power decides how local the guess is.
//   3. IDW never goes outside the range of its samples, so past the last
//      point it goes flat while the real signal keeps falling. A propagation
//      model can extrapolate, but cannot see a wall no one measured across.
//   4. Closer samples help up to a point; below that, noise on single
//      readings limits accuracy unless readings are averaged.
//   5. The guess range decides how far the map may guess. Beyond it the map
//      is white: no data, not no coverage.
//
// CLEAN-ROOM BUILD (2026-09-26) from the Wi-Fi Classroom wave 4 research
// brief §4 and §5, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/27-heat-map-builder.md. All math lives in lib/services/wifi_lab/
// heat_map_builder_engine.dart, behind the HmInterpolator interface so the
// method can be swapped when Keith's own description of heat-map generation
// arrives. The tool teaches documented methods and never names or implies a
// survey product's algorithm.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets over one HeatMapBuilderController.
//   - HeatMapBuilderStage    (heat_map_builder_stage.dart): floor, map,
//                            legend, inspector, lesson prompt, spacing plot.
//   - HeatMapBuilderControls (heat_map_builder_controls.dart): samples,
//                            readouts, method, noise, lesson, worked
//                            example, floor.
// This screen only composes them. The Present button (desktop and tablet
// windows) puts the stage beside the controls over the SAME controller
// (lib/widgets/presenter/, spec 00).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The floor is the
// GL-003 §8.22 brand-green heat map on the dark coverage viewport in both
// themes (lib/theme/app_coverage_ramp.dart, as Room Propagation), with its dB
// legend; white with a hatch is reserved for no data. Lime marks the samples,
// the measured quantity.
//
// MOTION (§8.8): nothing animates. Every change is a redraw in answer to the
// user's own tap or control, so reduced motion needs no special path.
//
// States (SOP-007 §5):
//   - empty       -> no samples: the whole floor is white (no data), the
//                    readouts say "no data" and a note says how to add
//                    samples; Undo and Clear are disabled
//   - success     -> the map, the readouts, the inspector and the plot
//   - full        -> at kHmMaxSamples a tap adds nothing and the count says
//                    the floor is full
//   - disabled    -> Power with nearest neighbor; Take the samples again
//                    with no noise or no samples
//   - loading / error -> not reachable: the engine is synchronous and pure
//                    (a 1 m grid maps in about 30 ms), and every input is a
//                    bounded slider, toggle, select or button
//   - interactive -> themed Material controls with the global focus ring;
//                    the floor, legend, worked example and plot carry worded
//                    screen-reader labels; every tap on the floor has a
//                    button or slider equivalent

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'heat_map_builder_controller.dart';
import 'heat_map_builder_controls.dart';
import 'heat_map_builder_parts.dart';
import 'heat_map_builder_stage.dart';

export 'heat_map_builder_controller.dart' show kHeatMapBuilderToolId;

const String _kTitle = 'Heat Map Builder';

class HeatMapBuilderScreen extends StatefulWidget {
  const HeatMapBuilderScreen({super.key, this.controller});

  /// Test seam: drive the screen from a given controller (not disposed here).
  final HeatMapBuilderController? controller;

  @override
  State<HeatMapBuilderScreen> createState() => _HeatMapBuilderScreenState();
}

class _HeatMapBuilderScreenState extends State<HeatMapBuilderScreen>
    with UnitSystemFollower<HeatMapBuilderScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  late final HeatMapBuilderController _controller =
      widget.controller ?? HeatMapBuilderController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: HeatMapBuilderStage(controller: _controller),
    controls: HeatMapBuilderControls(controller: _controller),
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
            toolRoute: AppRouter.heatMapBuilder,
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
                      HeatMapBuilderStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      HeatMapBuilderControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kHeatMapBuilderToolId),
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
            'A teaching model. The truth is a log-distance path-loss model '
            'plus wall losses, and the map shows the strongest AP. Each '
            'method here is one documented method from the interpolation '
            'literature. No survey product publishes its heat-map '
            'algorithm, so none of them is shown as any product\'s method.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Measurement noise is illustrative: each reading wanders around '
            'the true level by the sigma you set. Real fading, antennas, '
            'the adapter and the survey software all add their own error.',
            style: body,
          ),
        ],
      ),
    );
  }
}
