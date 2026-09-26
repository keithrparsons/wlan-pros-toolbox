// Legacy Protection Cost: Wi-Fi Classroom tool (legacy-protection).
//
// What an old 802.11b device costs a modern network while it sends nothing:
// a protection frame at an old, slow rate before every modern frame, and a
// longer slot time. Together they cut one 54 Mb/s sender's ceiling from about
// 30.5 to about 14.8 Mb/s. A beacon inspector shows the ERP bits and the HT
// Protection value that switch it on.
//
// CLEAN-ROOM BUILD (2026-09-27) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/39-legacy-protection.md. All math lives in
// lib/services/wifi_lab/legacy_protection_model.dart, which reuses Airtime
// Anatomy's timing (airtime_anatomy.dart) and the shared 802.11b timing
// (dsss_timing.dart).
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one LegacyProtectionController.
//   - LegacyProtectionStage    (legacy_protection_stage.dart)
//   - LegacyProtectionControls (legacy_protection_controls.dart)
// This screen only composes them. On a phone they stack; the Present button
// (desktop and tablet windows) opens the stage beside the controls over the
// SAME controller in the presenter layout (lib/widgets/presenter/).
//
// THEME: context.colors only (dark §8 / light §8.20). See the stage for the
// color, pattern and motion notes.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'legacy_protection_controller.dart';
import 'legacy_protection_controls.dart';
import 'legacy_protection_stage.dart';

export 'legacy_protection_controller.dart'
    show
        kLegacyProtectionToolId,
        kLpSweepDuration,
        LegacyProtectionController,
        LpGuess,
        LpQuestion;

const String _kTitle = 'Legacy Protection Cost';

class LegacyProtectionScreen extends StatefulWidget {
  const LegacyProtectionScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final LegacyProtectionController? controller;

  @override
  State<LegacyProtectionScreen> createState() => _LegacyProtectionScreenState();
}

class _LegacyProtectionScreenState extends State<LegacyProtectionScreen> {
  late final LegacyProtectionController _controller =
      widget.controller ?? LegacyProtectionController();

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
    stage: LegacyProtectionStage(controller: _controller),
    controls: LegacyProtectionControls(controller: _controller),
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
            toolRoute: AppRouter.legacyProtection,
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
                      LegacyProtectionStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      LegacyProtectionControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kLegacyProtectionToolId),
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

  final LegacyProtectionController controller;

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
              label: Text(playing ? 'Pause' : 'Play'),
            ),
            OutlinedButton.icon(
              onPressed: controller.stepCycle,
              style: style(),
              icon: const Icon(Icons.skip_next_rounded),
              label: const Text('Next cycle'),
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
            'The data frame and the ACK (acknowledgment) use the same timing '
            'as Airtime Anatomy: 802.11g at 2.4 GHz, a 20 µs preamble, '
            '6 µs signal extension, SIFS (short interframe space) 10 µs, the '
            'ACK at 24 Mb/s. Protection frames at 802.11b rates use the '
            '802.11b transmit time: 192 µs long or 96 µs short preamble and '
            'header, plus the bits over the rate, rounded up to a whole '
            'microsecond.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The network is open (no encryption bytes), which matches the '
            '254 µs data frame of the worked example. One sender, no '
            'collisions, no retries, and the old device sends nothing: '
            'Airtime Fairness shows the cost of its own slow traffic. '
            'Everything here is 2.4 GHz: there is no DSSS (direct sequence '
            'spread spectrum) at 5 GHz.',
            style: body,
          ),
        ],
      ),
    );
  }
}
