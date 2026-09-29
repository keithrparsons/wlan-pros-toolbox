// Polarization: Wi-Fi Classroom tool (polarization).
//
// One wave, drawn as its electric field along the direction of travel, in a
// 3D view you can turn. Pick Vertical, Horizontal, Slant 45°, Circular or
// Elliptical, show the horizontal and vertical parts it is made of, and read
// what the tip of the field traces (a line, a circle, an ellipse) and its
// axial ratio. Keith, 2026-09-29 (ruling 4): "Just the top graphic that shows
// Vertical, Horizontal, circular, slants, etc. Not the entire rest of that
// page." No receiving antenna, no mismatch loss, no indoor setting.
//
// CLEAN-ROOM BUILD (2026-09-29) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/45-polarization.md. Math in lib/services/wifi_lab/
// polarization_model.dart. The view follows EMANIM Classic by Andras
// Szilagyi (public domain); no EMANIM code is ported. Circular polarization
// is never labelled right-hand or left-hand (spec: the conventions differ
// and IEEE Std 145 is not pinned).
//
// STRUCTURE: one PolarizationController (polarization_controller.dart) holds
// the wave, the preset, the play state, the phase and the camera; the screen
// creates and disposes it and composes:
//   PolarizationStage     the 3D field and readouts (polarization_stage.dart)
//   PolarizationControls  the inputs (polarization_controls.dart)
// The 3D uses the orbit camera shared with Antenna Pattern
// (wifi_lab_orbit.dart). The Present button (desktop and tablet windows) puts
// the stage beside the controls over the SAME controller.
//
// States (SOP-007 §5):
//   - running     -> the field animates (default unless reduced motion is on)
//   - paused      -> Pause, app backgrounded, or reduced motion at open (the
//                    stage says so)
//   - empty       -> both amplitudes 0: the viewport says "No field" and the
//                    readouts say none
//   - custom      -> sliders off every preset: the select reads Custom
//   - error       -> none: every input is a clamped slider or a select
//   - disabled    -> none needed
//   - interactive -> themed Material controls with the global focus ring;
//                    the 3D viewport is focusable, shows a lime ring when
//                    focused, and rotates with the arrow keys

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/polarization_model.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'antenna_pattern_parts.dart';
import 'polarization_controller.dart';
import 'polarization_controls.dart';
import 'polarization_parts.dart';
import 'polarization_stage.dart';

export 'polarization_controller.dart' show PolarizationController;
export 'polarization_parts.dart' show kPolarizationToolId;

class PolarizationScreen extends StatefulWidget {
  const PolarizationScreen({
    super.key,
    this.initialPreset = PolarizationPreset.vertical,
  });

  final PolarizationPreset initialPreset;

  @override
  State<PolarizationScreen> createState() => _PolarizationScreenState();
}

class _PolarizationScreenState extends State<PolarizationScreen>
    with WidgetsBindingObserver {
  late final PolarizationController _controller = PolarizationController(
    initialPreset: widget.initialPreset,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: 'Polarization',
    stage: PolarizationStage(controller: _controller),
    controls: PolarizationControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Polarization'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.polarization, builder: _presenter),
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
                      PolarizationStage(
                        controller: _controller,
                        viewportHeight: isDesktop ? 400 : 320,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      PolarizationControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _ExplainerCard(),
                      ToolHelpFooter(toolId: kPolarizationToolId),
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

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    return const PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PatternSectionLabel('What you are seeing'),
          SizedBox(height: AppSpacing.xs),
          PatternNote(
            icon: Icons.call_split,
            message:
                'Every polarization is two waves added together: one '
                'horizontal, one vertical. Turn on the component waves to see '
                'them. In step, they add to a straight line. A quarter cycle '
                'apart and equal in size, they add to a field that turns in a '
                'circle.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternNote(
            icon: Icons.crop_square,
            message:
                'The square in the corner is the wave seen end on, from the '
                'front end looking back toward the source. The lime shape '
                'inside it is what the tip of the field traces: a line, a '
                'circle or an ellipse. The '
                'axial ratio is its long axis over its short axis: 1 for a '
                'circle, infinite for a line.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternNote(
            icon: Icons.graphic_eq,
            message:
                'Same frequency and wavelength for every preset. '
                'Polarization is the direction the field points, not how fast '
                'it cycles.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternNote(
            icon: Icons.history_edu_outlined,
            message:
                'This view follows EMANIM Classic by Andras Szilagyi, a '
                'public-domain program for animating light waves.',
          ),
        ],
      ),
    );
  }
}
