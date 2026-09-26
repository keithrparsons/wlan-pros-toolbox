// Antenna Pattern: Wi-Fi Lab tool (antenna-pattern).
//
// Change an antenna from omni to directional, change its gain, and watch the
// 3D pattern reshape; import a pattern file's two 2D cuts and rotate the 3D
// estimate built from them. Keith, 2026-09-25 (spec 14): "change from Omni
// to directional, change the Antenna Gain and visually see changes in the 3D
// antenna pattern... Import in an antenna pattern from a 2d version... Then
// change the gain to make it flatter, or wider, or have the edges fall off
// faster."
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/14-antenna-pattern.md and Deliverables/2026-09-25-antenna-
// simulator-research/brief.md. Math in lib/services/wifi_lab/
// antenna_pattern_math.dart, files in antenna_pattern_formats.dart. No
// vendor's or planning tool's pattern viewer was consulted; no vendor pattern
// file is bundled; the front/back hybrid reconstruction (patent) is not
// implemented.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets
// over one state object.
//   antenna_pattern_model.dart     AntennaPatternLab (inputs, cached grid and
//                                  mesh, the camera notifier)
//   antenna_pattern_stage.dart     AntennaPatternStage: 3D + the two cuts
//   antenna_pattern_controls.dart  AntennaPatternControls: inputs, readouts
//   antenna_pattern_mesh.dart      the 3D mesh, projection and depth sort
//   antenna_pattern_painters.dart  the CustomPainters
//   antenna_pattern_parts.dart     shared cards, rows, sliders, formatters
//
// PRESENTER (spec 00, 2026-09-26): the Present button (desktop and tablet
// windows) opens the same stage and controls over the SAME lab in the
// presenter layout (lib/widgets/presenter/). The 3D takes the stage's extra
// height with the two cuts beside it. Keys: Space spins the 3D view, Right
// turns it one step, R resets it, Up and Down move the antenna's main
// setting (gain, elements or shape; none for the dipole).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The 3D colors
// are the GL-003 §8.15.2 gain ramp in lib/theme/app_gain_ramp.dart, on a dark
// viewport in both themes, with a dBi legend. Lime marks the measured
// quantity on the 2D cuts. ASCII copy apart from units and symbols; no em
// dashes.
//
// MOTION (§8.8): nothing animates by itself. The 3D moves only under the
// user's finger, mouse or arrow keys, so reduced motion needs no special
// path.
//
// States (SOP-007 §5):
//   - loading     -> none: the grid (65,160 directions) is computed
//                    synchronously on-device in a few milliseconds
//   - empty       -> Imported selected with nothing read: the stage says how
//                    to load a pattern; readouts say they are waiting
//   - error       -> unreadable pasted text: the field shows the reason in
//                    words, the last good pattern stays on screen
//   - success     -> live 3D, cuts and readouts
//   - disabled    -> none needed: every control is valid in every state
//                    (sliders are clamped, the example menu always loads)
//   - interactive -> themed Material controls with the global focus ring;
//                    the 3D viewport is focusable, shows a lime ring when
//                    focused, and rotates with the arrow keys

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/antenna_pattern_math.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'antenna_pattern_controls.dart';
import 'antenna_pattern_model.dart';
import 'antenna_pattern_parts.dart';
import 'antenna_pattern_stage.dart';
import 'wifi_lab_presenter_follow.dart';

export 'antenna_pattern_parts.dart' show kAntennaPatternToolId;

class AntennaPatternScreen extends StatefulWidget {
  const AntennaPatternScreen({
    super.key,
    this.initialKind = AntennaModelKind.omni,
  });

  final AntennaModelKind initialKind;

  @override
  State<AntennaPatternScreen> createState() => _AntennaPatternScreenState();
}

class _AntennaPatternScreenState extends State<AntennaPatternScreen> {
  late final AntennaPatternLab _lab = AntennaPatternLab(
    initialKind: widget.initialKind,
  );

  @override
  void dispose() {
    _lab.dispose();
    super.dispose();
  }

  // Copy payload (GL-003 §8.16).
  String _buildCopyText() {
    final PatternResult? r = _lab.result;
    final StringBuffer b = StringBuffer()
      ..writeln('Antenna Pattern (${_lab.kind.label})');
    if (r == null) {
      b.writeln('No pattern loaded.');
      return b.toString().trimRight();
    }
    final GainGrid g = r.grid;
    final double? hbw = r.cuts.horizontalBeamwidthDeg;
    final double? vbw = r.cuts.verticalBeamwidthDeg;
    b
      ..writeln(
        'Peak gain: ${fmtDbi(g.peakDbi)} (${fmtDbd(dbiToDbd(g.peakDbi))}), '
        '${fmtElevation(g.peakTheta - 90.0)}',
      )
      ..writeln(
        'Half-power beamwidth: horizontal '
        '${hbw == null ? 'omni' : fmtDeg1(hbw)}, vertical '
        '${vbw == null ? 'none' : fmtDeg1(vbw)}',
      )
      ..writeln('Mounting: ${_lab.mount.label}');
    if (!r.cuts.looksOmni) {
      b.writeln(
        'Front-to-back: '
        '${fmtDb1(g.peakDbi - g.oppositePeakDbi())} dB straight back, '
        '${fmtDb1(g.peakDbi - r.worstRear.dbi)} dB worst in the rear 120°',
      );
    }
    if (r.estimated) {
      b.writeln(
        '3D estimated from two cuts by ${_lab.method.label.toLowerCase()}',
      );
      final MethodErrors? e = r.errors;
      if (e != null) {
        for (final ReconstructionMethod m in ReconstructionMethod.values) {
          b.writeln(
            '${m.label} error: RMS ${e.of(m).rmsDb.toStringAsFixed(2)} dB, '
            'worst ${fmtDb1(e.of(m).worstDb)} dB',
          );
        }
      }
    }
    b.writeln(
      'Polarization mismatch at ${fmtDeg(_lab.polarizationDeg)}: '
      '${fmtPolarizationLoss(_lab.polarizationLossDb)}',
    );
    return b.toString().trimRight();
  }

  /// The presenter layout over this screen's lab (shared, not copied). The
  /// main slider's key follows the antenna, so the layout is rebuilt when
  /// that changes (and only then).
  Widget _presenter(BuildContext context) => PresenterFollow(
    listenable: _lab,
    select: () => _lab.mainSliderLabel,
    builder: (BuildContext context) => PresenterLayout(
      title: 'Antenna Pattern',
      stage: AntennaPatternStage(lab: _lab),
      controls: AntennaPatternControls(lab: _lab),
      actions: _lab.presenterActions,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Antenna Pattern'),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.antennaPattern,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _buildCopyText),
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
                      AntennaPatternStage(
                        lab: _lab,
                        viewportHeight: isDesktop ? 400 : 320,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AntennaPatternControls(lab: _lab),
                      ToolHelpFooter(toolId: kAntennaPatternToolId),
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
