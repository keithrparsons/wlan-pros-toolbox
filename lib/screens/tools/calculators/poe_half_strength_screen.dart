// PoE: Why the New AP Runs at Half Strength: Wi-Fi Classroom tool
// (poe-half-strength).
//
// One control, the switch port type (802.3af, 802.3at or 802.3bt), feeding a
// generic tri-band Wi-Fi 7 AP (three radios, each 4x4, about 29 W for full
// function). The drawing shows which radios and spatial streams stay live on
// each port, and that the power light is on in every case. On 802.3at the AP
// runs either three radios at 2x2 or two radios at 4x4, both from one
// published vendor guide; the 802.3af case is illustrative and says so.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate
// 10 and section 5. Sources (read for this build, named in help only as the
// brief asks): Juniper Mist, Wi-Fi 7 AP guide; Cisco Meraki, Wi-Fi 7
// (802.11be) Technical Guide. Port power per IEEE 802.3, the same figures as
// the PoE Reference tool.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets over
// one state object, and this screen only composes them.
//   - PoeHalfStrengthController (poe_half_strength_controller.dart)
//   - PoeHalfStrengthStage, PoeHalfStrengthReadouts, PoeHalfStrengthPredict
//                               (poe_half_strength_stage.dart)
//   - PoeHalfStrengthControls, PoeHalfStrengthExplainer
//                               (poe_half_strength_controls.dart)
//   - PhStagePainter            (poe_half_strength_painter.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller. The large-screen notice is applied
// centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device lookup, no I/O
//   - empty       -> 802.3af: no radio live (illustrative), said in words on
//                    the drawing, in the readouts and in a note
//   - error       -> none reachable: every input is a bounded toggle
//   - success     -> drawing, readouts, prediction
//   - disabled    -> the 802.3at choice on 802.3af and 802.3bt ports, with
//                    the reason in words beside it
//   - interactive -> port toggle, 802.3at choice, reveal; themed Material
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
import 'poe_half_strength_controller.dart';
import 'poe_half_strength_controls.dart';
import 'poe_half_strength_parts.dart';
import 'poe_half_strength_stage.dart';

export '../../../services/wifi_lab/poe_half_strength_model.dart'
    show kPoeHalfStrengthToolId;

/// Catalog and app-bar title.
const String kPoeHalfStrengthTitle =
    'PoE: Why the New AP Runs at Half Strength';

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class PoeHalfStrengthScreen extends StatefulWidget {
  const PoeHalfStrengthScreen({super.key});

  @override
  State<PoeHalfStrengthScreen> createState() => _PoeHalfStrengthScreenState();
}

class _PoeHalfStrengthScreenState extends State<PoeHalfStrengthScreen> {
  final PoeHalfStrengthController _controller = PoeHalfStrengthController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: kPoeHalfStrengthTitle,
    stage: PoeHalfStrengthStage(controller: _controller, stageHeight: 0),
    controls: PoeHalfStrengthControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kPoeHalfStrengthTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.poeHalfStrength,
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
            final double stageH = ((c.maxWidth - 2 * AppSpacing.lg) * 1.1)
                .clamp(320.0, 460.0);
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
          PoeHalfStrengthStage(
            controller: _controller,
            stageHeight: stageHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
          PoeHalfStrengthReadouts(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          PoeHalfStrengthPredict(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            PhCard(child: PoeHalfStrengthControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const PoeHalfStrengthExplainer(),
          const ToolHelpFooter(toolId: kPoeHalfStrengthToolId),
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
                child: PoeHalfStrengthControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
