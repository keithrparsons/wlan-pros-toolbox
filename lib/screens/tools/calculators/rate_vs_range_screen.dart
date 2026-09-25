// Rate vs Range: Wi-Fi Lab tool (rate-vs-range).
//
// MCS rings around an AP, top down. The lessons (spec 18): rate falls with
// distance in steps because each MCS needs a minimum signal; doubling the
// width costs 3 dB of sensitivity, so every ring shrinks; raising the minimum
// basic rate shrinks the cell edge and cuts beacon airtime; and the
// sensitivities are conformance floors that real radios beat.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/18-rate-vs-range.md,
// sensitivities from Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md
// section 10. Math in lib/services/wifi_lab/rate_vs_range_math.dart, which
// reuses fspl_math.dart for path loss and the ssid-airtime calculator for
// beacon airtime without modifying either.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one model, and this screen only composes them.
//   - RateVsRangeModel    (rate_vs_range_model.dart)    state + derived numbers
//   - RateVsRangeStage    (rate_vs_range_stage.dart)    rings, client, legend,
//                                                       beacon bar
//   - RateVsRangeControls, RateVsRangeReadouts, RateVsRangeExplainer
//                         (rate_vs_range_controls.dart) inputs and readouts
//   - RvrStagePainter     (rate_vs_range_painter.dart)
//
// LAYOUT: phone first. Below 720 px everything stacks in one scroll: stage,
// readouts, controls, explainer. At 720 px and up the controls become a side
// panel.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> none: there is always an AP and a client
//   - error       -> none reachable: every input is a bounded slider, toggle
//                    or select; a ring that falls under 1 m or past the view
//                    still reads in the legend ("under 1 m", its distance)
//   - success     -> rings, client readout, beacon bar
//   - disabled    -> widths the band does not allow are not offered
//   - interactive -> drag or tap the stage to move the client; a distance
//                    slider does the same from the keyboard; themed Material
//                    controls with the global focus ring
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'rate_vs_range_controls.dart';
import 'rate_vs_range_model.dart';
import 'rate_vs_range_parts.dart';
import 'rate_vs_range_stage.dart';

export 'rate_vs_range_model.dart' show kRateVsRangeToolId;

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class RateVsRangeScreen extends StatefulWidget {
  const RateVsRangeScreen({super.key});

  @override
  State<RateVsRangeScreen> createState() => _RateVsRangeScreenState();
}

class _RateVsRangeScreenState extends State<RateVsRangeScreen> {
  final RateVsRangeModel _model = RateVsRangeModel();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate vs Range'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _model.copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double stageH = (c.maxWidth - 2 * AppSpacing.lg).clamp(
              240.0,
              420.0,
            );
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
          RateVsRangeStage(model: _model, stageHeight: stageHeight),
          const SizedBox(height: AppSpacing.sm),
          RateVsRangeReadouts(model: _model),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            RvrCard(child: RateVsRangeControls(model: _model)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const RateVsRangeExplainer(),
          const ToolHelpFooter(toolId: kRateVsRangeToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double stageH = (c.maxHeight * 0.6).clamp(320.0, 560.0);
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
                child: RateVsRangeControls(model: _model),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
