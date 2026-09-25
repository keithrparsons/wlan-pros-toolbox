// Controls and readouts for Room Propagation. Separate widgets from the stage
// (room_propagation_stage.dart); each takes the shared
// RoomPropagationController, so the phone layout stacks them and a presenter
// layout can put them beside the stage.
//
//   RoomPropagationControls  preset, signal (band, channel, EIRP, antenna,
//                            reflections, diffraction), overlays, positions,
//                            and the wall editor (tool, material, thickness,
//                            doorways, delete)
//   RoomPropagationReadouts  received power at the client, where the loss
//                            comes from, and the same spot on all three bands
//
// THEME: GL-003 §8. AppSelect for 4+ options (§8.14), AppToggle for 2-3.
// Lime only on the received power (the quantity the tool is about). No status
// hues: nothing here is a pass or fail verdict. ASCII copy, no em dashes
// (GL-004).

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/room_propagation_model.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'room_propagation_controller.dart';
import 'wifi_through_a_wall_parts.dart'
    show WallCard, WallSectionLabel, WallRow, WallNote;

typedef _C = RoomPropagationController;

/// Thickness bounds for a wall, mm (the same as Wi-Fi Through a Wall).
const double kRoomWallMinMm = 1;
const double kRoomWallMaxMm = 500;

// ── Controls ──────────────────────────────────────────────────────────────

class RoomPropagationControls extends StatelessWidget {
  const RoomPropagationControls({super.key, required this.controller});

  final RoomPropagationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SignalCard(c: controller),
          const SizedBox(height: AppSpacing.sm),
          _PositionsCard(c: controller),
          const SizedBox(height: AppSpacing.sm),
          _WallsCard(c: controller),
        ],
      ),
    );
  }
}

TextStyle? _hint(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.colors.textTertiary);

/// The preset picker. Separate so the screen can put it above the stage.
class RoomPresetPicker extends StatelessWidget {
  const RoomPresetPicker({super.key, required this.controller});

  final RoomPropagationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final RoomPropagationController c = controller;
        return WallCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LabeledField(
                label: 'Floor plan',
                semanticLabel: 'Floor plan',
                field: AppSelect<int>(
                  value: c.presetIndex,
                  semanticLabel: 'Floor plan',
                  items: <AppSelectItem<int>>[
                    for (int i = 0; i < _C.presets.length; i++)
                      (i, _C.presets[i].label),
                  ],
                  onChanged: c.loadPreset,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(c.preset.lesson, style: _hint(context)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => c.loadPreset(c.presetIndex),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset this plan'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.textAccent,
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.c});

  final RoomPropagationController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('The signal'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<WifiBand>(
            label: 'Band',
            value: c.band,
            expand: true,
            items: <AppToggleItem<WifiBand>>[
              for (final WifiBand b in WifiBand.values) (b, b.label),
            ],
            onChanged: (WifiBand b) => c.band = b,
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Channel',
            semanticLabel: 'Channel',
            field: AppSelect<int>(
              value: c.channel,
              semanticLabel: 'Channel',
              items: <AppSelectItem<int>>[
                for (final int ch in channelsFor(c.band))
                  (
                    ch,
                    'Channel $ch  (${centerFrequencyMHzForBand(c.band, ch)} '
                        'MHz)',
                  ),
              ],
              onChanged: (int ch) => c.channel = ch,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Wavelength ${_C.cm(c.lambda)}, half wavelength '
            '${_C.cm(c.lambda / 2)}.',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              const WallSectionLabel('AP EIRP'),
              const Spacer(),
              Text(
                '${c.eirpDbm.toStringAsFixed(0)} dBm',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          Slider(
            value: c.eirpDbm,
            min: kEirpMin,
            max: kEirpMax,
            onChanged: (double v) => c.eirpDbm = v,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${c.eirpDbm.toStringAsFixed(0)} dBm',
            semanticFormatterCallback: (double v) => 'AP EIRP ${v.round()} dBm',
          ),
          Text(
            'Transmit power plus antenna gain. The receiver is a 0 dBi '
            'antenna.',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<Polarization>(
            label: 'AP antenna',
            value: c.polarization,
            expand: true,
            items: const <AppToggleItem<Polarization>>[
              (Polarization.te, 'Upright (TE)'),
              (Polarization.tm, 'Flat (TM)'),
            ],
            onChanged: (Polarization p) => c.polarization = p,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Upright: the electric field runs up and down, along every wall '
            'face (TE). Flat: it lies in the plan (TM), and walls reflect a '
            'glancing wave differently.',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<int>(
            label: 'Reflections',
            value: c.reflectionOrder,
            expand: true,
            items: const <AppToggleItem<int>>[
              (0, 'None'),
              (1, '1 bounce'),
              (2, '2 bounces'),
            ],
            onChanged: (int o) => c.reflectionOrder = o,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<bool>(
            label: 'Diffraction at wall ends and doorways',
            value: c.diffraction,
            expand: true,
            items: const <AppToggleItem<bool>>[(true, 'On'), (false, 'Off')],
            onChanged: (bool v) => c.diffraction = v,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Off: straight lines only, so every shadow edge is sharp. On: '
            'signal bends past edges (ITU-R P.526 knife edge).',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.md),
          const WallSectionLabel('Overlays'),
          _SwitchRow(
            title: 'Fresnel zone to the client',
            subtitle:
                'Radius ${_C.cm(c.fresnelMidRadiusM, 0)} at the middle of the '
                'path. Keep it clear of walls and edges.',
            value: c.showFresnel,
            onChanged: (bool v) => c.showFresnel = v,
          ),
          _SwitchRow(
            title: 'Doorway shadow edges',
            subtitle:
                'Straight lines from the AP past each door jamb: where a '
                'shadow would start with no diffraction.',
            value: c.showShadows,
            onChanged: (bool v) => c.showShadows = v,
          ),
          _SwitchRow(
            title: 'Close-up of the ripple',
            subtitle:
                'Peaks and nulls every half wavelength around the client.',
            value: c.showCloseUp,
            onChanged: (bool v) => c.showCloseUp = v,
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionsCard extends StatelessWidget {
  const _PositionsCard({required this.c});

  final RoomPropagationController c;

  @override
  Widget build(BuildContext context) {
    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Positions'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The same as dragging on the plan. Meters from the top-left '
            'corner.',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          _PosSlider(
            label: 'AP across',
            value: c.ap.x,
            max: c.widthM,
            onChanged: (double v) => c.moveAp(P2(v, c.ap.y)),
          ),
          _PosSlider(
            label: 'AP down',
            value: c.ap.y,
            max: c.heightM,
            onChanged: (double v) => c.moveAp(P2(c.ap.x, v)),
          ),
          _PosSlider(
            label: 'Client across',
            value: c.client.x,
            max: c.widthM,
            onChanged: (double v) => c.moveClient(P2(v, c.client.y)),
          ),
          _PosSlider(
            label: 'Client down',
            value: c.client.y,
            max: c.heightM,
            onChanged: (double v) => c.moveClient(P2(c.client.x, v)),
          ),
        ],
      ),
    );
  }
}

class _PosSlider extends StatelessWidget {
  const _PosSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Row(
      children: <Widget>[
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            max: max,
            onChanged: (double v) => onChanged((v * 10).roundToDouble() / 10),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: (double v) =>
                '$label ${v.toStringAsFixed(1)} meters',
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${value.toStringAsFixed(1)} m',
            textAlign: TextAlign.right,
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _WallsCard extends StatefulWidget {
  const _WallsCard({required this.c});

  final RoomPropagationController c;

  @override
  State<_WallsCard> createState() => _WallsCardState();
}

class _WallsCardState extends State<_WallsCard> {
  late final TextEditingController _mm;
  String? _mmError;
  int? _lastSelected;

  RoomPropagationController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _mm = TextEditingController(text: _C.fmtMm(c.editThicknessMm));
    _lastSelected = c.selectedWall;
  }

  @override
  void didUpdateWidget(_WallsCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // Mirror the thickness when the selection changes or it was set
    // elsewhere, unless the field already says the same number.
    final double? typed = tryParseFlexibleDouble(_mm.text);
    if (_lastSelected != c.selectedWall ||
        (typed != c.editThicknessMm && _mmError == null)) {
      _mm.text = _C.fmtMm(c.editThicknessMm);
      _mmError = null;
    }
    _lastSelected = c.selectedWall;
  }

  @override
  void dispose() {
    _mm.dispose();
    super.dispose();
  }

  void _onMm(String raw) {
    final double? v = tryParseFlexibleDouble(raw);
    if (v == null || v < kRoomWallMinMm || v > kRoomWallMaxMm) {
      setState(
        () => _mmError =
            'Enter a thickness from ${kRoomWallMinMm.toStringAsFixed(0)} to '
            '${kRoomWallMaxMm.toStringAsFixed(0)} mm',
      );
      return;
    }
    setState(() => _mmError = null);
    c.setThicknessMm(v);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RoomWall? sel = c.selected;
    final int? selIndex = c.selectedWall;
    final ButtonStyle outline = OutlinedButton.styleFrom(
      foregroundColor: colors.textAccent,
      disabledForegroundColor: colors.textDisabled,
      side: BorderSide(
        color: colors.borderStrong,
        width: colors.isLight ? 1.5 : 1,
      ),
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
    );

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Walls and doorways'),
          const SizedBox(height: AppSpacing.xs),
          // Four tools: GL-003 §8.14 routes 4+ options to AppSelect.
          LabeledField(
            label: 'What a tap or drag on the plan does',
            semanticLabel: 'Plan tool',
            field: AppSelect<RoomTool>(
              value: c.tool,
              semanticLabel: 'Plan tool',
              items: <AppSelectItem<RoomTool>>[
                for (final RoomTool t in RoomTool.values) (t, t.menuLabel),
              ],
              onChanged: (RoomTool t) => c.tool = t,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Wall',
            semanticLabel: 'Selected wall',
            field: AppSelect<int>(
              value: selIndex ?? -1,
              semanticLabel: 'Selected wall',
              maxLines: 2,
              items: <AppSelectItem<int>>[
                (-1, c.walls.isEmpty ? 'No walls yet' : 'None (new walls)'),
                for (int i = 0; i < c.walls.length; i++) (i, c.wallName(i)),
              ],
              onChanged: (int i) => c.selectWall(i < 0 ? null : i),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            sel == null
                ? 'Material and thickness below apply to the next wall you '
                      'draw.'
                : 'Material and thickness below change this wall. It runs '
                      'from ${_pt(sel.a)} to ${_pt(sel.b)}, '
                      '${sel.length.toStringAsFixed(1)} m.',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Material (ITU-R P.2040 Table 3)',
            semanticLabel: 'Wall material',
            field: AppSelect<WallMaterial>(
              value: c.editMaterial,
              semanticLabel: 'Wall material',
              items: <AppSelectItem<WallMaterial>>[
                for (final WallMaterial m in WallMaterial.values) (m, m.label),
              ],
              onChanged: c.setMaterial,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Thickness',
            hint: '(mm, 1 to 500)',
            semanticLabel: 'Wall thickness in millimeters',
            field: TextField(
              controller: _mm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: unsignedDecimalFormatters,
              onChanged: _onMm,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.inlineCode.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                errorText: _mmError,
                suffixText: 'mm',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: sel == null ? null : c.addDoorToSelected,
                icon: const Icon(Icons.door_front_door_outlined, size: 18),
                label: const Text('Add a doorway'),
                style: outline,
              ),
              OutlinedButton.icon(
                onPressed: sel == null || sel.doors.isEmpty
                    ? null
                    : c.removeDoorsFromSelected,
                icon: const Icon(Icons.border_clear, size: 18),
                label: const Text('Close its doorways'),
                style: outline,
              ),
              OutlinedButton.icon(
                onPressed: sel == null ? null : c.deleteSelected,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete wall'),
                style: outline,
              ),
            ],
          ),
          if (c.message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            WallNote(icon: Icons.info_outline, message: c.message!),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Up to $kMaxWalls walls. Each is one solid slab: real walls with '
            'studs and cavities lose differently.',
            style: _hint(context),
          ),
        ],
      ),
    );
  }

  static String _pt(P2 p) =>
      '(${p.x.toStringAsFixed(1)}, ${p.y.toStringAsFixed(1)})';
}

// ── Readouts ──────────────────────────────────────────────────────────────

class RoomPropagationReadouts extends StatelessWidget {
  const RoomPropagationReadouts({super.key, required this.controller});

  final RoomPropagationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ClientCard(c: controller),
          const SizedBox(height: AppSpacing.sm),
          _BandsCard(c: controller),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.c});

  final RoomPropagationController c;

  @override
  Widget build(BuildContext context) {
    final PointReport r = c.clientReport;
    final double? dif = r.diffractionDb;
    final double? refl = r.reflectionsDb;
    final bool blocked = !r.wallLossDb.isFinite || r.wallLossDb > 150;

    final String walls;
    if (r.crossed.isEmpty) {
      walls = 'none (clear line)';
    } else if (blocked) {
      walls = 'blocked (more than 150 dB)';
    } else {
      walls =
          '-${_C.lossDb(r.wallLossDb)} (${r.crossed.length} '
          'wall${r.crossed.length == 1 ? '' : 's'})';
    }

    final String difText;
    if (!c.diffraction) {
      difText = 'off';
    } else if (dif == null) {
      difText = r.directAmp2 > 0
          ? 'the only way through: around the edges'
          : 'nothing gets around';
    } else {
      difText = dif.abs() < 0.05
          ? '0.0 dB'
          : dif > 0
          ? '${_C.signedDb(-dif)} (lost at edges)'
          : '${_C.signedDb(-dif)} (bent around edges)';
    }

    final String reflText;
    if (c.reflectionOrder == 0) {
      reflText = 'off';
    } else if (refl == null) {
      reflText = r.pathCount > 1
          ? 'all of the signal (${r.pathCount - 1} reflected '
                'path${r.pathCount - 1 == 1 ? '' : 's'})'
          : 'none reach here';
    } else {
      reflText =
          '${_C.signedDb(refl)} (${r.pathCount - 1} reflected '
          'path${r.pathCount - 1 == 1 ? '' : 's'})';
    }

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('At the client'),
          const SizedBox(height: AppSpacing.xs),
          WallRow(
            label: 'Received here',
            value: _C.dbm(c.clientDbm),
            emphasize: true,
          ),
          WallRow(
            label: 'Local average',
            value: '${_C.dbm(c.clientAverageDbm)} (the map)',
          ),
          WallRow(
            label: 'Distance to AP',
            value:
                '${r.distanceM.toStringAsFixed(2)} m, '
                '${c.freqMHz} MHz',
          ),
          const SizedBox(height: AppSpacing.xs),
          const WallSectionLabel('Where the loss comes from'),
          const SizedBox(height: AppSpacing.xxs),
          WallRow(
            label: 'AP EIRP',
            value: '${c.eirpDbm.toStringAsFixed(0)} dBm',
          ),
          WallRow(label: 'Free space', value: '-${_C.fmt1(r.fsplDb)} dB'),
          WallRow(label: 'Walls in the way', value: walls),
          for (final CrossedWall w in r.crossed)
            WallRow(
              label: 'wall ${w.wallIndex + 1}',
              value:
                  '${c.walls[w.wallIndex].material.label} '
                  '${_C.fmtMm(c.walls[w.wallIndex].thicknessMm)} mm at '
                  '${w.angleDeg.toStringAsFixed(0)} deg: '
                  '${_C.lossDb(w.lossDb)}',
              indent: true,
            ),
          WallRow(label: 'Diffraction', value: difText),
          WallRow(label: 'Reflections', value: reflText),
          WallRow(label: 'Received here', value: _C.dbm(c.clientDbm)),
          const SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.calculate_outlined,
            message: blocked
                ? 'The straight line runs through metal, so the wall loss has '
                      'no useful number; what arrives comes around edges or '
                      'by bouncing.'
                : 'EIRP minus free space, minus the walls, plus or minus '
                      'diffraction and reflections, gives what the client '
                      'receives at this exact spot (before rounding).',
          ),
        ],
      ),
    );
  }
}

class _BandsCard extends StatelessWidget {
  const _BandsCard({required this.c});

  final RoomPropagationController c;

  static String _diff(PointReport r) {
    final double? d = r.diffractionDb;
    if (d == null) return '-';
    return _C.fmt1(d);
  }

  static String _walls(PointReport r) =>
      !r.wallLossDb.isFinite || r.wallLossDb > 150
      ? '>150'
      : _C.fmt1(r.wallLossDb);

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<RoomBandRow> rows = c.bandRows;
    final PointReport lo = rows.first.report;
    final PointReport hi = rows.last.report;

    final TextStyle head = text.labelMedium!.copyWith(
      color: colors.textTertiary,
    );
    final TextStyle cell = mono.inlineCode.copyWith(color: colors.textPrimary);

    Widget row(List<Widget> cells) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: <Widget>[
          SizedBox(width: 76, child: cells[0]),
          for (final Widget w in cells.skip(1))
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: w),
            ),
        ],
      ),
    );

    final double fsplUp = hi.fsplDb - lo.fsplDb;
    final bool wallsFinite =
        lo.wallLossDb.isFinite &&
        hi.wallLossDb.isFinite &&
        lo.wallLossDb < 150 &&
        hi.wallLossDb < 150;
    final double? dLo = lo.diffractionDb;
    final double? dHi = hi.diffractionDb;
    final StringBuffer story = StringBuffer(
      'From ${rows.first.band.label} to ${rows.last.band.label} at this '
      'spot: free space costs ${_C.fmt1(fsplUp)} dB more. That part is the '
      'antenna, not the air: at a shorter wavelength the same antenna '
      'catches less.',
    );
    if (lo.crossed.isNotEmpty && wallsFinite) {
      final double w = hi.wallLossDb - lo.wallLossDb;
      story.write(
        w >= 0
            ? ' The walls cost ${_C.fmt1(w)} dB more: the material absorbs '
                  'more per centimeter.'
            : ' The walls cost ${_C.fmt1(-w)} dB LESS: thin panels can pass '
                  'more at a higher frequency when their two faces\' echoes '
                  'cancel.',
      );
    }
    if (c.diffraction && dLo != null && dHi != null) {
      final double d = dHi - dLo;
      if (d.abs() >= 0.1) {
        story.write(
          d > 0
              ? ' Diffraction costs ${_C.fmt1(d)} dB more: less signal bends '
                    'into shadows at the shorter wavelength.'
              : ' Diffraction costs ${_C.fmt1(-d)} dB less here.',
        );
      }
    }

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('The same spot on all three bands'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Losses in dB. Received is the local average, so the fine '
            'ripple does not hide the trend. Diffraction: positive costs '
            'signal, negative brings it around a wall.',
            style: _hint(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: row(<Widget>[
              Text('Band', style: head),
              Text('Free sp.', style: head),
              Text('Walls', style: head),
              Text('Diffr.', style: head),
              Text('dBm', style: head),
            ]),
          ),
          Divider(height: 1, color: colors.border),
          for (final RoomBandRow b in rows)
            Semantics(
              label:
                  '${b.band.label}, channel ${b.channel}: free space '
                  '${_C.fmt1(b.report.fsplDb)} dB, walls '
                  '${_walls(b.report)} dB, diffraction ${_diff(b.report)} dB, '
                  'received ${_C.dbm(c.eirpDbm + b.report.averageGainDb)}'
                  '${b.band == c.band ? ', the selected band' : ''}',
              excludeSemantics: true,
              child: row(<Widget>[
                Text(
                  b.band.label,
                  style: cell.copyWith(
                    fontWeight: b.band == c.band
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                Text(_C.fmt1(b.report.fsplDb), style: cell),
                Text(_walls(b.report), style: cell),
                Text(_diff(b.report), style: cell),
                Text(
                  _C.fmt1(c.eirpDbm + b.report.averageGainDb),
                  style: cell.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ]),
            ),
          const SizedBox(height: AppSpacing.xs),
          WallNote(icon: Icons.stacked_line_chart, message: story.toString()),
          const SizedBox(height: AppSpacing.xs),
          const WallNote(
            icon: Icons.info_outline,
            message:
                'Model values, not measurements: ITU-R P.2040 walls (one '
                'solid slab each), ITU-R P.526 knife-edge diffraction, and '
                'reflections up to two bounces. No floor, ceiling, furniture '
                'or people.',
          ),
        ],
      ),
    );
  }
}
