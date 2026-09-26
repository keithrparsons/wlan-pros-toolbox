// Room Propagation: Wi-Fi Lab tool (room-propagation).
//
// A top-down floor plan with an AP, walls and doorways, and a heat map of the
// received power. The student sees four things (spec):
//   1. The signal in a room is the direct path plus reflections; walls both
//      pass and reflect energy.
//   2. Doorways and wall ends bend signal into shadows (diffraction), less at
//      2.4 GHz than at 6 GHz.
//   3. Why 6 GHz loses more, split into its parts: free-space loss (the
//      antenna aperture), wall absorption and diffraction.
//   4. Moving a few centimeters changes RSSI: nulls repeat every half
//      wavelength near a reflector (the close-up).
//
// CLEAN-ROOM BUILD (2026-09-25) from ITU-R P.2040 and P.526 as set out in
// myPKA Deliverables/2026-09-25-wifi-lab-research/brief.md §6.3 and §6.5, per
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/10-room-propagation.md. All
// physics lives in lib/services/wifi_lab/room_propagation_model.dart; every
// wall's T and R come from wall_slab_physics.dart (unchanged).
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets over one RoomPropagationController.
//   - RoomPropagationStage     (room_propagation_stage.dart): plan, heat map,
//                              legends, close-up.
//   - RoomPresetPicker, RoomPropagationControls, RoomPropagationReadouts
//                              (room_propagation_controls.dart).
// This screen only composes them. On a phone they stack: preset, stage,
// readouts, controls. The Present button (desktop and tablet windows) puts
// the stage beside the controls over the SAME controller
// (lib/widgets/presenter/).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The plan is the
// §8.22 brand-green heat map on a dark viewport in both themes
// (lib/theme/app_coverage_ramp.dart), always with its dBm legend. Wall hues
// per §8.15.2, always labeled in the legend. Lime marks the received power.
//
// MOTION (§8.8): nothing animates. Every change is a redraw in answer to the
// user's own drag, tap or control, so reduced motion needs no special path,
// and no drawing can suggest the frequency changed (Wi-Fi Lab standing rule).
//
// States (SOP-007 §5):
//   - loading     -> "Computing" beside the plan title while a map is on its
//                    way; before the first map, the plan shows walls and
//                    markers on an empty viewport labeled "Computing the map"
//   - empty       -> the Empty plan preset: no walls, free space; the wall
//                    list says "No walls yet" and the readouts say "none"
//   - error       -> a failed map run shows the reason and "Try again"; a
//                    thickness outside 1-500 mm shows inline field error text
//                    and the wall keeps its last valid value; an edit that
//                    cannot happen (too short, too many walls, no wall under
//                    the tap, door overlap) says why in one line
//   - success     -> the map, the close-up and every readout
//   - disabled    -> the doorway and delete buttons are disabled until a
//                    wall is selected; "Close its doorways" until it has one
//   - interactive -> themed Material controls with the global focus ring;
//                    the plan and close-up carry worded Semantics labels;
//                    every plan gesture has a slider or list equivalent

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'room_propagation_controller.dart';
import 'room_propagation_controls.dart';
import 'room_propagation_stage.dart';

export 'room_propagation_controller.dart'
    show kRoomPropagationToolId, RoomFieldRunner;

class RoomPropagationScreen extends StatefulWidget {
  const RoomPropagationScreen({super.key, this.runner, this.presetIndex = 0});

  /// Test seam: how a map job runs. Defaults to a background isolate.
  final RoomFieldRunner? runner;

  /// Test seam: which plan to open with.
  final int presetIndex;

  @override
  State<RoomPropagationScreen> createState() => _RoomPropagationScreenState();
}

class _RoomPropagationScreenState extends State<RoomPropagationScreen> {
  late final RoomPropagationController _controller = RoomPropagationController(
    runner: widget.runner,
    presetIndex: widget.presetIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'Room Propagation',
    stage: RoomPropagationStage(controller: _controller),
    controls: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The client readout is on the stage in presenter mode.
        RoomPresetPicker(controller: _controller),
        const SizedBox(height: AppSpacing.xs),
        RoomPropagationControls(controller: _controller),
      ],
    ),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Propagation'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.roomPropagation,
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
                      RoomPresetPicker(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      RoomPropagationStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      RoomPropagationReadouts(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      RoomPropagationControls(controller: _controller),
                      const ToolHelpFooter(toolId: kRoomPropagationToolId),
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
