// The controls for Legacy Protection Cost (Wi-Fi Classroom): readouts, the
// predict-then-reveal question, what old gear is nearby, the protection
// frame picker, the sender, and the spec's ceiling table. Reads and writes a
// [LegacyProtectionController]; owns no state, so a presenter layout can
// place it beside [LegacyProtectionStage].
//
// LABELED DEFAULTS (spec 39). The protection frame default (CTS-to-self at
// 1 Mb/s long preamble) and the HT Protection readout are defaults chosen by
// Larry pending Keith, and say so. CWmin 31 is labeled as coming from one
// unverified source. The neighbor-channel switch carries the spec's
// "Sources disagree" label word for word.
//
// States (SOP-007 §5):
//   - fresh       -> an 802.11b device associated, CTS-to-self at 1 Mb/s
//                    long preamble, CWmin 15, 1500 bytes at 54 Mb/s
//   - empty       -> nothing old associated or heard: both lanes match, the
//                    loss reads 0.0%, and the picker says it is not in use
//   - error       -> not reachable as an error: the one impossible choice,
//                    1 Mb/s short preamble, is disabled with its reason; a
//                    short-preamble frame the associated device cannot
//                    decode gets a warning note with an icon and words
//   - disabled    -> 1 Mb/s short; CWmin and "can use short preamble" while
//                    no 802.11b device is associated; the neighbor switches
//                    while nothing is heard (hidden)
//   - loading     -> not reachable: the model is synchronous and pure
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): the headline numbers are on the stage;
// the readouts and the ceiling table fold into PresenterDisclosures, and
// short inputs pair up two per row, so the panel fits with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/dsss_timing.dart';
import '../../../services/wifi_lab/legacy_protection_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'legacy_protection_controller.dart';

/// The question, word for word (spec 39).
const String kLpQuestionText =
    'An old 802.11b scanner sits in a drawer, associated but silent. How much '
    'does it cost the 54 Mb/s laptop?';

/// The neighbor-channel label, word for word (spec 39).
const String kLpSourcesDisagree =
    'Sources disagree: one open-source access point reacts only to its own '
    'channel; a 2004 lab report saw protection spread between channels 1 and '
    '11. The standard allows both.';

class LegacyProtectionControls extends StatelessWidget {
  const LegacyProtectionControls({super.key, required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final SizedBox gap = SizedBox(
          height: presenting ? AppSpacing.xs : AppSpacing.sm,
        );
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Predict(controller: controller, compact: true),
              gap,
              _Inputs(controller: controller, compact: true),
              // One disclosure, not three: at 1440x900 every closed header
              // costs a row the panel does not have.
              PresenterDisclosure(
                title: 'Sender, readouts and the ceiling table',
                children: <Widget>[
                  _SenderInputs(controller: controller),
                  const SizedBox(height: AppSpacing.xs),
                  _Readouts(controller: controller),
                  const SizedBox(height: AppSpacing.xs),
                  _Ceiling(controller: controller),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Readouts(controller: controller),
            gap,
            _Predict(controller: controller, compact: false),
            gap,
            _Inputs(controller: controller, compact: false),
            gap,
            _Ceiling(controller: controller),
          ],
        );
      },
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final LpResult r = controller.result;
    final bool masked = controller.masked;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);

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
            style: accent ? value.copyWith(color: colors.textAccent) : value,
          ),
        ),
      ],
    );

    String hide(String v) => masked ? '?' : v;

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              row('Cycle time', hide(lpUs(r.cycle.cycleUs))),
              row('Modern devices only', lpUs(r.baseline.cycleUs)),
              row(
                'Payload rate',
                hide(lpMbps(r.cycle.payloadRateMbps)),
                accent: true,
              ),
              row(
                'Lost versus modern devices only',
                hide(lpPct(r.lostShare)),
                accent: true,
              ),
              row(
                'Protection frames, per cycle',
                hide(lpUs(r.protectionTenths / 10)),
              ),
              row(
                'Added by the long slot, per cycle',
                hide(lpUs(r.slotAddedTenths / 10)),
              ),
              if (r.cwAddedTenths > 0)
                row(
                  'Added by CWmin 31, per cycle',
                  hide(lpUs(r.cwAddedTenths / 10)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The laptop sends back to back with no one else contending. The '
            'old device sends nothing: every microsecond above is overhead '
            'it causes by being there.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Predict, then reveal ────────────────────────────────────────────────────

class _Predict extends StatelessWidget {
  const _Predict({required this.controller, required this.compact});

  final LegacyProtectionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final LpQuestion q = controller.question;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> children = <Widget>[
      if (compact && q == LpQuestion.asking)
        Row(
          children: <Widget>[
            const Expanded(child: AirtimeSectionTitle('Predict, then reveal')),
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            ),
          ],
        )
      else if (compact && q == LpQuestion.revealed)
        Row(
          children: <Widget>[
            const Expanded(child: AirtimeSectionTitle('Predict, then reveal')),
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        )
      else
        const AirtimeSectionTitle('Predict, then reveal'),
      const SizedBox(height: AppSpacing.xxs),
      Text(kLpQuestionText, style: body),
    ];

    switch (q) {
      case LpQuestion.idle:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: controller.ask,
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Ask the class'),
            ),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Loads the question\'s settings (an 802.11b device associated, '
              'protection at 1 Mb/s long preamble) and hides the answers '
              'until you reveal them.',
              style: note,
            ),
          ],
        ]);
      case LpQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          if (compact)
            // One row in the presenter panel: each choice gets an equal
            // share and its label scales down rather than wrapping.
            Row(
              children: <Widget>[
                for (final LpGuess g in LpGuess.values) ...<Widget>[
                  if (g != LpGuess.values.first)
                    const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: LpChoiceButton(
                      label: g.label,
                      selected: controller.guess == g,
                      onPressed: () => controller.guess = g,
                      dense: true,
                      fit: true,
                    ),
                  ),
                ],
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final LpGuess g in LpGuess.values)
                  LpChoiceButton(
                    label: g.label,
                    selected: controller.guess == g,
                    onPressed: () => controller.guess = g,
                  ),
              ],
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: controller.reveal,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal'),
              ),
            ),
          ],
        ]);
      case LpQuestion.revealed:
        final LpResult r = controller.result;
        final LpGuess? g = controller.guess;
        final double lost = r.lostShare;
        final LpGuess answer = LpGuess.values.firstWhere(
          (LpGuess x) => x.contains(lost),
        );
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'It costs ${lpPct(lost)}${answer == LpGuess.aboutHalf ? ', about half' : ''}: '
            'the laptop falls from ${lpMbps(r.baseline.payloadRateMbps)} to '
            '${lpMbps(r.cycle.payloadRateMbps)}.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g == answer
                  ? 'The class picked ${g.label}: right.'
                  : 'The class picked ${g.label}. The answer is '
                        '${answer.label}.',
              style: body,
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(_why(r), style: note),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: controller.dismissQuestion,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ]);
    }

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// The reveal's explanation, from the result on screen.
String _why(LpResult r) {
  final List<String> parts = <String>[
    if (r.protecting)
      'before every data frame the laptop sends a '
          '${r.config.protection.label}, '
          '${lpUs(r.protectionTenths / 10)} with its gap',
    if (r.longSlot)
      'the old device forces the 20 µs slot, adding '
          '${lpUs(r.slotAddedTenths / 10)} of waiting per frame',
  ];
  if (parts.isEmpty) return 'Nothing old is associated or heard now.';
  return 'Why: ${parts.join('; and ')}. None of it carries data.';
}

// ── Inputs ──────────────────────────────────────────────────────────────────

class _Inputs extends StatelessWidget {
  const _Inputs({required this.controller, required this.compact});

  final LegacyProtectionController controller;

  /// The presenter arrangement: pairs, fewer notes.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final LegacyProtectionController m = controller;
    final LpConfig c = m.config;
    final LpResult r = m.result;
    final SizedBox gap = SizedBox(
      height: compact ? AppSpacing.xs : AppSpacing.sm,
    );
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

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

    final Widget associated = LpSwitchRow(
      title: compact ? '802.11b associated' : '802.11b device associated',
      value: c.associated,
      onChanged: (bool v) => m.associated = v,
    );
    final Widget heard = LpSwitchRow(
      title: '802.11b network heard nearby',
      value: c.heard,
      onChanged: (bool v) => m.heard = v,
    );
    final Widget shortPre = LpSwitchRow(
      title: 'The 802.11b device can use short preamble',
      value: c.oldDeviceShortPreamble,
      enabled: c.associated,
      onChanged: (bool v) => m.oldDeviceShortPreamble = v,
    );
    final Widget neighbor = AppToggle<NeighborChannel>(
      label: 'The old network is',
      semanticLabel: 'Where the old network is heard',
      value: c.neighborChannel,
      expand: true,
      items: <AppToggleItem<NeighborChannel>>[
        for (final NeighborChannel n in NeighborChannel.values) (n, n.label),
      ],
      onChanged: (NeighborChannel n) => m.neighborChannel = n,
    );
    final Widget policy = AppToggle<NeighborPolicy>(
      label: 'This AP reacts to',
      semanticLabel: 'Which heard networks this AP reacts to',
      value: c.policy,
      expand: true,
      items: <AppToggleItem<NeighborPolicy>>[
        for (final NeighborPolicy p in NeighborPolicy.values) (p, p.label),
      ],
      onChanged: (NeighborPolicy p) => m.policy = p,
    );

    final Widget kind = AppToggle<ProtectionKind>(
      label: compact ? null : 'Protection frame',
      semanticLabel: 'Protection frame',
      value: c.protection.kind,
      expand: true,
      items: const <AppToggleItem<ProtectionKind>>[
        (ProtectionKind.ctsToSelf, 'CTS-to-self'),
        (ProtectionKind.rtsCts, 'RTS/CTS'),
      ],
      onChanged: (ProtectionKind k) => m.protectionKind = k,
    );

    final Widget grid = _ProtectionGrid(controller: m, compact: compact);

    final Widget cw = AppToggle<LpCwMin>(
      label: 'CWmin with an 802.11b device associated',
      semanticLabel:
          'Minimum contention window with an 802.11b device associated',
      value: c.cwMin,
      expand: true,
      enabled: c.associated,
      items: const <AppToggleItem<LpCwMin>>[
        (LpCwMin.cw15, '15'),
        (LpCwMin.cw31, '31 (unverified)'),
      ],
      onChanged: (LpCwMin v) => m.cwMin = v,
    );

    final Widget size = _select<int>(
      label: 'Frame size',
      value: c.payloadBytes,
      items: <AppSelectItem<int>>[
        for (final int b in kLpPayloadSizes) (b, '${_thousands(b)} bytes'),
      ],
      onChanged: (int b) => m.payloadBytes = b,
    );
    final Widget rate = _select<int>(
      label: 'Data rate',
      value: c.rateMbps,
      items: <AppSelectItem<int>>[
        for (final int v in kLpDataRatesMbps) (v, '$v Mb/s'),
      ],
      onChanged: (int v) => m.rateMbps = v,
    );

    final bool undecodable =
        r.protecting &&
        r.erp.barkerPreambleMode &&
        c.protection.rate.isDsss &&
        c.protection.preamble == DsssPreamble.short;
    final bool ofdmContrast = r.protecting && !c.protection.rate.isDsss;

    final List<Widget> warnings = <Widget>[
      if (undecodable)
        _WarningNote(
          compact
              ? 'Barker_Preamble_Mode is 1: the old device could not decode '
                    'this short-preamble frame.'
              : 'The associated old device cannot use short preamble '
                    '(Barker_Preamble_Mode is 1), so it could not decode '
                    'this protection frame. The number shows what it would '
                    'cost if it could.',
        ),
      if (ofdmContrast)
        _WarningNote(
          compact
              ? 'Contrast only: 802.11b cannot decode OFDM, so this protects '
                    'nothing.'
              : 'Contrast only: an 802.11b device cannot decode a 6 Mb/s '
                    'OFDM frame, so this protects nothing. It shows that most '
                    'of the cost is the old preamble, not protection itself.',
        ),
    ];

    final Widget protectionState = Text(
      r.protecting
          ? 'Sent before every data frame (Use_Protection is 1).'
          : 'Not sent now: nothing old is associated, or heard where this AP '
                'listens, so Use_Protection is 0.',
      style: note,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                pair(associated, heard),
                gap,
                kind,
                const SizedBox(height: AppSpacing.xxs),
                grid,
                ...warnings,
              ],
            ),
          ),
          // Rarely changed, and only meaningful while a network is heard
          // (spec 00: group rarely used settings behind a disclosure). The
          // toggles stack at full width so their labels are never cut.
          if (c.heard)
            PresenterDisclosure(
              title: 'Where the old network is heard (sources disagree)',
              children: <Widget>[
                neighbor,
                gap,
                policy,
                const SizedBox(height: AppSpacing.xxs),
                Text(kLpSourcesDisagree, style: note),
              ],
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Old gear nearby'),
              const SizedBox(height: AppSpacing.xs),
              associated,
              Text(
                'Sets NonERP_Present and Use_Protection, and forces the long '
                'slot (9 to 20 µs).',
                style: note,
              ),
              gap,
              shortPre,
              Text(
                c.associated
                    ? 'Off sets Barker_Preamble_Mode (illustrative default: '
                          'an old scanner is assumed long-preamble only).'
                    : 'Matters only while an 802.11b device is associated.',
                style: note,
              ),
              gap,
              heard,
              Text(
                'Sets Use_Protection only. It never forces the long slot.',
                style: note,
              ),
              if (c.heard) ...<Widget>[
                gap,
                neighbor,
                gap,
                policy,
                const SizedBox(height: AppSpacing.xs),
                Text(kLpSourcesDisagree, style: note),
              ],
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('Protection frame'),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'A short frame the old device can decode, at an old DSSS or '
                'CCK rate (direct sequence spread spectrum, complementary '
                'code keying). A CTS-to-self is a CTS (Clear to Send) '
                'addressed to the sender itself; RTS/CTS is a Request to '
                'Send answered by a Clear to Send. Its Duration field makes '
                'every listener hold off.',
                style: note,
              ),
              gap,
              kind,
              gap,
              grid,
              protectionState,
              ...warnings,
              const SizedBox(height: AppSpacing.xs),
              Text(
                // Keith confirmed this default 2026-09-27.
                'Default: CTS-to-self at 1 Mb/s long preamble, the worst '
                'case the standard allows. Up and Down in Present mode step '
                'the rate.',
                style: note,
              ),
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('The sender'),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'One laptop on 802.11g OFDM (orthogonal frequency-division '
                'multiplexing) at 2.4 GHz, an open network, nobody else '
                'sending.',
                style: note,
              ),
              gap,
              size,
              gap,
              rate,
              gap,
              cw,
              const SizedBox(height: AppSpacing.xs),
              Text(
                'CWmin is the minimum contention window, in slots; the mean '
                'backoff is half of it. 15 is the default. "31 when an '
                '802.11b station is present" comes from one unverified '
                'source, so it is a setting here, applied only while one is '
                'associated.',
                style: note,
              ),
            ],
          ),
        ),
      ],
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

/// The presenter's sender settings and the OFDM contrast, inside the one
/// disclosure: frame size and data rate, CWmin, and whether protection is
/// being sent.
class _SenderInputs extends StatelessWidget {
  const _SenderInputs({required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final LegacyProtectionController m = controller;
    final LpConfig c = m.config;
    Widget select<T>(
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
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: select<int>(
                  'Frame size',
                  c.payloadBytes,
                  <AppSelectItem<int>>[
                    for (final int b in kLpPayloadSizes)
                      (b, '${_thousands(b)} bytes'),
                  ],
                  (int b) => m.payloadBytes = b,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: select<int>(
                  'Data rate',
                  c.rateMbps,
                  <AppSelectItem<int>>[
                    for (final int v in kLpDataRatesMbps) (v, '$v Mb/s'),
                  ],
                  (int v) => m.rateMbps = v,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<LpCwMin>(
            label: 'CWmin (minimum contention window) with 802.11b associated',
            semanticLabel:
                'Minimum contention window with an 802.11b device associated',
            value: c.cwMin,
            expand: true,
            enabled: c.associated,
            items: const <AppToggleItem<LpCwMin>>[
              (LpCwMin.cw15, '15'),
              (LpCwMin.cw31, '31 (unverified)'),
            ],
            onChanged: (LpCwMin v) => m.cwMin = v,
          ),
          const SizedBox(height: AppSpacing.xs),
          _OfdmContrast(controller: m, compact: true),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Protection default: CTS-to-self at 1 Mb/s long preamble.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The rate and preamble picker: 802.11b rates across, long and short down,
/// each cell showing what that exchange costs. 1 Mb/s short is disabled, with
/// the reason in words. The OFDM contrast sits under the grid.
class _ProtectionGrid extends StatelessWidget {
  const _ProtectionGrid({required this.controller, required this.compact});

  final LegacyProtectionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final ProtectionChoice cur = controller.config.protection;
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    Widget cell(ProtectionRate r, DsssPreamble p) {
      final ProtectionChoice c = cur.copyWith(rate: r, preamble: p);
      if (!c.isAvailable) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs / 2),
          child: Tooltip(
            message: kDsssNoShortAt1Reason,
            child: LpChoiceButton(
              label: 'n/a',
              semanticLabel:
                  '${r.label}, short preamble: unavailable. '
                  '$kDsssNoShortAt1Reason',
              selected: false,
              onPressed: null,
              dense: true,
            ),
          ),
        );
      }
      final ProtectionTiming t = protectionTiming(c);
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs / 2),
        child: LpChoiceButton(
          label: lpUs(t.totalUs),
          semanticLabel:
              '${c.kind.label} at ${r.label}, ${p.label.toLowerCase()} '
              'preamble, ${lpUs(t.totalUs)} with its gap',
          selected: cur.rate == r && cur.preamble == p,
          onPressed: () => controller.pickProtection(r, p),
          dense: true,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Table(
          columnWidths: const <int, TableColumnWidth>{
            0: IntrinsicColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: <TableRow>[
            TableRow(
              children: <Widget>[
                const SizedBox.shrink(),
                for (final ProtectionRate r in ProtectionRate.dsssRates)
                  Center(child: Text(r.label, style: head)),
              ],
            ),
            for (final DsssPreamble p in DsssPreamble.values)
              TableRow(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xxs),
                    child: Text(p.label, style: head),
                  ),
                  for (final ProtectionRate r in ProtectionRate.dsssRates)
                    cell(r, p),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.block_rounded,
              size: AppSpacing.sm,
              color: colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                compact
                    ? 'n/a: $kDsssNoShortAt1Reason'
                    : '1 Mb/s short: $kDsssNoShortAt1Reason',
                style: note,
              ),
            ),
          ],
        ),
        if (!compact) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          _OfdmContrast(controller: controller, compact: false),
          const SizedBox(height: AppSpacing.xxs),
        ],
      ],
    );
  }
}

/// The 6 Mb/s OFDM contrast choice.
class _OfdmContrast extends StatelessWidget {
  const _OfdmContrast({required this.controller, required this.compact});

  final LegacyProtectionController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ProtectionChoice cur = controller.config.protection;
    final ProtectionTiming t = protectionTiming(
      cur.copyWith(rate: ProtectionRate.ofdm6),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: LpChoiceButton(
        label: compact
            ? 'Contrast: 6 Mb/s OFDM, ${lpUs(t.totalUs)}'
            : 'Contrast: 6 Mb/s OFDM, ${lpUs(t.totalUs)} (an 802.11b '
                  'device cannot decode it)',
        selected: cur.rate == ProtectionRate.ofdm6,
        onPressed: () =>
            controller.pickProtection(ProtectionRate.ofdm6, DsssPreamble.long),
        dense: compact,
      ),
    );
  }
}

class _WarningNote extends StatelessWidget {
  const _WarningNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: AppSpacing.sm,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(
                color: colors.statusWarning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── The ceiling table ───────────────────────────────────────────────────────

class _Ceiling extends StatelessWidget {
  const _Ceiling({required this.controller});

  final LegacyProtectionController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final LpResult r = controller.result;
    final int? here = controller.masked ? null : ceilingRowOf(r);
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Where the ceiling goes'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'One sender, 1,500-byte frames at 54 Mb/s, CWmin 15 unless '
            'stated.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The table holds the question's answer (row 5), so it waits for
          // Reveal like every other number.
          if (controller.masked)
            Text(
              'Hidden until Reveal: this table holds the answer.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            )
          else
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(2.4),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(
                  children: <Widget>[
                    Text('Case', style: label),
                    Text('Cycle', textAlign: TextAlign.end, style: label),
                    Text('Payload', textAlign: TextAlign.end, style: label),
                  ],
                ),
                for (int i = 0; i < kLpCeilingCases.length; i++)
                  _ceilingRow(
                    context,
                    kLpCeilingCases[i],
                    computeCycle(kLpCeilingCases[i].spec),
                    here == i,
                    label,
                    value,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  TableRow _ceilingRow(
    BuildContext context,
    LpCeilingCase k,
    LpCycle c,
    bool here,
    TextStyle label,
    TextStyle value,
  ) {
    final AppColorScheme colors = context.colors;
    final TextStyle v = here
        ? value.copyWith(color: colors.textAccent, fontWeight: FontWeight.w700)
        : value;
    return TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Semantics(
            label: here ? '${k.label}, this network now' : k.label,
            excludeSemantics: true,
            child: Row(
              children: <Widget>[
                if (here) ...<Widget>[
                  Icon(
                    Icons.arrow_right_rounded,
                    size: AppSpacing.sm,
                    color: colors.textAccent,
                  ),
                ],
                Expanded(
                  child: Text(
                    here ? '${k.label} (this network)' : k.label,
                    style: here
                        ? label.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          )
                        : label,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(lpUs(c.cycleUs), textAlign: TextAlign.end, style: v),
        Text(lpMbps(c.payloadRateMbps), textAlign: TextAlign.end, style: v),
      ],
    );
  }
}

// ── Small parts ─────────────────────────────────────────────────────────────

/// A selectable outlined button, filled when selected, grayed when
/// [onPressed] is null.
class LpChoiceButton extends StatelessWidget {
  const LpChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.semanticLabel,
    this.dense = false,
    this.fit = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  /// What a screen reader hears instead of [label], when the label alone is
  /// a bare number.
  final String? semanticLabel;

  /// Tighter side padding, so a row of choices fits a narrow panel.
  final bool dense;

  /// Scale the label down to fit instead of clipping it (a row of equal
  /// choices).
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Widget button = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSpacing.minTouchTarget),
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: AppSpacing.xxs)
            : null,
        backgroundColor: selected ? colors.primary : null,
        foregroundColor: selected ? colors.onPrimary : colors.textPrimary,
        disabledForegroundColor: colors.textDisabled,
        disabledBackgroundColor: colors.disabledFill,
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      // The spoken label replaces the visible one inside the button, so the
      // button keeps its own tap action and enabled state for screen readers.
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: semanticLabel != null,
        child: fit
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, softWrap: false),
              )
            : Text(label, maxLines: 1, softWrap: false),
      ),
    );
    return Semantics(selected: selected, child: button);
  }
}

/// A switch with its title; the whole row toggles.
class LpSwitchRow extends StatelessWidget {
  const LpSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: text.bodyLarge?.copyWith(
                  color: enabled ? colors.textPrimary : colors.textDisabled,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: colors.primary,
            ),
          ],
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
