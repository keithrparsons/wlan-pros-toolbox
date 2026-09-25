// PhyPreambleControls: the inputs-and-readouts half of the PHY Preamble
// Reference (Wi-Fi Lab).
//
// Takes the shared PhyPreambleModel and a set of parts to show, so a phone
// stacks them under the stage while a presenter layout can show every part in
// one column beside it. No part draws the preamble; PhyPreambleStage owns it.
//
// Control types follow GL-003 §8.14: PPDU type (nine), LTF size and GI (four)
// and width (four) are Selects; the mode (two) is an AppToggle. A setting
// that changes nothing for the chosen PPDU is disabled with a sentence saying
// why. While a mystery PPDU is on the stage, every control and readout that
// would give its name away is hidden, and says so.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'phy_preamble_bit_table.dart';
import 'phy_preamble_model.dart';
import 'phy_preamble_parts.dart';

/// The groups PhyPreambleControls can show.
enum PreambleControlPart {
  /// Mode, and the walk's Next / Back / Reset / Reveal / New mystery.
  mode,

  /// PPDU type, streams, LTF size and GI, SIG symbols, width.
  settings,

  /// Totals, LTF count, BSS color position.
  readouts,

  /// The L-SIG LENGTH calculator.
  length,
}

class PhyPreambleControls extends StatelessWidget {
  const PhyPreambleControls({
    super.key,
    required this.model,
    this.parts = const <PreambleControlPart>{
      PreambleControlPart.mode,
      PreambleControlPart.settings,
      PreambleControlPart.readouts,
      PreambleControlPart.length,
    },
  });

  final PhyPreambleModel model;
  final Set<PreambleControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) {
        final List<Widget> cards = <Widget>[
          if (parts.contains(PreambleControlPart.mode)) _ModeCard(model),
          if (parts.contains(PreambleControlPart.settings))
            _SettingsCard(model),
          if (parts.contains(PreambleControlPart.readouts))
            _ReadoutsCard(model),
          if (parts.contains(PreambleControlPart.length))
            _LengthCard(model: model),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

String _hiddenNote(String what) =>
    '$what hidden with the PPDU\'s name. Finish the walk, or press Reveal.';

// ── Mode ────────────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  const _ModeCard(this.m);

  final PhyPreambleModel m;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool identify = m.mode == PreambleMode.identify;
    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<PreambleMode>(
            label: 'Mode',
            semanticLabel: 'Mode: explore the fields, or identify the PHY',
            value: m.mode,
            expand: true,
            items: <AppToggleItem<PreambleMode>>[
              for (final PreambleMode p in PreambleMode.values) (p, p.label),
            ],
            onChanged: (PreambleMode p) => m.mode = p,
          ),
          if (identify) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: m.walkDone
                    ? 'The walk is complete'
                    : 'Ask the receiver\'s next question',
                excludeSemantics: true,
                child: FilledButton.icon(
                  onPressed: m.walkDone ? null : m.stepWalk,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(m.walkDone ? 'Walk complete' : 'Next step'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    disabledBackgroundColor: colors.disabledFill,
                    disabledForegroundColor: colors.textDisabled,
                    minimumSize: const Size.fromHeight(
                      AppSpacing.minTouchTarget,
                    ),
                    textStyle: text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Expanded(
                  child: PpOutlineButton(
                    icon: Icons.skip_previous_rounded,
                    label: 'Back',
                    semanticLabel: 'Take back the last question',
                    onPressed: m.stepsShown == 0 ? null : m.backWalk,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: PpOutlineButton(
                    icon: Icons.visibility_rounded,
                    label: 'Reveal',
                    semanticLabel: 'Show every question and the verdict',
                    onPressed: m.walkDone ? null : m.revealWalk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: <Widget>[
                Expanded(
                  child: PpOutlineButton(
                    icon: Icons.restart_alt_rounded,
                    label: 'Reset',
                    semanticLabel: 'Back to the first question',
                    onPressed: m.stepsShown == 0 ? null : m.resetWalk,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: PpOutlineButton(
                    icon: Icons.casino_rounded,
                    label: 'Mystery',
                    semanticLabel:
                        'New mystery PPDU: pick one at random and hide its name',
                    onPressed: m.newMystery,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick a PPDU under Settings and walk it, or press Mystery to '
              'hide its name, predict, then reveal.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Settings ────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard(this.m);

  final PhyPreambleModel m;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? note = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    if (m.hidden) {
      return PpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PpSectionLabel('Settings'),
            const SizedBox(height: AppSpacing.xs),
            Text(_hiddenNote('Settings are'), style: note),
          ],
        ),
      );
    }
    final PreambleSettings s = m.settings;
    final PpduType t = s.type;
    final bool streamsOn = t != PpduType.nonHt;
    final int maxS = t.maxStreams;
    final int streams = s.effectiveStreams;
    final ({int count, Evidence evidence}) ltf = m.ltf;
    final String sigName = t == PpduType.ehtMu ? 'EHT-SIG' : 'HE-SIG-B';
    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PpSectionLabel('Settings'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'PPDU type',
            semanticLabel: 'PPDU type',
            field: AppSelect<PpduType>(
              value: t,
              semanticLabel: 'PPDU type',
              items: <AppSelectItem<PpduType>>[
                for (final PpduType p in PpduType.values) (p, p.label),
              ],
              onChanged: (PpduType p) => m.type = p,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(t.description, style: note),
          const SizedBox(height: AppSpacing.sm),
          PpSlider(
            label: 'Spatial streams (N_STS)',
            valueText: streamsOn ? '$streams' : 'none',
            value: streams.toDouble(),
            min: 1,
            max: maxS < 2 ? 2 : maxS.toDouble(),
            divisions: maxS < 2 ? 1 : maxS - 1,
            onChanged: streamsOn ? (double v) => m.streams = v.round() : null,
            semanticValue: (double v) =>
                '${v.round()} stream${v.round() == 1 ? '' : 's'}',
          ),
          if (streamsOn)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                Text(
                  '${ltf.count} LTF${ltf.count == 1 ? '' : 's'} for '
                  '$streams stream${streams == 1 ? '' : 's'}'
                  '${t == PpduType.htMixed ? ' (HT stops at 4)' : ''}.',
                  style: note,
                ),
                EvidenceChip(ltf.evidence),
              ],
            )
          else
            Text(
              'Non-HT sends one stream and nothing after L-SIG but data.',
              style: note,
            ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'LTF size and guard interval',
            semanticLabel: 'LTF size and guard interval',
            field: AppSelect<HeLtfMode>(
              value: s.ltf,
              enabled: t.hasHeLtf,
              semanticLabel: 'LTF size and guard interval',
              items: <AppSelectItem<HeLtfMode>>[
                for (final HeLtfMode h in HeLtfMode.values) (h, h.label),
              ],
              onChanged: (HeLtfMode h) => m.ltfMode = h,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            t.hasHeLtf
                ? 'Each LTF is 6.4 µs (2x) or 12.8 µs (4x) plus the guard '
                      'interval. These four pairs are the brief\'s EHT list; '
                      '1x is not offered.'
                : 'Only HE and EHT choose an LTF size. HT and VHT LTFs are '
                      '4 µs each.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.sm),
          PpSlider(
            label: t.hasSigBSymbols
                ? '$sigName symbols (set by the AP)'
                : 'HE-SIG-B / EHT-SIG symbols',
            valueText: t.hasSigBSymbols ? '${s.sigSymbols}' : 'none',
            value: s.sigSymbols.toDouble(),
            min: 1,
            max: kMaxSigSymbols.toDouble(),
            divisions: kMaxSigSymbols - 1,
            onChanged: t.hasSigBSymbols
                ? (double v) => m.sigSymbols = v.round()
                : null,
            semanticValue: (double v) =>
                '${v.round()} symbol${v.round() == 1 ? '' : 's'}',
          ),
          Text(
            t.hasSigBSymbols
                ? 'The count depends on the users and the SIG MCS. It is a '
                      'setting here, not computed.'
                : 'Only HE MU (HE-SIG-B) and EHT MU (EHT-SIG) carry a SIG '
                      'field whose length varies.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Channel width',
            semanticLabel: 'Channel width',
            field: AppSelect<int>(
              value: s.widthMhz,
              enabled: t.widthChangesLayout,
              semanticLabel: 'Channel width',
              items: <AppSelectItem<int>>[
                for (final int w in kPreambleWidthsMhz) (w, '$w MHz'),
              ],
              onChanged: (int w) => m.widthMhz = w,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            t.widthChangesLayout
                ? 'Width changes VHT-SIG-B\'s bit layout, not any duration.'
                : 'Preamble field durations are the same at every width, so '
                      'width changes nothing drawn here. In VHT it changes '
                      'VHT-SIG-B\'s layout.',
            style: note,
          ),
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.m);

  final PhyPreambleModel m;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? note = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary);
    if (m.hidden) {
      return PpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PpSectionLabel('Readouts'),
            const SizedBox(height: AppSpacing.xs),
            Text(_hiddenNote('Readouts are'), style: note),
          ],
        ),
      );
    }
    final PpduType t = m.type;
    final ({String symbol, int start, int end})? bss = bssColorPosition(t);
    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PpSectionLabel('Readouts'),
          const SizedBox(height: AppSpacing.xxs),
          PpRow(
            label: 'L-SIG RATE',
            value: t == PpduType.nonHt
                ? 'the real data rate'
                : '1101 (6 Mb/s), always',
          ),
          PpRow(
            label: 'L-SIG LENGTH mod 3',
            value: switch (t) {
              PpduType.nonHt => 'any (octets)',
              PpduType.htMixed || PpduType.vht => '0',
              _ => '${(3 - lsigM(t)) % 3}',
            },
          ),
          PpRow(
            label: 'BSS color',
            value: bss == null
                ? 'no BSS color field'
                : '${bss.symbol} B${bss.start}-B${bss.end}',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'BSS color moves with the PPDU type in HE (SU B8-B13, MU B5-B10, '
            'TB B1-B6 of HE-SIG-A1) and is fixed in EHT (U-SIG-1 B7-B12).',
            style: note,
          ),
        ],
      ),
    );
  }
}

// ── L-SIG LENGTH ────────────────────────────────────────────────────────────

class _LengthCard extends StatefulWidget {
  const _LengthCard({required this.model});

  final PhyPreambleModel model;

  @override
  State<_LengthCard> createState() => _LengthCardState();
}

class _LengthCardState extends State<_LengthCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.model.txtimeText,
  );

  @override
  void didUpdateWidget(covariant _LengthCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_controller.text != widget.model.txtimeText) {
      _controller.value = TextEditingValue(
        text: widget.model.txtimeText,
        selection: TextSelection.collapsed(
          offset: widget.model.txtimeText.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final PhyPreambleModel m = widget.model;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle? note = text.bodySmall?.copyWith(
      color: colors.textTertiary,
    );
    final PpduType t = m.type;

    if (m.hidden) {
      return PpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PpSectionLabel('L-SIG LENGTH calculator'),
            const SizedBox(height: AppSpacing.xs),
            Text(_hiddenNote('The calculator is'), style: note),
          ],
        ),
      );
    }

    final bool spoofed = t != PpduType.nonHt;
    final LsigLengthResult? r = spoofed ? m.lsigLength : null;
    final String? inputError = spoofed ? m.txtimeError?.message : null;
    final String? calcError = r == null || r.ok ? null : _errorText(r, m);

    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PpSectionLabel('L-SIG LENGTH calculator'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'In HT and later, L-SIG says 6 Mb/s and a LENGTH that makes a '
            'legacy radio stay quiet for the whole PPDU.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'True PPDU duration, TXTIME (µs)',
            semanticLabel: 'True PPDU duration in microseconds',
            field: TextField(
              controller: _controller,
              enabled: spoofed,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (String v) => m.txtimeText = v,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.inlineCode.copyWith(
                fontSize: AppTextSize.fieldNumeric,
                color: spoofed ? colors.textPrimary : colors.textDisabled,
              ),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(
                hintText: '200',
                suffixText: 'µs',
                errorText: inputError,
                errorMaxLines: 3,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MergeSemantics(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '2.4 GHz: 6 µs signal extension after the data',
                    style: text.bodyMedium?.copyWith(
                      color: spoofed
                          ? colors.textSecondary
                          : colors.textDisabled,
                    ),
                  ),
                ),
                Switch(
                  value: m.signalExtension,
                  onChanged: spoofed ? (bool v) => m.signalExtension = v : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          PpOutlineButton(
            icon: Icons.input_rounded,
            label: 'This preamble + 100 µs of data',
            semanticLabel:
                'Set TXTIME to this preamble plus 100 microseconds of data',
            onPressed: spoofed ? () => m.useExampleTxtime(100) : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!spoofed)
            Text(
              'In non-HT, LENGTH is the PSDU size in octets and RATE is the '
              'real rate, so nothing is spoofed. Pick HT or later.',
              style: note,
            )
          else if (calcError != null)
            _ErrorBox(message: calcError)
          else if (r != null) ...<Widget>[
            PpRow(label: 'm', value: _mText(t)),
            PpRow(label: 'LENGTH', value: '${r.length}', emphasize: true),
            _Formula(
              'ceil((${_fmt(r.txtimeTenths)}'
              '${r.signalExtensionUs > 0 ? ' - ${r.signalExtensionUs}' : ''}'
              ' - 20) / 4) x 3 - 3'
              '${r.m > 0 ? ' - ${r.m}' : ''} = ${r.length}',
            ),
            PpRow(label: 'LENGTH mod 3', value: '${r.lengthMod3}'),
            PpRow(
              label: 'A legacy radio counts',
              value: '${r.legacySymbols} symbols',
            ),
            _Formula(
              'ceil((16 + 8 x ${r.length} + 6) / 24) = ${r.legacySymbols}',
            ),
            PpRow(
              label: 'and defers, from the start',
              value: '${_fmt(r.legacyDeferTenths)} µs',
            ),
            _Formula(
              '20 + 4 x ${r.legacySymbols}'
              '${r.signalExtensionUs > 0 ? ' + ${r.signalExtensionUs}' : ''}'
              ' = ${_fmt(r.legacyDeferTenths)} µs',
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              r.legacyDeferTenths == r.txtimeTenths
                  ? 'Exactly the true duration.'
                  : 'The true duration rounded up to a whole 4 µs symbol.',
              style: note,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xxs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final Evidence e in lsigRuleEvidence(t)) EvidenceChip(e),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(int tenths) => formatPreambleTenths(tenths);

  static String _mText(PpduType t) => switch (t) {
    PpduType.heMu || PpduType.heErSu => '1 (HE MU and HE ER SU)',
    PpduType.heSu || PpduType.heTb => '2 (HE SU and HE TB)',
    PpduType.ehtMu || PpduType.ehtTb => '0 (EHT: LENGTH mod 3 = 0)',
    _ => '0 (HT and VHT)',
  };

  static String _errorText(LsigLengthResult r, PhyPreambleModel m) {
    switch (r.error!) {
      case LsigLengthError.notSpoofed:
        return 'Non-HT sends its real length.';
      case LsigLengthError.shorterThanPreamble:
        return 'Shorter than this PPDU\'s own preamble '
            '(${_fmt(m.preambleTenths)} µs). Enter a longer duration.';
      case LsigLengthError.tooLong:
        return 'LENGTH would be ${r.length}, over the 12-bit maximum of '
            '$kMaxLsigLength. The longest PPDU this L-SIG can cover is '
            '${_fmt(maxTxtimeTenths(r.m) + r.signalExtensionUs * 10)} µs.';
    }
  }
}

/// A worked formula on its own full-width line, under the row it explains.
class _Formula extends StatelessWidget {
  const _Formula(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: mono.inlineCode.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.statusDangerFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.statusDanger),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              color: colors.statusDanger,
              size: AppSpacing.md,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Cannot signal this. $message',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
