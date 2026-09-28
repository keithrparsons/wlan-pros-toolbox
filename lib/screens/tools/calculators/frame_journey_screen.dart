// A Frame's Journey: Wi-Fi Classroom tool (frame-journey).
//
// The bottom layer of Down the Stack, opened up: the laptop's air frame (the
// same frame object) goes from the transmitting NIC to the receiving one.
// Bits become RF, cross a distance at one unchanging frequency, and are
// decoded. A capturing receiver puts a radiotap header in front of the frame
// (never sent over the air). The receiver checks the FCS, a real CRC-32 over
// the frame's bytes, and only then, after SIFS, sends the ACK. Flip one bit
// and the FCS fails, no ACK comes back and the sender retries.
//
// CLEAN-ROOM BUILD (2026-09-27) from Keith's brief and Pax's sources (myPKA
// Deliverables/2026-09-27-classroom-interferer-and-ds-sources/RESEARCH-
// BRIEF.md Part 2). Logic in lib/services/wifi_lab/frame_journey_model.dart,
// shared with Down the Stack. No vendor or product names in shipped strings.
//
// STRUCTURE: stage and controls over one FrameJourneyController; Present
// opens them side by side over the SAME controller.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/unit_system_switch.dart';
import 'frame_journey_controller.dart';
import 'frame_journey_controls.dart';
import 'frame_journey_stage.dart';

export 'frame_journey_controller.dart'
    show
        kFrameJourneyToolId,
        kFhStepDuration,
        kFhDefaultFlipBit,
        FrameJourneyController,
        FhQuestion,
        FhGuess,
        kFhQuestionText;

const String _kTitle = 'A Frame\'s Journey';

class FrameJourneyScreen extends StatefulWidget {
  const FrameJourneyScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes.
  final FrameJourneyController? controller;

  @override
  State<FrameJourneyScreen> createState() => _FrameJourneyScreenState();
}

class _FrameJourneyScreenState extends State<FrameJourneyScreen>
    with UnitSystemFollower<FrameJourneyScreen> {
  late final FrameJourneyController _controller =
      widget.controller ?? FrameJourneyController();

  @override
  void applyUnitSystem(UnitSystem system) => _controller.setUnits(system);

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

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: FrameJourneyStage(controller: _controller),
    controls: FrameJourneyControls(controller: _controller),
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
          PresentButton(toolRoute: AppRouter.frameJourney, builder: _presenter),
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
                      FrameJourneyStage(
                        controller: _controller,
                        drawingHeight: isDesktop ? 250 : 220,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FrameJourneyControls(controller: _controller),
                      const ToolHelpFooter(toolId: kFrameJourneyToolId),
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
