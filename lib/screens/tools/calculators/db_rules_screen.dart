// Decibels in Your Head, the Rules of 3 and 10: Wi-Fi Classroom tool
// (db-rules).
//
// Corrects "-70 to -67 is a tiny change". dB is a ratio: +3 dB doubles the
// power (1.995x, about double) and +10 dB multiplies it by ten. One dB
// slider moves a signal against a fixed -70 dBm reference; a linear
// milliwatt bar shows what the dB ruler hides.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate
// 12 and the section 5 anti-patterns. Model in
// lib/services/wifi_lab/db_rules_model.dart.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one state object, and this screen only composes them.
//   - DbRulesController (db_rules_controller.dart)
//   - DbRulesStage      (db_rules_stage.dart)    picture, readouts, predict
//   - DbRulesPainter    (db_rules_painter.dart)
//   - DbRulesControls, DbRulesExplainer (db_rules_controls.dart)
//   - DrCard, DrReadout, DbRulesPredict (db_rules_parts.dart)
//
// The Present button (windows at least 1024 px wide) puts the stage beside
// the controls over the SAME controller (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router, from the catalog.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> the signal equal to the reference is a first-class
//                    state: "1x, the same power", "No steps"
//   - error       -> none reachable: the slider is bounded and whole-dB
//   - success     -> picture, readouts, rules path, prediction
//   - disabled    -> a step button that would leave -80 to -60 dBm, with the
//                    reason in words; Show -67 against -70 once it shows
//   - interactive -> themed Material controls with the global focus ring
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'db_rules_controller.dart';
import 'db_rules_controls.dart';
import 'db_rules_parts.dart';
import 'db_rules_stage.dart';

/// Side panel width on desktop.
const double _kPanelWidth = 360;

/// The screen title, shared with the presenter bar and the tests.
const String kDbRulesTitle = 'Decibels in Your Head: the Rules of 3 and 10';

class DbRulesScreen extends StatefulWidget {
  const DbRulesScreen({super.key});

  @override
  State<DbRulesScreen> createState() => _DbRulesScreenState();
}

class _DbRulesScreenState extends State<DbRulesScreen> {
  final DbRulesController _controller = DbRulesController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: kDbRulesTitle,
    stage: DbRulesStage(controller: _controller, stageHeight: 0),
    controls: DbRulesControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(kDbRulesTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.dbRules, builder: _presenter),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: _main(
                  edge: AppSpacing.screenEdgeMobile,
                  stageHeight: 200,
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
          if (withControls) ...<Widget>[
            // On a phone the slider sits right under the question it answers.
            DrCard(child: DbRulesControls(controller: _controller)),
            const SizedBox(height: AppSpacing.sm),
          ],
          DbRulesStage(controller: _controller, stageHeight: stageHeight),
          const SizedBox(height: AppSpacing.sm),
          const DbRulesExplainer(),
          const ToolHelpFooter(toolId: kDbRulesToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double stageH = (c.maxHeight * 0.34).clamp(200.0, 320.0);
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
                child: DbRulesControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
