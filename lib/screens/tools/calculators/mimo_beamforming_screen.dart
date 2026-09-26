// MIMO and Beamforming: Wi-Fi Classroom tool (mimo-beamforming).
//
// Teaches four things (Keith, 2026-09-25, spec 06):
//   1. Streams are capped by the smaller side: Nss = min(AP, client).
//   2. Spare chains still help: transmit beamforming on the downlink,
//      receive combining on the uplink; Swap shows the vice versa case.
//   3. Beamforming costs airtime: NDPA, NDP and the compressed report.
//   4. A local capture is not the AP's view: the sniffer is off the beam and
//      may have too few chains; our own measurement shows the effect.
//
// CLEAN-ROOM BUILD (2026-09-25) from MIMO fundamentals and the 802.11
// sounding frame formats, per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/06-mimo-beamforming.md. Capture figures ONLY from
// Deliverables/2026-08-19-beamforming-blinds-the-sniffer/NUMBER-AUDIT.md.
// All math lives in lib/services/wifi_lab/mimo_beamforming_model.dart.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one MimoController.
//   - MimoStage    (mimo_beamforming_stage.dart): streams, beam pattern,
//                  sounding exchange.
//   - MimoControls (mimo_beamforming_controls.dart): inputs and readouts, in
//                  three parts (setup, inputs, readouts).
// This screen only composes them. On a phone they stack: setup, then the
// stage, then inputs and readouts. The Present button (desktop and tablet
// windows) opens the stage and a full MimoControls side by side over the
// SAME controller in the presenter layout (lib/widgets/presenter/, spec 00).
// Keys: Up and Down steer the client 5 degrees, R resets.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Numerics in DM
// Mono. Streams take the §8.15.2 stream palette (mimo_beamforming_palette
// .dart), each labeled. Lime marks the steered beam, the sounding share and
// the headline numbers. The one status hue is the "sniffer cannot separate
// the streams" verdict (§8.13). ASCII copy, no em dashes.
//
// MOTION (§8.8): nothing animates. Every change is a direct redraw in answer
// to the user's own drag or tap, so reduced motion needs no special path.
//
// States (SOP-007 §5):
//   - loading / empty / error -> not reachable: the model is synchronous and
//                    pure, and every input is a bounded select, toggle or
//                    slider; the screen opens on a computed 4x4 to 2x2 link.
//   - success     -> always
//   - disabled    -> beamforming toggle with a 1-chain AP (with the reason in
//                    words); sounding interval slider while there is no
//                    sounding; the sounding card says why it is empty
//   - interactive -> themed Material controls with the global focus ring;
//                    painters carry worded screen-reader labels; dragging the
//                    pattern is a shortcut for the angle sliders, never the
//                    only way

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/mimo_beamforming_model.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'mimo_beamforming_controller.dart';
import 'mimo_beamforming_controls.dart';
import 'mimo_beamforming_stage.dart';

export 'mimo_beamforming_controller.dart' show kMimoBeamformingToolId;

class MimoBeamformingScreen extends StatefulWidget {
  const MimoBeamformingScreen({
    super.key,
    this.initialApChains = 4,
    this.initialClientChains = 2,
    this.initialDirection = LinkDirection.downlink,
  });

  /// Test seams: open on a given link.
  final int initialApChains;
  final int initialClientChains;
  final LinkDirection initialDirection;

  @override
  State<MimoBeamformingScreen> createState() => _MimoBeamformingScreenState();
}

class _MimoBeamformingScreenState extends State<MimoBeamformingScreen> {
  late final MimoController _controller = MimoController(
    apChains: widget.initialApChains,
    clientChains: widget.initialClientChains,
    initialDirection: widget.initialDirection,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied). Every control part in one column beside the stage.
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'MIMO and Beamforming',
    stage: MimoStage(controller: _controller),
    controls: MimoControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Scales down rather than truncating at phone width; the catalog
        // title is fixed.
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('MIMO and Beamforming'),
        ),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.mimoBeamforming,
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
                      MimoControls(
                        controller: _controller,
                        parts: const <MimoControlPart>{MimoControlPart.setup},
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      MimoStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      MimoControls(
                        controller: _controller,
                        parts: const <MimoControlPart>{
                          MimoControlPart.inputs,
                          MimoControlPart.readouts,
                        },
                      ),
                      const ToolHelpFooter(toolId: kMimoBeamformingToolId),
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
