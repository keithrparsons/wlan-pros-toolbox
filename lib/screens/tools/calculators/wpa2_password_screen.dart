// Why a Long Wi-Fi Password Matters More on WPA2: Wi-Fi Classroom tool
// (wpa2-password).
//
// One control, the network's security (WPA2-Personal, WPA3-Personal with
// SAE, or WPA3 transition mode), with the same short password on each. The
// drawing shows where each password guess is checked: on the attacker's own
// computer after one recorded association (WPA2, and transition mode through
// its WPA2 devices), or only in a live exchange with the AP (WPA3). The
// password's length and characters change the number of possible passwords,
// which is plain arithmetic. No crack times, anywhere.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 6
// and section 5. Source: Wi-Fi Alliance, WPA3 Security Considerations,
// November 2019 (read for this build). The frames themselves are not
// redrawn: the explainer opens Association, Frame by Frame on the WPA2 or
// the WPA3 frames.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets over
// one state object, and this screen only composes them.
//   - Wpa2PasswordController (wpa2_password_controller.dart)
//   - Wpa2PasswordStage, Wpa2PasswordReadouts, Wpa2PasswordPredict
//                            (wpa2_password_stage.dart)
//   - Wpa2PasswordControls, Wpa2PasswordExplainer
//                            (wpa2_password_controls.dart)
//   - WpStagePainter         (wpa2_password_painter.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller. The large-screen notice is applied
// centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> no guesses yet: both counters read 0, and the drawing
//                    still shows where a guess would be checked
//   - error       -> none reachable: every input is a bounded selector or
//                    slider, and the length clamps to 8 to 63
//   - success     -> drawing, readouts, prediction
//   - disabled    -> none: every control applies on every setting
//   - interactive -> security toggle, length slider, character menu, guess
//                    buttons, reveal; themed Material controls with the
//                    global focus ring
//
// MOTION (§8.8): one dot moves along the guess path while guessing. With the
// platform's reduce-motion setting on, the dot is not drawn and the counters
// still count.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'wpa2_password_controller.dart';
import 'wpa2_password_controls.dart';
import 'wpa2_password_parts.dart';
import 'wpa2_password_stage.dart';

export '../../../services/wifi_lab/wpa2_password_model.dart'
    show kWpa2PasswordToolId;

/// Catalog and app-bar title.
const String kWpa2PasswordTitle =
    'Why a Long Wi-Fi Password Matters More on WPA2';

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class Wpa2PasswordScreen extends StatefulWidget {
  const Wpa2PasswordScreen({super.key});

  @override
  State<Wpa2PasswordScreen> createState() => _Wpa2PasswordScreenState();
}

class _Wpa2PasswordScreenState extends State<Wpa2PasswordScreen> {
  final Wpa2PasswordController _controller = Wpa2PasswordController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: kWpa2PasswordTitle,
    stage: Wpa2PasswordStage(controller: _controller, stageHeight: 0),
    controls: Wpa2PasswordControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kWpa2PasswordTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.wpa2Password, builder: _presenter),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double stageH = ((c.maxWidth - 2 * AppSpacing.lg) * 0.8)
                .clamp(260.0, 380.0);
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
          Wpa2PasswordStage(controller: _controller, stageHeight: stageHeight),
          const SizedBox(height: AppSpacing.sm),
          Wpa2PasswordReadouts(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          Wpa2PasswordPredict(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            WpCard(child: Wpa2PasswordControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Wpa2PasswordExplainer(),
          const ToolHelpFooter(toolId: kWpa2PasswordToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double stageH = (c.maxHeight * 0.5).clamp(320.0, 480.0);
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
                child: Wpa2PasswordControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
