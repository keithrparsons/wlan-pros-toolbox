// Rate set card for the Wi-Fi Classroom Rate vs Range tool (spec 44).
//
// The 12 legacy rates as chips (off, supported, basic), the client picker,
// the "also require" selector, and the readouts that follow from them: who
// can associate (status 18), where beacons go, the Supported Rates element
// octets, and the "ACK to a frame sent at X" table. Every widget here takes a
// RateVsRangeModel; the model (lib/services/wifi_lab/rate_set_model.dart)
// does the arithmetic.
//
// STATES (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic
//   - empty       -> an empty basic set is valid: beacons go at a mandatory
//                    rate and the stage says so
//   - error       -> every rate off: "No rates are on", no beacon, no ACK
//                    rows, every verdict "No rates on"
//   - success     -> verdicts, beacon rate, octets, ACK table
//   - disabled    -> DSSS chips at 5 and 6 GHz ("2.4 GHz only"); HT is not
//                    offered as a requirement in 6 GHz
//   - interactive -> chips are buttons with the §8.3 focus ring (Tab, Enter
//                    or Space cycles); selects are AppSelect
//
// THEME: context.colors. A basic chip is lime-filled (the active role,
// §8.3), not a verdict. Only the association verdict uses the §8.13 status
// hues, always with an icon and words (rule 2). Chip state is a word on the
// chip, never color alone. UI text says associate, never join (Keith,
// 2026-09-29). ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/rate_set_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'rate_vs_range_model.dart';
import 'rate_vs_range_parts.dart';

// ── Chips ─────────────────────────────────────────────────────────────────

/// The 12 rates in three rows of four: DSSS/CCK, then OFDM low and high.
class RateSetChips extends StatelessWidget {
  const RateSetChips({super.key, required this.model});
  final RateVsRangeModel model;

  static const List<List<RsRate>> rows = <List<RsRate>>[
    <RsRate>[RsRate.r1, RsRate.r2, RsRate.r5_5, RsRate.r11],
    <RsRate>[RsRate.r6, RsRate.r9, RsRate.r12, RsRate.r18],
    <RsRate>[RsRate.r24, RsRate.r36, RsRate.r48, RsRate.r54],
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RateSet set = model.rateSet;
    final double icon = PresenterMode.scaleOf(context).markerSize(16);
    Widget row(List<RsRate> rates) => Row(
      children: <Widget>[
        for (int i = 0; i < rates.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: RvrRateChip(
              rate: rates[i],
              state: set.stateOf(rates[i]),
              mandatory: model.phy.isMandatory(rates[i]),
              enabled: model.phy.has(rates[i]),
              onTap: () => model.cycleRate(rates[i]),
            ),
          ),
        ],
      ],
    );
    TextStyle caption() =>
        text.labelSmall!.copyWith(color: colors.textTertiary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('DSSS/CCK (2.4 GHz only)', style: caption()),
        const SizedBox(height: AppSpacing.xxs),
        row(rows[0]),
        const SizedBox(height: AppSpacing.xs),
        Text('OFDM', style: caption()),
        const SizedBox(height: AppSpacing.xxs),
        row(rows[1]),
        const SizedBox(height: AppSpacing.xs),
        row(rows[2]),
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.star_rounded, size: icon, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  'Star: mandatory for ${model.phy == RsPhy.erp ? '802.11g (ERP)' : 'OFDM'}: '
                  'every device of that kind can use it. Tap a rate for '
                  'off, supported, basic.',
                  style: caption(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One rate: a button whose tap cycles off, supported, basic. The state is
/// written on the chip. Keyboard focus paints the §8.3 ring.
class RvrRateChip extends StatefulWidget {
  const RvrRateChip({
    super.key,
    required this.rate,
    required this.state,
    required this.mandatory,
    required this.enabled,
    required this.onTap,
  });

  final RsRate rate;
  final RsState state;
  final bool mandatory;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<RvrRateChip> createState() => _RvrRateChipState();
}

class _RvrRateChipState extends State<RvrRateChip> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double icon = PresenterMode.scaleOf(context).markerSize(12);
    final bool basic = widget.state == RsState.basic;
    final bool on = widget.enabled;

    final Color fill = !on
        ? colors.disabledFill
        : basic
        ? colors.primary
        : widget.state == RsState.supported
        ? colors.inputFill
        : Colors.transparent;
    final Color ink = !on
        ? colors.textDisabled
        : basic
        ? colors.onPrimary
        : widget.state == RsState.supported
        ? colors.textPrimary
        : colors.textSecondary;
    final Color hover = colors.textAccent.withValues(alpha: 0.08);
    final String stateWord = on ? widget.state.label : 'n/a';

    final Widget face = Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: _hovered && on && !basic ? hover : fill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: _focused && on
              ? (colors.isLight ? colors.textAccent : colors.primary)
              : (on ? colors.borderStrong : colors.border),
          width: _focused && on ? (colors.isLight ? 3 : 2) : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  widget.rate.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: mono.inlineCode.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                    decoration: widget.state == RsState.off && on
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              if (widget.mandatory && on) ...<Widget>[
                const SizedBox(width: AppSpacing.xxs),
                Icon(Icons.star_rounded, size: icon, color: ink),
              ],
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stateWord,
              maxLines: 1,
              style: text.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: on,
      label:
          '${widget.rate.mbpsLabel}, '
          '${on ? widget.state.label : 'not in this band, 2.4 GHz only'}'
          '${widget.mandatory && on ? ', mandatory' : ''}',
      hint: on ? 'Changes to ${widget.state.next.label}' : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: on,
        mouseCursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (bool v) {
          if (mounted) setState(() => _focused = v);
        },
        onShowHoverHighlight: (bool v) {
          if (mounted) setState(() => _hovered = v);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: on ? widget.onTap : null,
          child: face,
        ),
      ),
    );
  }
}

// ── Client and requirement pickers ─────────────────────────────────────────

/// "Client" select: the four client types.
class RateSetClientSelect extends StatelessWidget {
  const RateSetClientSelect({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) => _Labeled(
    label: 'Client asking to associate',
    child: AppSelect<RsClient>(
      value: model.rsClient,
      semanticLabel: 'Client asking to associate',
      items: <AppSelectItem<RsClient>>[
        for (final RsClient c in RsClient.values) (c, c.label),
      ],
      onChanged: model.setRsClient,
    ),
  );
}

/// "Also require" select: a BSS membership selector.
class RateSetRequireSelect extends StatelessWidget {
  const RateSetRequireSelect({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) => _Labeled(
    label: 'Network also requires',
    child: AppSelect<RsRequiredPhy>(
      value: model.requirePhy,
      semanticLabel: 'Network also requires',
      items: <AppSelectItem<RsRequiredPhy>>[
        for (final RsRequiredPhy p in model.requirePhyChoices) (p, p.label),
      ],
      onChanged: model.setRequirePhy,
    ),
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        child,
      ],
    );
  }
}

/// The derived minimum basic rate, one line.
class RateSetMinimumLine extends StatelessWidget {
  const RateSetMinimumLine({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RsRate? m = model.minimumBasic;
    return Semantics(
      container: true,
      label:
          'Minimum basic rate: ${m == null ? 'none, no basic rates' : '${m.mbpsLabel}, the lowest basic rate'}',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Minimum basic rate (lowest basic)',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            m == null ? 'none' : m.mbpsLabel,
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ── Verdicts ──────────────────────────────────────────────────────────────

/// Status icon and hue for a verdict (§8.13: a computed verdict, with words).
({IconData icon, Color color}) _verdictLook(
  RsAssociation a,
  AppColorScheme colors,
) {
  switch (a.verdict) {
    case RsVerdict.associates:
      return (icon: Icons.check_circle_outline, color: colors.statusSuccess);
    case RsVerdict.refusedBasicRates:
    case RsVerdict.lacksRequiredPhy:
    case RsVerdict.noRates:
      return (icon: Icons.error_outline, color: colors.statusDanger);
    case RsVerdict.otherBand:
      return (icon: Icons.info_outline, color: colors.statusInfo);
  }
}

/// The verdict sentence as displayed under its headline: the repeated
/// headline is dropped, and a line may break after each underscore so the
/// status name never breaks mid-word (REFUSED_BASIC_RATES_MISMATCH).
String verdictBody(RsAssociation a) {
  String line = rsVerdictLine(a);
  final String head = '${rsVerdictHeadline(a)}: ';
  if (line.startsWith(head)) {
    final String rest = line.substring(head.length);
    line = rest[0].toUpperCase() + rest.substring(1);
  }
  return line.replaceAll('_', '_\u200B');
}

/// The chosen client's verdict: headline with icon, then the sentence.
class RateSetVerdict extends StatelessWidget {
  const RateSetVerdict({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RsAssociation a = model.association;
    final ({IconData icon, Color color}) look = _verdictLook(a, colors);
    final double icon = PresenterMode.scaleOf(context).markerSize(20);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${a.client.label}: ${rsVerdictHeadline(a)}. ${rsVerdictLine(a)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Can a ${a.client.label} client associate?',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: <Widget>[
              Icon(look.icon, size: icon, color: look.color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  rsVerdictHeadline(a),
                  style: text.titleMedium?.copyWith(
                    color: look.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            verdictBody(a),
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// One line per client type.
class RateSetEveryClient extends StatelessWidget {
  const RateSetEveryClient({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double icon = PresenterMode.scaleOf(context).markerSize(16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Every client type',
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        for (final RsAssociation a in model.associations)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Semantics(
              container: true,
              label: '${a.client.label}: ${rsVerdictHeadline(a)}',
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _verdictLook(a, colors).icon,
                    size: icon,
                    color: _verdictLook(a, colors).color,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${a.client.label}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: rsVerdictHeadline(a)),
                          if (a.missingBasic.isNotEmpty)
                            TextSpan(
                              text: ', lacks ${rsRateList(a.missingBasic)}',
                            ),
                        ],
                      ),
                      style: text.bodySmall?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Beacon and element ────────────────────────────────────────────────────

class RateSetBeaconLines extends StatelessWidget {
  const RateSetBeaconLines({super.key, required this.model});
  final RateVsRangeModel model;

  static String hex(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RsBeacon? b = model.beacon;
    final ({List<int> supported, List<int> extended}) o =
        model.rateSet.elementOctets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          b == null
              ? 'No beacons: every rate is off.'
              : b.fromBasic
              ? 'Beacons go at ${b.rate.mbpsLabel}, the lowest basic rate. '
                    'The standard asks only for one of the basic rates; the '
                    'lowest is a common vendor choice, shown here as '
                    'illustrative.'
              : 'Beacons go at ${b.rate.mbpsLabel}: with no basic rates, '
                    'the standard asks for one of the mandatory rates.',
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        if (!model.rateSet.isEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'In the beacon (bit 7 set = basic):',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          Text(
            'Supported Rates: ${o.supported.map(hex).join(' ')}',
            style: mono.inlineCode.copyWith(color: colors.textSecondary),
          ),
          if (o.extended.isNotEmpty)
            Text(
              'Extended Supported Rates: ${o.extended.map(hex).join(' ')}',
              style: mono.inlineCode.copyWith(color: colors.textSecondary),
            ),
        ],
      ],
    );
  }
}

// ── ACK table ─────────────────────────────────────────────────────────────

/// "ACK to a frame sent at X": one row per rate that is on, then HE MCS 0
/// to 11 for a Wi-Fi 6 client.
class RateSetAckTable extends StatelessWidget {
  const RateSetAckTable({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<RsControlResponse> rows = model.ackTable;
    TextStyle cell([Color? c]) =>
        mono.inlineCode.copyWith(color: c ?? colors.textPrimary);
    final bool anyReading = rows.any(
      (RsControlResponse r) => r.classFilterDecided,
    );
    final bool anyHe = rows.any((RsControlResponse r) => r.eliciting.isHe);

    Widget row(RsControlResponse r) {
      final String note = <String>[
        r.fromBasic ? 'basic' : 'mandatory',
        if (r.classFilterDecided) 'model*',
      ].join(', ');
      return Semantics(
        container: true,
        label:
            'ACK to a frame sent at ${r.eliciting.label}'
            '${r.eliciting.isHe ? ' (${r.eliciting.modulation} ${r.eliciting.codeRate}, reference ${RvrFormat.n(r.eliciting.compareMbps, 0)} Mbps)' : ''}: '
            '${r.rate.mbpsLabel}, ${r.fromBasic ? 'a basic rate' : 'no basic rate fits, so the mandatory fallback'}'
            '${r.classFilterDecided ? ', the model\'s reading' : ''}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Row(
            children: <Widget>[
              Expanded(flex: 5, child: Text(r.eliciting.label, style: cell())),
              Expanded(
                flex: 4,
                child: Text(r.rate.mbpsLabel, style: cell(colors.textAccent)),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  note,
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      return Text(
        'No rates are on, so nothing is sent and nothing is acknowledged.',
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      );
    }
    final List<RsControlResponse> legacy = <RsControlResponse>[
      for (final RsControlResponse r in rows)
        if (!r.eliciting.isHe) r,
    ];
    final List<RsControlResponse> he = <RsControlResponse>[
      for (final RsControlResponse r in rows)
        if (r.eliciting.isHe) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 5,
                child: Text(
                  'Frame sent at',
                  style: text.labelSmall?.copyWith(color: colors.textTertiary),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  'ACK at',
                  style: text.labelSmall?.copyWith(color: colors.textTertiary),
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  'From',
                  style: text.labelSmall?.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
        ),
        for (final RsControlResponse r in legacy) row(r),
        if (anyHe) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Wi-Fi 6 (HE) frames: the MCS converts to a non-HT reference '
            'rate first (802.11-2024 10.6.11), and the ACK goes in OFDM, the '
            'model\'s reading.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          for (final RsControlResponse r in he) row(r),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The ACK goes at the highest basic rate not faster than the frame '
          'it answers, in the same modulation; if none fits, at the highest '
          'mandatory rate not faster (802.11-2024 10.6.6.5.2). The minimum '
          'basic rate is not a floor for ACKs.'
          '${anyReading ? ' * The model\'s reading: the standard does not say how to settle the rate rule against the modulation rule; the model keeps the modulation.' : ''}',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

// ── The card (phone and desktop) ──────────────────────────────────────────

/// Everything the rate set decides, in one card below the client readouts.
class RateSetReadouts extends StatelessWidget {
  const RateSetReadouts({super.key, required this.model});
  final RateVsRangeModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => RvrCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const RvrSectionLabel('Rate set: who can associate'),
            const SizedBox(height: AppSpacing.xs),
            RateSetVerdict(model: model),
            const SizedBox(height: AppSpacing.sm),
            RateSetEveryClient(model: model),
            const SizedBox(height: AppSpacing.sm),
            RateSetBeaconLines(model: model),
            const SizedBox(height: AppSpacing.sm),
            const RvrSectionLabel('ACK to a frame sent at X'),
            const SizedBox(height: AppSpacing.xxs),
            RateSetAckTable(model: model),
          ],
        ),
      ),
    );
  }
}
