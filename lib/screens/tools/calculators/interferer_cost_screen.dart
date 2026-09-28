// What an Interferer Costs (and how a NIC hears the air): Wi-Fi Classroom
// tool (interferer-cost).
//
// The lesson (Keith, 2026-09-27): "THe REAL cost is the super sensitivity of
// the NIC for backing off and not transmitting due to co-channel contention.
// So it proves co-channel contention slows down Wi-Fi far worse than non-
// Wi-Fi interference. Many people assume it is the non-Wi-Fi things that
// cause the harm. Not saying they can't..." Frame loss is not the headline;
// waiting is. The analog video sender is the "not saying they can't" panel.
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-27-classroom-
// interferer-and-ds-sources/RESEARCH-BRIEF.md Part 1. All math in
// lib/services/wifi_lab/interferer_cost_model.dart.
//
// STRUCTURE: the pictures and the controls are separate widgets over one
// InterfererCostController.
//   - InterfererCostStage    (interferer_cost_stage.dart): level meter,
//                            heard-at distances, 60 ms timeline, level
//                            slider; IcHeadline (the costs) sits beside it
//                            when presenting.
//   - InterfererCostControls (interferer_cost_controls.dart): inputs;
//                            IcQuestionCard, the opening question.
// The Present button places them side by side over the SAME controller.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> a source absent from the band (oven or Bluetooth on
//                    5 GHz) reads "Not on this band: nothing to wait for" on
//                    the meter, the timeline, the verdict and the table
//   - error       -> none reachable: every input is a bounded slider or a
//                    toggle, and the controller offers only the widths the
//                    band allows
//   - success     -> meter, distances, timeline, costs
//   - disabled    -> widths past 20 MHz are not offered on 2.4 GHz; the
//                    mains toggle shows only for the oven
//   - verdicts    -> "Your radio waits" / "Not heard: ... sends into it" /
//                    "Not on this band", each a word with its status hue
//   - interactive -> themed Material controls with the global focus ring;
//                    every painter carries a worded screen-reader label
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/interferer_cost_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/unit_system_switch.dart';
import 'interferer_cost_controller.dart';
import 'interferer_cost_controls.dart';
import 'interferer_cost_stage.dart';
import 'rate_vs_range_parts.dart';

export 'interferer_cost_controller.dart' show kInterfererCostToolId;

const String _kTitle = 'What an Interferer Costs (and how a NIC hears the air)';

/// Side panel width on a wide window.
const double _kPanelWidth = 380;

class InterfererCostScreen extends StatefulWidget {
  const InterfererCostScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final IcConfig? initial;

  @override
  State<InterfererCostScreen> createState() => _InterfererCostScreenState();
}

class _InterfererCostScreenState extends State<InterfererCostScreen>
    with UnitSystemFollower<InterfererCostScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  late final InterfererCostController _controller = InterfererCostController(
    initial: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: InterfererCostStage(controller: _controller),
    controls: InterfererCostControls(controller: _controller),
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
          PresentButton(
            toolRoute: AppRouter.interfererCost,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _controller.copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 900) return _wide(context);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: _main(
                  edge: c.maxWidth >= 720
                      ? AppSpacing.screenEdgeDesktop
                      : AppSpacing.screenEdgeMobile,
                  withControls: true,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _main({required double edge, required bool withControls}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          IcQuestionCard(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          InterfererCostStage(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          IcHeadline(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            InterfererCostControls(controller: _controller),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _AboutCard(),
          const ToolHelpFooter(toolId: kInterfererCostToolId),
        ],
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _main(
                edge: AppSpacing.screenEdgeDesktop,
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
                child: InterfererCostControls(controller: _controller),
              ),
            ),
          ],
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
    return RvrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RvrSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Clear channel assessment (CCA) is how a radio decides the air is '
            'busy. It waits for a Wi-Fi preamble it can decode at -82 dBm, '
            'and for any other energy only at -62 dBm. These are the '
            'standard\'s minimum requirements: real chips often detect '
            'preambles lower, near -91 dBm by one vendor\'s account, which '
            'makes the real gap wider.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Waiting is decided where the sender is; whether a frame '
            'survives is decided at its receiver. This tool puts both at your '
            'radio. Collisions between two Wi-Fi radios that start at once, '
            'adaptive hopping, and rate adaptation are left out.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'To see these interferers on a screen, open the Spectrum '
            'Analysis lesson, and the race between a swept analyzer and a '
            'fast Fourier transform (FFT) analyzer in Fourier and FFT.',
            style: body,
          ),
        ],
      ),
    );
  }
}
