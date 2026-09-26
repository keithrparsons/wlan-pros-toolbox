// Multicast at the Basic Rate: Wi-Fi Classroom tool (multicast-basic-rate).
//
// What multicast and broadcast data cost the channel: they go at a basic
// rate so every client can decode them, with no acknowledgment and no retry,
// and a client in power save makes the AP hold them for the DTIM beacon.
// Converting to unicast sends one acknowledged copy per listener at that
// listener's rate, which wins when few listen and loses when many do.
//
// CLEAN-ROOM BUILD (2026-09-26) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/30-multicast-basic-rate.md. All math lives in
// lib/services/wifi_lab/multicast_basic_rate_model.dart, which reuses
// Airtime Anatomy's timing (airtime_anatomy.dart).
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one MulticastBasicRateController.
//   - MulticastBasicRateStage    (multicast_basic_rate_stage.dart)
//   - MulticastBasicRateControls (multicast_basic_rate_controls.dart)
// This screen only composes them. On a phone they stack; the Present button
// (desktop and tablet windows) opens the stage beside the controls over the
// SAME controller in the presenter layout (lib/widgets/presenter/).
//
// THEME: context.colors only (dark §8 / light §8.20). See the stage for the
// color and motion notes.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'multicast_basic_rate_controller.dart';
import 'multicast_basic_rate_controls.dart';
import 'multicast_basic_rate_stage.dart';

export 'multicast_basic_rate_controller.dart'
    show
        kMulticastBasicRateToolId,
        kMcSweepDuration,
        McView,
        MulticastBasicRateController;

const String _kTitle = 'Multicast at the Basic Rate';

class MulticastBasicRateScreen extends StatefulWidget {
  const MulticastBasicRateScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final MulticastBasicRateController? controller;

  @override
  State<MulticastBasicRateScreen> createState() =>
      _MulticastBasicRateScreenState();
}

class _MulticastBasicRateScreenState extends State<MulticastBasicRateScreen> {
  late final MulticastBasicRateController _controller =
      widget.controller ?? MulticastBasicRateController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: MulticastBasicRateStage(controller: _controller),
    controls: MulticastBasicRateControls(controller: _controller),
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
            toolRoute: AppRouter.multicastBasicRate,
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
                      _PlayBar(controller: _controller),
                      const SizedBox(height: AppSpacing.xs),
                      MulticastBasicRateStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      MulticastBasicRateControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kMulticastBasicRateToolId),
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

/// Play, step and reset for the normal screen (the presenter has keys).
class _PlayBar extends StatelessWidget {
  const _PlayBar({required this.controller});

  final MulticastBasicRateController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool playing = controller.playing;
        ButtonStyle style() => OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          foregroundColor: colors.textPrimary,
        );
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: controller.togglePlay,
              style: style(),
              icon: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(playing ? 'Pause' : 'Play the second'),
            ),
            OutlinedButton.icon(
              onPressed: controller.stepBeacon,
              style: style(),
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('Next beacon'),
            ),
            OutlinedButton.icon(
              onPressed: controller.resetSweep,
              style: style(),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Reset'),
            ),
          ],
        );
      },
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
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Airtime is computed with the same frame timing as Airtime '
            'Anatomy. 802.11b rates use the long preamble (192 µs) and a '
            '20 µs slot; 802.11a/g rates a 9 µs slot. Multicast waits DIFS '
            'plus the average backoff and is never acknowledged. Frame sizes '
            'add a 26-byte header, a 4-byte checksum and 16 bytes of '
            'encryption to each packet.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One AP, no other traffic, no collisions, no retries. Beacons are '
            'drawn as markers; what they cost is what SSID Airtime shows. A '
            'unicast copy to a dozing client waits for that client to wake, '
            'which is not drawn: the power save switch holds multicast only.',
            style: body,
          ),
        ],
      ),
    );
  }
}
