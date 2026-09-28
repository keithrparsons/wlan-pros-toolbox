// Survey Walk: Wi-Fi Classroom tool (survey-walk).
//
// A surveyor walks a corridor-and-rooms floor with a scanner. The radio wave
// does not care how fast they walk, but the scanner does: each channel is
// visited once per revisit, so its samples land pace x revisit apart. The
// student changes the channel set, dwell, number of network interface cards
// (NICs) and the hopping algorithm, and sees the spacing against the guess
// range (Keith's Rule 4), the white no-data stretches, and how a pause at a
// door or per-cycle timestamps slide samples away from where they were
// taken. Survey types (passive, active, hybrid) and capture methods
// (continuous, line, stop and go) change what is collected and where.
//
// CLEAN-ROOM BUILD (2026-09-26) from the Wi-Fi Classroom wave 4 research
// brief §3 and §5, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/26-survey-walk.md. All math lives in lib/services/wifi_lab/
// survey_walk_engine.dart. Generic devices only, no product names (Keith,
// 2026-09-26).
//
// STRUCTURE: the pictures and the controls are separate widgets over one
// SurveyWalkController.
//   - SurveyWalkStage    (survey_walk_stage.dart): floor, channel strip,
//                        signal along the path.
//   - SurveyWalkControls (survey_walk_controls.dart): inputs and readouts.
// The Present button (desktop and tablet windows) places the same two side
// by side over the SAME controller (lib/widgets/presenter/, spec 00).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). AP hues from
// roaming_walk_palette.dart (§8.15.2), always with their "AP n, ch x" label.
// Lime marks the samples and the floor they cover; white marks no data.
// Status hues only on the Rule 4 verdict, with its word (§8.13).
//
// MOTION (§8.8): the walk opens paused at 0 s and moves only when the
// student presses Walk. Playback pauses when the app is backgrounded.
//
// States (SOP-007 §5):
//   - fresh     -> 0 s, paused, no samples yet; the opening question waits
//   - running   -> Walk advances at the chosen speed
//   - paused    -> Pause, Step, the slider, backgrounding
//   - ended     -> "Walk again" restarts; Step is disabled; the answer to
//                  the opening question is revealed
//   - empty     -> a channel with no AP says the scanner still dwells there;
//                  a channel with fewer than 2 samples says so
//   - drawing   -> the floor takes taps as waypoints; Walk and Step are
//                  disabled; "Use this path" needs 2 points and a first leg
//   - disabled  -> Hybrid with one NIC is refused, with the reason shown
//   - loading / error -> not reachable: the engine is synchronous and pure,
//                  and every input is a bounded slider, toggle or select
//   - interactive -> themed Material controls with the global focus ring;
//                  every painter carries a worded screen-reader label

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/survey_walk_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'roaming_walk_parts.dart';
import 'survey_walk_controller.dart';
import 'survey_walk_controls.dart';
import 'survey_walk_stage.dart';

export 'survey_walk_controller.dart' show kSurveyWalkToolId;

const String _kTitle = 'Survey Walk';

class SurveyWalkScreen extends StatefulWidget {
  const SurveyWalkScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final SurveyWalkConfig? initial;

  @override
  State<SurveyWalkScreen> createState() => _SurveyWalkScreenState();
}

class _SurveyWalkScreenState extends State<SurveyWalkScreen>
    with WidgetsBindingObserver, UnitSystemFollower<SurveyWalkScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  late final SurveyWalkController _controller = SurveyWalkController(
    initial: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: SurveyWalkStage(controller: _controller),
    controls: SurveyWalkControls(controller: _controller),
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
          PresentButton(toolRoute: AppRouter.surveyWalk, builder: _presenter),
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
                      SurveyWalkControls(
                        controller: _controller,
                        parts: const <SurveyControlPart>{
                          SurveyControlPart.question,
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SurveyWalkStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      SurveyWalkControls(
                        controller: _controller,
                        parts: const <SurveyControlPart>{
                          SurveyControlPart.transport,
                          SurveyControlPart.readouts,
                          SurveyControlPart.survey,
                          SurveyControlPart.scanner,
                          SurveyControlPart.walker,
                          SurveyControlPart.view,
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kSurveyWalkToolId),
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

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A teaching model. Each NIC spends one dwell on a channel, then '
            'moves on; a sample is stamped when its dwell ends. Signal is a '
            'log-distance average plus small-scale fading; the walls are '
            'drawn but not modeled.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The active client simply uses the strongest of our APs and '
            'tests once a second (illustrative). Real adapters scan on their '
            'own schedules, and how real survey apps stamp and place samples '
            'is not published.',
            style: body,
          ),
        ],
      ),
    );
  }
}
