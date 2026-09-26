// Controls and readouts for the Wi-Fi Classroom Channel Planner.
//
// ChannelPlannerControls: band, region, width, DFS and U-NII-4, the 2.4 GHz
// mask, Auto-plan, the AP list (pick, channel, width, position, add,
// remove), walls, and the floor and radio settings.
// ChannelPlannerReadouts: channels available at this width, the largest
// contention domain and its airtime share, who contends and which rule
// fired, the 2.4 GHz mask table, and the thresholds.
// Each takes a ChannelPlannerState and neither knows about the stage.
//
// PRESENTER (spec 00): inside a PresenterLayout the plan's verdict moves onto
// the stage (channel_planner_stage.dart), the controls keep band, width,
// Auto-plan and the selected AP in view, and walls, floor and radio
// settings, the pair list, the mask table and the thresholds fold into
// PresenterDisclosures. Phone-only prose is dropped there.
//
// THEME: context.colors only. Status hues appear once, on the domain
// verdict, with the verdict in words (§8.13 rules 2 and 6). Lime marks the
// largest-domain number, the quantity the tool is about.
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/channel_planner_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../labeled_field.dart';
import 'channel_planner_state.dart';

// ── Shared parts ──────────────────────────────────────────────────────────

class PlannerCard extends StatelessWidget {
  const PlannerCard({super.key, required this.child});
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

class PlannerSectionLabel extends StatelessWidget {
  const PlannerSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
          fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

class PlannerNote extends StatelessWidget {
  const PlannerNote(this.icon, this.message, {super.key, this.color});
  final IconData icon;
  final String message;

  /// A §8.13 status hue when the note is a verdict; neutral otherwise.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color ?? colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color ?? colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

String _db(double v) => v.toStringAsFixed(1);

/// `36/40`, or `overlapping channels 4 and 6` when members differ.
String _domainChannels(ChannelPlannerState s, List<int> members) {
  final List<String> labels = <String>[
    for (final int i in members)
      if (s.channelOf(i) != null) s.channelOf(i)!.shortLabel,
  ];
  final List<String> distinct = labels.toSet().toList();
  if (distinct.length == 1) return distinct.first;
  return 'overlapping channels ${distinct.join(' and ')}';
}

/// Lowercase the first letter only, so MHz keeps its case.
String _lower(String s) => s[0].toLowerCase() + s.substring(1);

/// The plan's verdict: an icon, its §8.13 hue and the sentence that says it.
typedef PlanVerdict = ({IconData icon, Color color, String message});

/// The verdict the readouts and the presenter stage both show: a danger
/// note when some AP has no channel at its width, else sharing by the size
/// of the largest contention domain.
PlanVerdict channelPlanVerdict(ChannelPlannerState s, AppColorScheme colors) {
  final List<int> unassigned = s.unassigned;
  if (unassigned.isNotEmpty) {
    final bool dfsOff = s.band == PlannerBand.band5 && !s.rules.dfs;
    return (
      icon: Icons.error,
      color: colors.statusDanger,
      message:
          'No ${s.apWidth(unassigned.first)} MHz channel exists in the '
          '${s.rules.region.label}${dfsOff ? ' with DFS off' : ''}. '
          '${unassigned.map(s.apName).join(', ')} '
          '${unassigned.length == 1 ? 'has' : 'have'} no channel. '
          '${dfsOff ? 'Turn DFS on or pick' : 'Pick'} a narrower width.',
    );
  }
  final int n = s.analysis.largestDomain.length;
  if (n <= 1) {
    return (
      icon: Icons.check_circle,
      color: colors.statusSuccess,
      message: 'No sharing: every AP has its channel to itself.',
    );
  }
  if (n <= 3) {
    return (
      icon: Icons.warning,
      color: colors.statusWarning,
      message: 'Shared: $n APs take turns on one channel.',
    );
  }
  return (
    icon: Icons.error,
    color: colors.statusDanger,
    message: 'Crowded: $n APs take turns on one channel.',
  );
}

// ── Controls ──────────────────────────────────────────────────────────────

class ChannelPlannerControls extends StatelessWidget {
  const ChannelPlannerControls({super.key, required this.state});
  final ChannelPlannerState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) =>
          PresenterMode.isActive(context)
          ? _presenter(context)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _children(context),
            ),
    );
  }

  /// Presenter panel: what a lesson changes stays in view (band, width,
  /// Auto-plan, the selected AP's channel); walls and the floor and radio
  /// settings fold. The explanatory notes are phone-only.
  Widget _presenter(BuildContext context) {
    final ChannelPlannerState s = state;
    final PlanRules r = s.rules;
    final bool is5 = r.band == PlannerBand.band5;
    final int? sel = s.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PlannerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  AppToggle<PlannerBand>(
                    semanticLabel: 'Band',
                    value: r.band,
                    items: <AppToggleItem<PlannerBand>>[
                      for (final PlannerBand b in PlannerBand.values)
                        (b, b.label),
                    ],
                    onChanged: s.setBand,
                  ),
                  AppToggle<PlannerRegion>(
                    semanticLabel: 'Region',
                    value: r.region,
                    items: <AppToggleItem<PlannerRegion>>[
                      for (final PlannerRegion g in PlannerRegion.values)
                        (g, g.label),
                    ],
                    onChanged: s.setRegion,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _widthSelect(s),
              if (is5)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _switch(context, 'DFS channels', r.dfs, s.setDfs),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _switch(
                        context,
                        'U-NII-4 (US)',
                        r.unii4,
                        r.region == PlannerRegion.us ? s.setUnii4 : null,
                      ),
                    ),
                  ],
                )
              else ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                AppToggle<TxMask>(
                  label: 'Transmit mask',
                  value: r.mask,
                  expand: true,
                  items: <AppToggleItem<TxMask>>[
                    for (final TxMask m in TxMask.values) (m, m.label),
                  ],
                  onChanged: s.setMask,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: s.available == 0 ? null : s.runAutoPlan,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Auto-plan'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    onPressed: s.reset,
                    tooltip: 'Reset to the starting floor (R)',
                    icon: const Icon(Icons.restart_alt),
                    color: context.colors.textAccent,
                  ),
                ],
              ),
              if (s.planNote != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                PlannerNote(Icons.auto_fix_high, s.planNote!),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: _apSelect(
                      s,
                      sel,
                      label: 'Selected AP (${s.apCount} of $kMaxAps)',
                    ),
                  ),
                  IconButton(
                    onPressed: s.canAdd ? s.addAp : null,
                    tooltip: 'Add AP',
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    onPressed: sel != null && s.canRemove
                        ? () => s.removeAp(sel)
                        : null,
                    tooltip: sel == null
                        ? 'Remove AP'
                        : 'Remove ${s.apName(sel)}',
                    icon: const Icon(Icons.remove),
                  ),
                ],
              ),
              if (sel != null) ...<Widget>[
                ..._apChannelAndWidth(sel),
                PresenterDisclosure(
                  title: 'Move ${s.apName(sel)} by the numbers',
                  children: _apPosition(context, sel),
                ),
              ],
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'Walls, floor size and radios',
          children: <Widget>[
            ..._walls(context),
            const SizedBox(height: AppSpacing.sm),
            ..._floorAndRadios(context),
          ],
        ),
      ],
    );
  }

  Widget _widthSelect(ChannelPlannerState s) {
    final PlanRules r = s.rules;
    // Up to four widths: GL-003 §8.14 routes 4+ options to AppSelect.
    return LabeledField(
      label: 'Channel width, every AP',
      field: AppSelect<int>(
        value: s.width,
        semanticLabel: 'Channel width, every AP',
        enabled: r.widths.length > 1,
        items: <AppSelectItem<int>>[
          for (final int w in r.widths)
            (w, '$w MHz  (${channelsAvailable(r, w)} available)'),
        ],
        onChanged: s.setWidth,
      ),
    );
  }

  Widget _apSelect(
    ChannelPlannerState s,
    int? sel, {
    String label = 'Selected AP',
  }) => LabeledField(
    label: label,
    field: AppSelect<int>(
      value: sel ?? 0,
      semanticLabel: 'Selected AP',
      items: <AppSelectItem<int>>[
        for (int i = 0; i < s.apCount; i++)
          (
            i,
            '${s.apName(i)}  (${s.channelOf(i)?.shortLabel ?? 'no channel'})',
          ),
      ],
      onChanged: s.select,
    ),
  );

  List<Widget> _children(BuildContext context) {
    final ChannelPlannerState s = state;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PlanRules r = s.rules;
    final bool is5 = r.band == PlannerBand.band5;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final int? sel = s.selected;

    return <Widget>[
      const PlannerSectionLabel('Band and rules'),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          AppToggle<PlannerBand>(
            semanticLabel: 'Band',
            value: r.band,
            items: <AppToggleItem<PlannerBand>>[
              for (final PlannerBand b in PlannerBand.values) (b, b.label),
            ],
            onChanged: s.setBand,
          ),
          AppToggle<PlannerRegion>(
            semanticLabel: 'Region',
            value: r.region,
            items: <AppToggleItem<PlannerRegion>>[
              for (final PlannerRegion g in PlannerRegion.values) (g, g.label),
            ],
            onChanged: s.setRegion,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      _widthSelect(s),
      if (is5) ...<Widget>[
        _switch(context, 'DFS channels (52-64, 100-144)', r.dfs, s.setDfs),
        _switch(
          context,
          'U-NII-4 (169-177, US only)',
          r.unii4,
          r.region == PlannerRegion.us ? s.setUnii4 : null,
        ),
        if (r.region == PlannerRegion.eu)
          Text('The EU plan has no U-NII-4 and stops at 140.', style: small()),
      ] else ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        AppToggle<TxMask>(
          label: 'Transmit mask',
          value: r.mask,
          expand: true,
          items: <AppToggleItem<TxMask>>[
            for (final TxMask m in TxMask.values) (m, m.label),
          ],
          onChanged: s.setMask,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          r.mask == TxMask.dsss
              ? 'DSSS is 22 MHz wide and has no 40 MHz channel.'
              : 'No DFS in 2.4 GHz.',
          style: small(),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      FilledButton.icon(
        onPressed: s.available == 0 ? null : s.runAutoPlan,
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('Auto-plan'),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        'A greedy teaching heuristic that shrinks the largest contention '
        'domain. Not a vendor RRM algorithm.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      PlannerSectionLabel('Access points (${s.apCount} of $kMaxAps)'),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: s.canAdd ? s.addAp : null,
            icon: const Icon(Icons.add),
            label: const Text('Add AP'),
          ),
          OutlinedButton.icon(
            onPressed: sel != null && s.canRemove
                ? () => s.removeAp(sel)
                : null,
            icon: const Icon(Icons.remove),
            label: Text(sel == null ? 'Remove AP' : 'Remove ${s.apName(sel)}'),
          ),
        ],
      ),
      if (!s.canRemove)
        Text('The plan needs at least $kMinAps APs.', style: small()),
      const SizedBox(height: AppSpacing.sm),
      _apSelect(s, sel),
      if (sel != null) ..._apEditor(context, sel),
      const SizedBox(height: AppSpacing.md),
      const PlannerSectionLabel('Walls'),
      ..._walls(context),
      const SizedBox(height: AppSpacing.md),
      const PlannerSectionLabel('Floor and radios'),
      ..._floorAndRadios(context),
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: s.reset,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset to the starting floor'),
        ),
      ),
    ];
  }

  List<Widget> _walls(BuildContext context) {
    final ChannelPlannerState s = state;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool presenting = PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    return <Widget>[
      _switch(
        context,
        'Wall tool: drag on the floor',
        s.wallMode,
        s.setWallMode,
      ),
      _slider(
        context,
        label: 'Loss per wall',
        unit: 'dB',
        value: s.propagation.wallLossDb,
        min: 0,
        max: 30,
        divisions: 30,
        decimals: 0,
        onChanged: s.setWallLoss,
      ),
      if (!presenting)
        Text(
          'One wall type, one number. 10 dB is a round starting value, not '
          'a measured material.',
          style: small(),
        ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          OutlinedButton(
            onPressed: () => s.addWallAcross(vertical: true),
            child: const Text('Add wall top to bottom'),
          ),
          OutlinedButton(
            onPressed: () => s.addWallAcross(vertical: false),
            child: const Text('Add wall side to side'),
          ),
        ],
      ),
      for (int i = 0; i < s.walls.length; i++)
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Wall ${i + 1}: (${s.walls[i].x1.round()}, '
                '${s.walls[i].y1.round()}) to (${s.walls[i].x2.round()}, '
                '${s.walls[i].y2.round()}) m',
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
            IconButton(
              tooltip: 'Remove wall ${i + 1}',
              onPressed: () => s.removeWall(i),
              icon: Icon(Icons.close, color: colors.textSecondary),
            ),
          ],
        ),
      if (s.walls.length > 1)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: s.clearWalls,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear walls'),
          ),
        ),
    ];
  }

  List<Widget> _floorAndRadios(BuildContext context) {
    final ChannelPlannerState s = state;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool presenting = PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    return <Widget>[
      _slider(
        context,
        label: 'AP EIRP',
        unit: 'dBm',
        value: s.propagation.eirpDbm,
        min: 0,
        max: 30,
        divisions: 30,
        decimals: 0,
        onChanged: s.setEirp,
      ),
      _slider(
        context,
        label: 'Path-loss exponent n',
        unit: '',
        value: s.propagation.exponent,
        min: 2,
        max: 4,
        divisions: 20,
        onChanged: s.setExponent,
      ),
      if (!presenting)
        Text(
          'Log-distance model: free-space loss at 1 m plus 10 n log10(d). '
          'n = 2 is free space; 3 is a common office guess.',
          style: small(),
        ),
      _slider(
        context,
        label: 'Floor width',
        unit: 'm',
        value: s.floorW,
        min: 20,
        max: 100,
        divisions: 16,
        decimals: 0,
        onChanged: (double v) => s.setFloorSize(w: v),
      ),
      _slider(
        context,
        label: 'Floor depth',
        unit: 'm',
        value: s.floorH,
        min: 10,
        max: 60,
        divisions: 10,
        decimals: 0,
        onChanged: (double v) => s.setFloorSize(h: v),
      ),
    ];
  }

  List<Widget> _apEditor(BuildContext context, int i) => <Widget>[
    ..._apChannelAndWidth(i),
    ..._apPosition(context, i),
  ];

  List<Widget> _apChannelAndWidth(int i) => <Widget>[
    const SizedBox(height: AppSpacing.xs),
    _apChannel(i),
    const SizedBox(height: AppSpacing.xs),
    _apWidth(i),
  ];

  Widget _apChannel(int i) {
    final ChannelPlannerState s = state;
    final List<ChannelOption> opts = s.optionsFor(s.apWidth(i));
    final ChannelOption? cur = s.channelOf(i);
    return LabeledField(
      label: '${s.apName(i)} channel',
      field: opts.isEmpty || cur == null
          ? AppSelect<int>(
              value: 0,
              semanticLabel: '${s.apName(i)} channel',
              enabled: false,
              errorText:
                  'No ${s.apWidth(i)} MHz channel exists under these rules.',
              items: const <AppSelectItem<int>>[(0, 'None')],
              onChanged: (int _) {},
            )
          : AppSelect<ChannelOption>(
              value: cur,
              semanticLabel: '${s.apName(i)} channel',
              items: <AppSelectItem<ChannelOption>>[
                for (final ChannelOption o in opts) (o, o.longLabel),
              ],
              onChanged: (ChannelOption o) => s.setApChannel(i, o),
            ),
    );
  }

  Widget _apWidth(int i) {
    final ChannelPlannerState s = state;
    return LabeledField(
      label: '${s.apName(i)} width',
      field: AppSelect<int>(
        value: s.apWidth(i),
        semanticLabel: '${s.apName(i)} width',
        enabled: s.rules.widths.length > 1,
        items: <AppSelectItem<int>>[
          for (final int w in s.rules.widths) (w, '$w MHz'),
        ],
        onChanged: (int w) => s.setApWidth(i, w),
      ),
    );
  }

  List<Widget> _apPosition(BuildContext context, int i) {
    final ChannelPlannerState s = state;
    final FloorPoint p = s.position(i);
    return <Widget>[
      _slider(
        context,
        label: '${s.apName(i)} across',
        unit: 'm',
        value: p.x.clamp(0, s.floorW).toDouble(),
        min: 0,
        max: s.floorW,
        divisions: (s.floorW * 2).round(),
        decimals: 1,
        onChanged: (double v) => s.moveAp(i, FloorPoint(v, p.y)),
      ),
      _slider(
        context,
        label: '${s.apName(i)} down',
        unit: 'm',
        value: p.y.clamp(0, s.floorH).toDouble(),
        min: 0,
        max: s.floorH,
        divisions: (s.floorH * 2).round(),
        decimals: 1,
        onChanged: (double v) => s.moveAp(i, FloorPoint(p.x, v)),
      ),
    ];
  }

  Widget _switch(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: onChanged == null
                    ? colors.textDisabled
                    : colors.textPrimary,
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
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
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    String fmt(double x) =>
        '${x.toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
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
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              Text(
                fmt(value),
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          label: fmt(value),
          semanticFormatterCallback: (double x) => '$label ${fmt(x)}',
        ),
      ],
    );
  }
}

// ── Readouts ──────────────────────────────────────────────────────────────

/// Show at most this many pairs; Copy has them all.
const int _kMaxPairs = 15;

class ChannelPlannerReadouts extends StatelessWidget {
  const ChannelPlannerReadouts({super.key, required this.state});
  final ChannelPlannerState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) =>
          PresenterMode.isActive(context)
          ? _presenter(context)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _summary(context),
                const SizedBox(height: AppSpacing.sm),
                _pairs(context),
                if (state.band == PlannerBand.band24) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  _maskTable(context),
                ],
                const SizedBox(height: AppSpacing.sm),
                const _Thresholds(),
              ],
            ),
    );
  }

  /// Presenter: the summary is on the stage; the detail folds.
  Widget _presenter(BuildContext context) {
    final int pairs =
        state.analysis.contending.length + state.analysis.oneWay.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PresenterDisclosure(
          title: 'Who contends ($pairs pair${pairs == 1 ? '' : 's'})',
          children: <Widget>[_pairs(context)],
        ),
        PresenterDisclosure(
          title: state.band == PlannerBand.band24
              ? 'Why they defer, and why 1, 6 and 11'
              : 'When an AP defers: -82, -72, -62 dBm',
          children: <Widget>[
            const _Thresholds(),
            if (state.band == PlannerBand.band24) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _maskTable(context),
            ],
          ],
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value, {
    bool accent = false,
  }) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          Text(
            value,
            style: mono.outputMedium.copyWith(
              color: accent ? colors.textAccent : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final ChannelPlannerState s = state;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PlanAnalysis a = s.analysis;
    final int n = a.largestDomain.length;
    final List<int> unassigned = s.unassigned;
    // No AP has a channel: there is no domain to report.
    final bool none = unassigned.length == s.apCount;
    final ChannelOption? domCh = s.channelOf(a.largestDomain.first);

    final PlanVerdict verdict = channelPlanVerdict(s, colors);

    return PlannerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PlannerSectionLabel('This plan'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _stat(context, 'Channels at ${s.width} MHz', '${s.available}'),
              _stat(
                context,
                'Largest contention domain',
                none ? '--' : '$n AP${n == 1 ? '' : 's'}',
                accent: true,
              ),
              _stat(
                context,
                'Airtime each (1/N)',
                none ? '--' : '${(a.largestShare * 100).round()}%',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          PlannerNote(verdict.icon, verdict.message, color: verdict.color),
          if (!none && n >= 2 && domCh != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${a.largestDomain.map(s.apName).join(', ')} all hear each '
              'other on ${_domainChannels(s, a.largestDomain)} and get about '
              '${(a.largestShare * 100).round()}% of the airtime each.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          if (s.planNote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            PlannerNote(Icons.auto_fix_high, s.planNote!),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Channels available by width, ${s.band.label} ${s.rules.region.label}'
            '${s.band == PlannerBand.band5 ? ', DFS ${s.rules.dfs ? 'on' : 'off'}' : ''}',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              for (final (int w, int c) in s.availableByWidth)
                Text(
                  '$w MHz: $c',
                  style: text.bodyMedium?.copyWith(
                    color: w == s.width
                        ? colors.textPrimary
                        : colors.textSecondary,
                    fontWeight: w == s.width ? FontWeight.w600 : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pairs(BuildContext context) {
    final ChannelPlannerState s = state;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PlanAnalysis a = s.analysis;
    final List<ApLink> shown = <ApLink>[...a.contending, ...a.oneWay];
    String line(ApLink l) {
      final String head =
          '${s.apName(l.a)} and ${s.apName(l.b)}: ${_db(l.rxDbm)} dBm'
          '${l.walls > 0 ? ' through ${l.walls} wall${l.walls == 1 ? '' : 's'}' : ''}. ';
      if (l.mutual) {
        final CcaRule ra = l.aDefersToB.rule!, rb = l.bDefersToA.rule!;
        if (ra == rb) {
          return '${head}Both defer: ${_lower(ra.label)}, '
              '${_db(l.aDefersToB.levelDbm!)} dBm per 20 MHz vs '
              '${ra.thresholdDbm.round()} (${ra.short}).';
        }
        return '$head${s.apName(l.a)} defers on ${ra.short} '
            '(${ra.thresholdDbm.round()}), ${s.apName(l.b)} on ${rb.short} '
            '(${rb.thresholdDbm.round()}).';
      }
      final bool aDefers = l.aDefersToB.defers;
      final int who = aDefers ? l.a : l.b;
      final int other = aDefers ? l.b : l.a;
      final CcaRule rule = (aDefers ? l.aDefersToB : l.bDefersToA).rule!;
      return '$head${s.apName(who)} defers (${rule.short}, '
          '${rule.thresholdDbm.round()}); ${s.apName(other)} does not, so '
          'they are not one domain.';
    }

    return PlannerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PlannerSectionLabel('Who contends, and which rule fired'),
          const SizedBox(height: AppSpacing.xs),
          if (shown.isEmpty)
            const PlannerNote(
              Icons.info_outline,
              'No two APs defer to each other. Every AP has its channel\'s '
              'airtime to itself.',
            )
          else ...<Widget>[
            for (final ApLink l in shown.take(_kMaxPairs))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  line(l),
                  style: text.bodySmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            if (shown.length > _kMaxPairs)
              Text(
                'and ${shown.length - _kMaxPairs} more; Copy results lists '
                'every pair.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
          ],
        ],
      ),
    );
  }

  Widget _maskTable(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TxMask m = state.rules.mask;
    TextStyle head() => text.labelSmall!.copyWith(color: colors.textTertiary);
    TextStyle val() => mono.inlineCode.copyWith(color: colors.textPrimary);
    Widget cell(String s, TextStyle st, {TextAlign a = TextAlign.right}) =>
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(s, style: st, textAlign: a),
        );
    return PlannerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PlannerSectionLabel('Why 1, 6 and 11: the ${m.label} mask'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.4),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  cell('Spacing', head(), a: TextAlign.left),
                  cell('Mask', head()),
                  cell('Leak in', head()),
                ],
              ),
              for (final (double off, String eg) in <(double, String)>[
                (15, '1 and 4'),
                (20, '1 and 5'),
                (25, '1 and 6'),
              ])
                TableRow(
                  children: <Widget>[
                    cell(
                      '${off.round()} MHz ($eg)',
                      text.bodySmall!.copyWith(color: colors.textSecondary),
                      a: TextAlign.left,
                    ),
                    cell('${_db(maskDbr(m, off))} dBr', val()),
                    cell('${_db(adjacentChannelDb(m, off))} dB', val()),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Mask is the ceiling at the neighbor\'s center. Leak in is that '
            'mask summed over the neighbor\'s whole 20 MHz, relative to the '
            'transmitter\'s own power. Both are the worst case the mask '
            'allows; real radios run below it.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Thresholds extends StatelessWidget {
  const _Thresholds();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle st() => text.bodySmall!.copyWith(color: colors.textSecondary);
    return PlannerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PlannerSectionLabel('When an AP defers'),
          const SizedBox(height: AppSpacing.xs),
          for (final CcaRule r in CcaRule.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                '${r.short}: ${_lower(r.label)} at '
                '${r.thresholdDbm.round()} dBm or more',
                style: st(),
              ),
            ),
          Text(
            'Levels are per 20 MHz, so a 40 MHz neighbor puts 3 dB less in '
            'each piece. SD applies to 5 GHz secondaries (VHT and later); '
            'a 2.4 GHz 40 MHz secondary uses ED only. On a secondary, '
            'deferring means sending narrower; the Lab counts it as sharing. '
            'Contention domain here means APs that all defer to each other.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
