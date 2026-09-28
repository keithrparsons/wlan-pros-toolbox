// The Number on the Box vs the Number in Your Hand: Wi-Fi Classroom tool
// (box-vs-hand).
//
// Corrects "a BE19000 router gives my phone 19 Gbps". The class number adds
// every radio at its maximum; one client uses one link with its own streams;
// distance takes it lower again. The one control is the client, a 2x2 phone
// by default.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 4
// and the section 5 anti-patterns. Model in
// lib/services/wifi_lab/box_vs_hand_model.dart, which reuses
// WifiPhyRateService (the Throughput Calculator) and RateVsRangeMath without
// modifying either.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - BoxVsHandController (box_vs_hand_controller.dart)
//   - BoxVsHandStage      (box_vs_hand_stage.dart)     the three bars
//   - BoxVsHandControls, BoxVsHandExplainer
//                         (box_vs_hand_controls.dart)
//   - BvhCard, BvhBar and friends (box_vs_hand_parts.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> a step not yet shown keeps its place and says how to
//                    reach it
//   - error       -> none reachable: every input is a bounded toggle or
//                    slider; out of range reads "No link" in words, never a
//                    negative or a blank
//   - success     -> the three bars, their numbers and their reasons
//   - disabled    -> Show the next step on the last step, Back a step on the
//                    first
//   - interactive -> themed Material controls with the global focus ring
//
// MOTION (§8.8): a bar that appears shrinks from the bar above it over
// kBvhShrinkDuration, a teaching animation; reduced motion makes it jump.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/unit_system_switch.dart';
import 'box_vs_hand_controller.dart';
import 'box_vs_hand_controls.dart';
import 'box_vs_hand_parts.dart';
import 'box_vs_hand_stage.dart';

/// Side panel width on desktop.
const double _kPanelWidth = 360;

/// The screen title, shared with the presenter bar and the tests.
const String kBoxVsHandTitle =
    'The Number on the Box vs the Number in Your Hand';

class BoxVsHandScreen extends StatefulWidget {
  const BoxVsHandScreen({super.key});

  @override
  State<BoxVsHandScreen> createState() => _BoxVsHandScreenState();
}

class _BoxVsHandScreenState extends State<BoxVsHandScreen>
    with UnitSystemFollower<BoxVsHandScreen> {
  final BoxVsHandController _controller = BoxVsHandController();

  @override
  void applyUnitSystem(UnitSystem system) => _controller.setUnits(system);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: kBoxVsHandTitle,
    stage: BoxVsHandStage(controller: _controller),
    controls: BoxVsHandControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kBoxVsHandTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          const UnitSystemSwitch(),
          PresentButton(toolRoute: AppRouter.boxVsHand, builder: _presenter),
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
          BoxVsHandStage(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            BvhCard(child: BoxVsHandControls(controller: _controller)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const BoxVsHandExplainer(),
          const ToolHelpFooter(toolId: kBoxVsHandToolId),
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
                child: BoxVsHandControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
