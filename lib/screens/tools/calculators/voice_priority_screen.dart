// Voice Priority, End to End: Wi-Fi Classroom tool (voice-priority).
//
// A voice packet marked EF travels toward a phone on Wi-Fi. Pick where the
// marking is lost (nowhere, at the AP mapping, at the tunnel, at the
// internet provider) and watch the call drop from the Voice queue to Best
// effort, where it waits behind a download. The lesson (research brief
// candidate 3): a call gets the voice lane on Wi-Fi only if its marking
// survives every hop; turning on WMM does not do it, and priority set on
// your own network does not reach across the internet.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 3
// and section 5. Model in lib/services/wifi_lab/voice_priority_model.dart,
// which reuses the Medium Access Simulator's engine for the Wi-Fi hop rather
// than rebuilding EDCA (anti-pattern 4).
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - VoicePriorityController (voice_priority_controller.dart)
//   - VoicePriorityStage      (voice_priority_stage.dart)
//   - VoicePriorityControls   (voice_priority_controls.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller. The large-screen notice is applied
// centrally by the router, from the catalog. No lengths, so no unit switch.
//
// States: see voice_priority_controls.dart. MOTION: the packet jumps hop to
// hop, nothing tweens.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'voice_priority_controller.dart';
import 'voice_priority_controls.dart';
import 'voice_priority_stage.dart';

export 'voice_priority_controller.dart'
    show
        kVoicePriorityToolId,
        kVpHopDuration,
        kVpQuestionText,
        VoicePriorityController,
        VpQuestion,
        VpGuess;

const String _kTitle = 'Voice Priority, End to End';

class VoicePriorityScreen extends StatefulWidget {
  const VoicePriorityScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final VoicePriorityController? controller;

  @override
  State<VoicePriorityScreen> createState() => _VoicePriorityScreenState();
}

class _VoicePriorityScreenState extends State<VoicePriorityScreen> {
  late final VoicePriorityController _controller =
      widget.controller ?? VoicePriorityController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: VoicePriorityStage(controller: _controller),
    controls: VoicePriorityControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.voicePriority,
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
                      VoicePriorityStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      VoicePriorityControls(controller: _controller),
                      const ToolHelpFooter(toolId: kVoicePriorityToolId),
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
