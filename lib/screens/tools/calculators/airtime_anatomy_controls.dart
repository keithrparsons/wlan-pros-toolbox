// The controls for Airtime Anatomy (Wi-Fi Classroom): readouts for each scenario,
// the compare switch, which scenario to edit, the four presets, and every
// input on the WLAN Pros Airtime Calculator sheet, with the less-used ones
// behind "More settings". Reads and writes an [AirtimeAnatomyModel]; owns no
// state of its own, so a presenter layout can place it beside
// [AirtimeAnatomyStage].
//
// States:
//   - disabled -> inputs the chosen PHY ignores (MCS, streams, GI, width and
//                 aggregation for Legacy; legacy rate for the rest; packet
//                 extension outside HE) stay visible, disabled, with a note
//   - invalid  -> the Check verdict in danger with icon and words; the
//                 readouts show "--" for that scenario rather than numbers
//                 for a combination the standard does not allow
//   - valid    -> Check "OK" in success with icon and words
//
// Status hues are verdicts only (§8.13): they color the Check row and nothing
// else. Numbers in DM Mono.
//
// PRESENTER (PresenterMode.isActive): the throughput, TXOP length and
// efficiency move onto the stage; the inputs pair up two per row; More
// settings and the full readouts table fold into PresenterDisclosures, so
// the panel fits at 1440x900 with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_model.dart';
import 'airtime_anatomy_stage.dart';

/// Payload sizes offered, bytes (the MSDU).
const List<int> kPayloadChoices = <int>[64, 128, 256, 512, 1000, 1500, 2304];

/// A-MPDU frame counts offered. 64 is the most a 32-byte compressed Block
/// Ack (a 64-bit bitmap) can acknowledge, and the sheet sizes its Block Ack
/// at 32 bytes.
const List<int> kFramesChoices = <int>[1, 2, 4, 8, 16, 32, 64];

class AirtimeAnatomyControls extends StatelessWidget {
  const AirtimeAnatomyControls({super.key, required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PresenterInputs(model: model),
              PresenterDisclosure(
                title: 'Segment table and all readouts',
                children: <Widget>[
                  AirtimeCard(child: AirtimeAnatomyBreakdown(model: model)),
                  const SizedBox(height: AppSpacing.xs),
                  _Readouts(model: model),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Readouts(model: model),
            const SizedBox(height: AppSpacing.md),
            _Inputs(model: model),
          ],
        );
      },
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<int> cols = model.visible;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    String v(int i, String Function(AirtimeResult r) f) {
      final AirtimeResult r = model.result(i);
      return r.check.isOk ? f(r) : '--';
    }

    TableRow row(
      String name,
      String Function(AirtimeResult r) f, {
      bool accent = false,
    }) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        for (final int i in cols)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Text(
              v(i, f),
              textAlign: TextAlign.end,
              style: accent ? value.copyWith(color: colors.textAccent) : value,
            ),
          ),
      ],
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: <int, TableColumnWidth>{
              0: const FlexColumnWidth(1.6),
              for (int c = 1; c <= cols.length; c++) c: const FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                children: <Widget>[
                  const SizedBox.shrink(),
                  for (final int i in cols)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: Text(
                        kScenarioLetters[i],
                        textAlign: TextAlign.end,
                        style: head,
                      ),
                    ),
                ],
              ),
              row(
                'PHY rate (Mbps)',
                (AirtimeResult r) => _num(r.phyRateMbps, 2),
              ),
              row(
                'Data bits per symbol',
                (AirtimeResult r) => _num(r.bitsPerSymbol, 2),
              ),
              row(
                'Total airtime (µs)',
                (AirtimeResult r) => formatTenthsUs(r.totalTenths),
              ),
              row(
                'Throughput (Mbps)',
                (AirtimeResult r) => r.throughputMbps.toStringAsFixed(1),
                accent: true,
              ),
              row(
                'Efficiency vs PHY rate (%)',
                (AirtimeResult r) => (r.efficiency * 100).toStringAsFixed(1),
              ),
              row(
                'Airtime on data symbols (%)',
                (AirtimeResult r) => (r.dataShare * 100).toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final int i in cols)
            _CheckLine(index: i, check: model.result(i).check),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Throughput is payload bits over the whole TXOP: one station, no '
            'contention, no retries.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.index, required this.check, this.who});

  final int index;
  final AirtimeCheck check;

  /// Which scenarios the line speaks for; defaults to [index]'s letter.
  final String? who;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Color hue = check.isOk ? colors.statusSuccess : colors.statusDanger;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            check.isOk
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: hue,
            size: AppSpacing.md - AppSpacing.xxs,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Check ${who ?? kScenarioLetters[index]}: ${check.message}',
              style: text.bodyMedium?.copyWith(
                color: hue,
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

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final int e = model.editing;
    final AirtimeScenario s = model.scenario(e);
    final bool legacy = s.phy == AirtimePhy.legacy;
    final bool he = s.phy == AirtimePhy.he;
    const SizedBox gap = SizedBox(height: AppSpacing.sm);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    void edit(AirtimeScenario Function(AirtimeScenario s) f) => model.edit(f);

    final List<GuardInterval> gis = guardIntervalsFor(s.phy);

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Scenario'),
          const SizedBox(height: AppSpacing.xs),
          _SwitchRow(
            title: 'Compare with scenario B',
            subtitle: 'Stack a second TXOP on the same scale',
            value: model.compare,
            onChanged: model.setCompare,
          ),
          if (model.compare) ...<Widget>[
            gap,
            AppToggle<int>(
              label: 'Edit scenario',
              value: e,
              expand: true,
              items: <AppToggleItem<int>>[(0, 'A'), (1, 'B')],
              onChanged: model.setEditing,
            ),
          ],
          gap,
          Text(
            'Presets',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final AirtimePreset p in AirtimePreset.values)
                _PresetButton(
                  preset: p,
                  selected: model.preset(e) == p,
                  onPressed: () => model.applyPreset(p),
                ),
            ],
          ),
          gap,
          AppToggle<AirtimeBand>(
            label: 'Band',
            value: s.band,
            expand: true,
            items: <AppToggleItem<AirtimeBand>>[
              for (final AirtimeBand b in AirtimeBand.values) (b, b.label),
            ],
            onChanged: (AirtimeBand b) => edit((x) => x.copyWith(band: b)),
          ),
          gap,
          _select<AirtimePhy>(
            label: 'PHY',
            value: s.phy,
            items: <AppSelectItem<AirtimePhy>>[
              for (final AirtimePhy p in AirtimePhy.values) (p, p.label),
            ],
            onChanged: (AirtimePhy p) => edit((x) => x.copyWith(phy: p)),
          ),
          gap,
          _select<int>(
            label: 'Channel width',
            value: s.widthMhz,
            enabled: !legacy,
            items: <AppSelectItem<int>>[
              for (final int w in AirtimeConstants.widthsMhz) (w, '$w MHz'),
            ],
            onChanged: (int w) => edit((x) => x.copyWith(widthMhz: w)),
          ),
          gap,
          if (legacy)
            _select<int>(
              label: 'Legacy data rate',
              value: s.legacyRateMbps,
              items: <AppSelectItem<int>>[
                for (final int r in AirtimeConstants.legacyRatesMbps)
                  (r, '$r Mbps'),
              ],
              onChanged: (int r) => edit((x) => x.copyWith(legacyRateMbps: r)),
            )
          else
            _select<int>(
              label: 'MCS (per stream)',
              value: s.mcs,
              items: <AppSelectItem<int>>[
                for (final McsRow m in AirtimeConstants.mcs)
                  (m.mcs, 'MCS ${m.mcs}: ${m.modulation} ${m.codingRateLabel}'),
              ],
              onChanged: (int m) => edit((x) => x.copyWith(mcs: m)),
            ),
          gap,
          _select<int>(
            label: 'Spatial streams',
            value: s.streams,
            enabled: !legacy,
            items: <AppSelectItem<int>>[
              for (int n = 1; n <= AirtimeConstants.maxStreams; n++) (n, '$n'),
            ],
            onChanged: (int n) => edit((x) => x.copyWith(streams: n)),
          ),
          gap,
          AppToggle<GuardInterval>(
            label: 'Guard interval',
            value: gis.contains(s.guardInterval) ? s.guardInterval : gis.last,
            expand: true,
            enabled: !legacy,
            items: <AppToggleItem<GuardInterval>>[
              for (final GuardInterval g in gis) (g, g.label),
            ],
            onChanged: (GuardInterval g) =>
                edit((x) => x.copyWith(guardInterval: g)),
          ),
          gap,
          _select<int>(
            label: 'Payload per frame',
            value: s.payloadBytes,
            items: <AppSelectItem<int>>[
              for (final int b in kPayloadChoices)
                (b, '${_thousands(b)} bytes'),
            ],
            onChanged: (int b) => edit((x) => x.copyWith(payloadBytes: b)),
          ),
          gap,
          _select<int>(
            label: 'Frames aggregated (A-MPDU)',
            value: s.framesAggregated,
            enabled: !legacy,
            items: <AppSelectItem<int>>[
              for (final int n in kFramesChoices) (n, '$n'),
            ],
            onChanged: (int n) => edit((x) => x.copyWith(framesAggregated: n)),
          ),
          if (legacy) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Legacy is 20 MHz, one stream, one frame per access; width, '
              'streams, guard interval and aggregation do not apply.',
              style: note,
            ),
          ],
          gap,
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: model.toggleMore,
              icon: Icon(
                model.moreOpen
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(model.moreOpen ? 'Fewer settings' : 'More settings'),
              style: TextButton.styleFrom(
                foregroundColor: colors.textAccent,
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
              ),
            ),
          ),
          if (model.moreOpen) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            AppToggle<int>(
              label: 'Encryption overhead',
              value: s.encryptionBytes == 0 ? 0 : 16,
              expand: true,
              items: const <AppToggleItem<int>>[
                (0, 'Open (0)'),
                (16, 'CCMP/GCMP (16)'),
              ],
              onChanged: (int b) => edit((x) => x.copyWith(encryptionBytes: b)),
            ),
            gap,
            _select<AirtimeAccessCategory>(
              label: 'Access category',
              value: s.accessCategory,
              items: <AppSelectItem<AirtimeAccessCategory>>[
                for (final AirtimeAccessCategory a
                    in AirtimeAccessCategory.values)
                  (a, '${a.label} (${a.shortLabel})'),
              ],
              onChanged: (AirtimeAccessCategory a) =>
                  edit((x) => x.copyWith(accessCategory: a)),
            ),
            gap,
            _SwitchRow(
              title: 'RTS/CTS protection',
              subtitle: 'Reserve the medium before the data frame',
              value: s.rtsCts,
              onChanged: (bool on) => edit((x) => x.copyWith(rtsCts: on)),
            ),
            gap,
            AppToggle<int>(
              label: 'Control frame rate',
              value: s.controlRateMbps,
              expand: true,
              items: <AppToggleItem<int>>[
                for (final int r in AirtimeConstants.controlRatesMbps)
                  (r, '$r Mbps'),
              ],
              onChanged: (int r) => edit((x) => x.copyWith(controlRateMbps: r)),
            ),
            gap,
            _select<int>(
              label: 'HE packet extension',
              value: s.hePacketExtensionUs,
              enabled: he,
              items: <AppSelectItem<int>>[
                for (final int p in AirtimeConstants.hePacketExtensionsUs)
                  (p, '$p µs'),
              ],
              onChanged: (int p) =>
                  edit((x) => x.copyWith(hePacketExtensionUs: p)),
            ),
            if (!he) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text('Packet extension applies to HE only.', style: note),
            ],
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
    bool enabled = true,
  }) => LabeledField(
    label: label,
    field: AppSelect<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      enabled: enabled,
      semanticLabel: label,
    ),
  );
}

/// The presenter panel's inputs: the same controls as [_Inputs], two per
/// row where they are short, with More settings folded.
class _PresenterInputs extends StatelessWidget {
  const _PresenterInputs({required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final int e = model.editing;
    final AirtimeScenario s = model.scenario(e);
    final bool legacy = s.phy == AirtimePhy.legacy;
    final bool he = s.phy == AirtimePhy.he;
    const SizedBox gap = SizedBox(height: AppSpacing.xs);
    final List<GuardInterval> gis = guardIntervalsFor(s.phy);
    void edit(AirtimeScenario Function(AirtimeScenario s) f) => model.edit(f);

    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: a),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: b),
      ],
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SwitchRow(
            title: 'Compare with scenario B',
            value: model.compare,
            onChanged: model.setCompare,
          ),
          if (model.compare) ...<Widget>[
            gap,
            AppToggle<int>(
              semanticLabel: 'Edit scenario',
              value: e,
              expand: true,
              items: <AppToggleItem<int>>[(0, 'Edit A'), (1, 'Edit B')],
              onChanged: model.setEditing,
            ),
          ],
          gap,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final AirtimePreset p in AirtimePreset.values)
                _PresetButton(
                  preset: p,
                  selected: model.preset(e) == p,
                  onPressed: () => model.applyPreset(p),
                ),
            ],
          ),
          gap,
          AppToggle<AirtimeBand>(
            semanticLabel: 'Band',
            value: s.band,
            expand: true,
            items: <AppToggleItem<AirtimeBand>>[
              for (final AirtimeBand b in AirtimeBand.values) (b, b.label),
            ],
            onChanged: (AirtimeBand b) => edit((x) => x.copyWith(band: b)),
          ),
          gap,
          pair(
            _labeledSelect<AirtimePhy>(
              label: 'PHY',
              value: s.phy,
              items: <AppSelectItem<AirtimePhy>>[
                for (final AirtimePhy p in AirtimePhy.values) (p, p.shortLabel),
              ],
              onChanged: (AirtimePhy p) => edit((x) => x.copyWith(phy: p)),
            ),
            _labeledSelect<int>(
              label: 'Width',
              value: s.widthMhz,
              enabled: !legacy,
              items: <AppSelectItem<int>>[
                for (final int w in AirtimeConstants.widthsMhz) (w, '$w MHz'),
              ],
              onChanged: (int w) => edit((x) => x.copyWith(widthMhz: w)),
            ),
          ),
          gap,
          pair(
            legacy
                ? _labeledSelect<int>(
                    label: 'Data rate',
                    value: s.legacyRateMbps,
                    items: <AppSelectItem<int>>[
                      for (final int r in AirtimeConstants.legacyRatesMbps)
                        (r, '$r Mbps'),
                    ],
                    onChanged: (int r) =>
                        edit((x) => x.copyWith(legacyRateMbps: r)),
                  )
                : _labeledSelect<int>(
                    label: 'MCS',
                    value: s.mcs,
                    items: <AppSelectItem<int>>[
                      for (final McsRow m in AirtimeConstants.mcs)
                        (m.mcs, 'MCS ${m.mcs} ${m.modulation}'),
                    ],
                    onChanged: (int m) => edit((x) => x.copyWith(mcs: m)),
                  ),
            _labeledSelect<int>(
              label: 'Streams',
              value: s.streams,
              enabled: !legacy,
              items: <AppSelectItem<int>>[
                for (int n = 1; n <= AirtimeConstants.maxStreams; n++)
                  (n, '$n'),
              ],
              onChanged: (int n) => edit((x) => x.copyWith(streams: n)),
            ),
          ),
          gap,
          pair(
            _labeledSelect<int>(
              label: 'Payload',
              value: s.payloadBytes,
              items: <AppSelectItem<int>>[
                for (final int b in kPayloadChoices) (b, '${_thousands(b)} B'),
              ],
              onChanged: (int b) => edit((x) => x.copyWith(payloadBytes: b)),
            ),
            _labeledSelect<int>(
              label: 'A-MPDU frames',
              value: s.framesAggregated,
              enabled: !legacy,
              items: <AppSelectItem<int>>[
                for (final int n in kFramesChoices) (n, '$n'),
              ],
              onChanged: (int n) =>
                  edit((x) => x.copyWith(framesAggregated: n)),
            ),
          ),
          gap,
          AppToggle<GuardInterval>(
            semanticLabel: 'Guard interval',
            value: gis.contains(s.guardInterval) ? s.guardInterval : gis.last,
            expand: true,
            enabled: !legacy,
            items: <AppToggleItem<GuardInterval>>[
              for (final GuardInterval g in gis) (g, 'GI ${g.label}'),
            ],
            onChanged: (GuardInterval g) =>
                edit((x) => x.copyWith(guardInterval: g)),
          ),
          if (legacy) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Legacy: 20 MHz, one stream, one frame per access.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          if (model.visible.every((int i) => model.result(i).check.isOk))
            _CheckLine(
              index: 0,
              check: model.result(0).check,
              who: model.compare ? 'A and B' : 'A',
            )
          else
            for (final int i in model.visible)
              _CheckLine(index: i, check: model.result(i).check),
          PresenterDisclosure(
            title: 'More settings',
            children: <Widget>[
              AppToggle<int>(
                label: 'Encryption overhead',
                value: s.encryptionBytes == 0 ? 0 : 16,
                expand: true,
                items: const <AppToggleItem<int>>[
                  (0, 'Open (0)'),
                  (16, 'CCMP/GCMP (16)'),
                ],
                onChanged: (int b) =>
                    edit((x) => x.copyWith(encryptionBytes: b)),
              ),
              gap,
              _labeledSelect<AirtimeAccessCategory>(
                label: 'Access category',
                value: s.accessCategory,
                items: <AppSelectItem<AirtimeAccessCategory>>[
                  for (final AirtimeAccessCategory a
                      in AirtimeAccessCategory.values)
                    (a, '${a.label} (${a.shortLabel})'),
                ],
                onChanged: (AirtimeAccessCategory a) =>
                    edit((x) => x.copyWith(accessCategory: a)),
              ),
              gap,
              _SwitchRow(
                title: 'RTS/CTS protection',
                value: s.rtsCts,
                onChanged: (bool on) => edit((x) => x.copyWith(rtsCts: on)),
              ),
              gap,
              AppToggle<int>(
                label: 'Control frame rate',
                value: s.controlRateMbps,
                expand: true,
                items: <AppToggleItem<int>>[
                  for (final int r in AirtimeConstants.controlRatesMbps)
                    (r, '$r Mbps'),
                ],
                onChanged: (int r) =>
                    edit((x) => x.copyWith(controlRateMbps: r)),
              ),
              gap,
              _labeledSelect<int>(
                label: he
                    ? 'HE packet extension'
                    : 'HE packet extension (HE only)',
                value: s.hePacketExtensionUs,
                enabled: he,
                items: <AppSelectItem<int>>[
                  for (final int p in AirtimeConstants.hePacketExtensionsUs)
                    (p, '$p µs'),
                ],
                onChanged: (int p) =>
                    edit((x) => x.copyWith(hePacketExtensionUs: p)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A §8.14 Select under its §8.4 label line.
Widget _labeledSelect<T>({
  required String label,
  required T value,
  required List<AppSelectItem<T>> items,
  required ValueChanged<T> onChanged,
  bool enabled = true,
}) => LabeledField(
  label: label,
  field: AppSelect<T>(
    value: value,
    items: items,
    onChanged: onChanged,
    enabled: enabled,
    semanticLabel: label,
  ),
);

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.selected,
    required this.onPressed,
  });

  final AirtimePreset preset;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ButtonStyle style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      backgroundColor: selected ? colors.primary : null,
      foregroundColor: selected ? colors.onPrimary : colors.textPrimary,
      textStyle: text.labelLarge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: Text(preset.label),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;

  /// A line under the title; the presenter panel leaves it out.
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    // The whole row toggles on tap; keyboard focus stays on the Switch, which
    // paints the ring.
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          // The presenter panel drops the row's padding: the Switch's own
          // 48 px target already spaces it.
          padding: EdgeInsets.symmetric(
            vertical: PresenterMode.isActive(context) ? 0 : AppSpacing.xxs,
          ),
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
                    if (subtitle case final String sub)
                      Text(
                        sub,
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

/// [v] with up to [decimals] places, trailing zeros trimmed: 6, 866.67.
String _num(double v, int decimals) {
  String s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

String _thousands(int n) {
  final String s = '$n';
  if (s.length <= 3) return s;
  return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
}
