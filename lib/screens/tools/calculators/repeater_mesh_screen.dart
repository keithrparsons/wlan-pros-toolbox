// Repeaters and Mesh Backhaul: Wi-Fi Classroom tool (repeater-mesh).
//
// A relay with one radio on one channel receives each frame and sends it
// again on the same channel, so its hops take turns: 1/T = 1/T1 + 1/T2. Two
// equal hops give half; a weak backhaul hop drags the total down; each extra
// same-channel hop cuts it again and adds delay. A dedicated backhaul radio
// on another channel lets the hops run at once (the slowest hop sets the
// total), and a wired backhaul leaves only the last hop on the air.
//
// CLEAN-ROOM BUILD (2026-09-26) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/36-repeater-mesh.md. All math lives in
// lib/services/wifi_lab/repeater_mesh_model.dart, which reuses Roaming Walk's
// path loss, Rate vs Range's receiver sensitivities and Airtime Anatomy's
// PHY rates.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one RepeaterMeshController.
//   - RepeaterMeshStage    (repeater_mesh_stage.dart)
//   - RepeaterMeshControls (repeater_mesh_controls.dart)
// This screen only composes them. On a phone they stack; the Present button
// (desktop and tablet windows) opens the stage beside the controls over the
// SAME controller in the presenter layout (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router
// (lib/widgets/presenter/large_screen_gate.dart).
//
// THEME: context.colors only (dark §8 / light §8.20). See the painter for
// the color and motion notes.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'repeater_mesh_controller.dart';
import 'repeater_mesh_controls.dart';
import 'repeater_mesh_stage.dart';

export 'repeater_mesh_controller.dart'
    show
        kRepeaterMeshToolId,
        kRmCycle,
        kRmQuestionConfig,
        RepeaterMeshController,
        RmGuess,
        RmQuestion;

const String _kTitle = 'Repeaters and Mesh Backhaul';

class RepeaterMeshScreen extends StatefulWidget {
  const RepeaterMeshScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final RepeaterMeshController? controller;

  @override
  State<RepeaterMeshScreen> createState() => _RepeaterMeshScreenState();
}

class _RepeaterMeshScreenState extends State<RepeaterMeshScreen> {
  late final RepeaterMeshController _controller =
      widget.controller ?? RepeaterMeshController();

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
    stage: RepeaterMeshStage(controller: _controller),
    controls: RepeaterMeshControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.repeaterMesh, builder: _presenter),
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
                      RepeaterMeshStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      RepeaterMeshControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kRepeaterMeshToolId),
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

/// Play and reset for the normal screen (the presenter has keys).
class _PlayBar extends StatelessWidget {
  const _PlayBar({required this.controller});

  final RepeaterMeshController controller;

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
              label: Text(playing ? 'Pause' : 'Play the frames'),
            ),
            OutlinedButton.icon(
              onPressed: controller.resetAll,
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
            'The 1/T rule is for one radio relaying on one channel. It is '
            'worked out from airtime, not taken from a published multihop '
            'measurement. Each hop\'s level uses the same path-loss model as '
            'Roaming Walk, its MCS the receiver floors of Rate vs Range, and '
            'its PHY rate the 802.11ax timing of Airtime Anatomy.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Traffic flows one way, with nothing else on the channel: no '
            'neighbors, no collisions, no retries. The dedicated backhaul '
            'gives every hop a channel of its own; with two or more relays on '
            'one backhaul channel, those hops would take turns again. The '
            'delay counts only the forwarding delay, not time spent waiting '
            'for the air.',
            style: body,
          ),
        ],
      ),
    );
  }
}
