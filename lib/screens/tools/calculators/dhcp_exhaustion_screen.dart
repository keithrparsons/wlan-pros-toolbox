// Conference Wi-Fi Runs Out of Addresses: Wi-Fi Classroom tool
// (dhcp-exhaustion).
//
// A conference morning, 07:00 to 13:00. Set the lease time and watch the
// DHCP pool: with a long lease it runs dry mid-morning while the hall is
// half empty, because devices that left still hold their addresses; with a
// short lease it holds. A switch makes devices rotate their private address
// on the open network and come back as new clients (a labeled assumption).
// The lesson (research brief candidate 9): the pool has to cover everyone
// who arrives within one lease time. Corrects "the Wi-Fi is down, add APs".
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 9
// and section 5. Model in lib/services/wifi_lab/dhcp_exhaustion_model.dart
// (RFC 2131 lease mechanics).
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - DhcpExhaustionController (dhcp_exhaustion_controller.dart)
//   - DhcpExhaustionStage      (dhcp_exhaustion_stage.dart)
//   - DhcpExhaustionControls   (dhcp_exhaustion_controls.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller. The large-screen notice is applied
// centrally by the router, from the catalog. No lengths, so no unit switch.
//
// States: see dhcp_exhaustion_controls.dart. MOTION: the playhead jumps,
// nothing tweens.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'dhcp_exhaustion_controller.dart';
import 'dhcp_exhaustion_controls.dart';
import 'dhcp_exhaustion_stage.dart';

export 'dhcp_exhaustion_controller.dart'
    show
        kDhcpExhaustionToolId,
        kDxTick,
        kDxQuestionText,
        DhcpExhaustionController,
        DxQuestion,
        DxGuess;

const String _kTitle = 'Conference Wi-Fi Runs Out of Addresses';

class DhcpExhaustionScreen extends StatefulWidget {
  const DhcpExhaustionScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final DhcpExhaustionController? controller;

  @override
  State<DhcpExhaustionScreen> createState() => _DhcpExhaustionScreenState();
}

class _DhcpExhaustionScreenState extends State<DhcpExhaustionScreen> {
  late final DhcpExhaustionController _controller =
      widget.controller ?? DhcpExhaustionController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: DhcpExhaustionStage(controller: _controller),
    controls: DhcpExhaustionControls(controller: _controller),
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
            toolRoute: AppRouter.dhcpExhaustion,
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
                      DhcpExhaustionStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      DhcpExhaustionControls(controller: _controller),
                      const ToolHelpFooter(toolId: kDhcpExhaustionToolId),
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
