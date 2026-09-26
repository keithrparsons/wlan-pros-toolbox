// Modulation Simulator: Wi-Fi Classroom tool (modulation-simulator).
//
// Shows how bits become a radio wave. A group of k bits picks one point on the
// I/Q plane; that point sets the carrier's amplitude and phase for one symbol.
// Higher orders carry more bits per symbol, pack points closer, and need a
// cleaner signal to decode.
//
// CLEAN-ROOM BUILD (2026-09-25) from the IEEE 802.11 constellation math and
// textbook AWGN, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 01-modulation-simulator.md. All math lives in ModulationMath
// (lib/services/rf/modulation_math.dart).
//
// This is NOT the 'modulation' reference-card tool, which is untouched.
//
// STRUCTURE (Keith, 2026-09-25; split 2026-09-26 as the presenter pilot): one
// ModulationSimulatorController holds all state; this screen owns it and only
// composes the views over it:
//   - ModulationSimulatorStage  (modulation_simulator_stage.dart)
//   - ModulationPicker, ModulationSimulatorControls, ModulationReadouts,
//     ModulationExplainer       (modulation_simulator_controls.dart)
// On a phone they stack in the original order. The Present button (desktop
// and tablet windows) opens the same views over the SAME controller in the
// presenter layout (lib/widgets/presenter/).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Numerics in DM
// Mono (AppMonoText). Lime (textAccent) marks the measured quantity (received
// points, the bold carrier); status hues appear only on computed verdicts
// (a wrong decision, meets / misses the transmit EVM limit), always paired
// with a word or glyph (§8.13 rules 2 and 6). No new tokens. ASCII copy, no
// em dashes (GL-004).
//
// MOTION (§8.8): the simulator always opens PAUSED, so nothing moves until the
// user asks. Play advances whole symbols on a timer (discrete redraws, no
// tweened transitions); Step sends exactly one. With reduced motion on, a note
// says so and Step is the suggested path; Play still works because the user
// starts it.
//
// States (SOP-007 §5):
//   - empty       -> nothing sent yet: plots show ideal points only, with a
//                    prompt; EVM and error readouts say "send symbols first"
//   - running     -> Play: one symbol per tick at the chosen speed
//   - paused      -> default; Step and +100 work
//   - error       -> text source with an empty message: transport disabled,
//                    inline prompt to type something or switch to random
//   - disabled    -> Step / Play / +100 disabled in the error state; Reset
//                    disabled when there is nothing to clear
//   - interactive -> every control is a themed Material control with the
//                    global focus ring; plots are labelled for screen readers

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'modulation_simulator_controller.dart';
import 'modulation_simulator_controls.dart';
import 'modulation_simulator_stage.dart';

export 'modulation_simulator_controller.dart'
    show
        kModulationSimulatorToolId,
        BitSource,
        SimSpeed,
        ModulationSimulatorController;

const String _kTitle = 'Modulation Simulator';

class ModulationSimulatorScreen extends StatefulWidget {
  const ModulationSimulatorScreen({super.key, this.seed});

  /// Test seam: a fixed RNG seed makes a run reproducible.
  final int? seed;

  @override
  State<ModulationSimulatorScreen> createState() =>
      _ModulationSimulatorScreenState();
}

class _ModulationSimulatorScreenState extends State<ModulationSimulatorScreen> {
  late final ModulationSimulatorController _controller =
      ModulationSimulatorController(seed: widget.seed);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: ModulationSimulatorStage(controller: _controller),
    controls: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The modulation select rides inside the controls card here.
        ModulationSimulatorControls(controller: _controller),
        const SizedBox(height: AppSpacing.xs),
        ModulationReadouts(controller: _controller),
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
            toolRoute: AppRouter.modulationSimulator,
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
                      ModulationPicker(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      ModulationSimulatorStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      ModulationSimulatorControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      ModulationReadouts(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const ModulationExplainer(),
                      const ToolHelpFooter(toolId: kModulationSimulatorToolId),
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
