// The frame-structure view of Airtime Anatomy (Wi-Fi Classroom, 1.11.0,
// aggregation-structure). The time view draws the TXOP to scale in
// microseconds; this view opens up the PSDU those data symbols carry and
// draws its STRUCTURE in bytes: one MPDU, an A-MSDU, an A-MPDU, or an A-MPDU
// of A-MSDUs, built from the same scenario (lib/services/wifi_lab/
// aggregation_structure.dart). Corrupt one MSDU and it shows what the
// receiver can report and what the sender has to send again.
//
// Parts, top to bottom:
//   - arrangement, MSDUs per A-MSDU, corrupt switch with previous/next
//   - the link line: whether this is the aggregate the time view draws
//   - the PSDU, one cell per retransmission unit, bytes to scale inside
//     each cell (lime = MSDU payload, neutral = overhead)
//   - inside one unit: every part, schematic width, labeled when it fits
//   - the acknowledgment: the Block Ack bitmap, or the ACK that never comes
//   - the outcome (a live region): what is resent, bytes and time
//   - bytes by part (this unit, whole PSDU) and the four arrangements side
//     by side for one bad MSDU
//
// States: nothing corrupted (all delivered); corrupted (the bad MSDU in
// danger with a cross and the words; the resent unit outlined in danger and
// named in the outcome); Legacy (only a single MPDU, the other arrangements
// say why); a scenario the Check refuses (bytes still shown, no time, the
// verdict in words).
//
// COLOR (GL-003 §8.13 / §8.15): lime marks the MSDU payload, the quantity
// the lesson is about; overhead is the neutral stack; the one status hue,
// danger, marks the corrupted MSDU and the unit that fails, each paired with
// a cross mark and words. Nothing animates.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/aggregation_structure.dart';
import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_model.dart';
import 'airtime_anatomy_stage.dart';

/// Cells per row in the PSDU and bitmap grids.
int _perRow(double width) => width >= 440 ? 16 : 8;

class AirtimeStructureView extends StatelessWidget {
  const AirtimeStructureView({super.key, required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final bool presenting = PresenterMode.isActive(context);
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final AggregateStructure st = model.structure;
    final CorruptionOutcome? bad = model.corruption;
    final int shownUnit = bad?.failedUnit ?? 0;
    const SizedBox gap = SizedBox(height: AppSpacing.sm);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    if (presenting) {
      return _presenterBody(context, st, bad, shownUnit, mono);
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle(
            'Inside the PSDU, scenario '
            '${kScenarioLetters[model.editing]}',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The bytes the data symbols carry. Corrupt one MSDU (MAC service '
            'data unit, one packet of your data) to see what has to be sent '
            'again.',
            style: note,
          ),
          gap,
          _StructureInputs(model: model),
          gap,
          _LinkLine(model: model, mono: mono),
          const SizedBox(height: AppSpacing.xs),
          _Limits(model: model, mono: mono),
          gap,
          _SubTitle(_psduTitle(st)),
          const SizedBox(height: AppSpacing.xs),
          _UnitGrid(model: model),
          const SizedBox(height: AppSpacing.xxs),
          Text(_psduCaption(st), style: note),
          gap,
          _SubTitle(
            st.unitCount == 1
                ? 'Inside the ${st.inAmpdu ? 'A-MPDU subframe' : 'MPDU'}'
                : 'Inside A-MPDU subframe ${shownUnit + 1}',
          ),
          const SizedBox(height: AppSpacing.xs),
          _PartStrip(
            unit: st.units[shownUnit],
            corruptedMsdu: bad?.corruptedMsdu,
          ),
          if (st.inAmpdu) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(_delimiterNote(st.scenario.phy), style: note),
          ],
          gap,
          _SubTitle(
            st.usesBlockAck
                ? 'Block Ack bitmap, one bit per MPDU'
                : 'Acknowledgment',
          ),
          const SizedBox(height: AppSpacing.xs),
          _AckRow(structure: st, outcome: bad, mono: mono),
          gap,
          _Outcome(model: model, mono: mono),
          if (!presenting) ...<Widget>[
            gap,
            _BytesTable(structure: st, unit: shownUnit, mono: mono),
          ],
          gap,
          _Compare(model: model, mono: mono),
        ],
      ),
    );
  }
}

extension on AirtimeStructureView {
  /// Presenter: the drawing on the left, the outcome and the comparison on
  /// the right, inputs on one row, no captions, so the stage box holds it
  /// near full size on a projector.
  Widget _presenterBody(
    BuildContext context,
    AggregateStructure st,
    CorruptionOutcome? bad,
    int shownUnit,
    AppMonoText mono,
  ) {
    const SizedBox gap = SizedBox(height: AppSpacing.sm);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle(
            'Inside the PSDU, scenario ${kScenarioLetters[model.editing]}',
          ),
          const SizedBox(height: AppSpacing.xs),
          _StructureInputs(model: model, compact: true),
          const SizedBox(height: AppSpacing.xs),
          _LinkLine(model: model, mono: mono),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SubTitle(_psduTitle(st)),
                    const SizedBox(height: AppSpacing.xs),
                    _UnitGrid(model: model),
                    gap,
                    _SubTitle(
                      st.unitCount == 1
                          ? 'Inside the ${st.inAmpdu ? 'A-MPDU subframe' : 'MPDU'}'
                          : 'Inside A-MPDU subframe ${shownUnit + 1}',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _PartStrip(
                      unit: st.units[shownUnit],
                      corruptedMsdu: bad?.corruptedMsdu,
                    ),
                    gap,
                    _SubTitle(
                      st.usesBlockAck
                          ? 'Block Ack bitmap, one bit per MPDU'
                          : 'Acknowledgment',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _AckRow(structure: st, outcome: bad, mono: mono),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Outcome(model: model, mono: mono),
                    gap,
                    _Limits(model: model, mono: mono),
                    gap,
                    _Compare(model: model, mono: mono),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _psduTitle(AggregateStructure st) => switch (st.kind) {
  AggregationKind.singleMpdu => 'The PSDU: one MPDU',
  AggregationKind.amsdu => 'The PSDU: one A-MSDU',
  AggregationKind.ampdu =>
    st.unitCount == 1
        ? 'The PSDU: one MPDU'
        : 'The PSDU: ${st.unitCount} A-MPDU subframes',
  AggregationKind.ampduOfAmsdus =>
    st.unitCount == 1
        ? 'The PSDU: one A-MSDU'
        : 'The PSDU: ${st.unitCount} A-MPDU subframes, an A-MSDU in each',
};

String _psduCaption(AggregateStructure st) {
  final String each = st.unitCount == 1 ? 'The box' : 'Each box';
  final String fcs = st.msdusPerMpdu > 1
      ? 'one MAC header and one FCS (frame check sequence) over '
            '${st.msdusPerMpdu} MSDUs'
      : 'its own MAC header and FCS (frame check sequence)';
  return '$each is one MPDU (MAC protocol data unit) with $fcs, drawn to '
      'scale in bytes: lime is MSDU payload, gray is overhead.'
      '${st.inAmpdu ? ' In an A-MPDU each MPDU also has a 4-byte delimiter '
                'and pads to a 4-byte boundary.' : ''}';
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ── Inputs ─────────────────────────────────────────────────────────────────

class _StructureInputs extends StatelessWidget {
  const _StructureInputs({required this.model, this.compact = false});

  final AirtimeAnatomyModel model;

  /// Presenter: arrangement, MSDUs per A-MSDU and the corrupt switch on
  /// one row, no Legacy note (the comparison table says it).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AirtimePhy phy = model.scenario(model.editing).phy;
    final AggregationKind kind = model.effectiveArrangement;
    final AggregateStructure st = model.structure;
    final int? bad = model.corruptedMsdu;

    final Widget arrangement = LabeledField(
      label: 'Arrangement',
      field: AppSelect<AggregationKind>(
        value: kind,
        semanticLabel: 'Arrangement',
        items: <AppSelectItem<AggregationKind>>[
          for (final AggregationKind k in AggregationKind.values)
            if (aggregationSupported(phy, k)) (k, k.label),
        ],
        onChanged: model.setArrangement,
      ),
    );
    final Widget perAmsdu = AppToggle<int>(
      label: 'MSDUs per A-MSDU',
      value: model.msdusPerAmsdu,
      expand: true,
      enabled: kind.usesAmsdu,
      items: <AppToggleItem<int>>[
        for (final int n in AggregationConstants.msdusPerAmsduChoices)
          (n, '$n'),
      ],
      onChanged: model.setMsdusPerAmsdu,
    );

    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(flex: 3, child: arrangement),
          const SizedBox(width: AppSpacing.sm),
          Expanded(flex: 2, child: perAmsdu),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: MergeSemantics(
              child: InkWell(
                onTap: () => model.setCorrupt(bad == null),
                canRequestFocus: false,
                excludeFromSemantics: true,
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        bad == null
                            ? 'Corrupt one MSDU'
                            : 'MSDU ${bad + 1} of ${st.msduCount} corrupted',
                        style: text.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Switch(
                      value: bad != null,
                      onChanged: model.setCorrupt,
                      activeThumbColor: colors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) => c.maxWidth >= 520
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: arrangement),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: perAmsdu),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    arrangement,
                    const SizedBox(height: AppSpacing.sm),
                    perAmsdu,
                  ],
                ),
        ),
        if (phy == AirtimePhy.legacy) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Legacy (802.11a/g) has no aggregation: every MSDU is its own '
            'MPDU and its own frame exchange. A-MSDU and A-MPDU arrived with '
            'HT (802.11n).',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        // The whole row toggles on tap, like the controls' switch rows;
        // keyboard focus stays on the Switch, which paints the ring.
        MergeSemantics(
          child: InkWell(
            onTap: () => model.setCorrupt(bad == null),
            canRequestFocus: false,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Corrupt one MSDU',
                        style: text.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        bad == null
                            ? 'One bad bit, as noise or a collision would leave'
                            : 'MSDU ${bad + 1} of ${st.msduCount}',
                        style: text.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: bad != null,
                  onChanged: model.setCorrupt,
                  activeThumbColor: colors.primary,
                ),
              ],
            ),
          ),
        ),
        if (bad != null && st.msduCount > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              IconButton(
                tooltip: 'Corrupt the previous MSDU',
                onPressed: () => model.stepCorrupt(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                color: colors.textPrimary,
              ),
              IconButton(
                tooltip: 'Corrupt the next MSDU',
                onPressed: () => model.stepCorrupt(1),
                icon: const Icon(Icons.chevron_right_rounded),
                color: colors.textPrimary,
              ),
            ],
          ),
      ],
    );
  }
}

// ── The link to the time view ──────────────────────────────────────────────

class _LinkLine extends StatelessWidget {
  const _LinkLine({required this.model, required this.mono});

  final AirtimeAnatomyModel model;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AirtimeResult r = model.result(model.editing);
    final AggregateStructure st = model.structure;
    final bool same =
        st.psduBytes == r.psduBytes && st.msduCount == r.framesSent;
    final String bytes = _bytes(st.psduBytes);

    final String line;
    if (!r.check.isOk) {
      line =
          'No airtime for this scenario: ${r.checkMessage}. The bytes '
          'below still hold.';
    } else if (same) {
      line =
          'The same aggregate the time view draws: $bytes bytes, '
          '${formatTenthsUs(r.ppduTenths)} µs of preamble and data.';
    } else {
      line =
          'The time view draws ${r.framesSent} MSDU'
          '${r.framesSent == 1 ? '' : 's'} in ${_bytes(r.psduBytes)} bytes. '
          'This arrangement packs ${st.msduCount} in $bytes bytes, '
          '${formatTenthsUs(ppduTenthsForPsdu(r, st.psduBytes))} µs of '
          'preamble and data at the same rate.';
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            r.check.isOk
                ? (same ? Icons.link_rounded : Icons.compare_arrows_rounded)
                : Icons.error_outline_rounded,
            size: AppSpacing.md,
            color: r.check.isOk ? colors.textSecondary : colors.statusDanger,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              line,
              style: text.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── The PSDU grid ──────────────────────────────────────────────────────────

class _UnitGrid extends StatelessWidget {
  const _UnitGrid({required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final AggregateStructure st = model.structure;
    final CorruptionOutcome? bad = model.corruption;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final double h = scale.markerSize(AppSpacing.lg);
    final String spoken =
        '${_psduTitle(st)}, ${_bytes(st.psduBytes)} bytes, '
        '${st.msduCount} MSDUs'
        '${bad == null ? ', nothing corrupted' : ', MSDU ${bad.corruptedMsdu + 1} corrupted, ${st.unitCount == 1 ? 'the whole PSDU' : 'subframe ${bad.failedUnit + 1}'} fails its check'}';

    return Semantics(
      label: spoken,
      container: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final int n = st.unitCount;
          final int per = math.min(_perRow(c.maxWidth), n);
          final List<Widget> rows = <Widget>[];
          for (int start = 0; start < n; start += per) {
            final int end = (start + per).clamp(0, n);
            rows.add(
              Padding(
                padding: EdgeInsets.only(top: start == 0 ? 0 : AppSpacing.xxs),
                child: Row(
                  children: <Widget>[
                    for (int i = start; i < start + per; i++) ...<Widget>[
                      if (i > start) const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: i < end
                            ? _UnitCell(
                                unit: st.units[i],
                                height: h,
                                corruptedMsdu: bad?.corruptedMsdu,
                                onTapMsdu: model.corruptMsdu,
                              )
                            : SizedBox(height: h),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          );
        },
      ),
    );
  }
}

/// One unit, bytes to scale across its width.
class _UnitCell extends StatelessWidget {
  const _UnitCell({
    required this.unit,
    required this.height,
    required this.corruptedMsdu,
    required this.onTapMsdu,
  });

  final StructureUnit unit;
  final double height;
  final int? corruptedMsdu;
  final ValueChanged<int> onTapMsdu;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double stroke = PresenterMode.scaleOf(context).stroke;
    final int? c = corruptedMsdu;
    final bool failed = c != null && unit.holdsMsdu(c);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapMsdu(unit.firstMsdu),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.border,
          border: Border.all(
            color: failed ? colors.statusDanger : colors.borderStrong,
            width: (failed ? 2.5 : 1) * stroke,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final StructurePart p in unit.parts)
              if (p.bytes > 0)
                Expanded(
                  flex: p.bytes,
                  child: p.kind == StructurePartKind.msdu
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onTapMsdu(p.msduIndex!),
                          child: _MsduFill(bad: p.msduIndex == c),
                        )
                      : const SizedBox.shrink(),
                ),
          ],
        ),
      ),
    );
  }
}

class _MsduFill extends StatelessWidget {
  const _MsduFill({required this.bad});

  final bool bad;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      color: bad ? colors.statusDangerFill : colors.primary,
      alignment: Alignment.center,
      child: bad
          ? FittedBox(
              child: Icon(Icons.close_rounded, color: colors.statusDanger),
            )
          : null,
    );
  }
}

// ── Inside one unit ────────────────────────────────────────────────────────

String _partShort(StructurePart p) => switch (p.kind) {
  StructurePartKind.delimiter => 'Delim',
  StructurePartKind.macHeader => 'MAC',
  StructurePartKind.security => 'Security',
  StructurePartKind.subframeHeader => 'Sub-hdr',
  StructurePartKind.msdu => 'MSDU ${p.msduIndex! + 1}',
  StructurePartKind.amsduPadding || StructurePartKind.ampduPadding => 'Pad',
  StructurePartKind.fcs => 'FCS',
};

/// Schematic width per part: payload wide, headers and FCS medium, pads
/// narrow. Not to scale; the grid above is.
int _partFlex(StructurePartKind k) => switch (k) {
  StructurePartKind.msdu => 5,
  StructurePartKind.amsduPadding || StructurePartKind.ampduPadding => 1,
  _ => 2,
};

class _PartStrip extends StatelessWidget {
  const _PartStrip({required this.unit, required this.corruptedMsdu});

  final StructureUnit unit;
  final int? corruptedMsdu;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final double stroke = scale.stroke;
    final TextStyle base =
        text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption);
    final String spoken = <String>[
      for (final StructurePart p in unit.parts)
        '${p.kind == StructurePartKind.msdu ? 'MSDU ${p.msduIndex! + 1}' : p.kind.label} '
            '${p.bytes} bytes'
            '${p.kind == StructurePartKind.msdu && p.msduIndex == corruptedMsdu ? ', corrupted' : ''}',
    ].join(', ');

    return Semantics(
      label: spoken,
      container: true,
      excludeSemantics: true,
      child: SizedBox(
        height: scale.markerSize(AppSpacing.xxl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final StructurePart p in unit.parts)
              Expanded(
                flex: _partFlex(p.kind),
                child: _PartBox(
                  part: p,
                  bad:
                      p.kind == StructurePartKind.msdu &&
                      p.msduIndex == corruptedMsdu,
                  base: base,
                  stroke: stroke,
                  colors: colors,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartBox extends StatelessWidget {
  const _PartBox({
    required this.part,
    required this.bad,
    required this.base,
    required this.stroke,
    required this.colors,
  });

  final StructurePart part;
  final bool bad;
  final TextStyle base;
  final double stroke;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final bool payload = part.kind == StructurePartKind.msdu;
    final bool pad = part.kind.isPadding;
    final Color fill = bad
        ? colors.statusDangerFill
        : payload
        ? colors.primary
        : pad
        ? colors.surface1
        : colors.border;
    final Color ink = bad
        ? colors.textPrimary
        : payload
        ? colors.onPrimary
        : colors.textPrimary;
    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(
          color: bad ? colors.statusDanger : colors.borderStrong,
          width: (bad ? 2.5 : 1) * stroke,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxs / 2),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          if (c.maxWidth < AppSpacing.md) return const SizedBox.shrink();
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (bad)
                  Icon(
                    Icons.close_rounded,
                    color: colors.statusDanger,
                    size: base.fontSize,
                  ),
                Text(
                  _partShort(part),
                  style: base.copyWith(
                    color: ink,
                    fontWeight: payload ? FontWeight.w600 : null,
                  ),
                ),
                Text('${part.bytes} B', style: base.copyWith(color: ink)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Acknowledgment ─────────────────────────────────────────────────────────

class _AckRow extends StatelessWidget {
  const _AckRow({
    required this.structure,
    required this.outcome,
    required this.mono,
  });

  final AggregateStructure structure;
  final CorruptionOutcome? outcome;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final CorruptionOutcome? o = outcome;

    if (!structure.usesBlockAck) {
      final String line = o == null
          ? 'One MPDU, so the receiver answers with a 14-byte ACK: all or '
                'nothing.'
          : 'No ACK. The one FCS covers the whole MPDU, so the receiver '
                'cannot tell which part was hit, discards all of it and '
                'stays silent. The sender times out and resends everything.';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            o == null ? Icons.check_rounded : Icons.close_rounded,
            size: AppSpacing.md,
            color: o == null ? colors.textSecondary : colors.statusDanger,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              line,
              style: text.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      );
    }

    final int n = structure.unitCount;
    final List<bool> bits = o?.blockAckBitmap ?? List<bool>.filled(n, true);
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final double h = scale.markerSize(AppSpacing.md);
    final TextStyle bitStyle = mono.inlineCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          label: o == null
              ? 'Block Ack bitmap: all $n subframes received'
              : 'Block Ack bitmap: ${n - 1} subframes received, subframe '
                    '${o.failedUnit + 1} missing',
          container: true,
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final int per = math.min(_perRow(c.maxWidth), n);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int start = 0; start < n; start += per)
                    Padding(
                      padding: EdgeInsets.only(
                        top: start == 0 ? 0 : AppSpacing.xxs,
                      ),
                      child: Row(
                        children: <Widget>[
                          for (int i = start; i < start + per; i++) ...<Widget>[
                            if (i > start)
                              const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: i < n
                                  ? _Bit(
                                      ok: bits[i],
                                      height: h,
                                      style: bitStyle,
                                    )
                                  : SizedBox(height: h),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          o == null
              ? 'One bit per MPDU, 1 for received. Every A-MPDU subframe '
                    'has its own FCS, so the receiver can say which arrived.'
                    '${structure.msdusPerMpdu > 1 ? ' An A-MSDU is one MPDU, so one bit covers all of its MSDUs.' : ''}'
              : 'Bit ${o.failedUnit + 1} is 0: that subframe failed its own '
                    'FCS. The other ${n - 1} are acknowledged and not sent '
                    'again.',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'This Block Ack covers up to 64 MPDUs, the compressed bitmap HT '
          'introduced. HE raised it to 256 MPDUs, EHT (Wi-Fi 7) to 512 or '
          '1,024.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _Bit extends StatelessWidget {
  const _Bit({required this.ok, required this.height, required this.style});

  final bool ok;
  final double height;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double stroke = PresenterMode.scaleOf(context).stroke;
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ok ? colors.surface2 : colors.statusDangerFill,
        border: Border.all(
          color: ok ? colors.borderStrong : colors.statusDanger,
          width: (ok ? 1 : 2) * stroke,
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          ok ? '1' : '0',
          style: style.copyWith(
            color: ok ? colors.textSecondary : colors.textPrimary,
            fontWeight: ok ? null : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Outcome ────────────────────────────────────────────────────────────────

class _Outcome extends StatelessWidget {
  const _Outcome({required this.model, required this.mono});

  final AirtimeAnatomyModel model;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AggregateStructure st = model.structure;
    final CorruptionOutcome? o = model.corruption;
    final AirtimeResult r = model.result(model.editing);

    final Widget body;
    if (o == null) {
      body = Text(
        'Nothing corrupted: every FCS checks and all ${st.msduCount} '
        'MSDU${st.msduCount == 1 ? '' : 's'} arrive. Turn on Corrupt one '
        'MSDU, or tap a lime block, to damage one.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      );
    } else {
      final double pct = o.resentBytes / st.psduBytes * 100;
      final String what = st.unitCount == 1
          ? 'the whole ${st.inAmpdu ? 'PSDU' : 'MPDU'}'
          : 'A-MPDU subframe ${o.failedUnit + 1} only';
      final String riders = o.resentMsdus > 1
          ? ' The ${o.resentMsdus - 1} good MSDU'
                '${o.resentMsdus - 1 == 1 ? '' : 's'} beside the bad one go '
                'again too, because they share its FCS.'
          : '';
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Resent: $what',
            style: text.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${_bytes(o.resentBytes)} of ${_bytes(st.psduBytes)} bytes '
            '(${pct.toStringAsFixed(1)} %), ${o.resentMsdus} of '
            '${st.msduCount} MSDU${st.msduCount == 1 ? '' : 's'}',
            style: mono.inlineCode.copyWith(color: colors.textAccent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'MSDU ${o.corruptedMsdu + 1} took the bad bit.$riders',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (r.check.isOk) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The resend is a new PPDU: '
              '${formatTenthsUs(ppduTenthsForPsdu(r, o.resentBytes))} µs of '
              'preamble and data, against '
              '${formatTenthsUs(ppduTenthsForPsdu(r, st.psduBytes))} µs for '
              'the first try, with a new wait and acknowledgment on top.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border),
        ),
        child: body,
      ),
    );
  }
}

// ── Limits ─────────────────────────────────────────────────────────────────

/// The 4-byte MPDU delimiter's fields. The length field's width is why an
/// HT A-MPDU cannot carry an MPDU over 4,095 bytes.
String _delimiterNote(AirtimePhy phy) => phy == AirtimePhy.ht
    ? 'The 4-byte delimiter holds a 12-bit MPDU Length (so an MPDU in an HT '
          'A-MPDU is at most 4,095 bytes), an 8-bit CRC and the signature '
          '0x4E.'
    : 'The 4-byte delimiter holds an EOF bit, a 14-bit MPDU Length (12 bits '
          'in HT), an 8-bit CRC and the signature 0x4E.';

String _limitValue(AggregationLimitCheck c) =>
    c.kind == AggregationLimitKind.ppduTime
    ? '${formatTenthsUs(c.value)} µs'
    : '${_bytes(c.value)} bytes';

String _limitCap(AggregationLimitCheck c) =>
    c.kind == AggregationLimitKind.ppduTime
    ? '${formatTenthsUs(c.cap)} µs'
    : '${_bytes(c.cap)} bytes';

String _limitLine(AggregationLimitCheck c) {
  final String v = _limitValue(c);
  switch (c.verdict) {
    case LimitVerdict.ok:
      return '${c.kind.label}: $v, within ${_limitCap(c)}.';
    case LimitVerdict.needsLargerSetting:
      return '${c.kind.label}: $v. Too long for a receiver advertising '
          '${_bytes(c.settings.first)}; it needs one advertising '
          '${_bytes(c.smallestFitting!)}.';
    case LimitVerdict.exceeds:
      return '${c.kind.label}: $v, over the maximum of ${_limitCap(c)}.';
  }
}

/// What is not pinned for this PHY, so the list never implies a limit was
/// checked when it was not. Null when every limit that applies is checked.
String? _notChecked(AirtimePhy phy) => phy == AirtimePhy.he
    ? 'Not checked for HE: the Maximum MPDU Length, and the smaller A-MPDU '
          'limit a receiver can advertise.'
    : null;

class _Limits extends StatelessWidget {
  const _Limits({required this.model, required this.mono});

  final AirtimeAnatomyModel model;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final List<AggregationLimitCheck> checks = model.limits;
    final String? unchecked = _notChecked(model.scenario(model.editing).phy);
    if (checks.isEmpty && unchecked == null) return const SizedBox.shrink();

    Widget row(AggregationLimitCheck c) {
      final (IconData icon, Color color, String word) = switch (c.verdict) {
        LimitVerdict.ok => (
          Icons.check_rounded,
          colors.textSecondary,
          'Within limit',
        ),
        LimitVerdict.needsLargerSetting => (
          Icons.warning_amber_rounded,
          colors.statusWarning,
          'Depends on the receiver',
        ),
        LimitVerdict.exceeds => (
          Icons.error_outline_rounded,
          colors.statusDanger,
          'Over the maximum',
        ),
      };
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: MergeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: AppSpacing.md, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      if (c.verdict != LimitVerdict.ok)
                        TextSpan(
                          text: '$word. ',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      TextSpan(text: _limitLine(c)),
                    ],
                  ),
                  style: text.bodySmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SubTitle('Limits from the standard'),
        for (final AggregationLimitCheck c in checks) row(c),
        if (unchecked != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            unchecked,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ],
    );
  }
}

// ── Tables ─────────────────────────────────────────────────────────────────

class _BytesTable extends StatelessWidget {
  const _BytesTable({
    required this.structure,
    required this.unit,
    required this.mono,
  });

  final AggregateStructure structure;
  final int unit;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final StructureTotals all = structure.totals;
    final Map<StructurePartKind, int> one = <StructurePartKind, int>{};
    for (final StructurePart p in structure.units[unit].parts) {
      one[p.kind] = (one[p.kind] ?? 0) + p.bytes;
    }
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle num = mono.inlineCode.copyWith(color: colors.textPrimary);
    final String unitHead = structure.unitCount == 1
        ? 'The MPDU'
        : 'Subframe ${unit + 1}';

    TableRow row(String label, int a, int b, {bool bold = false}) => TableRow(
      decoration: bold
          ? BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            )
          : null,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
          child: Text(
            label,
            style: text.bodySmall?.copyWith(
              color: bold ? colors.textPrimary : colors.textSecondary,
              fontWeight: bold ? FontWeight.w600 : null,
            ),
          ),
        ),
        Text(_bytes(a), textAlign: TextAlign.end, style: num),
        Text(_bytes(b), textAlign: TextAlign.end, style: num),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SubTitle('Bytes, part by part'),
        const SizedBox(height: AppSpacing.xs),
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(1.6),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: <TableRow>[
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              children: <Widget>[
                Text('Part', style: head),
                Text(unitHead, textAlign: TextAlign.end, style: head),
                Text('Whole PSDU', textAlign: TextAlign.end, style: head),
              ],
            ),
            for (final StructurePartKind k in StructurePartKind.values)
              if (all[k] > 0) row(_kindLabel(k), one[k] ?? 0, all[k]),
            row('Total', structure.units[unit].bytes, all.total, bold: true),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Overhead: ${_bytes(all.overhead)} of ${_bytes(all.total)} bytes '
          '(${(all.overhead / all.total * 100).toStringAsFixed(1)} %).',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

String _kindLabel(StructurePartKind k) => switch (k) {
  StructurePartKind.delimiter => 'MPDU delimiters',
  StructurePartKind.macHeader => 'MAC headers',
  StructurePartKind.security => 'Security header and MIC',
  StructurePartKind.subframeHeader => 'A-MSDU subframe headers',
  StructurePartKind.msdu => 'MSDU payload',
  StructurePartKind.amsduPadding => 'A-MSDU padding',
  StructurePartKind.fcs => 'FCS',
  StructurePartKind.ampduPadding => 'A-MPDU padding',
};

/// The four arrangements for one bad MSDU, side by side.
class _Compare extends StatelessWidget {
  const _Compare({required this.model, required this.mono});

  final AirtimeAnatomyModel model;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AirtimePhy phy = model.scenario(model.editing).phy;
    final AggregationKind shown = model.effectiveArrangement;
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget cell(String s, {bool on = false, TextAlign align = TextAlign.end}) =>
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xxs / 2,
            bottom: AppSpacing.xxs / 2,
            left: AppSpacing.xs,
          ),
          // One line always: a byte count never wraps mid-number.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              s,
              textAlign: align,
              maxLines: 1,
              style: mono.inlineCode.copyWith(
                color: colors.textPrimary,
                fontWeight: on ? FontWeight.w700 : null,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SubTitle('One bad MSDU, under each arrangement'),
        const SizedBox(height: AppSpacing.xs),
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: FlexColumnWidth(1.7),
            1: FlexColumnWidth(0.9),
            2: FlexColumnWidth(1.3),
            3: FlexColumnWidth(1.1),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: <TableRow>[
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              children: <Widget>[
                Text('Arrangement', style: head),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('MSDUs', maxLines: 1, style: head),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('Bytes', maxLines: 1, style: head),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text('Resent', maxLines: 1, style: head),
                ),
              ],
            ),
            for (final AggregationKind k in AggregationKind.values)
              if (!aggregationSupported(phy, k))
                TableRow(
                  children: <Widget>[
                    Text(
                      k.label,
                      style: text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    Text(
                      'not on Legacy',
                      textAlign: TextAlign.end,
                      style: text.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                )
              else
                _compareRow(context, k, k == shown, cell),
          ],
        ),
      ],
    );
  }

  TableRow _compareRow(
    BuildContext context,
    AggregationKind k,
    bool on,
    Widget Function(String s, {bool on, TextAlign align}) cell,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AggregateStructure st = model.structureFor(k);
    final CorruptionOutcome o = st.corrupt(0);
    final double pct = o.resentBytes / st.psduBytes * 100;
    return TableRow(
      children: <Widget>[
        Semantics(
          selected: on,
          child: Text(
            on ? '${k.label} (shown)' : k.label,
            style: text.bodySmall?.copyWith(
              color: on ? colors.textPrimary : colors.textSecondary,
              fontWeight: on ? FontWeight.w700 : null,
            ),
          ),
        ),
        cell('${st.msduCount}', on: on),
        cell(_bytes(st.psduBytes), on: on),
        cell(pct >= 99.95 ? 'all' : '${pct.toStringAsFixed(1)} %', on: on),
      ],
    );
  }
}

String _bytes(int n) {
  final String s = '$n';
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
