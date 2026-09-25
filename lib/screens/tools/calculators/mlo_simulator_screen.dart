// Multi-Link Operation: Wi-Fi Lab tool (mlo-simulator).
//
// A Wi-Fi 7 client with links on two or three bands, other networks keeping
// each band busy, and a stream of frames. Single link, STR, NSTR and EMLSR
// run over the same random traffic, and the student compares mean and
// 99th-percentile latency: MLO wins when the links are equally busy, the win
// shrinks when one is much busier, and it can lose (a slow link that is free
// first, or EMLSR's switch cost).
//
// CLEAN-ROOM BUILD (2026-09-25) from the Wi-Fi Lab wave 3 research brief §7
// and wave 5 brief §10, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/22-mlo.md. The model lives in lib/services/wifi_lab/mlo_model.dart;
// airtime comes from lib/services/wifi_lab/airtime_anatomy.dart.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one MloSimulatorState.
//   - MloSimulatorStage    (mlo_simulator_stage.dart): link lanes and the
//                          latency histograms.
//   - MloSimulatorControls (mlo_simulator_controls.dart): readouts and
//                          inputs, in parts.
// This screen only composes them. On a phone they stack; a presenter layout
// can put the stage beside a full MloSimulatorControls with no change to
// either.
//
// States (SOP-007 §5):
//   - fresh       -> the "Two equal links" lesson, computed at once
//   - success     -> every change recomputes the run (about 10 ms)
//   - one link    -> every mode is the single link, said in words
//   - no modes    -> all three MLO modes off: the verdict line asks for one;
//                    the single links still show
//   - overloaded  -> a mode that cannot keep up is labeled Overloaded in
//                    red with the reason, instead of a misleading mean
//   - disabled    -> the last link's switch (it stays on), and the driver
//                    switch with one link, each with its reason
//   - loading / error -> not reachable: the model is synchronous and pure,
//                    and every input is a toggle, select or bounded slider
//   - interactive -> themed Material controls with the global focus ring;
//                    the lanes and each histogram carry worded
//                    screen-reader labels
//
// MOTION (§8.8): none. The lanes are a still picture the student slides.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mlo_model.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'mlo_simulator_controls.dart';
import 'mlo_simulator_stage.dart';
import 'mlo_simulator_state.dart';

export 'mlo_simulator_state.dart' show kMloSimulatorToolId;

class MloSimulatorScreen extends StatefulWidget {
  const MloSimulatorScreen({super.key, this.initial, this.preset});

  /// Test seam: start from a given configuration.
  final MloConfig? initial;

  /// Test seam: start from a lesson.
  final MloPreset? preset;

  @override
  State<MloSimulatorScreen> createState() => _MloSimulatorScreenState();
}

class _MloSimulatorScreenState extends State<MloSimulatorScreen> {
  late final MloSimulatorState _state = MloSimulatorState(
    initial: widget.initial,
    preset: widget.preset,
  );

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-Link Operation'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _state.copyText)],
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
                      MloSimulatorStage(state: _state),
                      const SizedBox(height: AppSpacing.sm),
                      MloSimulatorControls(state: _state),
                      const ToolHelpFooter(toolId: kMloSimulatorToolId),
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
