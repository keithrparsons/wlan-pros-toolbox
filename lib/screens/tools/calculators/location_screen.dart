// Where Am I? Signal Strength vs Round-Trip Timing: Wi-Fi Classroom tool
// (location-rssi-ftm).
//
// The student drags a device across a floor of APs and watches two ways of
// finding it. What they should see (spec 33):
//   1. Signal strength falls with distance, so it can estimate distance, but
//      badly: a few dB of shadowing becomes a large distance error, and the
//      error grows with distance.
//   2. A one-sigma error multiplies the distance by 10^(sigma / 10n): with
//      sigma = 6 dB and n = 3, x1.58, so 10 m reads 6.3 m to 15.8 m.
//   3. Fine timing measurement (FTM, 802.11mc) times the round trip instead;
//      light covers about 30 cm per nanosecond, so timing gives meter-class
//      distance.
//   4. Three or more distances to known APs give a position (trilateration).
//      Bad distances give a bad, and sometimes impossible, position.
//   5. Timing has its own errors: a blocked direct path reads long.
//
// CLEAN-ROOM BUILD (2026-09-26) from the Wi-Fi Classroom wave 4 research
// brief, row F, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 33-location-rssi-vs-ftm.md. All math lives in lib/services/wifi_lab/
// location_engine.dart. No vendor or product is named anywhere in the tool.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets over one LocationController.
//   - LocationStage    (location_stage.dart): the floor(s), circles, the
//                      estimate and its scatter, the lesson banner.
//   - LocationControls (location_controls.dart): method, readouts, signal
//                      strength, timing, lesson, floor.
// This screen only composes them. The Present button (desktop and tablet
// windows) puts the stage beside the controls over the SAME controller
// (lib/widgets/presenter/, spec 00).
//
// THEME: context.colors only. Methods are told apart by label and marker
// shape (diamond, triangle); lime marks the estimates, the computed quantity.
//
// MOTION (§8.8): nothing animates. Every change is a redraw in answer to the
// user's own drag or control, so reduced motion needs no special path.
//
// States (SOP-007 §5):
//   - success     -> the floor(s), circles, estimate, scatter and readouts
//   - degenerate  -> circles that cannot meet: a worded "impossible" note
//                    names the AP pairs, and the dot is the best compromise;
//                    a fix that cannot be computed reads "no fix"
//   - empty / loading / error -> not reachable: there are always 3 to 6 APs
//                    and the engine is synchronous and pure; every input is a
//                    bounded slider, toggle, chip, select or button
//   - interactive -> themed Material controls with the global focus ring; the
//                    floors carry worded screen-reader labels, and a drag on
//                    the floor has slider equivalents

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/unit_system_switch.dart';
import 'location_controller.dart';
import 'location_controls.dart';
import 'location_parts.dart';
import 'location_stage.dart';

export 'location_controller.dart' show kLocationToolId;

const String _kTitle = 'Where Am I? Signal Strength vs Round-Trip Timing';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, this.controller});

  /// Test seam: drive the screen from a given controller (not disposed here).
  final LocationController? controller;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
    with UnitSystemFollower<LocationScreen> {
  @override
  void applyUnitSystem(UnitSystem system) {
    _controller.setUnits(system);
  }

  late final LocationController _controller =
      widget.controller ?? LocationController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    showUnitSwitch: true,
    title: _kTitle,
    stage: LocationStage(controller: _controller),
    controls: LocationControls(controller: _controller),
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
            toolRoute: AppRouter.locationRssiFtm,
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
                      LocationStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      LocationControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kLocationToolId),
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
    return LocCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LocSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A teaching model. Signal strength follows the log-distance '
            'path-loss model with Gaussian shadowing; the device inverts the '
            'same model without the shadowing, because it cannot know it. '
            'Timing adds a Gaussian ranging error and, for a blocked direct '
            'path, a fixed extra distance.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Illustrative values: the shadowing sigma, the power each AP '
            'radiates and the blocked-path extra distance. The '
            '${locVendorRange(UnitSystemScope.systemOf(context))} '
            'timing accuracy is from a vendor developer document. Real '
            'systems also face AP position errors, clock offsets, antennas and '
            'floors above and below.',
            style: body,
          ),
        ],
      ),
    );
  }
}
