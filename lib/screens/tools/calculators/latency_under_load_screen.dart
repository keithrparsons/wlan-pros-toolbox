// Why a Busy Line Lags: Wi-Fi Classroom tool (latency-under-load).
//
// A video call's delay on a home line, before, during and after someone
// else's upload. With smart queue management (SQM) off, the call's packets
// wait behind the upload and the delay climbs from the idle figure to
// hundreds of milliseconds (the FCC's measurements). With it on, the router
// keeps the queue short and the call stays near idle (illustrative). A
// faster plan drains a queue faster, but the upload still fills it.
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-27-
// classroom-candidates/RESEARCH-BRIEF.md section 3, candidate 1. All math
// lives in lib/services/wifi_lab/latency_under_load_model.dart.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one LatencyUnderLoadController.
//   - LatencyUnderLoadStage    (latency_under_load_stage.dart)
//   - LatencyUnderLoadControls (latency_under_load_controls.dart)
// This screen only composes them. On a phone they stack; the Present button
// (desktop and tablet windows) opens the stage beside the controls over the
// SAME controller in the presenter layout (lib/widgets/presenter/). The
// large-screen notice is applied centrally by the router.
//
// No lengths appear, so there is no metric/imperial switch.
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
import 'latency_under_load_controller.dart';
import 'latency_under_load_controls.dart';
import 'latency_under_load_stage.dart';

export 'latency_under_load_controller.dart'
    show kLatencyUnderLoadToolId, kLulStepS, LatencyUnderLoadController;

const String _kTitle = 'Why a Busy Line Lags';

class LatencyUnderLoadScreen extends StatefulWidget {
  const LatencyUnderLoadScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final LatencyUnderLoadController? controller;

  @override
  State<LatencyUnderLoadScreen> createState() => _LatencyUnderLoadScreenState();
}

class _LatencyUnderLoadScreenState extends State<LatencyUnderLoadScreen> {
  late final LatencyUnderLoadController _controller =
      widget.controller ?? LatencyUnderLoadController();

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
    stage: LatencyUnderLoadStage(controller: _controller),
    controls: LatencyUnderLoadControls(controller: _controller),
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
            toolRoute: AppRouter.latencyUnderLoad,
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
                      LatencyUnderLoadStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      LatencyUnderLoadControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kLatencyUnderLoadToolId),
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

  final LatencyUnderLoadController controller;

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
              label: Text(playing ? 'Pause' : 'Play the call'),
            ),
            OutlinedButton.icon(
              onPressed: controller.step,
              style: style(),
              icon: const Icon(Icons.skip_next_rounded),
              label: Text('${kLulStepS.round()} s on'),
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
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Why a faster plan does not fix it'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lag is delay, not speed. An upload sends as fast as the line '
            'allows, so it fills the queue on any plan. A faster plan '
            'drains the queue faster, but the call still waits behind '
            'whatever is in it. Keeping the queue short is what brings the '
            'delay back down, and that is what smart queue management does.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.sm),
          const AirtimeSectionTitle('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One home line, one upload, one call. The delay here is the '
            'line\'s: the Wi-Fi hop, the far end and any queue in the '
            'provider\'s network are left out, and nothing jitters. The FCC '
            'measured in 2022 and notes that some providers have since added '
            'queue management of their own, so today\'s lines may do better.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'To measure your own line while it is busy, use Network Quality '
            '(its responsiveness figure) or Test My Connection (its loaded '
            'responsiveness check). Both measure delay during a download.',
            style: body,
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.netQuality),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Network Quality'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.testMyConnection),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Test My Connection'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
