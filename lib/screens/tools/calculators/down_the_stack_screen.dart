// Down the Stack, Across the Air, Up the Other Side: Wi-Fi Classroom tool
// (down-the-stack).
//
// Keith's way of teaching the stack for twenty years, animated: a laptop on
// Wi-Fi sends data to a wired server through an AP and a router. Going down
// the laptop's stack the data gains a port, an IP address, a MAC address and
// becomes bits; it crosses the air as RF; each device climbs only as far as
// it needs and rebuilds layer 2 for the next hop. The IP addresses stay end
// to end (no NAT) while the MAC addresses change on every hop. The address
// view explains To DS / From DS and why an 802.11 frame can carry four
// addresses. Pairs with A Frame's Journey, which opens up the air hop.
//
// CLEAN-ROOM BUILD (2026-09-27) from Keith's brief and Pax's sources (myPKA
// Deliverables/2026-09-27-classroom-interferer-and-ds-sources/RESEARCH-
// BRIEF.md Part 2). All logic lives in lib/services/wifi_lab/
// frame_journey_model.dart, shared with A Frame's Journey. No vendor,
// product or operating-system name appears in any shipped string.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets over
// one DownTheStackController; the Present button opens them side by side in
// the presenter layout over the SAME controller.
//
// THEME: context.colors only; header hues per frame_journey_parts.dart
// (§8.15.2).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'down_the_stack_controller.dart';
import 'down_the_stack_controls.dart';
import 'down_the_stack_stage.dart';

export 'down_the_stack_controller.dart'
    show
        kDownTheStackToolId,
        kDtsStepDuration,
        DownTheStackController,
        DtsView,
        DtsQuestion,
        DtsGuess,
        kDtsQuestionText;

const String _kTitle = 'Down the Stack, Across the Air, Up the Other Side';

class DownTheStackScreen extends StatefulWidget {
  const DownTheStackScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final DownTheStackController? controller;

  @override
  State<DownTheStackScreen> createState() => _DownTheStackScreenState();
}

class _DownTheStackScreenState extends State<DownTheStackScreen> {
  late final DownTheStackController _controller =
      widget.controller ?? DownTheStackController();

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
    title: _kTitle,
    stage: DownTheStackStage(controller: _controller),
    controls: DownTheStackControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.downTheStack, builder: _presenter),
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
                      DownTheStackStage(
                        controller: _controller,
                        diagramHeight: isDesktop ? 340 : 300,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DownTheStackControls(controller: _controller),
                      const ToolHelpFooter(toolId: kDownTheStackToolId),
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
