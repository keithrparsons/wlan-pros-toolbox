// 6 GHz Power and PSD: Wi-Fi Lab tool (six-ghz-psd).
//
// EIRP and SNR against channel width, one line per regulatory class, and one
// channel's spectrum as a flat PSD block. The lessons (spec 17): a
// PSD-limited class gains 3 dB of EIRP per doubling of width, which exactly
// offsets the 3 dB higher noise floor, so SNR holds; a cap-limited class
// loses 3 dB of SNR per doubling; and the client -6 dB rule applies as a
// relative limit only to Standard Power and GVP clients.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/17-six-ghz-psd.md, values
// from Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md §1 (47 CFR
// §15.407 and ETSI EN 303 687 V1.1.1, read from the primary text). All math is
// in lib/services/wifi_lab/six_ghz_psd_math.dart; path loss reuses
// lib/services/wifi_lab/fspl_math.dart.
//
// This does NOT touch the 'spectrum' reference screen or the 6 GHz reference
// cards; their known errors are a separate ruling for Keith.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one model, and this screen only composes them.
//   - SixGhzPsdModel     (six_ghz_psd_model.dart)     state + derived numbers
//   - SixGhzPsdStage     (six_ghz_psd_stage.dart)     view toggle, plot,
//                                                     legend, width cursor
//   - SixGhzPsdControls, SixGhzPsdReadouts, SixGhzPsdExplainer
//                        (six_ghz_psd_controls.dart)  inputs and readouts
//   - PsdWidthChartPainter, PsdSpectrumPainter (six_ghz_psd_chart.dart)
// A later full-screen presenter layout reuses the same widgets side by side.
//
// LAYOUT: phone first. Below 720 px everything stacks in one scroll: stage,
// readouts, controls, explainer. At 720 px and up the controls become a side
// panel.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> every class off: plot, spectrum and readouts say to
//                    turn one on; the width slider is disabled; copy is off
//   - error       -> none reachable: every input is a bounded slider, toggle
//                    or checkbox, so no invalid value can be entered
//   - success     -> lines, spectrum block, per-class readouts
//   - disabled    -> an AP authorized-power slider while no class it governs
//                    is shown; the width slider while no class is shown
//   - interactive -> chart tap and drag pick a width; width slider
//                    (keyboard); themed Material controls with the global
//                    focus ring
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'six_ghz_psd_controls.dart';
import 'six_ghz_psd_model.dart';
import 'six_ghz_psd_parts.dart';
import 'six_ghz_psd_stage.dart';

export 'six_ghz_psd_model.dart' show kSixGhzPsdToolId;

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class SixGhzPsdScreen extends StatefulWidget {
  const SixGhzPsdScreen({super.key});

  @override
  State<SixGhzPsdScreen> createState() => _SixGhzPsdScreenState();
}

class _SixGhzPsdScreenState extends State<SixGhzPsdScreen> {
  final SixGhzPsdModel _model = SixGhzPsdModel();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('6 GHz Power and PSD'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _model.copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double chartH = (c.maxHeight * 0.42).clamp(220.0, 380.0);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: _main(
                  edge: AppSpacing.screenEdgeMobile,
                  chartHeight: chartH,
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
          SixGhzPsdStage(model: _model, chartHeight: chartHeight),
          const SizedBox(height: AppSpacing.sm),
          SixGhzPsdReadouts(model: _model),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            PsdCard(child: SixGhzPsdControls(model: _model)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const SixGhzPsdExplainer(),
          const ToolHelpFooter(toolId: kSixGhzPsdToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double chartH = (c.maxHeight * 0.5).clamp(280.0, 460.0);
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
                child: SixGhzPsdControls(model: _model),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
