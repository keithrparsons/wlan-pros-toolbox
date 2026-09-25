// The controls for OFDMA Resource Units (Wi-Fi Lab): readouts (airtime per
// mode, the SU / OFDMA ratio, and where the savings came from) and the
// inputs (direction, channel width, clients, frame size, MCS, and each
// client's RU). Reads and writes an [OfdmaSimulatorModel]; owns no state, so
// a presenter layout can place it beside [OfdmaSimulatorStage].
//
// States:
//   - OFDMA drawable   -> totals, ratios and the savings line
//   - check failed     -> the check in danger with icon and words; OFDMA
//                         readouts show "--" (SU still computes)
//   - PPDU too long    -> that mode shows "--" and says why
//   - client selected  -> RU size and the move buttons act on that client;
//                         "All clients" sets every RU at once
//   - move impossible  -> Move left / right disabled at the channel edge
//
// Status hues are verdicts only (§8.13): the failed check and nothing else.
// Numbers in DM Mono. Lime (textAccent) marks the one quantity the tool is
// about: the ratio for the direction being compared.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart'
    show AirtimeConstants, McsRow, formatTenthsUs;
import '../../../services/wifi_lab/ofdma_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'ofdma_simulator_model.dart';

/// The value the Client select uses for "All clients".
const int _kAll = -1;

class OfdmaSimulatorControls extends StatelessWidget {
  const OfdmaSimulatorControls({super.key, required this.model});

  final OfdmaSimulatorModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Readouts(model: model),
          const SizedBox(height: AppSpacing.md),
          _Inputs(model: model),
        ],
      ),
    );
  }
}

/// The line naming where the savings came from, for [mode]; null when that
/// mode is not drawable.
String? ofdmaSavingsLine(OfdmaResult r, OfdmaMode mode) {
  final double? ratio = r.ratio(mode);
  final Map<OfdmaPart, int>? s = r.savings(mode);
  if (ratio == null || s == null) return null;
  final int total = r.su.totalTenths - r.timeline(mode)!.totalTenths;
  String us(int t) => '${formatTenthsUs(t.abs())} µs';
  final List<String> gains = <String>[
    for (final OfdmaPart p in <OfdmaPart>[
      OfdmaPart.contention,
      OfdmaPart.preamble,
      OfdmaPart.acks,
    ])
      if (s[p]! > 0) '${us(s[p]!)} of ${p.label}',
  ];
  final List<String> costs = <String>[
    for (final OfdmaPart p in <OfdmaPart>[
      OfdmaPart.contention,
      OfdmaPart.preamble,
      OfdmaPart.acks,
    ])
      if (s[p]! < 0) '${us(s[p]!)} more ${p.label}',
  ];
  final int data = s[OfdmaPart.data]!;
  final String dataNote = data < 0
      ? ' The data itself takes ${us(data)} longer on narrower RUs, so the '
            'win is overhead, not a faster PHY.'
      : (data > 0
            ? ' The data takes ${us(data)} less: the RUs run side by side.'
            : '');
  if (total > 0) {
    return '${mode.shortLabel} saves ${us(total)}'
        '${gains.isEmpty ? '' : ': ${gains.join(', ')}'}'
        '${costs.isEmpty ? '' : '; it spends ${costs.join(', ')}'}.$dataNote';
  }
  if (total == 0) {
    return '${mode.shortLabel} takes the same airtime as SU.$dataNote';
  }
  return '${mode.shortLabel} takes ${us(total)} MORE than SU'
      '${costs.isEmpty ? '' : ': ${costs.join(', ')}'}'
      '${gains.isEmpty ? '' : '; it saves ${gains.join(', ')}'}. With one '
      'client on the whole channel there is no overhead to share.$dataNote';
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.model});

  final OfdmaSimulatorModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final OfdmaResult r = model.result;
    final OfdmaMode cmp = model.direction.mode;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);

    String total(OfdmaMode m) {
      final OfdmaTimeline? t = r.timeline(m);
      if (t == null || t.ppduTooLong) return '--';
      return formatTenthsUs(t.totalTenths);
    }

    String ratio(OfdmaMode m) {
      final double? x = r.ratio(m);
      return x == null ? '--' : '${x.toStringAsFixed(2)}x';
    }

    TableRow row(String name, String v, {bool accent = false}) => TableRow(
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
            style: accent
                ? value.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w700,
                  )
                : value,
          ),
        ),
      ],
    );

    final String? line = ofdmaSavingsLine(r, cmp);
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
                'SU airtime, ${model.clients} TXOPs (µs)',
                total(OfdmaMode.su),
              ),
              row('DL OFDMA airtime (µs)', total(OfdmaMode.dl)),
              row('UL OFDMA airtime (µs)', total(OfdmaMode.ul)),
              row(
                'SU / DL OFDMA',
                ratio(OfdmaMode.dl),
                accent: cmp == OfdmaMode.dl,
              ),
              row(
                'SU / UL OFDMA',
                ratio(OfdmaMode.ul),
                accent: cmp == OfdmaMode.ul,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!r.check.isOk)
            _CheckLine(message: r.check.message)
          else if (line == null)
            _CheckLine(
              message:
                  '${cmp.shortLabel}: a PPDU would run past the 5.484 ms limit',
            )
          else
            Semantics(
              liveRegion: true,
              child: Text(
                line,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'A teaching estimate: one frame per client, no collisions, the '
            'average backoff. See Assumptions below.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: colors.statusDanger,
            size: AppSpacing.md - AppSpacing.xxs,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Check: $message',
              style: text.bodyMedium?.copyWith(
                color: colors.statusDanger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inputs ──────────────────────────────────────────────────────────────────

class _Inputs extends StatelessWidget {
  const _Inputs({required this.model});

  final OfdmaSimulatorModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    const SizedBox gap = SizedBox(height: AppSpacing.sm);
    final int w = model.widthMhz;
    final int? sel = model.selected;
    final RuSize shown = sel == null
        ? (model.sizes.toSet().length == 1
              ? model.sizes.first
              : model.sizes.last)
        : model.sizes[sel];
    final bool mixed = sel == null && model.sizes.toSet().length > 1;
    final bool canMove = sel != null && model.placement[sel] != null;

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Scenario'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<OfdmaDirection>(
            label: 'Direction',
            value: model.direction,
            expand: true,
            items: <AppToggleItem<OfdmaDirection>>[
              for (final OfdmaDirection d in OfdmaDirection.values)
                (d, d.label),
            ],
            onChanged: model.setDirection,
          ),
          gap,
          _select<int>(
            label: 'Channel width',
            value: w,
            items: <AppSelectItem<int>>[
              for (final int x in OfdmaTonePlan.widthsMhz) (x, '$x MHz'),
            ],
            onChanged: model.setWidth,
          ),
          gap,
          _select<int>(
            label: 'Clients',
            value: model.clients,
            items: <AppSelectItem<int>>[
              for (int n = 1; n <= model.maxClients; n++) (n, '$n'),
            ],
            onChanged: model.setClientCount,
          ),
          gap,
          _select<int>(
            label: 'Frame size per client',
            value: model.payloadBytes,
            items: <AppSelectItem<int>>[
              for (final int b in kOfdmaPayloadChoices)
                (b, '${_thousands(b)} bytes'),
            ],
            onChanged: model.setPayload,
          ),
          gap,
          _select<int>(
            label: 'MCS (every client)',
            value: model.mcs,
            items: <AppSelectItem<int>>[
              for (final McsRow m in AirtimeConstants.mcs)
                (m.mcs, 'MCS ${m.mcs}: ${m.modulation} ${m.codingRateLabel}'),
            ],
            onChanged: model.setMcs,
          ),
          const SizedBox(height: AppSpacing.md),
          const AirtimeSectionTitle('Resource units'),
          const SizedBox(height: AppSpacing.xs),
          _select<int>(
            label: 'Client',
            value: sel ?? _kAll,
            items: <AppSelectItem<int>>[
              (_kAll, 'All clients'),
              for (int i = 0; i < model.clients; i++)
                (i, 'Client ${clientLetter(i)}: ${model.sizes[i].toneLabel}'),
            ],
            onChanged: (int v) => model.setSelected(v == _kAll ? null : v),
          ),
          gap,
          _select<RuSize>(
            label: sel == null
                ? 'RU size, every client'
                : 'RU size, client ${clientLetter(sel)}',
            value: shown,
            items: <AppSelectItem<RuSize>>[
              for (final RuSize s in OfdmaTonePlan.sizesFor(w))
                (
                  s,
                  '${s.toneLabel} (${s.dataTones} data + ${s.pilotTones} '
                      'pilot), ${OfdmaTonePlan.count(s, w)} fit',
                ),
            ],
            onChanged: model.setRuSize,
          ),
          if (mixed) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Clients have different RU sizes; picking one here sets them all.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          gap,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _Button(
                label: 'Largest equal RUs',
                icon: Icons.view_week_outlined,
                onPressed: model.equalRus,
              ),
              _Button(
                label: 'Re-pack',
                icon: Icons.align_horizontal_left_rounded,
                onPressed: model.autoPlace,
              ),
              _Button(
                label: 'Move left',
                icon: Icons.chevron_left_rounded,
                onPressed: canMove ? () => model.nudge(sel, -1) : null,
              ),
              _Button(
                label: 'Move right',
                icon: Icons.chevron_right_rounded,
                onPressed: canMove ? () => model.nudge(sel, 1) : null,
              ),
            ],
          ),
          if (sel == null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Pick a client, here or in the channel, to move it.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _select<T>({
    required String label,
    required T value,
    required List<AppSelectItem<T>> items,
    required ValueChanged<T> onChanged,
  }) => LabeledField(
    label: label,
    field: AppSelect<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      semanticLabel: label,
    ),
  );
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

String _thousands(int n) {
  final String s = '$n';
  if (s.length <= 3) return s;
  return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}
