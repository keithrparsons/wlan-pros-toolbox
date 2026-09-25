// Rate Adaptation: Wi-Fi Lab tool (rate-adaptation).
//
// A radio does not know the best rate; it learns it. This screen runs one
// link frame by frame under Minstrel-style rate control: per-rate success
// statistics smoothed every 50 ms, a share of sample frames at other rates,
// and a retry chain on every frame. The student walks the client away and
// back, watches the chosen rate step down and climb again, and sees what
// each retry costs in airtime.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/23-rate-adaptation.md,
// the wave-3 brief section 8 and the wave-5 brief section 9. The model is in
// lib/services/wifi_lab/rate_adaptation_model.dart and reuses Rate vs Range
// (sensitivity and SNR), Airtime Anatomy (TXTIME) and Medium Access (CW
// doubling) without modifying them.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one controller, and this screen only composes them.
//   - RateAdaptationController (rate_adaptation_controller.dart)
//   - RateAdaptationStage      (rate_adaptation_stage.dart): attempts strip,
//                              rate chart, statistics table
//   - RateAdaptationControls, RateAdaptationReadouts,
//     RateAdaptationExplainer  (rate_adaptation_controls.dart)
//
// LAYOUT: phone first. Below 720 px everything stacks in one scroll: stage,
// readouts, controls, explainer. At 720 px and up the controls become a side
// panel.
//
// MOTION (§8.8): opens paused at 0 s and moves only on Play; Step
// moves one frame. Playback pauses when the app is backgrounded.
//
// States (SOP-007 §5):
//   - fresh       -> 0 s, paused, every rate "untried", readouts "-", the
//                    strip says "No frames yet"
//   - running     -> Play advances air time at the chosen speed
//   - paused      -> Pause, Step, backgrounding
//   - disabled    -> Restart at 0 s
//   - loading / error -> not reachable: the model is synchronous and pure,
//                    and every input is a toggle, select or bounded slider
//   - interactive -> themed Material controls with the global focus ring;
//                    the strip, chart and every table row carry worded
//                    screen-reader labels

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'rate_adaptation_controller.dart';
import 'rate_adaptation_controls.dart';
import 'rate_adaptation_stage.dart';

export 'rate_adaptation_controller.dart' show kRateAdaptationToolId;

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class RateAdaptationScreen extends StatefulWidget {
  const RateAdaptationScreen({super.key, this.seed = 1});

  /// Seed for every random draw. Same seed, same run.
  final int seed;

  @override
  State<RateAdaptationScreen> createState() => _RateAdaptationScreenState();
}

class _RateAdaptationScreenState extends State<RateAdaptationScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final RateAdaptationController _controller = RateAdaptationController(
    vsync: this,
    seed: widget.seed,
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
        title: const Text('Rate Adaptation'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _controller.copyText)],
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
                  chartHeight: 180,
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
    required double chartHeight,
    required bool withControls,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RateAdaptationStage(
            controller: _controller,
            chartHeight: chartHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
          RateAdaptationReadouts(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            RateAdaptationControls(controller: _controller),
          ],
          const SizedBox(height: AppSpacing.sm),
          const RateAdaptationExplainer(),
          const ToolHelpFooter(toolId: kRateAdaptationToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double chartH = (c.maxHeight * 0.3).clamp(180.0, 280.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _main(
                edge: AppSpacing.screenEdgeDesktop,
                chartHeight: chartH,
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
                child: RateAdaptationControls(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
