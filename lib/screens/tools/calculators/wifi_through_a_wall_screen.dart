// Wi-Fi Through a Wall: Wi-Fi Lab tool (wifi-through-a-wall).
//
// One wave, one wall. Part of the wave reflects off the face and the
// amplitude decays through the wall; the frequency never changes, so the
// drawn wave keeps one wavelength everywhere unless the optional "Show
// wavelength inside the material" view is on. Then the per-band story: concrete loses more
// at 6 GHz than at 2.4 GHz, but thin panels do not lose monotonically more at
// higher frequency, because of thin-slab resonance.
//
// CLEAN-ROOM BUILD (2026-09-25) from ITU-R P.2040-4 as set out in myPKA
// Deliverables/2026-09-25-wifi-lab-research/brief.md §6.3-§6.4, per
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/12-wall-slab.md. All math
// lives in lib/services/wifi_lab/wall_slab_physics.dart.
//
// This is NOT the 'rf-attenuation' tool, which is untouched; whether its
// numbers change is Keith's decision (spec).
//
// STRUCTURE: one WallSlabController (wifi_through_a_wall_controller.dart)
// holds the wall, the play state, the view toggle and the phase; the screen
// creates and disposes it and composes separate widgets over it:
//   WallSlabStage     the animated wave (wifi_through_a_wall_stage.dart)
//   WallSlabControls  the inputs      (wifi_through_a_wall_controls.dart)
//   WallSlabReadouts, WallBandsCard, WallMeasuredCard  the numbers
// The Present button (desktop and tablet windows) puts the stage beside the
// controls over the SAME controller (lib/widgets/presenter/).
//
// States (SOP-007 §5):
//   - running     -> the wave animates (default unless reduced motion is on)
//   - paused      -> Pause, app backgrounded, or reduced motion at open
//   - error       -> thickness field outside 1-500 mm or unparseable: inline
//                    error text, the last valid wall stays on screen
//   - empty       -> a material with no measured data: the measured card says
//                    so instead of showing an empty table
//   - disabled    -> "Set the wall to N mm" is hidden when the wall is
//                    already that thick
//   - interactive -> themed Material controls with the global focus ring;
//                    the plot and tables carry worded Semantics labels

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'wifi_through_a_wall_controller.dart';
import 'wifi_through_a_wall_controls.dart';
import 'wifi_through_a_wall_parts.dart';
import 'wifi_through_a_wall_stage.dart';

export 'wifi_through_a_wall_controller.dart' show WallSlabController;
export 'wifi_through_a_wall_parts.dart' show kWifiThroughAWallToolId;

class WifiThroughAWallScreen extends StatefulWidget {
  const WifiThroughAWallScreen({super.key, this.initial = const WallConfig()});

  /// Starting wall. Defaults to 102 mm concrete on channel 100.
  final WallConfig initial;

  @override
  State<WifiThroughAWallScreen> createState() => _WifiThroughAWallScreenState();
}

class _WifiThroughAWallScreenState extends State<WifiThroughAWallScreen>
    with WidgetsBindingObserver {
  late final WallSlabController _controller = WallSlabController(
    initial: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Animate on open only when reduced motion is off (GL-003 §8.8); the
    // controller decides once.
    _controller.decideMotion(
      reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.setPlaying(false);
  }

  /// The presenter layout over this screen's controller (shared, not
  /// copied). The loss and the three-band table are on the stage; the
  /// detailed readouts and the measured values fold into the panel.
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'Wi-Fi Through a Wall',
    stage: WallSlabStage(controller: _controller),
    controls: ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, _) {
        final WallConfig c = _controller.config;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WallSlabControls(config: c, onChanged: _controller.setConfig),
            const SizedBox(height: AppSpacing.xs),
            PresenterDisclosure(
              title: 'Readouts: absorption, reflection, wavelengths',
              children: <Widget>[WallSlabReadouts(config: c)],
            ),
            PresenterDisclosure(
              title: 'Measured values beside the model',
              children: <Widget>[
                WallMeasuredCard(
                  config: c,
                  onUseThickness: (double mm) =>
                      _controller.setConfig(c.copyWith(thicknessMm: mm)),
                ),
              ],
            ),
          ],
        );
      },
    ),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Through a Wall'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.wifiThroughAWall,
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
                      WallSlabStage(
                        controller: _controller,
                        plotHeight: isDesktop ? 260 : 200,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ListenableBuilder(
                        listenable: _controller,
                        builder: (BuildContext context, _) {
                          final WallConfig c = _controller.config;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              WallSlabControls(
                                config: c,
                                onChanged: _controller.setConfig,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              WallSlabReadouts(config: c),
                              const SizedBox(height: AppSpacing.sm),
                              WallBandsCard(config: c),
                              const SizedBox(height: AppSpacing.sm),
                              WallMeasuredCard(
                                config: c,
                                onUseThickness: (double mm) => _controller
                                    .setConfig(c.copyWith(thicknessMm: mm)),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _FreeSpaceCard(),
                      const SizedBox(height: AppSpacing.sm),
                      const _ExplainerCard(),
                      ToolHelpFooter(toolId: kWifiThroughAWallToolId),
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

/// Free-space loss is a separate effect (spec): keeps the student from
/// blaming the wall for the antenna-aperture difference.
class _FreeSpaceCard extends StatelessWidget {
  const _FreeSpaceCard();

  @override
  Widget build(BuildContext context) {
    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Not the wall: free-space loss'),
          const SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.settings_input_antenna,
            message:
                'Every number above is the wall alone. Separately, with the '
                'same antennas, free-space loss rises '
                '${fmt1(fsplDeltaDb(2.4, 5.5))} dB from 2.4 to 5.5 GHz and '
                '${fmt1(fsplDeltaDb(2.4, 6.5))} dB from 2.4 to 6.5 GHz, '
                'because an antenna at a shorter wavelength captures less. '
                'That happens with no wall at all. The Free Space Path Loss '
                'calculator covers it.',
          ),
        ],
      ),
    );
  }
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    return const WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WallSectionLabel('What you are seeing'),
          SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.u_turn_left,
            message:
                'Reflection: in front of the wall the incident and reflected '
                'waves overlap. Their peaks line up every half wavelength and '
                'cancel in between, which is why moving a phone a few '
                'centimeters can change the signal.',
          ),
          SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.graphic_eq,
            message:
                'Same frequency everywhere: in front of, inside and behind '
                'the wall the wave cycles at the channel frequency. The wave '
                'does travel slower inside, so the same frequency packs into '
                'a shorter wavelength there; switch on Show wavelength inside '
                'the material to see it.',
          ),
          SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.trending_down,
            message:
                'Decay: the material turns some of the energy into heat, so '
                'the amplitude falls steadily through the wall. The wave '
                'behind is the same frequency, just smaller.',
          ),
        ],
      ),
    );
  }
}
