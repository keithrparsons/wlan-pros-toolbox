// Channel Planner: Wi-Fi Classroom tool (channel-planner).
//
// Place 2 to 12 APs on a floor, give each a channel and width, and see which
// ones share airtime. Teaches four things (spec 16): APs on one channel that
// hear each other are one contention domain; wider channels leave fewer to
// reuse; 1/6/11 is the 2.4 GHz plan because of the transmit mask; and the
// -82 / -72 / -62 dBm thresholds decide who defers.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/16-channel-planner.md.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets over
// one state object; this screen only composes them.
//   - ChannelPlannerState    (channel_planner_state.dart)   state + analysis
//   - ChannelPlannerStage    (channel_planner_stage.dart)   floor + spectrum
//   - ChannelPlannerControls, ChannelPlannerReadouts
//                            (channel_planner_panels.dart)  inputs, numbers
//   - the math               (services/wifi_lab/channel_planner_model.dart)
// The Present button (desktop and tablet windows) opens the same widgets over
// the SAME state in the presenter layout (lib/widgets/presenter/, spec 00).
//
// LAYOUT: the stage never sits inside a scroll view, so dragging an AP is
// never taken for a scroll. Phone (< 720 px): stage on top, readouts and
// controls scroll below it. Desktop: stage and readouts on the left, controls
// in a side panel.
//
// States (SOP-007 §5):
//   - loading     -> none: on-device arithmetic, no I/O
//   - empty       -> no contending pair: the pairs card says so
//   - error       -> a width with no channel under the rules (160 MHz with
//                    DFS off): APs show "--", a danger note says why and
//                    how to fix it, Auto-plan is disabled
//   - success     -> links, domain outline, readouts
//   - disabled    -> Add at 12 APs, Remove at 2, U-NII-4 in the EU, width
//                    with DSSS
//   - interactive -> tap/drag on the floor; every control is keyboard
//                    reachable with the global focus ring
//
// MOTION (§8.8): none, so reduced motion needs nothing.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'channel_planner_panels.dart';
import 'channel_planner_stage.dart';
import 'channel_planner_state.dart';

export 'channel_planner_state.dart' show kChannelPlannerToolId;

const double _kPanelWidth = 360;

const String _kTitle = 'Channel Planner';

class ChannelPlannerScreen extends StatefulWidget {
  const ChannelPlannerScreen({super.key});

  @override
  State<ChannelPlannerScreen> createState() => _ChannelPlannerScreenState();
}

class _ChannelPlannerScreenState extends State<ChannelPlannerScreen>
    with UnitSystemFollower<ChannelPlannerScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _state.setUnits(system);
  }

  final ChannelPlannerState _state = ChannelPlannerState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's state (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: ChannelPlannerStage(state: _state, maxFloorHeight: double.infinity),
    controls: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ChannelPlannerControls(state: _state),
        ChannelPlannerReadouts(state: _state),
      ],
    ),
    actions: _state.presenterActions,
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
            toolRoute: AppRouter.channelPlanner,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _state.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) =>
              c.maxWidth >= 720 ? _desktop(c) : _phone(c),
        ),
      ),
    );
  }

  Widget _phone(BoxConstraints c) {
    const double edge = AppSpacing.screenEdgeMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(edge, AppSpacing.xs, edge, 0),
          child: ChannelPlannerStage(
            state: _state,
            maxFloorHeight: (c.maxHeight * 0.34).clamp(140.0, 320.0),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ChannelPlannerReadouts(state: _state),
                const SizedBox(height: AppSpacing.sm),
                PlannerCard(child: ChannelPlannerControls(state: _state)),
                const ToolHelpFooter(toolId: kChannelPlannerToolId),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    const double edge = AppSpacing.screenEdgeDesktop;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      edge,
                      AppSpacing.sm,
                      edge,
                      0,
                    ),
                    child: ChannelPlannerStage(
                      state: _state,
                      maxFloorHeight: (c.maxHeight * 0.52).clamp(200.0, 560.0),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        edge,
                        AppSpacing.sm,
                        edge,
                        edge,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ChannelPlannerReadouts(state: _state),
                          const ToolHelpFooter(toolId: kChannelPlannerToolId),
                        ],
                      ),
                    ),
                  ),
                ],
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
                child: ChannelPlannerControls(state: _state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
