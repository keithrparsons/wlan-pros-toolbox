// Medium Access Simulator (Wi-Fi Classroom, 2026-09-25) — medium-access-simulator.
//
// Watch 802.11 contention happen one 9 us slot at a time: stations wait out
// AIFS, count down a random backoff, freeze when someone else takes the
// medium, collide when two counts hit zero together, and double their
// contention window after each loss. Toggle EDCA to see voice win, hidden node
// to see collisions no one could hear coming, and RTS/CTS to see them go away.
//
// Built clean-room from IEEE 802.11 clause 10 (DCF/EDCA) and clause 17 (OFDM
// timing). Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 02-medium-access-simulator.md. The engine is pure Dart and lives in
// lib/services/wifi_lab/medium_access_engine.dart.
//
// STRUCTURE (Keith, 2026-09-25; split 2026-09-26 as the presenter pilot): one
// MediumAccessSimulatorController holds the configuration, the run and the
// clock; this screen owns it and composes the views over it:
//   - MediumAccessSimulatorStage  (medium_access_simulator_stage.dart)
//   - MediumAccessTransport, MediumAccessResults, MediumAccessStations,
//     MediumAccessRules, MediumAccessAbout
//                                 (medium_access_simulator_controls.dart)
// On a phone they stack in the original order. The Present button (desktop
// and tablet windows) opens the same views over the SAME controller in the
// presenter layout (lib/widgets/presenter/).
//
// THEME: context.colors only (dark §8 / light §8.20). Stations are told apart
// by lane and letter, never by hue (§8.15). Status hues are verdicts only
// (§8.13): danger on a lost frame, success on an ACK. Numerics in DM Mono.
//
// States (SOP-007 §5):
//   - fresh     -> clock at 0, paused, stats read "Press Play or Step"
//   - running   -> Ticker advances whole slots at the chosen speed
//   - paused    -> clock frozen; the timeline can be scrolled back
//   - disabled  -> Add at 10 stations, Remove at 1, access-category selects
//                  in Legacy DCF, hidden node with one station
//   - reduced motion -> starts paused (it always does); Step works; the
//                  timeline jumps to "now" rather than animating
//   - interactive -> every control is a themed Material control with the
//                  global focus ring

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'medium_access_simulator_controller.dart';
import 'medium_access_simulator_controls.dart';
import 'medium_access_simulator_stage.dart';

export 'medium_access_simulator_controller.dart'
    show kMediumAccessToolId, SimSpeed, MediumAccessSimulatorController;

const String _kTitle = 'Medium Access Simulator';

class MediumAccessSimulatorScreen extends StatefulWidget {
  const MediumAccessSimulatorScreen({super.key, this.seed = 1});

  /// Seed for every random draw. Same seed, same run.
  final int seed;

  @override
  State<MediumAccessSimulatorScreen> createState() =>
      _MediumAccessSimulatorScreenState();
}

class _MediumAccessSimulatorScreenState
    extends State<MediumAccessSimulatorScreen> {
  late final MediumAccessSimulatorController _controller =
      MediumAccessSimulatorController(seed: widget.seed);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: MediumAccessSimulatorStage(controller: _controller),
    controls: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MediumAccessTransport(controller: _controller),
        const SizedBox(height: AppSpacing.xs),
        MediumAccessStations(controller: _controller),
        const SizedBox(height: AppSpacing.xs),
        MediumAccessRules(controller: _controller),
      ],
    ),
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
            toolRoute: AppRouter.mediumAccessSimulator,
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
                  maxWidth: AppSpacing.contentMaxWidth,
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
                      MediumAccessTransport(controller: _controller),
                      const SizedBox(height: AppSpacing.md),
                      MediumAccessSimulatorStage(controller: _controller),
                      const SizedBox(height: AppSpacing.md),
                      MediumAccessResults(controller: _controller),
                      const SizedBox(height: AppSpacing.md),
                      MediumAccessStations(controller: _controller),
                      const SizedBox(height: AppSpacing.md),
                      MediumAccessRules(controller: _controller),
                      const SizedBox(height: AppSpacing.md),
                      const MediumAccessAbout(),
                      const ToolHelpFooter(toolId: kMediumAccessToolId),
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
