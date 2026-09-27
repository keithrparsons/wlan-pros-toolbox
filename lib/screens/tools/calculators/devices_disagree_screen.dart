// Why Two Devices Disagree About Signal: Wi-Fi Classroom tool
// (devices-disagree).
//
// The true power at one spot is held fixed, and up to four generic devices
// standing side by side report it. Each reading is the true power plus the
// device's own fixed offset, minus how it is held and any body in the way,
// plus fading at the exact point its antenna sits, averaged and rounded the
// way that device reports. The lessons (spec 31): RSSI is each chipset's own
// number; the difference has a fixed part and a changing part; a survey
// tool's per-adapter offset removes the fixed part and nothing else; 802.11k
// RCPI exists as a standardized measurement (concept only here).
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/31-devices-disagree.md.
// All math is in lib/services/wifi_lab/devices_disagree_model.dart: path
// loss reuses the Roaming Walk engine, fading reuses the Multipath
// Simulator's Rayleigh scene. No device, vendor or product is named.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one controller, and this screen only composes them.
//   - DevicesDisagreeController (devices_disagree_controller.dart)
//   - DevicesDisagreeStage      (devices_disagree_stage.dart): predict card,
//                               floor, device cards, strip chart, readouts
//   - DevicesDisagreeControls, DevicesDisagreeExplainer
//                               (devices_disagree_controls.dart)
//   - DdFloorPainter, DdStripPainter (devices_disagree_painters.dart)
// The Present button (tablet and computer windows) puts the stage beside the
// controls over the SAME controller (lib/widgets/presenter/). Keys: Space
// re-samples, R resets, Up and Down move the AP a meter.
//
// LAYOUT: at 720 px and up the controls are a side panel; below it
// everything stacks in one scroll (the large-screen notice, applied in the
// router, comes first on a phone).
//
// States (SOP-007 §5):
//   - loading / empty / error -> not reachable: the model is synchronous,
//                    pure and seeded; every input is a bounded slider,
//                    toggle, switch or select, and at least two devices are
//                    always in use, so there is always a run to show
//   - success     -> every setting
//   - disabled    -> none needed: every control applies at all times
//   - interactive -> themed Material controls with the global focus ring;
//                    painters carry worded screen-reader labels, and every
//                    number they draw is also a text readout
//
// MOTION (§8.8): none. A run is computed at once; Re-sample redraws.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'devices_disagree_controller.dart';
import 'devices_disagree_controls.dart';
import 'devices_disagree_parts.dart';
import 'devices_disagree_stage.dart';

export 'devices_disagree_controller.dart'
    show kDevicesDisagreeToolId, kDevicesDisagreeTitle;

/// Side panel width on desktop, matching the other Classroom tools.
const double _kPanelWidth = 380;

class DevicesDisagreeScreen extends StatefulWidget {
  const DevicesDisagreeScreen({super.key});

  @override
  State<DevicesDisagreeScreen> createState() => _DevicesDisagreeScreenState();
}

class _DevicesDisagreeScreenState extends State<DevicesDisagreeScreen>
    with UnitSystemFollower<DevicesDisagreeScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  final DevicesDisagreeController _controller = DevicesDisagreeController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied). The readouts are on the stage.
  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: kDevicesDisagreeTitle,
    stage: DevicesDisagreeStage(controller: _controller),
    controls: DevicesDisagreeControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kDevicesDisagreeTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          const UnitSystemSwitch(),
          PresentButton(
            toolRoute: AppRouter.devicesDisagree,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop();
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: _main(
                  edge: AppSpacing.screenEdgeMobile,
                  withControls: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _main({required double edge, required bool withControls}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DevicesDisagreeStage(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            DdCard(child: DevicesDisagreeControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const DevicesDisagreeExplainer(),
          const ToolHelpFooter(toolId: kDevicesDisagreeToolId),
        ],
      ),
    );
  }

  Widget _desktop() {
    final AppColorScheme colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _main(
                edge: AppSpacing.screenEdgeDesktop,
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
                child: DevicesDisagreeControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
