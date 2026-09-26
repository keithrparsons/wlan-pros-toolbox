// Adjacent Channels and AP Stacking: Wi-Fi Classroom tool (adjacent-channel).
//
// Channel Planner shows which channels overlap on paper. This tool shows why
// a channel that does NOT overlap still hurts when the other transmitter is
// close: the neighbor's out-of-channel energy lands in your receiver, and
// your receiver can only reject so much of it. The lessons (spec 29):
//   1. A transmitter's energy does not stop at its channel edge; the
//      spectral mask limits the leakage, and real radios run at or below it.
//   2. A receiver rejects the next channel only so far, and higher rates
//      tolerate less.
//   3. So two radios on clean channels, close together, still interfere;
//      distance and channel separation both matter.
//   4. The mask is a ceiling: what the tool computes is the worst case the
//      rule allows.
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/29-adjacent-channel.md.
// All math in lib/services/wifi_lab/adjacent_channel_model.dart, which
// reuses Channel Planner's OFDM mask and energy-detect threshold, Roaming
// Walk's free-space loss at 1 m, and Rate vs Range's sensitivities and noise
// floor.
//
// STRUCTURE: the pictures and the controls are separate widgets over one
// AdjacentChannelController.
//   - AdjacentChannelStage    (adjacent_channel_stage.dart): spectrum strip,
//                             floor line, neighbor distance; AciHeadline
//                             (the verdicts) sits beside it when presenting.
//   - AdjacentChannelControls (adjacent_channel_controls.dart): inputs;
//                             AciQuestionCard, the opening question.
// The Present button (desktop and tablet windows) places the stage and the
// controls side by side over the SAME controller (lib/widgets/presenter/,
// spec 00).
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> none: there are always three radios
//   - error       -> none reachable: every input is a bounded slider, toggle
//                    or select, and the controller offers only the widths,
//                    masks and separations the band allows
//   - success     -> spectrum, floor, verdicts
//   - disabled    -> widths and masks the band does not allow are not
//                    offered; 2.4 GHz is held to its 20 MHz plans
//   - verdicts    -> "Link lost" / "Down n MCS steps" / "No rate lost" and
//                    "Busy" / "Clear", each a word with its status hue
//   - interactive -> themed Material controls with the global focus ring;
//                    every painter carries a worded screen-reader label
//
// MOTION (§8.8): none. Nothing animates.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/adjacent_channel_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'adjacent_channel_controller.dart';
import 'adjacent_channel_controls.dart';
import 'adjacent_channel_stage.dart';
import 'rate_vs_range_parts.dart';

export 'adjacent_channel_controller.dart' show kAdjacentChannelToolId;

const String _kTitle = 'Adjacent Channels and AP Stacking';

/// Side panel width on a wide window.
const double _kPanelWidth = 380;

class AdjacentChannelScreen extends StatefulWidget {
  const AdjacentChannelScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final AciConfig? initial;

  @override
  State<AdjacentChannelScreen> createState() => _AdjacentChannelScreenState();
}

class _AdjacentChannelScreenState extends State<AdjacentChannelScreen> {
  late final AdjacentChannelController _controller = AdjacentChannelController(
    initial: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: AdjacentChannelStage(controller: _controller),
    controls: AdjacentChannelControls(controller: _controller),
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
            toolRoute: AppRouter.adjacentChannel,
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
          AciQuestionCard(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          AdjacentChannelStage(controller: _controller),
          const SizedBox(height: AppSpacing.sm),
          AciHeadline(controller: _controller),
          if (withControls) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            AdjacentChannelControls(controller: _controller),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _AboutCard(),
          const ToolHelpFooter(toolId: kAdjacentChannelToolId),
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
                child: AdjacentChannelControls(controller: _controller),
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
            'Leakage is the neighbor\'s received power times the share of its '
            'transmit mask that falls inside your 20 MHz, the mask taken '
            'linearly in dB between its points and added up across your '
            'channel. The mask at your center frequency is not that figure. '
            'dBr means decibels relative to the neighbor\'s in-channel level.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The mask is a ceiling on the transmitter, so the leakage is the '
            'worst case the rule allows; real radios leak less. The '
            'receiver\'s filter works only on the neighbor\'s own channel, '
            'so interference = leakage plus what the filter lets through, '
            'added in milliwatts. The selectivity values are illustrative. '
            'Walls, antenna patterns and fading are left out.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The rate enters only through what each MCS needs. The '
            'standard\'s minimum adjacent-channel rejection plus minimum '
            'sensitivity is -66 dBm at every MCS (via a 2024 802.11be test '
            'white paper): the receiver\'s rejection does not change with '
            'rate, only how much interference each rate can absorb.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Which channels overlap on paper, and who shares airtime with '
            'whom, is the Channel Planner\'s lesson.',
            style: body,
          ),
        ],
      ),
    );
  }
}
