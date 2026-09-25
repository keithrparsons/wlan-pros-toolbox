// DFS and Radar: Wi-Fi Lab tool (dfs-simulator).
//
// An AP on a simulated one-hour clock. On a DFS channel it must listen for
// radar before it transmits (the channel availability check: 60 s, or 10 min
// in the EU on 120/124/128). When radar appears it stops traffic, leaves the
// channel within 10 s, and cannot come back for 30 minutes; its clients
// follow it to a non-DFS channel at once or wait out a new CAC. The student
// presses "Radar now" and watches the outage.
//
// CLEAN-ROOM BUILD (2026-09-25) from the Wi-Fi Lab wave 3 research brief §2
// (FCC 47 CFR §15.407(h)(2), ETSI EN 301 893 V2.1.1), per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/25-dfs.md. All rules and
// the run live in lib/services/wifi_lab/dfs_model.dart; channel data comes
// from lib/data/channel_frequency_data.dart.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one DfsSimulatorController.
//   - DfsSimulatorStage    (dfs_simulator_stage.dart): channel strip and
//                          timeline.
//   - DfsSimulatorControls (dfs_simulator_controls.dart): inputs and
//                          readouts, in parts (transport, readouts, log,
//                          setup, rules).
// This screen only composes them. On a phone they stack; a presenter layout
// can put the stage beside a full DfsSimulatorControls with no change to
// either.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Lime marks the
// channel in use and the time the AP and clients are served. Status hues are
// verdicts with words: amber = not usable yet (CAC) or an outage, red =
// blocked after radar or no service (§8.13).
//
// MOTION (§8.8): the clock opens paused at 0:00 and moves only when the
// student presses Play; Step and the clock slider move it without animation.
// Playback pauses when the app is backgrounded.
//
// States (SOP-007 §5):
//   - fresh       -> 0:00, paused, the log reads "No radar yet..."
//   - running     -> Play advances the clock at the chosen speed
//   - paused      -> Pause, Step, the slider, backgrounding
//   - ended       -> at 60:00 Play reads "Play again"; Step and Radar now
//                    are disabled
//   - empty       -> no radar: the log says how to make some; on a non-DFS
//                    channel it says the AP does not listen for radar
//   - disabled    -> Radar now on a non-DFS channel or while leaving one,
//                    with the reason in words; Restart at 0:00 with no radar
//                    added; New random pattern with random radar off
//   - loading / error -> not reachable: the model is synchronous and pure,
//                    and every input is a toggle, select or bounded slider
//   - interactive -> themed Material controls with the global focus ring;
//                    every channel cell and the timeline carry worded
//                    screen-reader labels

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/dfs_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'dfs_simulator_controller.dart';
import 'dfs_simulator_controls.dart';
import 'dfs_simulator_parts.dart';
import 'dfs_simulator_stage.dart';

export 'dfs_simulator_controller.dart' show kDfsSimulatorToolId;

class DfsSimulatorScreen extends StatefulWidget {
  const DfsSimulatorScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final DfsConfig? initial;

  @override
  State<DfsSimulatorScreen> createState() => _DfsSimulatorScreenState();
}

class _DfsSimulatorScreenState extends State<DfsSimulatorScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final DfsSimulatorController _controller = DfsSimulatorController(
    vsync: this,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DFS and Radar'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _controller.copyText)],
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
                      DfsSimulatorStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      DfsSimulatorControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kDfsSimulatorToolId),
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
    return DfsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const DfsSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A teaching model of one AP. The CAC, closing time, move time and '
            'non-occupancy period are the rule values. The AP here leaves a '
            'channel ${fmtSpan(kApSwitchS)} after radar, well inside the '
            '10 s limit, and the clients\' scan-and-join delays (1 to 2.5 s) '
            'are illustrative.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Radar blocks every 20 MHz channel the AP was using; some APs '
            'block only the part that saw the radar. The US plan here stops '
            'at 165 (U-NII-4 has no DFS); the EU plan is 36 to 64 and 100 to '
            '140. Real APs may also run an off-channel CAC in the EU, keep a '
            'second radio listening, or narrow their width on their own; '
            'none of that is modeled.',
            style: body,
          ),
        ],
      ),
    );
  }
}
