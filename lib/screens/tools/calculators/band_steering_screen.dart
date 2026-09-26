// Band Steering: Wi-Fi Classroom tool (band-steering).
//
// One dual-band AP and a client walking a line toward it or away from it.
// The client chooses the band; the AP can only hide (stop answering
// broadcast probes on 2.4 GHz), refuse (reject authentication on 2.4 GHz) or
// suggest (a BSS Transition Management request naming 5 GHz), and none of
// the three stops the 2.4 GHz beacons. Three generic clients follow
// published rule sets, and the rules themselves explain the sticky
// 2.4 GHz client. Pairs with Roaming Walk, whose log-distance model it
// reuses: that tool is APs on one band, this one is bands on one AP.
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/38-band-steering.md. All logic lives in
// lib/services/wifi_lab/band_steering_model.dart. No vendor, product or
// operating-system name appears in any shipped string (Keith, 2026-09-26);
// the sources are named in that file's comments only.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one BandSteeringController.
//   - BandSteeringStage    (band_steering_stage.dart)
//   - BandSteeringControls (band_steering_controls.dart)
// This screen only composes them. On a phone they stack; the Present button
// (desktop and tablet windows) opens the stage beside the controls over the
// SAME controller in the presenter layout (lib/widgets/presenter/).
//
// THEME: context.colors only (dark §8 / light §8.20); band hues per
// band_steering_parts.dart (§8.15.2).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';
import 'band_steering_controller.dart';
import 'band_steering_controls.dart';
import 'band_steering_stage.dart';

export 'band_steering_controller.dart'
    show
        kBandSteeringToolId,
        kBsStepDuration,
        BandSteeringController,
        BsQuestion,
        BsGuess,
        kBsQuestionText;

const String _kTitle = 'Band Steering';

class BandSteeringScreen extends StatefulWidget {
  const BandSteeringScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final BandSteeringController? controller;

  @override
  State<BandSteeringScreen> createState() => _BandSteeringScreenState();
}

class _BandSteeringScreenState extends State<BandSteeringScreen> {
  late final BandSteeringController _controller =
      widget.controller ?? BandSteeringController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: BandSteeringStage(controller: _controller),
    controls: BandSteeringControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.bandSteering, builder: _presenter),
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
                      BandSteeringStage(
                        controller: _controller,
                        floorHeight: isDesktop ? 320 : 260,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      BandSteeringControls(controller: _controller),
                      const ToolHelpFooter(toolId: kBandSteeringToolId),
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
