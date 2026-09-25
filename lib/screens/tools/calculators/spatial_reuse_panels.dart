// Controls and readouts for the Wi-Fi Lab Spatial Reuse simulator.
//
// SpatialReuseControls: BSS coloring on or off, each BSS's color number,
// OBSS_PD, TX_PWRref class, channel width, AP power, path-loss exponent and
// the four positions.
// SpatialReuseReadouts: the decision and the rule that fired, AP B's power
// after the limit, each link's SINR, the airtime the pair uses, and the
// rules with their sources and what is out of scope.
// Each takes a SpatialReuseState and neither knows about the stage.
//
// THEME: context.colors only. Waiting or sending together is a consequence
// of the settings, not a pass or fail, so the decision carries no status hue
// (§8.13 rule 6). The one verdict is whether a link still holds the MCS the
// student picked: success or danger, always with an icon and the words
// (§8.13 case 2). Lime marks OBSS_PD and the airtime result, the quantities
// the tool is about.
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/spatial_reuse_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'spatial_reuse_state.dart';

// ── Shared parts ──────────────────────────────────────────────────────────

class ReuseCard extends StatelessWidget {
  const ReuseCard({super.key, required this.child});
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
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

String _db(double v) => v.toStringAsFixed(1);

// ── Controls ──────────────────────────────────────────────────────────────

class SpatialReuseControls extends StatelessWidget {
  const SpatialReuseControls({super.key, required this.state});
  final SpatialReuseState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final SpatialReuseState st = state;
    final ReuseScenario s = st.scenario;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return <Widget>[
      const _SectionLabel('BSS coloring (802.11ax)'),
      _switch(
        context,
        'BSS coloring on (off = legacy radios)',
        s.coloring,
        st.setColoring,
      ),
      _slider(
        context,
        label: 'BSS A color',
        unit: '',
        value: s.colorA.toDouble(),
        min: kMinBssColor.toDouble(),
        max: kMaxBssColor.toDouble(),
        divisions: kMaxBssColor - kMinBssColor,
        decimals: 0,
        onChanged: s.coloring ? (double v) => st.setColorA(v.round()) : null,
      ),
      _slider(
        context,
        label: 'BSS B color',
        unit: '',
        value: s.colorB.toDouble(),
        min: kMinBssColor.toDouble(),
        max: kMaxBssColor.toDouble(),
        divisions: kMaxBssColor - kMinBssColor,
        decimals: 0,
        onChanged: s.coloring ? (double v) => st.setColorB(v.round()) : null,
      ),
      Text(
        s.coloring
            ? 'A 6-bit number, 1 to 63, sent in every HE preamble. Give both '
                  'BSSs the same number and AP B can no longer tell them '
                  'apart.'
            : 'Legacy radios have no BSS color, so every Wi-Fi frame counts '
                  'at -82 dBm.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      const _SectionLabel('AP B spatial reuse'),
      _slider(
        context,
        label: 'OBSS_PD threshold, per 20 MHz',
        unit: 'dBm',
        value: s.obssPdDbm,
        min: kObssPdMinDbm,
        max: kObssPdMaxDbm,
        divisions: (kObssPdMaxDbm - kObssPdMinDbm).round(),
        decimals: 0,
        onChanged: s.coloring ? st.setObssPd : null,
      ),
      Text(
        s.coloring
            ? 'Each 1 dB above -82 costs AP B 1 dB of transmit power for that '
                  'frame.'
            : 'Turn BSS coloring on to use OBSS_PD.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppToggle<TxPwrRefClass>(
        label: 'TX_PWRref (single source)',
        value: s.txPwrRef,
        expand: true,
        enabled: s.coloring,
        items: <AppToggleItem<TxPwrRefClass>>[
          for (final TxPwrRefClass c in TxPwrRefClass.values) (c, c.short),
        ],
        onChanged: st.setTxPwrRef,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '${s.txPwrRef.short}: ${s.txPwrRef.label}. Both values come from one '
        'secondary source.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      const _SectionLabel('MCS each link must hold'),
      const SizedBox(height: AppSpacing.xs),
      for (final (String name, int mcs, ValueChanged<int> set)
          in <(String, int, ValueChanged<int>)>[
            ('Link A MCS', s.mcsA, st.setMcsA),
            ('Link B MCS', s.mcsB, st.setMcsB),
          ]) ...<Widget>[
        LabeledField(
          label: name,
          field: AppSelect<int>(
            value: mcs,
            semanticLabel: name,
            items: <AppSelectItem<int>>[
              for (int m = 0; m <= kReuseMaxMcs; m++) (m, mcsLabel(m)),
            ],
            onChanged: set,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
      Text(
        'MCS 10 and up need Wi-Fi 6 or 7 (1024- and 4096-QAM).',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      const _SectionLabel('Radios'),
      const SizedBox(height: AppSpacing.xs),
      LabeledField(
        label: 'Channel width, both BSSs',
        field: AppSelect<int>(
          value: s.widthMHz,
          semanticLabel: 'Channel width, both BSSs',
          items: <AppSelectItem<int>>[
            for (final int w in kReuseWidths) (w, '$w MHz'),
          ],
          onChanged: st.setWidth,
        ),
      ),
      _slider(
        context,
        label: 'AP transmit power, both',
        unit: 'dBm',
        value: s.apPowerDbm,
        min: 5,
        max: 25,
        divisions: 20,
        decimals: 0,
        onChanged: st.setApPower,
      ),
      _slider(
        context,
        label: 'Path-loss exponent n',
        unit: '',
        value: s.exponent,
        min: 2,
        max: 4,
        divisions: 20,
        onChanged: st.setExponent,
      ),
      Text(
        'Log-distance model at 5180 MHz (channel 36): free-space loss at 1 m '
        'plus 10 n log10(d). n = 2 is free space; 3 is a common office '
        'guess. 0 dBi antennas.',
        style: small(),
      ),
      const SizedBox(height: AppSpacing.md),
      const _SectionLabel('Positions on the line'),
      for (final ReuseNode n in ReuseNode.values)
        _slider(
          context,
          label: n.label,
          unit: 'm',
          value: st.position(n),
          min: 0,
          max: kReuseLineM,
          divisions: (kReuseLineM * 2).round(),
          onChanged: (double v) => st.move(n, v),
        ),
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: st.reset,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset to the starting line'),
        ),
      ),
    ];
  }

  Widget _switch(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
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
    required ValueChanged<double>? onChanged,
    int decimals = 1,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool on = onChanged != null;
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
                  style: text.bodyMedium?.copyWith(
                    color: on ? colors.textSecondary : colors.textDisabled,
                  ),
                ),
              ),
              Text(
                fmt(value),
                style: mono.inlineCode.copyWith(
                  color: on ? colors.textPrimary : colors.textDisabled,
                ),
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

class SpatialReuseReadouts extends StatelessWidget {
  const SpatialReuseReadouts({super.key, required this.state});
  final SpatialReuseState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _decision(context),
          const SizedBox(height: AppSpacing.sm),
          _links(context),
          const SizedBox(height: AppSpacing.sm),
          _rules(context),
        ],
      ),
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

  Widget _decision(BuildContext context) {
    final ReuseAnalysis a = state.analysis;
    final ReuseScenario s = a.scenario;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ReuseRule r = a.decision.rule;
    final String headline = a.together
        ? 'AP B sends at the same time'
        : 'AP B waits its turn';
    final String why = switch (r) {
      ReuseRule.energyDetect =>
        'AP A is so loud that energy detect fires. No color or threshold '
            'lets AP B past -62 dBm.',
      ReuseRule.preambleDetect =>
        'Without BSS color AP B cannot tell a neighbor from its own BSS, so '
            'any Wi-Fi preamble at -82 dBm or more makes it wait, even one '
            'that would barely bother client B.',
      ReuseRule.intraBss =>
        'Both BSSs use color ${s.colorA}, so AP B reads AP A\'s frame as its '
            'own BSS. Intra-BSS frames keep -82 dBm whatever OBSS_PD is.',
      ReuseRule.obssPd =>
        'The frame carries a neighbor\'s color, but at ${_db(a.heardByBDbm)} '
            'dBm it is at or above OBSS_PD (${_db(clampObssPd(s.obssPdDbm))} '
            'dBm). Raise OBSS_PD above ${_db(a.heardByBDbm)} to reuse the '
            'air.',
      ReuseRule.spatialReuse =>
        'The frame carries a neighbor\'s color and is below OBSS_PD, so AP B '
            'ignores it, and in return caps its power at '
            '${_db(a.decision.txPowerLimitDbm!)} dBm for this frame.',
      ReuseRule.notDetected =>
        'AP A\'s frame reaches AP B below -82 dBm, so AP B never detects it '
            'and sends at full power. No spatial reuse is needed.',
    };

    return ReuseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SectionLabel('Decision'),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              headline,
              style: text.titleMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Rule: ${r.label}.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            why,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _stat(
                context,
                'AP B hears AP A (per 20 MHz)',
                '${_db(a.heardByBDbm)} dBm',
              ),
              _stat(
                context,
                'AP B transmit power',
                '${_db(a.txPowerBDbm)} dBm',
              ),
              _stat(
                context,
                'Airtime, one frame each',
                '${a.frameTimes} frame-time${a.frameTimes == 1 ? '' : 's'}',
                accent: true,
              ),
            ],
          ),
          if (a.decision.txPowerLimitDbm != null && !a.powerCut) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The cap (${_db(a.decision.txPowerLimitDbm!)} dBm) is above '
              'AP B\'s setting, so it changes nothing here.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _links(BuildContext context) {
    final ReuseAnalysis a = state.analysis;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    Widget link(String name, ReuseLink k) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            name,
            style: text.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _stat(context, 'Signal', '${_db(k.signalDbm)} dBm'),
              _stat(
                context,
                'Interference',
                k.interferenceDbm == null
                    ? 'none'
                    : '${_db(k.interferenceDbm!)} dBm',
              ),
              _stat(context, 'SINR', '${_db(k.sinrDb)} dB'),
              _stat(context, 'SNR alone', '${_db(k.snrDb)} dB'),
              _stat(
                context,
                'Highest MCS this SINR supports',
                k.bestMcs == null ? 'none' : 'MCS ${k.bestMcs}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _verdict(context, k),
          if (k.interferenceDbm != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              k.sinrDb < 0
                  ? 'The other AP is louder here than the wanted signal.'
                  : 'The other AP costs this link ${_db(k.costDb)} dB.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );

    return ReuseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SectionLabel('Links, per 20 MHz'),
          link('Link A: AP A to client A', a.linkA),
          link('Link B: AP B to client B', a.linkB),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Noise floor ${_db(reuseNoiseFloorDbm())} dBm per 20 MHz: thermal '
            'noise (kT at 290 K) plus a 7 dB noise figure, as in Rate vs '
            'Range. The SNR an MCS needs is its minimum sensitivity minus the '
            'noise floor at that width (MCS 0 about '
            '${_db(mcsRequiredSnrDb(0, a.scenario.widthMHz))} dB, MCS 7 about '
            '${_db(mcsRequiredSnrDb(7, a.scenario.widthMHz))} dB), and a link '
            'holds an MCS when its SINR is at least that. The sensitivities '
            'are 802.11 conformance floors; real radios beat them, so these '
            'verdicts are the worst case the standard allows.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _verdict(BuildContext context, ReuseLink k) {
    final AppColorScheme colors = context.colors;
    final Color c = k.holds ? colors.statusSuccess : colors.statusDanger;
    final String best = k.bestMcs == null
        ? 'not even MCS 0 (needs ${_db(mcsRequiredSnrDb(0, k.widthMHz))} dB)'
        : mcsLabel(k.bestMcs!);
    final String msg = k.holds
        ? 'Holds MCS ${k.targetMcs}: SINR ${_db(k.sinrDb)} dB, needs '
              '${_db(k.requiredSnrDb)} dB.'
        : 'Does not hold MCS ${k.targetMcs}: SINR ${_db(k.sinrDb)} dB, needs '
              '${_db(k.requiredSnrDb)} dB. Best it supports: $best.';
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(k.holds ? Icons.check_circle : Icons.error, size: 16, color: c),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rules(BuildContext context) {
    final ReuseAnalysis a = state.analysis;
    final ReuseScenario s = a.scenario;
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double pd = clampObssPd(s.obssPdDbm);
    TextStyle body() => text.bodySmall!.copyWith(color: colors.textSecondary);

    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: Text(k, style: body())),
            const SizedBox(width: AppSpacing.xs),
            Text(v, style: mono.inlineCode.copyWith(color: colors.textPrimary)),
          ],
        ),
      ),
    );

    return ReuseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SectionLabel('The rules, per 20 MHz'),
          line('Preamble detect (any Wi-Fi frame, own BSS)', '-82 dBm'),
          line('Energy detect (anything)', '-62 dBm'),
          line('OBSS_PD range (neighbor color only)', '-82 to -62 dBm'),
          const SizedBox(height: AppSpacing.xs),
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Power cap: TX_PWRmax = TX_PWRref - (OBSS_PD - (-82))',
                  style: body(),
                ),
                Text(
                  '${_db(s.txPwrRef.dbm)} - ${_db(pd + 82)} = '
                  '${_db(txPowerLimitDbm(obssPdDbm: pd, txPwrRefDbm: s.txPwrRef.dbm))} dBm',
                  style: mono.inlineCode.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          line(
            'OBSS_PD for a whole ${s.widthMHz} MHz frame',
            '${_db(a.obssPdAtWidthDbm)} dBm',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Single source: TX_PWRref (21 dBm for a client or an AP with 1 or '
            '2 streams, 25 dBm for an AP with more) and the rise of 3 dB per '
            'doubling of width each come from one secondary reference. The '
            'Lab compares levels per 20 MHz, which is the same test.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Out of scope: SRG (spatial reuse group) thresholds and '
            'parameterized spatial reuse (PSR) are not modeled.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One frame each, drawn as equal lengths: backoff, ACKs and rate '
            'changes are left out so the airtime comparison stays simple.',
            style: body(),
          ),
        ],
      ),
    );
  }
}
