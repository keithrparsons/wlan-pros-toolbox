// Roaming Walk: Wi-Fi Classroom tool (roaming-walk).
//
// A client walks across a floor of APs. It holds its AP until the signal
// falls below its trigger, then moves only to an AP that is delta stronger,
// and every roam costs a gap that is mostly scanning. Presets for a phone and
// a laptop (Apple's published iPhone and Mac values, with generic labels on
// screen) and two illustrative clients show a sticky
// client and a ping-pong one; 802.11k, PMK caching and FT change the gap.
//
// CLEAN-ROOM BUILD (2026-09-25) from the Wi-Fi Classroom wave 3 research brief §3,
// per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 15-roaming-walk.md. All math lives in lib/services/wifi_lab/
// roaming_walk_engine.dart.
//
// This is NOT the 'roaming' reference card or the 'roaming-log' live tool;
// both are untouched.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one RoamingWalkController.
//   - RoamingWalkStage    (roaming_walk_stage.dart): floor plan, RSSI plot.
//   - RoamingWalkControls (roaming_walk_controls.dart): inputs and readouts,
//                         in parts (transport, readouts, client, roam cost,
//                         floor).
// This screen only composes them. On a phone they stack: the stage, then
// playback and readouts, then the setup cards. A presenter layout can place
// the stage and a full RoamingWalkControls side by side with no change to
// either. The Present button (desktop and tablet windows) does exactly that,
// over the SAME controller (lib/widgets/presenter/, spec 00).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Each AP has its
// own hue from roaming_walk_palette.dart under GL-003 §8.15.2, always with its
// "AP n" label. Lime marks the serving link. Warning amber only on the two
// verdict readouts (ping-pong, time below -70 dBm), with words (§8.13).
//
// MOTION (§8.8): the walk opens paused at 0 s and moves only when the student
// presses Play; Step and the walk-time slider move it without animation.
// With reduced motion on the screen says so and nothing starts by itself.
// Playback pauses when the app is backgrounded.
//
// States (SOP-007 §5):
//   - fresh       -> 0 s, paused, roam log reads "No roams yet. Press Play
//                    or Step."
//   - running     -> Play advances the walk at the chosen speed
//   - paused      -> Pause, Step, the slider, a path change, backgrounding
//   - ended       -> Play reads "Play again" and restarts; Step is disabled
//   - empty       -> a walk with no roams says the client is holding its AP
//   - drawing     -> the floor takes taps as waypoints; Play and Step are
//                    disabled; "Use this path" is disabled until 2 points
//                    at least 1 m apart
//   - disabled    -> Restart at 0 s; New shadowing with shadowing off
//   - loading / error -> not reachable: the engine is synchronous and pure,
//                    and every input is a bounded slider, toggle or select
//   - interactive -> themed Material controls with the global focus ring;
//                    both painters carry worded screen-reader labels;
//                    dragging an AP is a shortcut for the AP sliders

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/roaming_walk_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'roaming_walk_controller.dart';
import 'roaming_walk_controls.dart';
import 'roaming_walk_parts.dart';
import 'roaming_walk_stage.dart';

export 'roaming_walk_controller.dart' show kRoamingWalkToolId;

const String _kTitle = 'Roaming Walk';

class RoamingWalkScreen extends StatefulWidget {
  const RoamingWalkScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final RoamWalkConfig? initial;

  @override
  State<RoamingWalkScreen> createState() => _RoamingWalkScreenState();
}

class _RoamingWalkScreenState extends State<RoamingWalkScreen>
    with WidgetsBindingObserver, UnitSystemFollower<RoamingWalkScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  // The controller builds its own Ticker, so the walk keeps running while
  // the presenter route covers (and mutes) this one.
  late final RoamingWalkController _controller = RoamingWalkController(
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

  /// The presenter layout over this screen's controller (shared, not
  /// copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: RoamingWalkStage(controller: _controller),
    controls: RoamingWalkControls(controller: _controller),
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
          PresentButton(toolRoute: AppRouter.roamingWalk, builder: _presenter),
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
                      RoamingWalkStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      RoamingWalkControls(
                        controller: _controller,
                        parts: const <RoamControlPart>{
                          RoamControlPart.transport,
                          RoamControlPart.readouts,
                          RoamControlPart.client,
                          RoamControlPart.roamCost,
                          RoamControlPart.floor,
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kRoamingWalkToolId),
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
            'A teaching model. APs radiate equally in every direction with '
            'no walls; signal follows a log-distance path-loss model plus '
            'seeded shadowing that is smooth over about '
            '${UnitSystemScope.systemOf(context).isMetric ? '5 m' : '16 ft'}. '
            'The contours '
            'on the floor use the average signal, without shadowing.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The client checks its signal every 100 ms. Real clients average '
            'readings, scan on their own schedule and weigh more than signal '
            'strength. Scan and authentication timings are illustrative; '
            'change them to match what you measure.',
            style: body,
          ),
        ],
      ),
    );
  }
}
