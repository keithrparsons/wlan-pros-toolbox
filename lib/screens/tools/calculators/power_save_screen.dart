// Power Save: Wi-Fi Classroom tool (power-save).
//
// A client and its AP on a timeline: beacons every beacon interval, a DTIM
// every N beacons, frames the AP holds while the client dozes, and the
// client's radio waking and sleeping under four modes (always awake, legacy
// PS with PS-Poll, U-APSD, and Target Wake Time). Two modes side by side
// show what each saving costs in latency. Readouts: time awake, average
// current, a battery estimate, and downlink, group and uplink latency.
//
// CLEAN-ROOM BUILD (2026-09-25) from the Wi-Fi Classroom wave 3 research brief §9
// and wave 5 brief §9, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/
// specs/24-power-save.md. All rules and the run live in
// lib/services/wifi_lab/power_save_model.dart.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one PowerSaveController.
//   - PowerSaveStage    (power_save_stage.dart): the timeline.
//   - PowerSaveControls (power_save_controls.dart): readouts and inputs, in
//                       parts (readouts, mode, ap, client, twt, traffic,
//                       energy).
// This screen only composes them. On a phone they stack; the Present button
// (desktop and tablet windows) opens the stage beside PowerSaveControls over
// the SAME controller in the presenter layout (lib/widgets/presenter/).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The awake
// states take PsPalette (§8.15.2), each named in the legend. Lime marks the
// measured quantities; amber, with a word and an icon, is the only verdict
// (group frames missed while dozing, TWT values that cannot run).
//
// MOTION (§8.8): none. The run is computed whole; the student slides a
// window along it.
//
// States (SOP-007 §5):
//   - fresh       -> Legacy PS vs TWT at 1 s, phone-idle traffic, window
//                    at 0 s
//   - empty       -> no downlink / uplink / group traffic: the readouts say
//                    "No downlink", "No uplink", "None heard"
//   - error       -> a TWT mantissa that is empty, 0 or over 16 bits, an
//                    interval over 5 minutes, or a wake duration as long as
//                    the interval: the reason in words, and the last valid
//                    run stays on screen
//   - disabled    -> "New random pattern" with regular arrivals, with the
//                    reason in words
//   - loading     -> not reachable: the model is synchronous and pure
//   - interactive -> themed Material controls with the global focus ring;
//                    the timeline carries a worded screen-reader summary

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/power_save_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'power_save_controller.dart';
import 'power_save_controls.dart';
import 'power_save_parts.dart';
import 'power_save_stage.dart';

export 'power_save_controller.dart' show kPowerSaveToolId, PowerSaveController;

const String _kTitle = 'Power Save';

class PowerSaveScreen extends StatefulWidget {
  const PowerSaveScreen({
    super.key,
    this.initial,
    this.compare = PsMode.twt,
    this.controller,
  });

  /// Test seam: start from a given configuration.
  final PsConfig? initial;

  /// Test seam: the mode to compare with, or null for none.
  final PsMode? compare;

  /// Test and render seam: a controller the caller owns and disposes (then
  /// [initial] and [compare] are ignored). Null (the app) makes the screen
  /// create and dispose its own.
  final PowerSaveController? controller;

  @override
  State<PowerSaveScreen> createState() => _PowerSaveScreenState();
}

class _PowerSaveScreenState extends State<PowerSaveScreen> {
  late final PowerSaveController _controller =
      widget.controller ??
      PowerSaveController(initial: widget.initial, compare: widget.compare);

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: PowerSaveStage(controller: _controller),
    controls: PowerSaveControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.powerSave, builder: _presenter),
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
                      PowerSaveStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      PowerSaveControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kPowerSaveToolId),
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
    String ms(double us) => '${(us / 1000).toStringAsFixed(1)} ms';
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A teaching model of one client and one AP. The field sizes and '
            'units (TU, the TWT mantissa and exponent, the U-APSD flags and '
            'Max SP Length) are the standard\'s. The durations are '
            'illustrative: waking takes ${ms(kWakeRampUs)}, a beacon '
            '${ms(kBeaconRxUs)}, a PS-Poll exchange ${ms(kPsPollUs)}, a frame '
            'in a service period ${ms(kSpFrameUs)}, a trigger '
            '${ms(kTriggerUs)}, an uplink frame ${ms(kUplinkUs)}, a group '
            'frame ${ms(kGroupFrameUs)}.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Other clients in the cell doze, so the AP holds broadcast and '
            'multicast for the DTIM in every mode. The TIM here is set when '
            'any frame waits for the client. Real clients also stay awake a '
            'while after traffic, retry, scan and roam; APs limit how long '
            'they hold frames; broadcast TWT here starts at a beacon; and '
            'TWT uplink is sent at once rather than held for the next '
            'service period. None of that is modeled.',
            style: body,
          ),
        ],
      ),
    );
  }
}
