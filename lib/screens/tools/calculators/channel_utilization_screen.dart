// Channel Utilization Meter: Wi-Fi Classroom tool (channel-utilization).
//
// The number an AP reports as "channel utilization" in its BSS Load element,
// and what it does and does not mean: busy is not the same as used for your
// data, idle is not the same as available, one sender at full speed cannot
// push it to 100%, and the station count beside it counts associated
// stations, not busy ones.
//
// CLEAN-ROOM BUILD (2026-09-26) from myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/37-channel-utilization.md. All math lives in
// lib/services/wifi_lab/channel_utilization_model.dart, which reuses Airtime
// Anatomy's timing (airtime_anatomy.dart) and the Medium Access engine's
// contention rules (medium_access_engine.dart).
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one ChannelUtilizationController.
//   - ChannelUtilizationStage    (channel_utilization_stage.dart)
//   - ChannelUtilizationControls (channel_utilization_controls.dart)
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
import 'channel_utilization_controller.dart';
import 'channel_utilization_controls.dart';
import 'channel_utilization_stage.dart';

export 'channel_utilization_controller.dart'
    show
        kChannelUtilizationToolId,
        ChannelUtilizationController,
        CuQuestion,
        CuGuess,
        CuSpeed;

const String _kTitle = 'Channel Utilization Meter';

class ChannelUtilizationScreen extends StatefulWidget {
  const ChannelUtilizationScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final ChannelUtilizationController? controller;

  @override
  State<ChannelUtilizationScreen> createState() =>
      _ChannelUtilizationScreenState();
}

class _ChannelUtilizationScreenState extends State<ChannelUtilizationScreen> {
  late final ChannelUtilizationController _controller =
      widget.controller ?? ChannelUtilizationController();

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
    stage: ChannelUtilizationStage(controller: _controller),
    controls: ChannelUtilizationControls(controller: _controller),
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
            toolRoute: AppRouter.channelUtilization,
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
                      CuTransport(controller: _controller, compact: false),
                      const SizedBox(height: AppSpacing.xs),
                      ChannelUtilizationStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      ChannelUtilizationControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kChannelUtilizationToolId),
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
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The formula is the definition, not any product\'s code: real '
            'access points may compute it differently, for example by '
            'averaging the radio\'s busy counters over a period the operator '
            'sets. Only the primary 20 MHz channel is modeled.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Frame timing is Airtime Anatomy\'s, at 2.4 GHz with 802.11g '
            'rates and the short 9 µs slot; contention follows the Medium '
            'Access Simulator\'s rules. Every station hears every other. '
            'After a collision everyone waits out the ACK timeout. Frames '
            'carry no encryption bytes. Beacons\' own airtime is left out '
            '(SSID Airtime shows it).',
            style: body,
          ),
        ],
      ),
    );
  }
}
