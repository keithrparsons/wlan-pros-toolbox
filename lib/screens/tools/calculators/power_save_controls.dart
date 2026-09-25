// PowerSaveControls: the inputs-and-readouts half of Power Save.
//
// Takes the shared PowerSaveController and a set of parts to show, so the
// phone layout can put the readouts right under the stage and the setup
// cards after them, while a presenter layout shows every part in one column
// beside the stage. No part draws the timeline; PowerSaveStage owns it.
//
// Control types follow GL-003 §8.14: two-option choices are AppToggles,
// longer lists are Selects, bounded integers are sliders, and the TWT
// mantissa (a 16-bit field) is a numeric text field with its error in
// words. Status hues are verdicts only (§8.13 rule 6): amber, with the word
// "missed" and an icon, for group frames sent while the client dozed; amber
// for TWT values that cannot run. Lime marks the measured quantities (time
// awake and the battery estimate).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/power_save_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'power_save_controller.dart';
import 'power_save_parts.dart';

/// The groups PowerSaveControls can show.
enum PsControlPart {
  /// Awake share, current, battery, latency, per mode.
  readouts,

  /// Mode and comparison.
  mode,

  /// Beacon interval and DTIM period.
  ap,

  /// Listen interval and U-APSD.
  client,

  /// TWT fields.
  twt,

  /// Traffic pattern.
  traffic,

  /// Currents, battery, and the vendor example.
  energy,
}

class PowerSaveControls extends StatelessWidget {
  const PowerSaveControls({
    super.key,
    required this.controller,
    this.parts = const <PsControlPart>{
      PsControlPart.readouts,
      PsControlPart.mode,
      PsControlPart.ap,
      PsControlPart.client,
      PsControlPart.twt,
      PsControlPart.traffic,
      PsControlPart.energy,
    },
  });

  final PowerSaveController controller;
  final Set<PsControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final PowerSaveController c = controller;
        final List<Widget> cards = <Widget>[
          if (parts.contains(PsControlPart.readouts)) _ReadoutsCard(c),
          if (parts.contains(PsControlPart.mode)) _ModeCard(c),
          if (parts.contains(PsControlPart.ap)) _ApCard(c),
          if (parts.contains(PsControlPart.client)) _ClientCard(c),
          if (parts.contains(PsControlPart.twt)) _TwtCard(c),
          if (parts.contains(PsControlPart.traffic)) _TrafficCard(c),
          if (parts.contains(PsControlPart.energy)) _EnergyCard(c),
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

// ── Readouts ────────────────────────────────────────────────────────────────

/// One value cell: text, and optionally a verdict hue with its icon.
class _Cell {
  const _Cell(this.text, {this.emphasize = false, this.warning = false});

  final String text;
  final bool emphasize;
  final bool warning;
}

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final List<PsRun> runs = c.runs;
    final String span = fmtUs(c.config.horizonUs.toDouble());

    List<_Cell> row(_Cell Function(PsRun r) f) => <_Cell>[
      for (final PsRun r in runs) f(r),
    ];

    _Cell latency(LatencyStats s, bool worst, String none) {
      if (s.count == 0) return _Cell(none);
      return _Cell(fmtUs(worst ? s.worstUs! : s.meanUs!));
    }

    final List<(String, List<_Cell>)> rows = <(String, List<_Cell>)>[
      (
        'Time awake',
        row((PsRun r) => _Cell(fmtPct(r.awakeFraction), emphasize: true)),
      ),
      (
        'Wakes per second',
        row(
          (PsRun r) =>
              _Cell((r.wakeCount / (r.horizonUs / 1e6)).toStringAsFixed(1)),
        ),
      ),
      (
        'Beacons heard (of ${runs.first.beacons.length})',
        row((PsRun r) => _Cell('${r.beaconsHeard}')),
      ),
      ('Average current', row((PsRun r) => _Cell(fmtCurrent(r.averageMa)))),
      (
        'Battery life (estimate)',
        row((PsRun r) => _Cell(fmtLife(r.batteryLifeHours), emphasize: true)),
      ),
      (
        'Downlink latency, mean',
        row((PsRun r) => latency(r.downlink, false, 'No downlink')),
      ),
      (
        'Downlink latency, worst',
        row((PsRun r) => latency(r.downlink, true, 'No downlink')),
      ),
      (
        'Group frames, worst wait',
        row((PsRun r) => latency(r.group, true, 'None heard')),
      ),
      (
        'Group frames missed',
        row(
          (PsRun r) => r.groupMissed == 0
              ? const _Cell('None')
              : _Cell('${r.groupMissed} missed', warning: true),
        ),
      ),
      (
        'Uplink latency, worst',
        row((PsRun r) => latency(r.uplink, true, 'No uplink')),
      ),
      if (runs.any((PsRun r) => r.downlinkWaiting > 0))
        (
          'Downlink still held at the end',
          row((PsRun r) => _Cell('${r.downlinkWaiting}')),
        ),
    ];

    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PsSectionLabel('Over the whole $span run'),
          const SizedBox(height: AppSpacing.xs),
          _Table(
            headers: <String>[for (final PsRun r in runs) r.mode.short],
            rows: rows,
          ),
          const SizedBox(height: AppSpacing.xs),
          PsHint(
            'Battery life is an estimate: capacity divided by the average '
            'current. It ignores self-discharge, temperature, retries and '
            'everything the device does besides Wi-Fi. Latency is from the '
            'frame reaching the AP (or, uplink, being ready to send) to its '
            'delivery.',
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.headers, required this.rows});

  final List<String> headers;
  final List<(String, List<_Cell>)> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final int valueFlex = headers.length == 1 ? 6 : 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (headers.length > 1)
          ExcludeSemantics(
            child: Row(
              children: <Widget>[
                const Spacer(flex: 5),
                for (final String h in headers) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    flex: valueFlex,
                    child: Text(
                      h,
                      style: text.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        for (final (String label, List<_Cell> cells) in rows)
          Semantics(
            label:
                '$label: ${<String>[for (int i = 0; i < cells.length; i++) '${headers.length > 1 ? '${headers[i]} ' : ''}${cells[i].text}'].join(', ')}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Text(
                      label,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  for (final _Cell cell in cells) ...<Widget>[
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      flex: valueFlex,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (cell.warning) ...<Widget>[
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: colors.statusWarning,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                          ],
                          Expanded(
                            child: Text(
                              cell.text,
                              style: mono.inlineCode.copyWith(
                                color: cell.warning
                                    ? colors.statusWarning
                                    : cell.emphasize
                                    ? colors.textAccent
                                    : colors.textPrimary,
                                fontWeight: cell.emphasize
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Mode ────────────────────────────────────────────────────────────────────

String _modeDescription(PsMode m) => switch (m) {
  PsMode.awake =>
    'The radio never dozes. Frames arrive at once, and the battery pays for '
        'every moment.',
  PsMode.legacy =>
    'The client dozes, wakes for beacons, and reads the TIM. If the AP holds '
        'frames for it, it sends one PS-Poll per frame.',
  PsMode.uapsd =>
    'Like legacy PS, but on its U-APSD access categories one trigger frame '
        '(or any uplink frame) opens a service period and the AP sends up to '
        'Max SP Length frames.',
  PsMode.twt =>
    'Client and AP agree a wake schedule. The client wakes only for its '
        'service periods and can sleep through beacons entirely.',
};

class _ModeCard extends StatelessWidget {
  const _ModeCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final PsMode m = c.config.mode;
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('Power save mode'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Mode',
            semanticLabel: 'Power save mode',
            field: AppSelect<PsMode>(
              value: m,
              semanticLabel: 'Power save mode',
              items: <AppSelectItem<PsMode>>[
                for (final PsMode p in PsMode.values) (p, p.label),
              ],
              onChanged: (PsMode p) => c.mode = p,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          PsHint(_modeDescription(m)),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Compare with',
            semanticLabel: 'Compare with another mode',
            field: AppSelect<PsMode?>(
              value: c.compare,
              semanticLabel: 'Compare with another mode',
              items: <AppSelectItem<PsMode?>>[
                (null, 'Nothing'),
                for (final PsMode p in PsMode.values)
                  if (p != m) (p, p.label),
              ],
              onChanged: (PsMode? p) => c.compare = p,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const PsHint(
            'Both modes run the same traffic, beacons and currents.',
          ),
        ],
      ),
    );
  }
}

// ── AP ──────────────────────────────────────────────────────────────────────

const List<int> _kBeaconChoices = <int>[50, 100, 200, 300, 500, 1000];

class _ApCard extends StatelessWidget {
  const _ApCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final PsConfig cfg = c.config;
    final double dtimMs = tuToMs(cfg.beaconTu * cfg.dtimPeriod);
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('The AP'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Beacon interval',
            semanticLabel: 'Beacon interval',
            field: AppSelect<int>(
              value: cfg.beaconTu,
              semanticLabel: 'Beacon interval',
              items: <AppSelectItem<int>>[
                for (final int tu in _kBeaconChoices)
                  (
                    tu,
                    '$tu TU (${tuToMs(tu).toStringAsFixed(1)} ms)'
                        '${tu == 100 ? ', the common default' : ''}',
                  ),
              ],
              onChanged: (int v) => c.beaconTu = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const PsHint(
            '100 TU is the usual default, not a rule; the AP may use any '
            'interval.',
          ),
          const SizedBox(height: AppSpacing.sm),
          PsSlider(
            label: 'DTIM period',
            valueText: '${cfg.dtimPeriod} (${dtimMs.toStringAsFixed(1)} ms)',
            value: cfg.dtimPeriod.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (double v) => c.dtimPeriod = v.round(),
            semanticValue: (double v) =>
                'every ${v.round()} beacons, '
                '${tuToMs(cfg.beaconTu * v.round()).toStringAsFixed(1)} '
                'milliseconds',
          ),
          PsHint(
            'Broadcast and multicast frames wait for a DTIM beacon. A longer '
            'DTIM lets a client sleep longer and makes those frames wait up '
            'to ${fmtUs(groupLatencyBoundUs(cfg.beaconTu, cfg.dtimPeriod))} '
            'here.',
          ),
        ],
      ),
    );
  }
}

// ── Client: listen interval and U-APSD ──────────────────────────────────────

class _ClientCard extends StatelessWidget {
  const _ClientCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PsConfig cfg = c.config;
    final int li = cfg.listenInterval;
    final int d = cfg.dtimPeriod;
    final bool aligned = li % d == 0 || d % li == 0;
    // Wakes per lcm(li, d) beacons: multiples of li or d.
    int gcd(int a, int b) => b == 0 ? a : gcd(b, a % b);
    final int lcm = li * d ~/ gcd(li, d);
    final int wakes = lcm ~/ li + lcm ~/ d - 1;
    final int q = qosInfoByte(cfg.uapsd.acs, cfg.uapsd.maxSp);
    final String bits = q.toRadixString(2).padLeft(8, '0');
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('The client: legacy PS and U-APSD'),
          const SizedBox(height: AppSpacing.xs),
          PsSlider(
            label: 'Listen interval',
            valueText: 'every $li beacon${li == 1 ? '' : 's'}',
            value: li.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (double v) => c.listenInterval = v.round(),
            semanticValue: (double v) => 'every ${v.round()} beacons',
          ),
          PsHint(
            'The client reads the TIM on every ${li == 1 ? '' : '${li}th '}'
            'beacon and also wakes for every DTIM beacon to hear group '
            'traffic (a teaching model).',
          ),
          if (!aligned) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            PsNote(
              icon: Icons.info_outline_rounded,
              message:
                  'Listen interval $li and DTIM $d do not line up, so the '
                  'client wakes for both: $wakes of every $lcm beacons. Make '
                  'one a multiple of the other and it wakes less.',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const PsSectionLabel('U-APSD access categories'),
          for (final AccessCategory ac in AccessCategory.values)
            _AcRow(
              ac: ac,
              on: cfg.uapsd.acs.contains(ac),
              onChanged: (bool v) => c.setUapsdAc(ac, v),
            ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Max SP Length',
            semanticLabel: 'Max service period length',
            field: AppSelect<MaxSpLength>(
              value: cfg.uapsd.maxSp,
              semanticLabel: 'Max service period length',
              items: <AppSelectItem<MaxSpLength>>[
                for (final MaxSpLength m in MaxSpLength.values)
                  (m, '${m.code}: ${m.label}'),
              ],
              onChanged: (MaxSpLength m) => c.maxSp = m,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label:
                'QoS Info byte hexadecimal '
                '${q.toRadixString(16).padLeft(2, '0').toUpperCase()}',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'QoS Info  ',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  TextSpan(
                    text:
                        '0x${q.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                        '  ${bits.substring(0, 4)} ${bits.substring(4)}',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const PsHint(
            'Bits 0 to 3: VO, VI, BK, BE U-APSD flags; bits 5 and 6: Max SP '
            'Length (0 = all buffered, 1 = 2, 2 = 4, 3 = 6). A flagged AC is '
            'both trigger- and delivery-enabled. Traffic on an AC without '
            'its flag falls back to PS-Poll.',
          ),
        ],
      ),
    );
  }
}

class _AcRow extends StatelessWidget {
  const _AcRow({required this.ac, required this.on, required this.onChanged});

  final AccessCategory ac;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () => onChanged(!on),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: on,
                onChanged: (bool? v) => onChanged(v ?? false),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  '${ac.label} (${ac.code}), bit ${ac.qosInfoBit}',
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── TWT ─────────────────────────────────────────────────────────────────────

class _TwtCard extends StatelessWidget {
  const _TwtCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TwtSettings t = c.twtDraft;
    final String? error = c.twtError;
    final int? interval = t.intervalUs;
    final int? dur = t.durationUs;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('Target Wake Time'),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<TwtKind>(
            label: 'Agreement',
            semanticLabel: 'TWT agreement',
            value: t.kind,
            expand: true,
            items: <AppToggleItem<TwtKind>>[
              for (final TwtKind k in TwtKind.values) (k, k.label),
            ],
            onChanged: (TwtKind k) => c.twtKind = k,
          ),
          const SizedBox(height: AppSpacing.xxs),
          PsHint(
            t.kind == TwtKind.individual
                ? 'Individual: this client and the AP agree its own schedule.'
                : 'Broadcast: the AP announces one schedule in its beacons for '
                      'a group of clients. Here each service period starts '
                      'at a beacon (interval rounded up to whole beacons), '
                      'and the client wakes for that beacon.',
          ),
          const SizedBox(height: AppSpacing.sm),
          _MantissaField(controller: c),
          const SizedBox(height: AppSpacing.xs),
          PsSlider(
            label: 'Wake interval exponent',
            valueText: '${t.exponent}',
            value: t.exponent.toDouble(),
            min: 0,
            max: kTwtExponentMax.toDouble(),
            divisions: kTwtExponentMax,
            onChanged: (double v) => c.twtExponent = v.round(),
            semanticValue: (double v) => '${v.round()}',
          ),
          Semantics(
            label: interval == null
                ? 'Wake interval: not valid'
                : 'Wake interval ${fmtUs(interval.toDouble())}',
            excludeSemantics: true,
            child: Text(
              '${c.mantissaText.isEmpty ? '?' : c.mantissaText} x '
              '2^${t.exponent} µs = '
              '${interval == null ? '?' : fmtUs(interval.toDouble())}',
              style: mono.inlineCode.copyWith(color: colors.textAccent),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: PsOutlineButton(
                  icon: Icons.timer_outlined,
                  label: '1 s',
                  semanticLabel: 'Set a 1 second wake interval, 62500 x 2^4',
                  onPressed: () => c.twtPreset(62500, 4),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: PsOutlineButton(
                  icon: Icons.timer_outlined,
                  label: '30 s',
                  semanticLabel: 'Set a 30 second wake interval, 58594 x 2^9',
                  onPressed: () => c.twtPreset(58594, 9),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PsSlider(
            label: 'Minimum wake duration',
            valueText:
                '${t.duration} x ${t.durationUnit.label} = '
                '${dur == null ? '?' : fmtUs(dur.toDouble())}',
            value: t.duration.toDouble(),
            min: 1,
            max: kTwtDurationMax.toDouble(),
            divisions: kTwtDurationMax - 1,
            onChanged: (double v) => c.twtDuration = v.round(),
            semanticValue: (double v) =>
                '${v.round()} units, '
                '${fmtUs(v.round() * t.durationUnit.us.toDouble())}',
          ),
          AppToggle<TwtDurationUnit>(
            label: 'Duration unit',
            semanticLabel: 'Wake duration unit',
            value: t.durationUnit,
            expand: true,
            items: <AppToggleItem<TwtDurationUnit>>[
              for (final TwtDurationUnit u in TwtDurationUnit.values)
                (u, u.label),
            ],
            onChanged: (TwtDurationUnit u) => c.twtDurationUnit = u,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<bool>(
            label: 'Beacons',
            semanticLabel: 'TWT client and beacons',
            value: t.wakeForDtim,
            expand: true,
            items: const <AppToggleItem<bool>>[
              (false, 'Sleep through'),
              (true, 'Wake for DTIM'),
            ],
            onChanged: (bool v) => c.twtWakeForDtim = v,
          ),
          const SizedBox(height: AppSpacing.xxs),
          PsHint(
            t.wakeForDtim
                ? 'The client also wakes for every DTIM beacon to hear '
                      'broadcast and multicast frames.'
                : 'The client skips every beacon it can. Broadcast and '
                      'multicast frames sent after a DTIM go by while it '
                      'dozes.',
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            PsNote(
              icon: Icons.error_outline_rounded,
              color: colors.statusWarning,
              message:
                  '$error The timeline and readouts keep the last TWT values '
                  'that worked.',
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          const PsHint(
            'Fields: mantissa 16 bits (0 to 65535), exponent 5 bits (0 to '
            '31), wake duration one octet (0 to 255) in units of 256 µs or '
            '1 TU. This simulator runs intervals up to 5 minutes.',
          ),
        ],
      ),
    );
  }
}

/// The mantissa as a numeric field. Keeps its own text controller, synced
/// from the shared controller when a preset changes the value.
class _MantissaField extends StatefulWidget {
  const _MantissaField({required this.controller});

  final PowerSaveController controller;

  @override
  State<_MantissaField> createState() => _MantissaFieldState();
}

class _MantissaFieldState extends State<_MantissaField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.mantissaText,
  );

  @override
  void didUpdateWidget(covariant _MantissaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final String want = widget.controller.mantissaText;
    if (_text.text != want) {
      _text.value = TextEditingValue(
        text: want,
        selection: TextSelection.collapsed(offset: want.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return LabeledField(
      label: 'Wake interval mantissa',
      semanticLabel: 'TWT wake interval mantissa, 0 to 65535',
      field: TextField(
        key: const ValueKey<String>('twt-mantissa'),
        controller: _text,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        onChanged: widget.controller.setMantissaText,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: mono.outputLarge.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: colors.textAccent,
        decoration: InputDecoration(
          hintText: 'e.g. 62500',
          errorText: widget.controller.mantissaError,
          errorMaxLines: 3,
        ),
      ),
    );
  }
}

// ── Traffic ─────────────────────────────────────────────────────────────────

const List<double> _kDlRates = <double>[0, 0.02, 0.1, 0.5, 1, 5, 50];
const List<int> _kBurstSizes = <int>[1, 4, 16];
const List<double> _kUlRates = <double>[0, 0.1, 0.5, 1, 50];
const List<double> _kGroupRates = <double>[0, 0.5, 2, 10, 20];

String _rate(double r) {
  if (r == 0) return 'None';
  if (r < 1) return 'One every ${(1 / r).toStringAsFixed(0)} s';
  return '${r.toStringAsFixed(0)} per second';
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final TrafficSettings t = c.config.traffic;
    final PsScenario s = c.scenario;
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('Traffic'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Pattern',
            semanticLabel: 'Traffic pattern',
            field: AppSelect<PsScenario>(
              value: s,
              semanticLabel: 'Traffic pattern',
              items: <AppSelectItem<PsScenario>>[
                for (final PsScenario p in PsScenario.values)
                  if (p != PsScenario.custom || s == PsScenario.custom)
                    (p, p.label),
              ],
              onChanged: (PsScenario p) => c.scenario = p,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          PsHint(s.description),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Downlink bursts',
            semanticLabel: 'Downlink bursts arriving at the AP',
            field: AppSelect<double>(
              value: t.dlBurstsPerS,
              semanticLabel: 'Downlink bursts arriving at the AP',
              items: <AppSelectItem<double>>[
                for (final double r in _kDlRates) (r, _rate(r)),
              ],
              onChanged: (double v) => c.dlBurstsPerS = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Frames per burst',
            semanticLabel: 'Frames per downlink burst',
            field: AppSelect<int>(
              value: t.dlBurstSize,
              semanticLabel: 'Frames per downlink burst',
              items: <AppSelectItem<int>>[
                for (final int n in _kBurstSizes) (n, '$n'),
              ],
              onChanged: (int v) => c.dlBurstSize = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Uplink frames',
            semanticLabel: 'Uplink frames from the client',
            field: AppSelect<double>(
              value: t.ulPerS,
              semanticLabel: 'Uplink frames from the client',
              items: <AppSelectItem<double>>[
                for (final double r in _kUlRates) (r, _rate(r)),
              ],
              onChanged: (double v) => c.ulPerS = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Broadcast and multicast',
            semanticLabel: 'Group-addressed frames',
            field: AppSelect<double>(
              value: t.groupPerS,
              semanticLabel: 'Group-addressed frames',
              items: <AppSelectItem<double>>[
                for (final double r in _kGroupRates) (r, _rate(r)),
              ],
              onChanged: (double v) => c.groupPerS = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Access category',
            semanticLabel: 'Access category of the unicast traffic',
            field: AppSelect<AccessCategory>(
              value: t.ac,
              semanticLabel: 'Access category of the unicast traffic',
              items: <AppSelectItem<AccessCategory>>[
                for (final AccessCategory a in AccessCategory.values)
                  (a, '${a.label} (${a.code})'),
              ],
              onChanged: (AccessCategory a) => c.trafficAc = a,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<bool>(
            label: 'Arrivals',
            semanticLabel: 'Arrival timing',
            value: t.regular,
            expand: true,
            items: const <AppToggleItem<bool>>[
              (true, 'Regular'),
              (false, 'Random'),
            ],
            onChanged: (bool v) => c.regular = v,
          ),
          const SizedBox(height: AppSpacing.xs),
          PsOutlineButton(
            icon: Icons.shuffle_rounded,
            label: 'New random pattern',
            semanticLabel: 'New random arrival pattern',
            onPressed: t.regular ? null : c.newRandomPattern,
          ),
          const SizedBox(height: AppSpacing.xxs),
          PsHint(
            t.regular
                ? 'Regular arrivals are evenly spaced, so there is no random '
                      'pattern to change.'
                : 'Random arrivals follow a fixed seed, so the same settings '
                      'give the same run.',
          ),
        ],
      ),
    );
  }
}

// ── Energy ──────────────────────────────────────────────────────────────────

const List<double> _kAwakeMa = <double>[20, 50, 100, 200];
const List<double> _kDozeMa = <double>[0.005, 0.02, 0.05, 0.2];
const List<double> _kBatteryMah = <double>[250, 1000, 3000, 10000];

class _EnergyCard extends StatelessWidget {
  const _EnergyCard(this.c);

  final PowerSaveController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PsConfig cfg = c.config;
    return PsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PsSectionLabel('Currents and battery'),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Awake current',
            semanticLabel: 'Awake current',
            field: AppSelect<double>(
              value: cfg.awakeMa,
              semanticLabel: 'Awake current',
              items: <AppSelectItem<double>>[
                for (final double v in _kAwakeMa) (v, fmtCurrent(v)),
              ],
              onChanged: (double v) => c.awakeMa = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Doze current',
            semanticLabel: 'Doze current',
            field: AppSelect<double>(
              value: cfg.dozeMa,
              semanticLabel: 'Doze current',
              items: <AppSelectItem<double>>[
                for (final double v in _kDozeMa) (v, fmtCurrent(v)),
              ],
              onChanged: (double v) => c.dozeMa = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Battery',
            semanticLabel: 'Battery capacity',
            field: AppSelect<double>(
              value: cfg.batteryMah,
              semanticLabel: 'Battery capacity',
              items: <AppSelectItem<double>>[
                for (final double v in _kBatteryMah)
                  (v, '${v.toStringAsFixed(0)} mAh'),
              ],
              onChanged: (double v) => c.batteryMah = v,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const PsHint(
            'These currents are parameters for the arithmetic, not '
            'measurements of any device. Use the figures from your own '
            'device if you have them. Average current = awake share x awake '
            'current + doze share x doze current.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const PsSectionLabel(
                  'One vendor example, not a general figure',
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Silicon Labs SiWx917, tested by Novus Labs in a study '
                  'Silicon Labs commissioned: about 90 µA average at DTIM '
                  '10 on a clean channel, and 49 µA with a 30 s TWT, about '
                  '45% less. Silicon Labs projects roughly 5 years on 4 '
                  'lithium AA cells.',
                  style: text.bodySmall?.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                const PsHint(
                  'One chip, one test, paid for by the vendor. Other '
                  'devices, channels and traffic give other numbers. The '
                  'simulator does not use these figures.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
