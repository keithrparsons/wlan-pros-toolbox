// The controls for OFDMA vs MU-MIMO (Wi-Fi Classroom): readouts (total
// airtime, sounding, per-client SNR loss and MCS) and the inputs (scenario,
// AP antennas, clients, width, frame size, exchanges per sounding, the
// reflection, and a keyboard path to move each client). Reads and writes an
// [OfdmaVsMumimoController]; owns no state.
//
// States:
//   - a preset             -> the scenario select shows it
//   - edited               -> the select reads "Your own layout"
//   - MU-MIMO not drawn    -> its readouts show "--" and the reason
//   - a client at an edge  -> the matching move button is disabled
//
// Numbers in DM Mono. Lime (textAccent) marks the one quantity the tool is
// about: the total of the scheme that wins.
//
// PRESENTER (PresenterMode.isActive): inputs two per row; the readouts fold
// into a PresenterDisclosure so the panel fits at 1440x900.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart' show formatTenthsUs;
import '../../../services/wifi_lab/mu_mimo_model.dart';
import '../../../services/wifi_lab/ofdma_model.dart' show clientLetter;
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'ofdma_vs_mumimo_controller.dart';

class OfdmaVsMumimoControls extends StatelessWidget {
  const OfdmaVsMumimoControls({super.key, required this.controller});

  final OfdmaVsMumimoController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Inputs(c: controller, compact: true),
              PresenterDisclosure(
                title: 'All readouts',
                children: <Widget>[_Readouts(c: controller)],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Readouts(c: controller),
            const SizedBox(height: AppSpacing.md),
            _Inputs(c: controller, compact: false),
          ],
        );
      },
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.c});

  final OfdmaVsMumimoController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final MuResult r = c.result;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);
    final TextStyle accent = value.copyWith(
      color: colors.textAccent,
      fontWeight: FontWeight.w700,
    );
    String us(int? t) => t == null ? '--' : formatTenthsUs(t);

    TableRow row(String name, String v, {bool lead = false}) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: lead ? accent : value,
          ),
        ),
      ],
    );

    Widget cell(String s, {TextAlign align = TextAlign.end, TextStyle? st}) =>
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xxs,
            horizontal: AppSpacing.xxs,
          ),
          child: Text(s, textAlign: align, style: st ?? value),
        );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              row(
                'OFDMA, total airtime (µs)',
                us(r.ofdma?.totalTenths),
                lead:
                    r.winner == MuWinner.ofdma ||
                    r.winner == MuWinner.muUnavailable,
              ),
              row(
                'MU-MIMO, total airtime (µs)',
                us(r.mu?.totalTenths),
                lead: r.winner == MuWinner.muMimo,
              ),
              row(
                'MU-MIMO sounding, once (µs)',
                r.mu == null ? '--' : us(r.soundingTenths),
              ),
              row(
                'Data per exchange, OFDMA / MU-MIMO (µs)',
                r.mu == null || r.ofdma == null
                    ? '--'
                    : '${us(r.ofdmaDataTenths)} / ${us(r.muDataTenths)}',
              ),
              row('One MU report (bytes)', '${r.report.bytes}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Per client',
            style: text.titleSmall?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
              3: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                children: <Widget>[
                  cell('Client', align: TextAlign.start, st: label),
                  cell('SNR loss', st: label),
                  cell('OFDMA MCS', st: label),
                  cell('MU MCS', st: label),
                ],
              ),
              for (int i = 0; i < c.clientCount; i++)
                TableRow(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxs,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ClientChip(index: i),
                      ),
                    ),
                    cell(
                      r.precoding.possible
                          ? muLossText(r.links[i].zfLossDb)
                          : '--',
                    ),
                    cell('${r.links[i].ofdmaMcs ?? '--'}'),
                    cell('${r.links[i].muMcs ?? '--'}'),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'SNR loss is what zero-forcing costs each client against the AP '
            'aiming every antenna at it alone. MU-MIMO also splits the power '
            'over ${c.clientCount} streams and gains ${c.antennas} antennas: '
            '${_signed(10 * math.log(c.antennas / c.clientCount) / math.ln10)} '
            'before that loss.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _signed(double db) {
    if (!db.isFinite) return '--';
    final String v = db.abs().toStringAsFixed(1);
    return db >= 0 ? '+$v dB' : '-$v dB';
  }
}

/// A client's letter on its hue, as drawn in the room and the lanes.
class ClientChip extends StatelessWidget {
  const ClientChip({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final WifiLabClientStyle st = WifiLabClientPalette.of(index, colors);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: st.hue,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        clientLetter(index),
        style: text.labelMedium?.copyWith(
          color: st.onHue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Inputs ──────────────────────────────────────────────────────────────────

class _Inputs extends StatelessWidget {
  const _Inputs({required this.c, required this.compact});

  final OfdmaVsMumimoController c;

  /// Presenter panel: two inputs per row, shorter option labels.
  final bool compact;

  Widget _select<T>(
    String label,
    T value,
    List<AppSelectItem<T>> items,
    ValueChanged<T> onChanged,
  ) => LabeledField(
    label: label,
    field: AppSelect<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      semanticLabel: label,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final SizedBox gap = SizedBox(
      height: compact ? AppSpacing.xs : AppSpacing.sm,
    );

    Widget pair(Widget a, Widget b) => compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: a),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[a, gap, b],
          );

    final Widget scenario = _select<MuPreset?>(
      'Scenario',
      c.preset,
      <AppSelectItem<MuPreset?>>[
        for (final MuPreset p in MuPreset.values) (p, p.label),
        if (c.preset == null) (null, 'Your own layout'),
      ],
      (MuPreset? p) {
        if (p != null) c.applyPreset(p);
      },
    );
    final Widget antennas = _select<int>(
      'AP antennas',
      c.antennas,
      <AppSelectItem<int>>[
        for (int m = MuLimits.minAntennas; m <= MuLimits.maxAntennas; m++)
          (m, '$m'),
      ],
      c.setAntennas,
    );
    final Widget clients = _select<int>(
      'Clients',
      c.clientCount,
      <AppSelectItem<int>>[
        for (int k = MuLimits.minClients; k <= MuLimits.maxClients; k++)
          (k, '$k'),
      ],
      c.setClientCount,
    );
    final Widget width = _select<int>(
      'Channel width',
      c.widthMhz,
      <AppSelectItem<int>>[
        for (final int w in MuLimits.widthsMhz) (w, '$w MHz'),
      ],
      c.setWidth,
    );
    final Widget payload = _select<int>(
      'Frame size',
      c.payloadBytes,
      <AppSelectItem<int>>[
        for (final int b in MuLimits.payloadChoices) (b, '$b bytes'),
      ],
      c.setPayload,
    );
    final Widget exchanges = _select<int>(
      'Exchanges per sounding',
      c.exchanges,
      <AppSelectItem<int>>[
        for (final int n in MuLimits.exchangeChoices) (n, '$n'),
      ],
      c.setExchanges,
    );
    final Widget reflection = AppToggle<bool>(
      label: 'Side-wall reflection',
      semanticLabel: 'Side-wall reflection',
      value: c.reflection,
      items: const <AppToggleItem<bool>>[(false, 'Off'), (true, 'On')],
      onChanged: c.setReflection,
    );
    final Widget who = _select<int>(
      'Move client',
      c.selected,
      <AppSelectItem<int>>[
        for (int i = 0; i < c.clientCount; i++)
          (i, '${clientLetter(i)}, ${c.placeOf(i)}'),
      ],
      c.select,
    );
    final Widget moves = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _Button(
          label: 'Turn left',
          icon: Icons.rotate_left_rounded,
          onPressed: c.canTurnLeft
              ? () => c.turnSelected(-kMuTurnStepDeg)
              : null,
        ),
        _Button(
          label: 'Turn right',
          icon: Icons.rotate_right_rounded,
          onPressed: c.canTurnRight
              ? () => c.turnSelected(kMuTurnStepDeg)
              : null,
        ),
        _Button(
          label: 'Closer',
          icon: Icons.south_rounded,
          onPressed: c.canCloser
              ? () => c.stepSelectedDistance(-kMuDistanceStepM)
              : null,
        ),
        _Button(
          label: 'Farther',
          icon: Icons.north_rounded,
          onPressed: c.canFarther
              ? () => c.stepSelectedDistance(kMuDistanceStepM)
              : null,
        ),
      ],
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Scenario'),
          const SizedBox(height: AppSpacing.xs),
          scenario,
          if (c.preset != null && !compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              c.preset!.detail,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          gap,
          pair(antennas, clients),
          gap,
          pair(width, payload),
          gap,
          pair(exchanges, reflection),
          gap,
          who,
          const SizedBox(height: AppSpacing.xs),
          moves,
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Turn moves the client ${kMuTurnStepDeg.round()} deg around the '
              'AP; Closer and Farther move it ${kMuDistanceStepM.round()} m. '
              'You can also drag it in the room.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSpacing.minTouchTarget),
        foregroundColor: colors.textPrimary,
        disabledForegroundColor: colors.textDisabled,
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
    );
  }
}
