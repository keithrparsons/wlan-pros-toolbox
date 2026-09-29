// Antenna Pattern: Wi-Fi Classroom tool (antenna-pattern).
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
// FLOOR COVERAGE (spec 46, 2026-09-29): a second view of the same antenna,
// switched above the stage ("3D pattern" / "Floor coverage"). It puts the
// pattern on a warehouse or office floor at a mount height from 3 to 15 m:
// a side view to scale with the floor colored by what a client receives,
// readouts both ways, and a link into Uplink vs Downlink. State in
// antenna_floor_controller.dart (FloorCoverageController, over this lab),
// drawing in antenna_floor_stage.dart, inputs in antenna_floor_controls.dart.
// In the floor view the presenter keys change: Up and Down move the mount
// height, Right steps to the next preset, R goes back to the first; V
// switches views in both.
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
import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/antenna_pattern_math.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'antenna_floor_controller.dart';
import 'antenna_floor_controls.dart';
import 'antenna_floor_stage.dart';
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
    this.initialView = AntennaStageView.pattern,
  });

  final AntennaModelKind initialKind;

  /// Which view the stage opens on (the 3D pattern unless a caller asks).
  final AntennaStageView initialView;

  @override
  State<AntennaPatternScreen> createState() => _AntennaPatternScreenState();
}

class _AntennaPatternScreenState extends State<AntennaPatternScreen> {
  late final AntennaPatternLab _lab = AntennaPatternLab(
    initialKind: widget.initialKind,
  );
  late final FloorCoverageController _floor = FloorCoverageController(
    lab: _lab,
    initialView: widget.initialView,
  );

  @override
  void dispose() {
    _floor.dispose();
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
    final FloorLink? link = _floor.link;
    final FloorCell? cell = _floor.cell;
    if (_floor.showingFloor && link != null && cell != null) {
      b
        ..writeln()
        ..writeln(
          'Floor coverage: mount height ${fmtFloorLength(_floor.heightM)}, '
          'AP ${_floor.apTxDbm.round()} dBm, client '
          '${_floor.clientTxDbm.round()} dBm, ${_floor.band.label}, '
          'exponent ${_floor.exponent.toStringAsFixed(1)}',
        );
      for (final double x in kFloorReadoutsM) {
        final FloorPoint p = link.at(x);
        b.writeln(
          '${fmtFloorWhere(x)}: AP to client '
          '${fmtFloorLevelDbm(p.downlinkDbm, inNull: floorInNull(p))}, '
          'client to AP '
          '${fmtFloorLevelDbm(p.uplinkDbm, inNull: floorInNull(p))}',
        );
      }
      b.writeln(
        'Floor cell radius at $fmtFloorTarget: '
        '${floorCellWords(cell)}'
        '${cell.holeM == null ? '' : ', hole under the AP out to ${fmtFloorLength(cell.holeM!)}'}',
      );
    }
    return b.toString().trimRight();
  }

  /// The presenter layout over this screen's lab (shared, not copied). The
  /// main slider's key follows the antenna, so the layout is rebuilt when
  /// that changes (and only then).
  Widget _presenter(BuildContext context) => PresenterFollow(
    listenable: _floor,
    select: () => _floor.presenterKey,
    builder: (BuildContext context) => PresenterLayout(
      title: 'Antenna Pattern',
      // The view switch sits on the stage, over the view it changes, so the
      // 3D view's controls panel keeps the height it was fitted to.
      stage: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AntennaViewSwitch(floor: _floor),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _floor.showingFloor
                ? FloorCoverageStage(floor: _floor)
                : AntennaPatternStage(lab: _lab),
          ),
        ],
      ),
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_floor.showingFloor) ...<Widget>[
            FloorCoverageControls(floor: _floor),
            const SizedBox(height: AppSpacing.sm),
            PatternCard(
              child: PresenterDisclosure(
                title: 'Antenna: ${_lab.kind.label}',
                children: <Widget>[AntennaPatternControls(lab: _lab)],
              ),
            ),
          ] else
            AntennaPatternControls(lab: _lab),
        ],
      ),
      actions: _floor.presenterActions,
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
                      AntennaViewSwitch(floor: _floor),
                      const SizedBox(height: AppSpacing.sm),
                      ListenableBuilder(
                        listenable: _floor,
                        builder: (BuildContext context, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (_floor.showingFloor)
                              FloorCoverageStage(
                                floor: _floor,
                                viewportHeight: isDesktop ? 400 : 260,
                              )
                            else
                              AntennaPatternStage(
                                lab: _lab,
                                viewportHeight: isDesktop ? 400 : 320,
                              ),
                            const SizedBox(height: AppSpacing.sm),
                            if (_floor.showingFloor) ...<Widget>[
                              FloorCoverageControls(floor: _floor),
                              const SizedBox(height: AppSpacing.sm),
                              const PatternSectionLabel(
                                'The antenna on the floor',
                              ),
                              const SizedBox(height: AppSpacing.xs),
                            ],
                            AntennaPatternControls(lab: _lab),
                          ],
                        ),
                      ),
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
