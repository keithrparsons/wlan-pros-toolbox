// Controls for the Wi-Fi Lab "Antenna Pattern" tool (antenna-pattern): the
// inputs and the readouts. They write AntennaPatternLab and never draw the
// pattern, so a presenter layout can put them beside AntennaPatternStage
// unchanged.
//
// IMPORT: the app has no file-picking dependency (pubspec.yaml, 2026-09-25),
// so a pattern file is read by PASTING its text. No dependency was added for
// this; the card says so.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/antenna_pattern_formats.dart';
import '../../../services/wifi_lab/antenna_pattern_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'antenna_pattern_model.dart';
import 'antenna_pattern_parts.dart';

class AntennaPatternControls extends StatelessWidget {
  const AntennaPatternControls({super.key, required this.lab});
  final AntennaPatternLab lab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lab,
      builder: (BuildContext context, _) {
        const Widget gap = SizedBox(height: AppSpacing.sm);
        if (PresenterMode.isActive(context)) {
          // Presenter panel: the headline readouts are on the stage, so the
          // panel keeps the antenna and its sliders, mounting and
          // polarization; the rest of the readouts and the explainer fold.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ModelCard(lab: lab, presenting: true),
              gap,
              if (lab.kind == AntennaModelKind.imported) ...<Widget>[
                _ImportCard(lab: lab, presenting: true),
                gap,
              ],
              _MountCard(lab: lab, presenting: true),
              gap,
              PatternCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PresenterDisclosure(
                      title:
                          'Polarization mismatch: '
                          '${fmtPolarizationLoss(lab.polarizationLossDb)}',
                      children: <Widget>[
                        _PolarizationCard(lab: lab, presenting: true),
                      ],
                    ),
                    PresenterDisclosure(
                      title: 'All readouts',
                      children: <Widget>[_ReadoutsCard(lab: lab)],
                    ),
                    const PresenterDisclosure(
                      title: 'What you are seeing',
                      children: <Widget>[_ExplainerCard()],
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ModelCard(lab: lab),
            gap,
            if (lab.kind == AntennaModelKind.imported) ...<Widget>[
              _ImportCard(lab: lab),
              gap,
            ],
            _ReadoutsCard(lab: lab),
            gap,
            _MountCard(lab: lab),
            gap,
            _PolarizationCard(lab: lab),
            gap,
            const _ExplainerCard(),
          ],
        );
      },
    );
  }
}

// ── Model and its parameters ──────────────────────────────────────────────

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.lab, this.presenting = false});
  final AntennaPatternLab lab;

  /// Presenter panel: the sentences under the controls are dropped, and the
  /// directional antenna's floors and tilt fold.
  final bool presenting;

  static String blurb(AntennaModelKind k) => switch (k) {
    AntennaModelKind.dipole =>
      'The reference antenna: a half-wave dipole, 2.15 dBi (0 dBd). A '
          'doughnut with nothing straight up or down.',
    AntennaModelKind.omni =>
      'An omni set by its gain, using the ITU-R F.1336 planning envelope. '
          'Raise the gain and the doughnut flattens into a pancake.',
    AntennaModelKind.collinear =>
      'Dipoles stacked in a vertical line. More elements squeeze the energy '
          'toward the horizon; a phase step between them tilts the cone down.',
    AntennaModelKind.directional =>
      'A patch or sector, using the 3GPP TR 38.901 element: beamwidths, a '
          'front-to-back floor and a side-lobe floor.',
    AntennaModelKind.imported =>
      'A pattern file with a horizontal and a vertical cut. The 3D between '
          'the cuts is estimated, not measured.',
  };

  @override
  Widget build(BuildContext context) {
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Antenna',
            semanticLabel: 'Antenna model',
            field: AppSelect<AntennaModelKind>(
              value: lab.kind,
              semanticLabel: 'Antenna model',
              items: <AppSelectItem<AntennaModelKind>>[
                for (final AntennaModelKind k in AntennaModelKind.values)
                  (k, k.label),
              ],
              onChanged: lab.setKind,
            ),
          ),
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            PatternCaption(blurb(lab.kind)),
          ],
          ..._parameters(context),
          if (lab.kind.isParametric) ...<Widget>[
            SizedBox(height: presenting ? AppSpacing.xs : AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: lab.rebuildFromTwoCuts,
              icon: const Icon(Icons.content_cut, size: 20),
              label: const Text('Rebuild from its two cuts'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.textPrimary,
                side: BorderSide(
                  color: context.colors.borderStrong,
                  width: 1.5,
                ),
                minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
              ),
            ),
            if (!presenting) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              const PatternCaption(
                'Writes this antenna as an MSI file (two 2D cuts), reads it '
                'back and rebuilds the 3D from the cuts, the way a planning '
                'tool does. The readouts then show how far off the rebuild '
                'is.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _parameters(BuildContext context) {
    const Widget gap = SizedBox(height: AppSpacing.xs);
    switch (lab.kind) {
      case AntennaModelKind.dipole:
      case AntennaModelKind.imported:
        return const <Widget>[];
      case AntennaModelKind.omni:
        final double th3 = f1336OmniBeamwidthDeg(lab.omniGainDbi);
        return <Widget>[
          gap,
          PatternSlider(
            label: 'Gain',
            valueText:
                '${fmtDbi(lab.omniGainDbi)} (${fmtDbd(dbiToDbd(lab.omniGainDbi))})',
            value: lab.omniGainDbi,
            min: kOmniGainMin,
            max: kOmniGainMax,
            divisions: ((kOmniGainMax - kOmniGainMin) * 4).round(),
            onChanged: (double v) => lab.setOmniGain(
              v <= kOmniGainMin + 0.01 ? kOmniGainMin : (v * 4).round() / 4,
            ),
            semanticValue: (double v) => fmtDbi(v),
          ),
          PatternSlider(
            label: 'Electrical downtilt',
            valueText: fmtDeg(lab.omniTiltDeg),
            value: lab.omniTiltDeg,
            min: 0,
            max: kOmniTiltMax,
            divisions: kOmniTiltMax.round(),
            onChanged: (double v) => lab.setOmniTilt(v.roundToDouble()),
            semanticValue: (double v) => '${v.round()} degrees',
          ),
          if (!presenting)
            PatternCaption(
              'F.1336 half-power beamwidth at this gain: θ3 = 107.6 × '
              '10^(−0.1 × G) = ${fmtDeg1(th3)}. The tilt tilts the whole cone, '
              'so the ring of strongest signal moves closer on the floor.',
            ),
        ];
      case AntennaModelKind.collinear:
        return <Widget>[
          gap,
          PatternSlider(
            label: 'Elements',
            valueText: '${lab.elements}',
            value: lab.elements.toDouble(),
            min: 1,
            max: kCollinearMaxElements.toDouble(),
            divisions: kCollinearMaxElements - 1,
            onChanged: (double v) => lab.setElements(v.round()),
            semanticValue: (double v) => '${v.round()} elements',
          ),
          PatternSlider(
            label: 'Spacing',
            valueText: '${lab.spacingWl.toStringAsFixed(2)} wavelength',
            value: lab.spacingWl,
            min: kSpacingMin,
            max: kSpacingMax,
            divisions: ((kSpacingMax - kSpacingMin) * 20).round(),
            onChanged: (double v) => lab.setSpacing((v * 20).round() / 20),
            semanticValue: (double v) => '${v.toStringAsFixed(2)} wavelengths',
          ),
          PatternSlider(
            label: 'Electrical downtilt',
            valueText: fmtDeg(lab.collinearTiltDeg),
            value: lab.collinearTiltDeg,
            min: 0,
            max: kCollinearTiltMax,
            divisions: kCollinearTiltMax.round(),
            onChanged: (double v) => lab.setCollinearTilt(v.roundToDouble()),
            semanticValue: (double v) => '${v.round()} degrees',
          ),
          if (!presenting)
            const PatternCaption(
              'Element pattern times array factor. Watch the nulls between the '
              'lobes: at 1 λ spacing a second beam (a grating lobe) appears '
              'straight up and down.',
            ),
        ];
      case AntennaModelKind.directional:
        final double g = lab.directionalBeamwidthGainDbi;
        return <Widget>[
          gap,
          PatternSlider(
            label: 'Gain (sets both beamwidths)',
            valueText: fmtDbi(g),
            value: g.clamp(3, 21),
            min: 3,
            max: 21,
            divisions: 36,
            onChanged: (double v) => lab.setDirectionalGain(v),
            semanticValue: (double v) => fmtDbi(v),
          ),
          PatternSlider(
            label: 'Horizontal beamwidth',
            valueText: fmtDeg(lab.hBeamDeg),
            value: lab.hBeamDeg,
            min: kHBeamMin,
            max: kHBeamMax,
            divisions: (kHBeamMax - kHBeamMin).round(),
            onChanged: (double v) => lab.setHBeam(v.roundToDouble()),
            semanticValue: (double v) => '${v.round()} degrees',
          ),
          PatternSlider(
            label: 'Vertical beamwidth',
            valueText: fmtDeg(lab.vBeamDeg),
            value: lab.vBeamDeg,
            min: kVBeamMin,
            max: kVBeamMax,
            divisions: (kVBeamMax - kVBeamMin).round(),
            onChanged: (double v) => lab.setVBeam(v.roundToDouble()),
            semanticValue: (double v) => '${v.round()} degrees',
          ),
          if (presenting)
            PresenterDisclosure(
              title: 'Front-to-back, side lobes and tilt',
              children: _directionalFloors(),
            )
          else
            ..._directionalFloors(),
          if (!presenting)
            const PatternCaption(
              'The gain slider uses the practical rule G = 10 log10(31,000 / '
              '(θ × φ)) and keeps the beam\'s shape. The readouts show what '
              'this exact shape integrates to, which is not the same number.',
            ),
        ];
    }
  }

  List<Widget> _directionalFloors() => <Widget>[
    PatternSlider(
      label: 'Front-to-back (A_max)',
      valueText: '${lab.frontToBackDb.round()} dB',
      value: lab.frontToBackDb,
      min: kLevelMin,
      max: kLevelMax,
      divisions: (kLevelMax - kLevelMin).round(),
      onChanged: (double v) => lab.setFrontToBack(v.roundToDouble()),
      semanticValue: (double v) => '${v.round()} dB',
    ),
    PatternSlider(
      label: 'Side-lobe level (SLA_V)',
      valueText: '${lab.sideLobeDb.round()} dB',
      value: lab.sideLobeDb,
      min: kLevelMin,
      max: kLevelMax,
      divisions: (kLevelMax - kLevelMin).round(),
      onChanged: (double v) => lab.setSideLobe(v.roundToDouble()),
      semanticValue: (double v) => '${v.round()} dB',
    ),
    PatternSlider(
      label: 'Mechanical downtilt',
      valueText: fmtDeg(lab.sectorTiltDeg),
      value: lab.sectorTiltDeg,
      min: 0,
      max: kSectorTiltMax,
      divisions: kSectorTiltMax.round(),
      onChanged: (double v) => lab.setSectorTilt(v.roundToDouble()),
      semanticValue: (double v) => '${v.round()} degrees',
    ),
  ];
}

// ── Import ─────────────────────────────────────────────────────────────────

class _ImportCard extends StatefulWidget {
  const _ImportCard({required this.lab, this.presenting = false});
  final AntennaPatternLab lab;

  /// Presenter panel: the example, the rebuild method and the shape slider
  /// stay out; pasting a file and what was read fold.
  final bool presenting;

  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  late final TextEditingController _text = TextEditingController(
    text: widget.lab.importText,
  );
  late int _seenRevision = widget.lab.importTextRevision;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AntennaPatternLab lab = widget.lab;
    final AppColorScheme colors = context.colors;
    if (lab.importTextRevision != _seenRevision) {
      _seenRevision = lab.importTextRevision;
      _text.text = lab.importText;
    }
    final ParsedPattern? p = lab.parsed;
    final bool presenting = widget.presenting;
    final Widget example = LabeledField(
      label: 'Generated example',
      semanticLabel: 'Load a generated example file',
      field: AppSelect<PatternExample?>(
        value: lab.example,
        semanticLabel: 'Load a generated example file',
        maxLines: 2,
        items: <AppSelectItem<PatternExample?>>[
          if (lab.example == null) (null, 'Pick one to load it'),
          for (final PatternExample e in PatternExample.values) (e, e.label),
        ],
        onChanged: (PatternExample? e) {
          if (e != null) lab.loadExample(e);
        },
      ),
    );
    final List<Widget> paste = <Widget>[
      LabeledField(
        label: 'Or paste pattern text (MSI or NSMA)',
        semanticLabel: 'Pattern file text',
        field: TextField(
          controller: _text,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          style: patternMono(
            context,
          ).inlineCode.copyWith(color: colors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'NAME ...\nGAIN 5 dBi\nHORIZONTAL 360\n0 0.00\n...',
            errorText: lab.importError,
            errorMaxLines: 4,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      FilledButton.icon(
        onPressed: () => lab.importPattern(_text.text),
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('Read pattern'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      const PatternCaption(
        'There is no file picker in this version. Open the .msi, .pln, '
        '.adf or .txt file in a text editor, copy all of it and paste it '
        'here.',
      ),
    ];
    final List<Widget> parsed = <Widget>[
      if (p != null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        PatternReadoutRow(label: 'Format', value: p.format.label),
        if (p.name != null && p.name!.isNotEmpty)
          PatternReadoutRow(label: 'Name', value: p.name!),
        PatternReadoutRow(label: 'Gain as written', value: p.gainAsWritten),
        PatternReadoutRow(
          label: 'Gain in dBi',
          value: fmtDbi(p.gainDbi),
          emphasize: true,
        ),
        if (p.tilt != null && p.tilt!.isNotEmpty)
          PatternReadoutRow(label: 'Tilt as written', value: p.tilt!),
        for (final String w in p.warnings) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          PatternNote(icon: Icons.info_outline, message: w),
        ],
      ],
    ];
    final Widget method = AppToggle<ReconstructionMethod>(
      label: 'Rebuild the 3D by',
      value: lab.method,
      expand: true,
      items: <AppToggleItem<ReconstructionMethod>>[
        for (final ReconstructionMethod m in ReconstructionMethod.values)
          (m, m.label),
      ],
      onChanged: lab.setMethod,
    );
    final Widget shape = PatternSlider(
      label: 'What if: shape (× the file\'s dB)',
      valueText: '× ${lab.shaping.toStringAsFixed(2)}',
      value: lab.shaping,
      min: kShapingMin,
      max: kShapingMax,
      divisions: ((kShapingMax - kShapingMin) * 20).round(),
      onChanged: (double v) => lab.setShaping((v * 20).round() / 20),
      semanticValue: (double v) => 'times ${v.toStringAsFixed(2)}',
    );
    if (presenting) {
      return PatternCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            example,
            const SizedBox(height: AppSpacing.xs),
            method,
            const SizedBox(height: AppSpacing.xs),
            shape,
            PresenterDisclosure(
              title: 'Paste a pattern file, and what was read',
              children: <Widget>[...paste, ...parsed],
            ),
          ],
        ),
      );
    }
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PatternSectionLabel('Pattern file'),
          const SizedBox(height: AppSpacing.xs),
          example,
          const SizedBox(height: AppSpacing.xxs),
          const PatternCaption(
            'Made by this app from closed-form models, so the exact 3D is '
            'known. No manufacturer file is included.',
          ),
          const SizedBox(height: AppSpacing.sm),
          ...paste,
          ...parsed,
          const SizedBox(height: AppSpacing.sm),
          method,
          const SizedBox(height: AppSpacing.xxs),
          PatternCaption(
            lab.method == ReconstructionMethod.summing
                ? 'Summing adds the two cuts in dB (the 3GPP form), with a '
                      '30 dB floor. It returns both cuts exactly on the front '
                      'side; behind the antenna it can only guess.'
                : 'Cross-weighted blends the cuts, trusting each one more '
                      'where the other is strong (Vasiliadis et al., 2005, '
                      'k = 2). It is often better in the main lobe, not '
                      'always.',
          ),
          const SizedBox(height: AppSpacing.xs),
          shape,
          const PatternCaption(
            'Multiplies every loss in the file. Above 1 the beams narrow and '
            'the edges fall off faster; below 1 the pattern flattens. The '
            'gain moves so the total power stays the same. A what-if, not '
            'the file.',
          ),
        ],
      ),
    );
  }
}

// ── Readouts ───────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard({required this.lab});
  final AntennaPatternLab lab;

  @override
  Widget build(BuildContext context) {
    final PatternResult? r = lab.result;
    if (r == null) {
      return const PatternCard(
        child: PatternNote(
          icon: Icons.info_outline,
          message: 'Readouts appear once a pattern is loaded.',
        ),
      );
    }
    final GainGrid g = r.grid;
    final double? hbw = r.cuts.horizontalBeamwidthDeg;
    final double? vbw = r.cuts.verticalBeamwidthDeg;
    final bool omni = r.cuts.looksOmni;
    final double fbOpp = g.peakDbi - g.oppositePeakDbi();
    final double fbWorst = g.peakDbi - r.worstRear.dbi;
    final double dLinear = math.pow(10, g.directivityDbi / 10).toDouble();
    final MethodErrors? errors = r.errors;
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PatternSectionLabel('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          PatternReadoutRow(
            label: 'Peak gain',
            value: '${fmtDbi(g.peakDbi)}  (${fmtDbd(dbiToDbd(g.peakDbi))})',
            emphasize: true,
          ),
          PatternReadoutRow(
            label: 'Peak direction',
            value: fmtElevation(g.peakTheta - 90.0),
          ),
          PatternReadoutRow(
            label: 'Horizontal beamwidth',
            value: hbw == null ? 'omni (no -3 dB points)' : fmtDeg1(hbw),
          ),
          PatternReadoutRow(
            label: 'Vertical beamwidth',
            value: vbw == null ? 'none (never 3 dB down)' : fmtDeg1(vbw),
          ),
          PatternReadoutRow(
            label: 'Front-to-back',
            value: omni
                ? 'about 0 dB: an omni has no back'
                : '${fmtDb1(fbOpp)} dB straight back; '
                      '${fmtDb1(fbWorst)} dB worst in the rear 120°',
          ),
          PatternReadoutRow(
            label: 'Beam solid angle',
            value:
                '${(4 * math.pi / dLinear).toStringAsFixed(2)} sr of '
                '${(4 * math.pi).toStringAsFixed(2)} (4π / D)',
          ),
          if (lab.kind == AntennaModelKind.directional) ...<Widget>[
            PatternReadoutRow(
              label: 'Rule of thumb',
              value:
                  '${fmtDbi(gainFromBeamwidthsDbi(lab.hBeamDeg, lab.vBeamDeg))}'
                  ' by 31,000; '
                  '${fmtDbi(gainFromBeamwidthsDbi(lab.hBeamDeg, lab.vBeamDeg, constant: kKrausIdealConstant))}'
                  ' by 41,253 (ideal)',
            ),
          ],
          if (r.estimated) ...<Widget>[
            PatternReadoutRow(
              label: 'Directivity of the rebuild',
              value: fmtDbi(g.directivityDbi),
            ),
            const PatternNote(
              icon: Icons.info_outline,
              message:
                  'The peak is the gain the file states. The rebuilt shape '
                  'integrates to its own directivity; a gap between the two '
                  'is losses in the real antenna, or the estimate between '
                  'the cuts.',
            ),
          ],
          if (errors != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            const PatternSectionLabel('Rebuild error, against the exact 3D'),
            const SizedBox(height: AppSpacing.xxs),
            for (final ReconstructionMethod m in ReconstructionMethod.values)
              PatternReadoutRow(
                label: m.label,
                emphasize: m == lab.method,
                value:
                    'RMS ${errors.of(m).rmsDb.toStringAsFixed(2)} dB; worst '
                    '${fmtDb1(errors.of(m).worstDb)} dB '
                    '${_where(errors.of(m).worstTheta, errors.of(m).worstPhi)}',
              ),
            const PatternCaption(
              'Over every direction within 30 dB of the peak, weighted by '
              'the solid angle it covers. The worst miss is usually behind '
              'the antenna or between the two cuts.',
            ),
          ],
        ],
      ),
    );
  }

  static String _where(int theta, int phi) {
    final int az = phi > 180 ? phi - 360 : phi;
    final String side = az.abs() > 90 ? 'behind' : 'in front';
    return '($side, ${fmtElevation(theta - 90.0)}, ${az.abs()}° off the '
        'front)';
  }
}

// ── Mount ──────────────────────────────────────────────────────────────────

class _MountCard extends StatelessWidget {
  const _MountCard({required this.lab, this.presenting = false});
  final AntennaPatternLab lab;

  /// Presenter panel: the toggle and its one-line consequence only.
  final bool presenting;

  @override
  Widget build(BuildContext context) {
    final bool omniFrame = switch (lab.kind) {
      AntennaModelKind.directional => false,
      AntennaModelKind.imported => lab.parsed?.cuts.looksOmni ?? false,
      _ => true,
    };
    final String what = switch ((omniFrame, lab.mount)) {
      (true, AntennaMount.ceiling) =>
        'Omni on the ceiling: the doughnut lies flat, so the room is lit '
            'sideways and the spot straight below sits in the null.',
      (true, AntennaMount.wall) =>
        'The same omni turned onto a wall: the doughnut stands on edge, the '
            'null points straight into the room, and half the energy goes '
            'into the wall.',
      (false, AntennaMount.wall) =>
        'Directional on a wall: the beam goes across the room; the back '
            'lobe goes into the wall and the room behind it.',
      (false, AntennaMount.ceiling) =>
        'The same directional on the ceiling, facing down: the beam lights '
            'the floor below and the back lobe goes up through the ceiling.',
    };
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<AntennaMount>(
            label: 'Mounting',
            value: lab.mount,
            expand: true,
            items: <AppToggleItem<AntennaMount>>[
              for (final AntennaMount m in AntennaMount.values) (m, m.label),
            ],
            onChanged: lab.setMount,
          ),
          // The stage shows what mounting does; the sentence is the
          // phone's.
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            PatternCaption(what),
          ],
          if (!presenting && lab.kind == AntennaModelKind.imported) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const PatternCaption(
              'A file with a horizontal cut within 3 dB all around is taken '
              'as an omni drawn for the ceiling; any other as drawn for a '
              'wall. Some indoor files are drawn turned 90° or 180°, so check '
              'which way the peak points.',
            ),
          ],
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const PatternCaption(
              'Mounting turns the 3D view only. The 2D cuts stay in the '
              'antenna\'s own frame, the way a datasheet draws them.',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Polarization ───────────────────────────────────────────────────────────

class _PolarizationCard extends StatelessWidget {
  const _PolarizationCard({required this.lab, this.presenting = false});
  final AntennaPatternLab lab;

  /// Presenter panel: the slider and the loss, without the formula note.
  final bool presenting;

  @override
  Widget build(BuildContext context) {
    final double loss = lab.polarizationLossDb;
    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PatternSectionLabel('Polarization mismatch'),
          const SizedBox(height: AppSpacing.xs),
          PatternSlider(
            label: 'Angle between the two antennas',
            valueText: fmtDeg(lab.polarizationDeg),
            value: lab.polarizationDeg,
            min: 0,
            max: 90,
            divisions: 90,
            onChanged: (double v) => lab.setPolarization(v.roundToDouble()),
            semanticValue: (double v) => '${v.round()} degrees',
          ),
          PatternReadoutRow(
            label: 'Mismatch loss',
            value: fmtPolarizationLoss(loss),
            emphasize: true,
          ),
          if (!presenting)
            PatternCaption(
              loss.isFinite && loss <= 40
                  ? 'Loss = −20 log10|cos Δ|. At 45° it is 3.01 dB. Real links '
                        'lose less than the formula at large angles, because '
                        'reflections scramble polarization.'
                  : 'Crossed at 90°, the formula says nothing arrives at all '
                        '(unbounded), so the display stops at 40 dB. Real '
                        'links still see something, from reflections that '
                        'scramble polarization.',
            ),
        ],
      ),
    );
  }
}

// ── Explainer ──────────────────────────────────────────────────────────────

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
            icon: Icons.balance,
            message:
                'Gain is not power. Every antenna here radiates the same '
                'power; more gain only moves it. Raise the gain and the '
                'pattern grows in one direction and shrinks everywhere else, '
                'which is why a high-gain omni leaves a hole under itself.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternNote(
            icon: Icons.compare_arrows,
            message:
                'Gain and beamwidth trade directly. A rule of thumb: gain is '
                'about 31,000 divided by the two beamwidths multiplied '
                'together, in degrees. 41,253 is the ideal (the square '
                'degrees in a sphere); real antennas fall short of it.',
          ),
          SizedBox(height: AppSpacing.xs),
          PatternNote(
            icon: Icons.layers_outlined,
            message:
                'A pattern file holds two slices. Everything between them is '
                'estimated, and the estimate is weakest behind the antenna. '
                'Rebuild an antenna from its two cuts to see the error.',
          ),
        ],
      ),
    );
  }
}
