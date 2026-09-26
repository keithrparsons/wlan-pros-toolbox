// Uplink vs Downlink: Wi-Fi Classroom tool (uplink-downlink).
//
// Both directions of one AP-to-client link at once, and where they diverge.
// The lessons (spec 28): every link is two links; the client usually
// transmits less and has the worse antenna; so there is a zone where the
// client hears the AP but the AP cannot hear the client, which is normal;
// regulations set the client's power relative to the AP's, as a flat number,
// or not at all; and turning the AP down to "match" shrinks the downlink
// cell and does nothing for the uplink.
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/28-uplink-downlink.md.
// Model in lib/services/wifi_lab/uplink_downlink_model.dart, which reuses
// RateVsRangeMath (path loss, sensitivity, noise floor) and SixGhzPsdMath
// (6 GHz limits) without modifying either.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - UplinkDownlinkController (uplink_downlink_controller.dart)
//   - UplinkDownlinkStage      (uplink_downlink_stage.dart)    floor, rings,
//                                                               arrows, legend
//   - UplinkDownlinkControls, UplinkDownlinkExplainer
//                              (uplink_downlink_controls.dart)
//   - UplinkDownlinkReadouts, UplinkDownlinkPredict
//                              (uplink_downlink_readouts.dart)
//   - UdStagePainter           (uplink_downlink_painter.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> none: there is always an AP and a client
//   - error       -> none reachable: every input is a bounded slider, toggle
//                    or select; a ring past the view still reads in the
//                    legend and the readouts
//   - success     -> rings, arrows, both readouts
//   - disabled    -> the client power slider under a regulatory rule (the
//                    rule sets it); "Turn AP down to match" when the AP
//                    already transmits no more than the client, with the
//                    reason in words; "Put the client in the zone" when
//                    there is no zone; widths the band does not allow are
//                    not offered
//   - interactive -> drag or tap the floor to move the client; a distance
//                    slider does the same from the keyboard; themed Material
//                    controls with the global focus ring
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'uplink_downlink_controller.dart';
import 'uplink_downlink_controls.dart';
import 'uplink_downlink_parts.dart';
import 'uplink_downlink_readouts.dart';
import 'uplink_downlink_stage.dart';

export '../../../services/wifi_lab/uplink_downlink_model.dart'
    show kUplinkDownlinkToolId;

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class UplinkDownlinkScreen extends StatefulWidget {
  const UplinkDownlinkScreen({super.key});

  @override
  State<UplinkDownlinkScreen> createState() => _UplinkDownlinkScreenState();
}

class _UplinkDownlinkScreenState extends State<UplinkDownlinkScreen> {
  final UplinkDownlinkController _controller = UplinkDownlinkController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied). Both directions' numbers and the prediction are on the stage.
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'Uplink vs Downlink',
    stage: UplinkDownlinkStage(controller: _controller, stageHeight: 0),
    controls: UplinkDownlinkControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uplink vs Downlink'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.uplinkDownlink,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double stageH = (c.maxWidth - 2 * AppSpacing.lg).clamp(
              240.0,
              420.0,
            );
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
          UplinkDownlinkStage(
            controller: _controller,
            stageHeight: stageHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
          UplinkDownlinkReadouts(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          UplinkDownlinkPredict(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            UdCard(child: UplinkDownlinkControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const UplinkDownlinkExplainer(),
          const ToolHelpFooter(toolId: kUplinkDownlinkToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double stageH = (c.maxHeight * 0.6).clamp(320.0, 560.0);
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
                child: UplinkDownlinkControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
