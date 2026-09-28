// Controls and readouts for the Wi-Fi Classroom FSPL Simulator.
//
// Everything that is not the plot: band toggles, channel and link inputs, the
// indoor model, the measured point (FsplControls, FsplBandChips), and the
// numbers the plot is about (FsplReadouts: the cursor table, band differences,
// the measured gap, and the Why panel that splits each band's loss into
// spreading and aperture). Each takes an FsplSimModel and none knows about
// FsplStage, so a screen composes them in whatever arrangement it needs.
//
// PRESENTER: FsplControls drops its phone prose and folds the channels and
// the measured point into PresenterDisclosures; FsplCursorHeadline carries
// the per-band numbers onto the stage in headline type.
//
// THEME: context.colors only (dark §8 / light §8.20). No status hues (nothing
// here is a pass/fail verdict, §8.13 rule 6). Lime marks the received-power
// values and the aperture bar, the one quantity that changes with band.
// ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/unit_system.dart';
import '../labeled_field.dart';
import 'fspl_simulator_chart.dart';
import 'fspl_simulator_model.dart';

// ── Shared parts ──────────────────────────────────────────────────────────

class FsplCard extends StatelessWidget {
  const FsplCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

class FsplSectionLabel extends StatelessWidget {
  const FsplSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: colors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}

class FsplNote extends StatelessWidget {
  const FsplNote(this.icon, this.message, {super.key});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// The stroke-and-marker sample for one band, matching the chart exactly.
class FsplBandSample extends StatelessWidget {
  const FsplBandSample({super.key, required this.band, this.model = false});
  final WifiBand band;

  /// Draw the indoor-model variant (thin, grey, hollow marker).
  final bool model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final (CurveStroke stroke, CurveMarker marker) = kFsplBandLook[band]!;
    return CustomPaint(
      painter: FsplStrokeSamplePainter(
        stroke: stroke,
        marker: marker,
        color: model ? colors.textTertiary : colors.textAccent,
        surface: colors.surface1,
        model: model,
        scale: PresenterMode.scaleOf(context).marker,
      ),
    );
  }
}

// ── Band toggles ──────────────────────────────────────────────────────────

class FsplBandChips extends StatelessWidget {
  const FsplBandChips({super.key, required this.model});
  final FsplSimModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final WifiBand b in WifiBand.values)
            FilterChip(
              label: Text(b.label),
              selected: model.isEnabled(b),
              showCheckmark: true,
              checkmarkColor: colors.onPrimary,
              selectedColor: colors.primary,
              backgroundColor: colors.surface2,
              labelStyle: TextStyle(
                color: model.isEnabled(b)
                    ? colors.onPrimary
                    : colors.textPrimary,
              ),
              side: BorderSide(color: colors.borderStrong),
              tooltip:
                  '${model.isEnabled(b) ? 'Hide' : 'Show'} the ${b.label} '
                  'curve',
              onSelected: (bool on) => model.setBand(b, on),
            ),
        ],
      ),
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────────

class FsplControls extends StatefulWidget {
  const FsplControls({super.key, required this.model});
  final FsplSimModel model;

  @override
  State<FsplControls> createState() => _FsplControlsState();
}

class _FsplControlsState extends State<FsplControls> {
  // Seeded from the model so a second FsplControls (a different layout)
  // shows what the user already typed.
  late final TextEditingController _rssi = TextEditingController(
    text: widget.model.rssiText,
  );
  late final TextEditingController _dist = TextEditingController(
    text: widget.model.distText,
  );

  FsplSimModel get m => widget.model;

  @override
  void initState() {
    super.initState();
    m.addListener(_followModelText);
  }

  /// A unit flip rewrites the typed distance in the model (setUnits); mirror
  /// it here. Runs from the model's notify, outside build.
  void _followModelText() {
    if (_dist.text != m.distText && m.distText.isNotEmpty) {
      _dist.text = m.distText;
    }
  }

  @override
  void dispose() {
    m.removeListener(_followModelText);
    _rssi.dispose();
    _dist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    if (PresenterMode.isActive(context)) return _presenterChildren(context);
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return <Widget>[
      const FsplSectionLabel('Channels'),
      const SizedBox(height: AppSpacing.xs),
      ..._channelFields(),
      const SizedBox(height: AppSpacing.sm),
      const FsplSectionLabel('Link'),
      ..._linkSliders(context),
      Text(
        '0 dBi is an isotropic antenna, the one the aperture term assumes.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      const FsplSectionLabel('Indoor model'),
      ..._indoor(context),
      Text(
        'A model with an exponent you choose, not a measurement. n = 2 is '
        'free space; 3 is a common starting guess for offices.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      const FsplSectionLabel('Measured point'),
      const SizedBox(height: AppSpacing.xs),
      ..._measuredFields(context),
      const SizedBox(height: AppSpacing.md),
      const FsplSectionLabel('Design targets'),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        'The dashed lines in the Received view. Your lines are saved on this '
        'device for every lesson.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.xs),
      FsplTargetEditor(model: m),
    ];
  }

  /// Presenter panel: the link and the indoor model open, phone prose gone,
  /// channels and the measured point folded (set once per lesson).
  List<Widget> _presenterChildren(BuildContext context) {
    return <Widget>[
      const FsplSectionLabel('Link'),
      ..._linkSliders(context),
      const SizedBox(height: AppSpacing.sm),
      const FsplSectionLabel('Indoor model'),
      ..._indoor(context),
      const SizedBox(height: AppSpacing.xs),
      PresenterDisclosure(title: 'Channels', children: _channelFields()),
      PresenterDisclosure(
        title: 'Measured point',
        children: _measuredFields(context),
      ),
      PresenterDisclosure(
        title: 'Design targets',
        children: <Widget>[FsplTargetEditor(model: m)],
      ),
    ];
  }

  List<Widget> _channelFields() {
    return <Widget>[
      for (final WifiBand b in WifiBand.values) ...<Widget>[
        // 14, 28 and 60 options: GL-003 §8.14 routes 4+ options to AppSelect.
        LabeledField(
          label: '${b.label} channel',
          field: AppSelect<int>(
            value: m.channel(b),
            semanticLabel: '${b.label} channel',
            items: <AppSelectItem<int>>[
              for (final int ch in channelsFor(b))
                (ch, '$ch  (${channelToFrequency(b, ch)} MHz)'),
            ],
            onChanged: (int ch) => m.setChannel(b, ch),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    ];
  }

  List<Widget> _linkSliders(BuildContext context) {
    return <Widget>[
      _slider(
        context,
        label: 'Tx power',
        unit: 'dBm',
        value: m.txPowerDbm,
        min: 0,
        max: 30,
        divisions: 30,
        decimals: 0,
        onChanged: m.setTxPower,
      ),
      _slider(
        context,
        label: 'Tx antenna gain',
        unit: 'dBi',
        value: m.txGainDbi,
        min: -5,
        max: 15,
        divisions: 40,
        onChanged: m.setTxGain,
      ),
      _slider(
        context,
        label: 'Rx antenna gain',
        unit: 'dBi',
        value: m.rxGainDbi,
        min: -5,
        max: 15,
        divisions: 40,
        onChanged: m.setRxGain,
      ),
      _slider(
        context,
        label: 'Other losses',
        unit: 'dB',
        value: m.otherLossDb,
        min: 0,
        max: 30,
        divisions: 60,
        onChanged: m.setOtherLoss,
      ),
    ];
  }

  List<Widget> _indoor(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return <Widget>[
      MergeSemantics(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Show log-distance curves',
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
            Switch(value: m.indoor, onChanged: m.setIndoor),
          ],
        ),
      ),
      _slider(
        context,
        label: 'Path-loss exponent n',
        unit: '',
        value: m.exponent,
        min: 2,
        max: 4,
        divisions: 20,
        enabled: m.indoor,
        onChanged: m.setExponent,
      ),
    ];
  }

  List<Widget> _measuredFields(BuildContext context) {
    final FsplMeasuredInput mi = m.measuredInput;
    final ({double rssi, double dist})? meas = m.measured;
    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: LabeledField(
              label: 'RSSI',
              hint: '(dBm)',
              semanticLabel: 'Measured RSSI in dBm',
              field: _numberField(
                context,
                _rssi,
                'e.g. -62',
                mi.rssiError,
                (String s) => m.setMeasuredText(rssi: s),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: LabeledField(
              label: 'Distance',
              hint: '(${m.units.isMetric ? 'm' : 'ft'})',
              semanticLabel:
                  'Measured distance in ${m.units.isMetric ? 'meters' : 'feet'}',
              field: _numberField(
                context,
                _dist,
                m.units.isMetric ? 'e.g. 15' : 'e.g. 50',
                mi.distError,
                (String s) => m.setMeasuredText(dist: s),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      AppToggle<WifiBand>(
        label: 'Measured on',
        value: m.measuredBand,
        expand: true,
        items: <AppToggleItem<WifiBand>>[
          for (final WifiBand b in WifiBand.values) (b, b.label),
        ],
        onChanged: m.setMeasuredBand,
      ),
      const SizedBox(height: AppSpacing.xs),
      if (meas != null && !m.isEnabled(m.measuredBand))
        FsplNote(
          Icons.visibility_off_outlined,
          'Turn on ${m.measuredBand.label} to plot this point against its '
          'curve.',
        )
      else if (meas != null && meas.dist > m.maxM + 1e-9)
        FsplNote(
          Icons.open_in_full,
          'This point is past ${m.rangeLabel}. Switch the distance axis to '
          '${FsplRange.km1.labelFor(m.units)} to see it.',
        )
      else if (meas == null)
        const FsplNote(
          Icons.edit_outlined,
          'Manual entry. Type a reading and the distance it was taken at.',
        ),
      if (m.rssiText.isNotEmpty || m.distText.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              _rssi.clear();
              _dist.clear();
              m.setMeasuredText(rssi: '', dist: '');
            },
            icon: const Icon(Icons.clear),
            label: const Text('Clear measured point'),
          ),
        ),
    ];
  }

  Widget _numberField(
    BuildContext context,
    TextEditingController ctrl,
    String hint,
    String? error,
    ValueChanged<String> onChanged,
  ) {
    final AppColorScheme colors = context.colors;
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      onChanged: onChanged,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: colors.textPrimary),
      cursorColor: colors.textAccent,
      decoration: InputDecoration(hintText: hint, errorText: error),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String unit,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    int decimals = 1,
    bool enabled = true,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String v =
        '${FsplFormat.n(value, decimals)}${unit.isEmpty ? '' : ' $unit'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: enabled ? colors.textSecondary : colors.textDisabled,
                  ),
                ),
              ),
              Text(
                v,
                style: mono.inlineCode.copyWith(
                  color: enabled ? colors.textPrimary : colors.textDisabled,
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: enabled ? onChanged : null,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          label: v,
          semanticFormatterCallback: (double x) =>
              '$label ${FsplFormat.n(x, decimals)} $unit'.trimRight(),
        ),
      ],
    );
  }
}

// ── Design targets ────────────────────────────────────────────────────────

/// Edits the design-target lines: a dBm value and a label per line, up to
/// [kFsplMaxTargets], with Add, Remove and Reset (Keith, 2026-09-27).
///
/// States: default (the two Signal Thresholds lines, Reset disabled);
/// custom; empty (no lines, a note says so); error (value out of range or
/// not a number, shown in the field, line not drawn); at the cap (Add
/// disabled, the helper says why).
class FsplTargetEditor extends StatefulWidget {
  const FsplTargetEditor({super.key, required this.model});
  final FsplSimModel model;

  @override
  State<FsplTargetEditor> createState() => _FsplTargetEditorState();
}

class _FsplTargetEditorState extends State<FsplTargetEditor> {
  final Map<int, TextEditingController> _value = <int, TextEditingController>{};
  final Map<int, TextEditingController> _label = <int, TextEditingController>{};
  final Map<int, FocusNode> _valueFocus = <int, FocusNode>{};
  final Map<int, FocusNode> _labelFocus = <int, FocusNode>{};

  FsplSimModel get m => widget.model;

  @override
  void initState() {
    super.initState();
    _sync();
    m.addListener(_sync);
  }

  /// Keeps one controller pair per row id and mirrors text changed elsewhere
  /// (Reset, the store's load, the other layout over the same model) into
  /// any field the user is not typing in. Runs from the model's notify,
  /// outside build.
  void _sync() {
    final List<FsplTargetRow> rows = m.targetRows;
    final Set<int> ids = <int>{for (final FsplTargetRow r in rows) r.id};
    for (final FsplTargetRow r in rows) {
      final TextEditingController v = _value.putIfAbsent(
        r.id,
        () => TextEditingController(text: r.valueText),
      );
      final TextEditingController l = _label.putIfAbsent(
        r.id,
        () => TextEditingController(text: r.label),
      );
      final FocusNode vf = _valueFocus.putIfAbsent(r.id, FocusNode.new);
      final FocusNode lf = _labelFocus.putIfAbsent(r.id, FocusNode.new);
      if (!vf.hasFocus && v.text != r.valueText) v.text = r.valueText;
      if (!lf.hasFocus && l.text != r.label) l.text = r.label;
    }
    final List<int> gone = <int>[
      for (final int id in _value.keys)
        if (!ids.contains(id)) id,
    ];
    if (gone.isEmpty) return;
    final List<ChangeNotifier> dead = <ChangeNotifier>[
      for (final int id in gone) ...<ChangeNotifier>[
        _value.remove(id)!,
        _label.remove(id)!,
        _valueFocus.remove(id)!,
        _labelFocus.remove(id)!,
      ],
    ];
    // The fields using them unmount on the next build; dispose after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final ChangeNotifier c in dead) {
        c.dispose();
      }
    });
  }

  @override
  void dispose() {
    m.removeListener(_sync);
    for (final ChangeNotifier c in <ChangeNotifier>[
      ..._value.values,
      ..._label.values,
      ..._valueFocus.values,
      ..._labelFocus.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _add() {
    final int? id = m.addTarget();
    if (id == null) return;
    // _sync ran from the notify; put the caret in the new value field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _valueFocus[id]?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: m,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<FsplTargetRow> rows = m.targetRows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (rows.isEmpty)
          const FsplNote(
            Icons.horizontal_rule,
            'No design targets on the chart. Add a line, or reset to the '
            'defaults.',
          ),
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          _row(context, rows[i], i + 1),
          const SizedBox(height: AppSpacing.xs),
        ],
        Wrap(
          spacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TextButton.icon(
              onPressed: m.canAddTarget ? _add : null,
              icon: const Icon(Icons.add),
              label: const Text('Add line'),
            ),
            TextButton.icon(
              onPressed: m.targetsAreDefault ? null : m.resetTargets,
              icon: const Icon(Icons.restart_alt),
              label: Text(m.resetTargetsLabel),
            ),
          ],
        ),
        if (!m.canAddTarget)
          Text(
            'Up to $kFsplMaxTargets lines, so the labels stay readable.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, FsplTargetRow r, int n) {
    final AppColorScheme colors = context.colors;
    final TextStyle? fieldStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: colors.textPrimary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 112,
          child: LabeledField(
            label: 'Level',
            hint: '(dBm)',
            semanticLabel: 'Design target $n level in dBm',
            field: TextField(
              key: ValueKey<String>('fspl-target-value-${r.id}'),
              controller: _value[r.id],
              focusNode: _valueFocus[r.id],
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              onChanged: (String s) => m.setTargetValueText(r.id, s),
              style: fieldStyle,
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                hintText: 'e.g. -75',
                errorText: m.targetError(r.id),
                errorMaxLines: 2,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: LabeledField(
            label: 'Label',
            semanticLabel: 'Design target $n label',
            field: TextField(
              key: ValueKey<String>('fspl-target-label-${r.id}'),
              controller: _label[r.id],
              focusNode: _labelFocus[r.id],
              inputFormatters: <TextInputFormatter>[
                LengthLimitingTextInputFormatter(kFsplTargetLabelMax),
              ],
              onChanged: (String s) => m.setTargetLabel(r.id, s),
              style: fieldStyle,
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                hintText: r.dbm == null
                    ? 'e.g. data'
                    : '${fsplTargetValueText(r.dbm!)} dBm',
              ),
            ),
          ),
        ),
        Padding(
          // Level with the fields, below their label line.
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: IconButton(
            tooltip: 'Remove design target $n',
            onPressed: () => m.removeTarget(r.id),
            icon: Icon(Icons.close, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Readouts ──────────────────────────────────────────────────────────────

/// Cursor table, band differences, measured gap, and the Why panel.
class FsplReadouts extends StatelessWidget {
  const FsplReadouts({super.key, required this.model});
  final FsplSimModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _cursorCard(context),
          const SizedBox(height: AppSpacing.sm),
          FsplWhyPanel(model: model),
        ],
      ),
    );
  }

  Widget _cursorCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<WifiBand> bands = model.bands;
    final double d = model.cursorM;
    if (bands.isEmpty) {
      return const FsplCard(
        child: FsplNote(
          Icons.visibility_off_outlined,
          'No band is on. Turn on 2.4, 5 or 6 GHz to read path loss and '
          'received power.',
        ),
      );
    }
    TextStyle head() => text.labelSmall!.copyWith(color: colors.textTertiary);
    TextStyle val({bool strong = false}) => mono.inlineCode.copyWith(
      color: strong ? colors.textAccent : colors.textPrimary,
      fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
    );
    TextStyle sub() => mono.inlineCode.copyWith(color: colors.textSecondary);
    Widget cell(String s, TextStyle style, {double top = AppSpacing.xs}) =>
        Padding(
          padding: EdgeInsets.only(left: AppSpacing.sm, top: top),
          child: Text(s, style: style, textAlign: TextAlign.right),
        );

    final List<(WifiBand, WifiBand)> pairs = <(WifiBand, WifiBand)>[
      for (int i = 0; i < bands.length; i++)
        for (int j = i + 1; j < bands.length; j++) (bands[i], bands[j]),
    ];
    final ({double rssi, double dist})? meas = model.measured;
    final String Function(double, [int]) n = FsplFormat.n;

    return FsplCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FsplSectionLabel('At ${model.dist(d)}'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(),
              1: IntrinsicColumnWidth(),
              2: IntrinsicColumnWidth(),
            },
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  Text('Band', style: head()),
                  cell('Path loss', head(), top: 0),
                  cell('Received', head(), top: 0),
                ],
              ),
              for (final WifiBand b in bands) ...<TableRow>[
                TableRow(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 24,
                            height: 12,
                            child: FsplBandSample(band: b),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  b.label,
                                  style: text.bodyMedium?.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                Text(
                                  model.chanText(b),
                                  style: text.bodySmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    cell('${n(model.pathLoss(b, d))} dB', val()),
                    cell(
                      '${n(model.rx(model.pathLoss(b, d)))} dBm',
                      val(strong: true),
                    ),
                  ],
                ),
                if (model.indoor)
                  TableRow(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          'Indoor, n = ${n(model.exponent)}',
                          style: text.bodySmall?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                      cell(
                        '${n(model.pathLossIndoor(b, d))} dB',
                        sub(),
                        top: 0,
                      ),
                      cell(
                        '${n(model.rx(model.pathLossIndoor(b, d)))} dBm',
                        sub(),
                        top: 0,
                      ),
                    ],
                  ),
              ],
            ],
          ),
          if (pairs.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            const FsplSectionLabel('Difference between bands'),
            const SizedBox(height: AppSpacing.xxs),
            for (final (WifiBand lo, WifiBand hi) in pairs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${hi.label} vs ${lo.label}',
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '${FsplFormat.signed(FsplMath.bandDifferenceDb(model.freq(lo), model.freq(hi)))} dB',
                      style: val(),
                    ),
                  ],
                ),
              ),
            Text(
              'More loss at the higher band, the same at every distance: '
              '20 log10(f2 / f1).',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          if (meas != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            const FsplSectionLabel('Measured point'),
            const SizedBox(height: AppSpacing.xxs),
            _measuredSummary(context, meas.rssi, meas.dist),
          ],
        ],
      ),
    );
  }

  Widget _measuredSummary(BuildContext context, double rssi, double dist) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double gap = model.gap(rssi, dist);
    final double free = model.rx(model.pathLoss(model.measuredBand, dist));
    final double? fitN = model.fitExponent(rssi, dist);
    final String Function(double, [int]) n = FsplFormat.n;
    final String lead =
        '${n(rssi)} dBm at ${model.dist(dist)} on '
        '${model.measuredBand.label}. Free space predicts ${n(free)} dBm, so '
        'the reading is ${n(gap.abs())} dB ${gap < 0 ? 'below' : 'above'} '
        'free space.';
    final String follow = gap < 0
        ? ' That extra loss is walls, people, antenna pattern and fading: '
              'the part of a design free space leaves out.'
        : ' A real link rarely beats free space; check that Tx power and '
              'antenna gains match the link you measured.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          lead + follow,
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        if (fitN != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'A log-distance exponent of n = ${n(fitN)} would pass through '
            'this point.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

// ── Cursor headline (presenter stage) ─────────────────────────────────────

/// The numbers the lesson is about, in headline type across the top of the
/// presenter stage: each band's value at the cursor in the chart's current
/// view, the other quantity under it, and the gap between the highest and
/// lowest band.
class FsplCursorHeadline extends StatelessWidget {
  const FsplCursorHeadline({super.key, required this.model});
  final FsplSimModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final List<WifiBand> bands = model.bands;
    final double d = model.cursorM;
    final bool received = model.view == FsplView.received;
    final String Function(double, [int]) n = FsplFormat.n;

    if (bands.isEmpty) {
      return const FsplCard(
        child: FsplNote(
          Icons.visibility_off_outlined,
          'No band is on. Turn one on to read its loss.',
        ),
      );
    }
    final WifiBand lo = bands.first;
    final WifiBand hi = bands.last;

    Widget band(WifiBand b) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 28 * scale.marker,
              height: 14 * scale.marker,
              child: FsplBandSample(band: b),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                '${b.label} ch ${model.channel(b)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            received
                ? '${n(model.rx(model.pathLoss(b, d)))} dBm'
                : '${n(model.pathLoss(b, d))} dB',
            style: scale
                .headlineStyle(mono.outputLarge)
                .copyWith(color: colors.textAccent),
          ),
        ),
        Text(
          received
              ? '${n(model.pathLoss(b, d))} dB of path loss'
              : '${n(model.rx(model.pathLoss(b, d)))} dBm received',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );

    return FsplCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                FsplSectionLabel(
                  '${received ? 'Received' : 'Path loss'} at '
                  '${model.dist(d)}',
                ),
                if (bands.length > 1)
                  Text(
                    '${hi.label} vs ${lo.label}: '
                    '${FsplFormat.signed(FsplMath.bandDifferenceDb(model.freq(lo), model.freq(hi)))} dB '
                    'at every distance',
                    style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < bands.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: band(bands[i])),
                ],
                // Keep a lone band from spreading across the whole stage.
                for (int i = bands.length; i < 3; i++) ...<Widget>[
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Why panel ─────────────────────────────────────────────────────────────

/// Spreading loss and aperture term as two stacked bars per band, at the
/// cursor distance. The spreading bar is identical across bands; only the
/// aperture bar changes.
class FsplWhyPanel extends StatelessWidget {
  const FsplWhyPanel({super.key, required this.model, this.compact = false});
  final FsplSimModel model;

  /// Presenter stage: the closing paragraph shrinks to one line (the
  /// instructor says the rest).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<WifiBand> bands = model.bands;
    final double d = model.cursorM;
    final double spread = FsplMath.spreadingLossDb(d);
    final double maxTotal = bands.isEmpty
        ? 1
        : bands.map((WifiBand b) => model.pathLoss(b, d)).reduce(math.max);
    final String Function(double, [int]) n = FsplFormat.n;

    Widget key(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 14,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );

    return FsplCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FsplSectionLabel('Why higher bands lose more, at ${model.dist(d)}'),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                key(colors.borderStrong, 'Spreading, same for every band'),
                key(colors.textAccent, 'Aperture, the receive antenna'),
              ],
            ),
          ),
          if (bands.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const FsplNote(
              Icons.visibility_off_outlined,
              'Turn on a band to split its loss into the two parts.',
            ),
          ],
          for (final WifiBand b in bands) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _bandBars(context, mono, b, spread, maxTotal, n),
          ],
          if (bands.length > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              compact
                  ? 'Spreading is identical. Only the aperture changes: a '
                        'shorter wavelength makes a smaller antenna.'
                  : 'The spreading parts are identical: the energy spreads '
                        'over the same sphere at every frequency. Only the '
                        'aperture part changes. A shorter wavelength makes a '
                        'smaller antenna, which catches less of that energy.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bandBars(
    BuildContext context,
    AppMonoText mono,
    WifiBand b,
    double spread,
    double maxTotal,
    String Function(double, [int]) n,
  ) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double ap = FsplMath.apertureTermDb(model.freq(b));
    final double total = spread + ap;
    final double cm2 = FsplMath.isotropicApertureM2(model.freq(b)) * 1e4;
    return Semantics(
      label:
          '${b.label}: spreading ${n(spread)} dB plus aperture ${n(ap)} dB '
          'equals ${n(total)} dB. Isotropic antenna area ${n(cm2)} square '
          'centimetres.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  b.label,
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                '${n(total)} dB',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double w = c.maxWidth;
              final double sw = w * spread / maxTotal;
              final double aw = math.max(0.0, w * ap / maxTotal - 2);
              final double barH = 14 * PresenterMode.scaleOf(context).marker;
              return Row(
                children: <Widget>[
                  Container(
                    width: sw,
                    height: barH,
                    decoration: BoxDecoration(
                      color: colors.borderStrong,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: aw,
                    height: barH,
                    decoration: BoxDecoration(
                      color: colors.textAccent,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            compact
                ? '${n(spread)} + ${n(ap)} dB, antenna ${n(cm2)} cm²'
                : '${n(spread)} spreading + ${n(ap)} aperture. Antenna area '
                      '${n(cm2)} cm².',
            style: mono.inlineCode.copyWith(
              fontSize: AppTextSize.caption,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class FsplExplainer extends StatelessWidget {
  const FsplExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle formula() =>
        mono.inlineCode.copyWith(color: colors.textSecondary);
    return FsplCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const FsplSectionLabel('What the curve says'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '1. Signal falls fast close in and slowly far out. Every doubling '
            'of distance costs 6 dB, so '
            '${UnitSystemScope.systemOf(context).isMetric ? '1 m to 2 m costs the same as 50 m to 100 m' : '3 ft to 6 ft costs the same as 150 ft to 300 ft'}.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '2. Higher bands lose more at the same distance because the '
            'receive antenna is smaller, not because the air absorbs more. '
            'An isotropic antenna collects energy over an area of wavelength '
            'squared over 4 pi.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '3. Free space is the best case. Real rooms lose more, and the '
            'gap between this curve and a measurement is where the design '
            'work happens.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('FSPL = (4 pi d / lambda)^2', style: formula()),
          Text(
            'FSPL (dB) = 20 log10(d m) + 20 log10(f MHz) - 27.55',
            style: formula(),
          ),
          Text(
            '= 10 log10(4 pi d^2) - 10 log10(lambda^2 / 4 pi)',
            style: formula(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This screen uses c = 299,792,458 m/s exactly; the rounded 27.55 '
            'constant differs by under 0.01 dB.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
