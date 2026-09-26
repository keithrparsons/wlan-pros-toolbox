// Multipath Simulator: Wi-Fi Lab tool (multipath-simulator).
//
// A receiver hears the direct signal plus copies that bounced off walls. Each
// copy arrives later, so with a different phase, and the copies add as
// arrows. Three scenes:
//   1. One wall: the two-ray model. Drag the receiver and watch the reflected
//      arrow swing around the direct one.
//   2. Standing wave: walking toward a wall, the signal drops out every
//      half wavelength.
//   3. Many paths: random reflectors, direct path blocked. The sum fades at
//      random (Rayleigh), and a second antenna half a wavelength away rarely
//      fades at the same spot.
//
// CLEAN-ROOM BUILD (2026-09-25) from wave superposition, the two-ray model and
// Rayleigh fading theory, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/07-multipath.md. All math lives in lib/services/wifi_lab/
// multipath_model.dart.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one MultipathController.
//   - MultipathStage    (multipath_simulator_stage.dart): scene, phasors,
//                       plot, histogram.
//   - MultipathControls (multipath_simulator_controls.dart): inputs and
//                       readouts, in three parts (setup, inputs, readouts).
// This screen only composes them. On a phone they stack: setup and inputs,
// then the stage, then the readouts. A presenter layout can place the stage
// and a full MultipathControls side by side with no change to either.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Numerics in DM
// Mono. Lime marks the measured quantity (resultant arrow, antenna A's trace,
// the histogram, the received-power value); everything else is neutral and
// told apart by weight and dash (§8.15 case 3). The one status hue is the
// guard-interval verdict (§8.13). No new tokens. ASCII copy, no em dashes.
//
// MOTION (§8.8): nothing animates. Every change is a direct redraw in answer
// to the user's own drag or tap, so reduced motion needs no special path.
//
// States (SOP-007 §5):
//   - loading / empty / error -> not reachable: the model is synchronous and
//                    pure, every input is a bounded slider, toggle or select,
//                    and every scene opens with a computed result. An exact
//                    null prints as "null", never -infinity.
//   - success     -> every scene, always
//   - disabled    -> none needed; "Show all paths" appears only when there
//                    are more copies than the short list shows
//   - interactive -> themed Material controls with the global focus ring;
//                    painters carry worded screen-reader labels; dragging a
//                    picture is a shortcut for a slider, never the only way

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'multipath_simulator_controller.dart';
import 'multipath_simulator_controls.dart';
import 'multipath_simulator_stage.dart';

export 'multipath_simulator_controller.dart'
    show MultipathMode, kMultipathSimulatorToolId;

class MultipathSimulatorScreen extends StatefulWidget {
  const MultipathSimulatorScreen({super.key, this.initialMode});

  /// Test seam: open straight into a scene.
  final MultipathMode? initialMode;

  @override
  State<MultipathSimulatorScreen> createState() =>
      _MultipathSimulatorScreenState();
}

class _MultipathSimulatorScreenState extends State<MultipathSimulatorScreen> {
  late final MultipathController _controller = MultipathController(
    initialMode: widget.initialMode ?? MultipathMode.oneWall,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied). The received level and fade figures are on the stage.
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'Multipath Simulator',
    stage: MultipathStage(controller: _controller),
    controls: MultipathControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multipath Simulator'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.multipathSimulator,
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
                      MultipathControls(
                        controller: _controller,
                        parts: const <MultipathControlPart>{
                          MultipathControlPart.setup,
                          MultipathControlPart.inputs,
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MultipathStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      MultipathControls(
                        controller: _controller,
                        parts: const <MultipathControlPart>{
                          MultipathControlPart.readouts,
                        },
                      ),
                      const ToolHelpFooter(toolId: kMultipathSimulatorToolId),
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
