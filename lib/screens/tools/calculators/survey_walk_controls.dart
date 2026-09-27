// SurveyWalkControls: the inputs-and-readouts half of the Survey Walk.
//
// Takes the shared SurveyWalkController and a set of parts to show, so the
// phone layout can put playback, the opening question and the readouts
// right under the stage and the setup cards after them, while a presenter
// layout shows the most-used inputs in one column beside the stage and folds
// the rest into PresenterDisclosures. No part draws a plot.
//
// Control types follow GL-003 §8.14: device, channel set, path, the shown
// channel and playback speed are Selects; survey type, capture method,
// hopping algorithm and timestamp mode are AppToggles (2 or 3 options).
// Status hues are verdicts only (§8.13 rule 6): the Rule 4 pass or fail,
// always with its word and an icon.
//
// ACRONYMS (Keith's standing rule): spelled out on first use in each
// surface: network interface card (NIC), Preferred Scanning Channel (PSC).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/survey_walk_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../labeled_field.dart';
import 'roaming_walk_parts.dart';
import 'survey_walk_controller.dart';

/// The groups SurveyWalkControls can show.
enum SurveyControlPart {
  /// Play, pause, step, restart, scrub and speed.
  transport,

  /// "Does walking speed matter?" and its reveal.
  question,

  /// Rule 4, revisit and spacing, gaps, samples, position error, and the
  /// active-survey limits when Active is chosen.
  readouts,

  /// Survey type, capture method, timestamps, the door pause.
  survey,

  /// Device (NIC count), channel set, dwell, switch, hopping algorithm.
  scanner,

  /// Path, pace and guess range.
  walker,

  /// Which channel is shown, the signal layer.
  view,
}

const Set<SurveyControlPart> kAllSurveyParts = <SurveyControlPart>{
  SurveyControlPart.transport,
  SurveyControlPart.question,
  SurveyControlPart.readouts,
  SurveyControlPart.survey,
  SurveyControlPart.scanner,
  SurveyControlPart.walker,
  SurveyControlPart.view,
};

class SurveyWalkControls extends StatelessWidget {
  const SurveyWalkControls({
    super.key,
    required this.controller,
    this.parts = kAllSurveyParts,
  });

  final SurveyWalkController controller;
  final Set<SurveyControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final SurveyWalkController c = controller;
        if (PresenterMode.isActive(context)) return _PresenterPanel(c);
        final bool active = c.config.effectiveType == SurveyType.active;
        final List<Widget> cards = <Widget>[
          if (parts.contains(SurveyControlPart.transport)) _TransportCard(c),
          if (parts.contains(SurveyControlPart.question)) _QuestionCard(c),
          if (parts.contains(SurveyControlPart.readouts)) ...<Widget>[
            if (active) const SurveyActiveLimitsCard(),
            _ReadoutsCard(c),
          ],
          if (parts.contains(SurveyControlPart.survey)) _SurveyCard(c),
          if (parts.contains(SurveyControlPart.scanner)) _ScannerCard(c),
          if (parts.contains(SurveyControlPart.walker)) _WalkerCard(c),
          if (parts.contains(SurveyControlPart.view)) _ViewCard(c),
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

// ── Presenter panel ─────────────────────────────────────────────────────────

class _PresenterPanel extends StatelessWidget {
  const _PresenterPanel(this.c);

  final SurveyWalkController c;

  @override
  Widget build(BuildContext context) {
    // Active: the five limits sit on the stage, in place of the strip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TransportCard(c),
        const SizedBox(height: AppSpacing.xs),
        RwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _surveyTypeToggle(context, c),
              const SizedBox(height: AppSpacing.xs),
              _deviceSelect(c),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: <Widget>[
                  Expanded(child: _paceSlider(c, short: true)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _guessSlider(c, short: true)),
                ],
              ),
            ],
          ),
        ),
        PresenterDisclosure(
          title: 'Opening question',
          children: <Widget>[_QuestionCard(c)],
        ),
        PresenterDisclosure(
          title: 'Readouts: revisit, spacing, gaps, error',
          children: <Widget>[_ReadoutsCard(c)],
        ),
        PresenterDisclosure(
          title: 'Capture method, timestamps and the door',
          children: <Widget>[_SurveyCard(c, withType: false)],
        ),
        PresenterDisclosure(
          title: 'Scanner: channels, dwell and hopping',
          children: <Widget>[_ScannerCard(c, withDevice: false)],
        ),
        PresenterDisclosure(
          title: 'Path and view',
          children: <Widget>[
            _WalkerCard(c, withSliders: false),
            const SizedBox(height: AppSpacing.xs),
            _ViewCard(c),
          ],
        ),
      ],
    );
  }
}

// ── Transport ───────────────────────────────────────────────────────────────

class _TransportCard extends StatelessWidget {
  const _TransportCard(this.c);

  final SurveyWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final double dur = c.result.durationS;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: c.drawing ? null : c.togglePlay,
                  icon: Icon(
                    c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    c.playing
                        ? 'Pause'
                        : c.atEnd
                        ? 'Walk again'
                        : 'Walk',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    disabledBackgroundColor: colors.disabledFill,
                    disabledForegroundColor: colors.textDisabled,
                    minimumSize: const Size.fromHeight(
                      AppSpacing.minTouchTarget,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                flex: 2,
                child: RwOutlineButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Step',
                  semanticLabel: 'Step the walk forward one second',
                  onPressed: c.atEnd || c.drawing ? null : c.step,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                onPressed: c.atStart ? null : c.restart,
                tooltip: 'Back to the start of the walk (R)',
                icon: const Icon(Icons.restart_alt_rounded),
                color: colors.textAccent,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: RwSlider(
                  label: 'Walk time',
                  valueText:
                      '${c.timeS.toStringAsFixed(1)} of '
                      '${dur.toStringAsFixed(1)} s',
                  value: c.timeS,
                  min: 0,
                  max: dur,
                  divisions: (dur * 10).round().clamp(1, 100000),
                  onChanged: c.seek,
                  semanticValue: (double v) =>
                      '${v.toStringAsFixed(1)} of ${dur.toStringAsFixed(1)} '
                      'seconds',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: 120,
                child: AppSelect<SurveyPlaySpeed>(
                  value: c.speed,
                  semanticLabel: 'Playback speed',
                  items: <AppSelectItem<SurveyPlaySpeed>>[
                    for (final SurveyPlaySpeed s in SurveyPlaySpeed.values)
                      (s, s == SurveyPlaySpeed.x1 ? '1x' : s.label),
                  ],
                  onChanged: (SurveyPlaySpeed s) => c.speed = s,
                ),
              ),
            ],
          ),
          if (reducedMotion)
            Text(
              'Reduced motion is on: nothing moves until you press Walk.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

// ── Predict, then reveal ────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  const _QuestionCard(this.c);

  final SurveyWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SurveyWalkResult r = c.result;
    final SurveyWalkConfig cfg = c.config;
    final double pace = cfg.paceMps;
    final double lo = coherenceTimeMs(RoamBand.b6, pace);
    final double hi = coherenceTimeMs(RoamBand.b24, pace);
    final double revisit = r.ruleRevisitS;
    final SurveyPrediction? p = c.prediction;

    Widget choice(SurveyPrediction v, String label) => Expanded(
      child: Semantics(
        selected: p == v,
        child: OutlinedButton(
          onPressed: () => c.prediction = v,
          style: OutlinedButton.styleFrom(
            foregroundColor: p == v ? colors.onPrimary : colors.textAccent,
            backgroundColor: p == v ? colors.primary : null,
            side: BorderSide(
              color: p == v ? colors.primary : colors.borderStrong,
              width: colors.isLight ? 1.5 : 1,
            ),
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );

    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('Predict, then walk'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'RF (radio frequency) energy travels at the speed of light, so '
            'does walking speed matter?',
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              choice(SurveyPrediction.matters, 'Yes, it matters'),
              const SizedBox(width: AppSpacing.xs),
              choice(SurveyPrediction.doesNotMatter, 'No, light is too fast'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!c.revealed)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'The answer appears after the first full walk.',
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
                TextButton(
                  onPressed: c.reveal,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                  child: const Text('Reveal now'),
                ),
              ],
            )
          else
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    p == null
                        ? 'Both answers are half right.'
                        : p == SurveyPrediction.matters
                        ? 'Right, and not because of light.'
                        : 'Half right: the radio wave does not care, but the '
                              'scanner does.',
                    style: text.bodyLarge?.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Walking never distorts a measurement. At '
                    '${fmtPace(pace, UnitSystemScope.systemOf(context))} the channel holds still '
                    'for ${lo.toStringAsFixed(0)} to ${hi.toStringAsFixed(0)} '
                    'ms, and the longest Wi-Fi frame lasts '
                    '${kLongestPpduMs.toStringAsFixed(3)} ms.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Walking speed sets the spacing. Each channel is visited '
                    'once every ${fmtS(revisit)}, so its samples land '
                    '${fmtM(sampleSpacingM(pace, revisit), UnitSystemScope.systemOf(context))} apart at '
                    '${fmtPace(pace, UnitSystemScope.systemOf(context))}. With a '
                    '${fmtM(cfg.guessRangeM, UnitSystemScope.systemOf(context))} guess range that is a Rule 4 '
                    '${r.rule4Pass ? 'pass' : 'fail'}.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: c.askAgain,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textAccent,
                        minimumSize: const Size(0, AppSpacing.minTouchTarget),
                      ),
                      child: const Text('Ask again'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Active limits ───────────────────────────────────────────────────────────

/// Keith's five limits of an active survey (2026-09-26), in plain words.
const List<String> kActiveSurveyLimits = <String>[
  'One client: it measures what this one adapter gets, not what any other '
      'client would get.',
  'One point in time: the results hold for the moment of the walk.',
  'One walking path: roams happen where this walk made them happen.',
  'One set of other traffic: whatever else was on the air during the walk.',
  'A single AP at a time: it sees only the AP it is associated with.',
];

/// The same five limits in a few words each, for the presenter stage.
const List<String> kActiveSurveyLimitsShort = <String>[
  'One client',
  'One point in time',
  'One walking path',
  'One set of other traffic',
  'A single AP at a time',
];

/// Keith's five limits of an active survey. [compact] is the presenter
/// stage form: the summary sentence and the five short labels.
class SurveyActiveLimitsCard extends StatelessWidget {
  const SurveyActiveLimitsCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('What an active survey cannot show'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'An active survey shows where one client, at one point in time, '
            'on one walking path, with one set of other traffic, roams. It '
            'does not show where or how other clients will connect.',
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (compact)
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final String l in kActiveSurveyLimitsShort)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ExcludeSemantics(
                        child: Icon(
                          Icons.remove_rounded,
                          size: 16,
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        l,
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          else
            for (final String l in kActiveSurveyLimits)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: RwNote(icon: Icons.remove_rounded, message: l),
              ),
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard(this.c);

  final SurveyWalkController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final SurveyWalkResult r = c.result;
    final SurveyWalkConfig cfg = c.config;
    final ScanSchedule? sch = r.schedule;
    final double pace = cfg.paceMps;
    final bool pass = r.rule4Pass;
    final int? ch = c.shownIndex;

    final List<Widget> rows = <Widget>[
      RwRow(
        label: 'Longest allowed revisit (guess range / pace)',
        value:
            '${fmtS(r.maxAllowedRevisit)} = ${fmtM(cfg.guessRangeM, UnitSystemScope.systemOf(context))} / '
            '${fmtPace(pace, UnitSystemScope.systemOf(context))}',
      ),
      RwRow(
        label: 'Rule 4: a sample at least every guess range',
        value:
            '${pass ? 'Pass' : 'Fail'}: longest revisit ${fmtS(r.ruleRevisitS)}',
        valueColor: pass ? colors.statusSuccess : colors.statusDanger,
        icon: pass
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      ),
    ];
    if (sch == null) {
      rows.add(
        RwRow(
          label: 'Active test every',
          value:
              '${fmtS(kActiveTestIntervalS)}, spacing '
              '${fmtM(sampleSpacingM(pace, kActiveTestIntervalS), UnitSystemScope.systemOf(context))}',
        ),
      );
    } else if (sch.isPriority) {
      double mean(bool pri) {
        final List<double> v = <double>[
          for (int i = 0; i < sch.channels.length; i++)
            if (sch.isPriorityChannel(i) == pri) sch.revisit[i].meanS,
        ];
        return v.reduce((double a, double b) => a + b) / v.length;
      }

      for (final bool pri in <bool>[true, false]) {
        final double m = mean(pri);
        rows.add(
          RwRow(
            label: pri ? 'Priority channels' : 'Other channels',
            value:
                'revisit ${fmtS(m)}, spacing ${fmtM(sampleSpacingM(pace, m), UnitSystemScope.systemOf(context))}',
            emphasize: pri,
          ),
        );
      }
    } else {
      for (final MapEntry<RoamBand, double> e in sch.bandRevisitS.entries) {
        rows.add(
          RwRow(
            label: 'Revisit, ${e.key.label}',
            value:
                '${fmtS(e.value)}, spacing '
                '${fmtM(sampleSpacingM(pace, e.value), UnitSystemScope.systemOf(context))}',
          ),
        );
      }
    }
    if (ch != null) {
      final ChannelStats s = r.stats[ch];
      rows.addAll(<Widget>[
        RwRow(
          label: 'Shown: ch ${r.channels[ch].shortLabel}',
          value:
              '${fmtS(s.revisit.meanS)} revisit, ${fmtM(s.spacingM, UnitSystemScope.systemOf(context))} '
              'spacing, ${s.samples} samples',
          emphasize: true,
        ),
        RwRow(
          label: 'Largest gap, ch ${r.channels[ch].shortLabel}',
          value: s.largestGapM == null
              ? 'fewer than 2 samples'
              : fmtM(s.largestGapM!, UnitSystemScope.systemOf(context)),
        ),
      ]);
    }
    int lo = 1 << 30;
    int hi = 0;
    for (final ChannelStats s in r.stats) {
      if (s.samples < lo) lo = s.samples;
      if (s.samples > hi) hi = s.samples;
    }
    final double? gap = r.largestGapM;
    rows.addAll(<Widget>[
      RwRow(
        label: 'Largest gap, any channel',
        value: gap == null
            ? 'n/a'
            : fmtM(gap, UnitSystemScope.systemOf(context)),
      ),
      RwRow(
        label: 'Samples per channel',
        value: r.stats.isEmpty ? '0' : (lo == hi ? '$lo' : '$lo to $hi'),
      ),
      RwRow(
        label: 'Position error (pauses, stamping)',
        value:
            'up to ${fmtM(r.maxErrorM, UnitSystemScope.systemOf(context))}, mean ${fmtM(r.meanErrorM, UnitSystemScope.systemOf(context))}',
      ),
    ]);
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('Readouts, whole walk'),
          const SizedBox(height: AppSpacing.xxs),
          ...rows,
        ],
      ),
    );
  }
}

// ── Survey ──────────────────────────────────────────────────────────────────

Widget _surveyTypeToggle(BuildContext context, SurveyWalkController c) {
  final AppColorScheme colors = context.colors;
  final ({bool available, String? reason}) h = c.hybrid;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      LabeledField(
        label: 'Survey type',
        field: AppToggle<SurveyType>(
          value: c.config.effectiveType,
          semanticLabel: 'Survey type',
          expand: true,
          items: <AppToggleItem<SurveyType>>[
            for (final SurveyType t in SurveyType.values) (t, t.label),
          ],
          onChanged: (SurveyType t) => c.surveyType = t,
        ),
      ),
      if (!h.available)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(
            'Hybrid is not available: ${h.reason}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ),
    ],
  );
}

class _SurveyCard extends StatelessWidget {
  const _SurveyCard(this.c, {this.withType = true});

  final SurveyWalkController c;
  final bool withType;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SurveyWalkConfig cfg = c.config;
    final String captureNote = switch (cfg.capture) {
      CaptureMethod.continuous =>
        'Click at the start, every turn and the stop. Samples between two '
            'clicks are spread evenly in time, so the app assumes a steady '
            'pace.',
      CaptureMethod.line =>
        'Tap the start and end of each straight segment; the walker pauses '
            '${kLinePauseS.toStringAsFixed(0)} s between segments, not '
            'recorded.',
      CaptureMethod.stopAndGo =>
        'The walker stops at each point and the scanner completes two full '
            'cycles there (${fmtS(c.result.stopDurationS)} per stop).',
    };
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (withType) ...<Widget>[
            _surveyTypeToggle(context, c),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Passive hears every AP, neighbors included. Active joins one '
              'network and measures what one client gets. Hybrid does both '
              'and needs a radio for each job.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          LabeledField(
            label: 'Capture method',
            field: AppToggle<CaptureMethod>(
              value: cfg.capture,
              semanticLabel: 'Capture method',
              expand: true,
              items: <AppToggleItem<CaptureMethod>>[
                for (final CaptureMethod m in CaptureMethod.values)
                  (m, m.label),
              ],
              onChanged: (CaptureMethod m) => c.capture = m,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            captureNote,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          if (cfg.capture == CaptureMethod.stopAndGo)
            RwSlider(
              label: 'Stop every',
              valueText: fmtM(cfg.stopSpacingM, c.units),
              value: LengthFormat(c.units).distValue(cfg.stopSpacingM),
              min: _lo(c, kStopSpacingMin, 1),
              max: _hi(c, kStopSpacingMax, 1),
              divisions:
                  (_hi(c, kStopSpacingMax, 1) - _lo(c, kStopSpacingMin, 1))
                      .round(),
              onChanged: (double v) =>
                  c.stopSpacingM = LengthFormat(c.units).distToMetres(v),
              semanticValue: (double v) =>
                  '${v.toStringAsFixed(0)} ${LengthFormat(c.units).distUnitSpoken}',
            ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Timestamps',
            field: AppToggle<TimestampMode>(
              value: cfg.timestamp,
              semanticLabel: 'Timestamps',
              expand: true,
              items: <AppToggleItem<TimestampMode>>[
                for (final TimestampMode m in TimestampMode.values)
                  (m, m.label),
              ],
              onChanged: (TimestampMode m) => c.timestamp = m,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Per cycle gives the whole cycle one time, so early channels land '
            'up to one revisit later. Which one real products use is not '
            'published.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          RwSwitchRow(
            title: 'Pause at the door',
            subtitle:
                'The walker stops halfway along the first leg with no click.',
            value: cfg.doorPause,
            onChanged: (bool v) => c.doorPause = v,
          ),
          if (cfg.doorPause)
            RwSlider(
              label: 'Pause',
              valueText: '${cfg.doorPauseS.toStringAsFixed(0)} s',
              value: cfg.doorPauseS,
              min: kDoorPauseMin,
              max: kDoorPauseMax,
              divisions: (kDoorPauseMax - kDoorPauseMin).round(),
              onChanged: (double v) => c.doorPauseS = v,
              semanticValue: (double v) => '${v.toStringAsFixed(0)} seconds',
            ),
        ],
      ),
    );
  }
}

// ── Scanner ─────────────────────────────────────────────────────────────────

Widget _deviceSelect(SurveyWalkController c) => LabeledField(
  label: 'Data-collection device, by network interface cards (NICs)',
  semanticLabel: 'Data-collection device',
  field: AppSelect<int>(
    value: c.config.scanner.radios,
    semanticLabel: 'Data-collection device',
    items: <AppSelectItem<int>>[
      for (int n = kMinRadios; n <= kMaxRadios; n++) (n, nicPresetLabel(n)),
    ],
    onChanged: (int n) => c.radios = n,
  ),
);

class _ScannerCard extends StatelessWidget {
  const _ScannerCard(this.c, {this.withDevice = true});

  final SurveyWalkController c;
  final bool withDevice;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ScannerConfig s = c.config.scanner;
    final List<SurveyChannel> set = s.channels;
    // Channels in use on this floor, for marking priorities.
    final List<SurveyChannel> inUse = <SurveyChannel>[
      for (final SurveyChannel ch in <SurveyChannel>{
        ...kDefaultPriorityChannels,
        for (final SurveyAp ap in c.config.aps) ap.channel,
      })
        if (set.contains(ch)) ch,
    ];
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (withDevice) ...<Widget>[
            _deviceSelect(c),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The same channels and dwell on 1 to 4 radios, so only the '
              'number of NICs sharing the scan changes.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          LabeledField(
            label: 'Channels scanned',
            field: AppSelect<ChannelSetPreset>(
              value: s.channelSet,
              semanticLabel: 'Channels scanned',
              items: <AppSelectItem<ChannelSetPreset>>[
                for (final ChannelSetPreset p in ChannelSetPreset.values)
                  (p, p.label),
              ],
              onChanged: (ChannelSetPreset p) => c.channelSet = p,
            ),
          ),
          if (s.channelSet == ChannelSetPreset.custom)
            RwSlider(
              label: 'Channel count (first of the full US list)',
              valueText: '${s.customCount}',
              value: s.customCount.toDouble(),
              min: 1,
              max: kAllUsChannels.length.toDouble(),
              divisions: kAllUsChannels.length - 1,
              onChanged: (double v) => c.customCount = v.round(),
              semanticValue: (double v) => '${v.round()} channels',
            ),
          const SizedBox(height: AppSpacing.xxs),
          RwSlider(
            label: 'Dwell per channel',
            valueText: fmtMs(s.dwellMs),
            value: s.dwellMs,
            min: kDwellMin,
            max: kDwellMax,
            divisions: ((kDwellMax - kDwellMin) / 10).round(),
            onChanged: (double v) => c.dwellMs = (v / 10).round() * 10,
            semanticValue: (double v) => '${v.round()} milliseconds',
          ),
          Text(
            '250 ms is a common survey default.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          RwSlider(
            label: 'Channel switch per hop (illustrative)',
            valueText: fmtMs(s.switchMs),
            value: s.switchMs,
            min: 0,
            max: kSwitchMax,
            divisions: kSwitchMax.round(),
            onChanged: (double v) => c.switchMs = v,
            semanticValue: (double v) => '${v.round()} milliseconds',
          ),
          const SizedBox(height: AppSpacing.xs),
          LabeledField(
            label: 'Hopping algorithm',
            field: AppToggle<HoppingAlgorithm>(
              value: s.algorithm,
              semanticLabel: 'Hopping algorithm',
              expand: true,
              items: const <AppToggleItem<HoppingAlgorithm>>[
                (HoppingAlgorithm.sequentialShared, 'Sequential'),
                (HoppingAlgorithm.bandPerRadio, 'Band per NIC'),
                (HoppingAlgorithm.priority, 'Priority'),
              ],
              onChanged: (HoppingAlgorithm a) => c.algorithm = a,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(switch (s.algorithm) {
            HoppingAlgorithm.sequentialShared =>
              'One list; each NIC takes the next channel in turn.',
            HoppingAlgorithm.bandPerRadio =>
              'Each NIC owns whole bands; spare NICs split the slowest '
                  'band. Each band gets its own revisit time.',
            HoppingAlgorithm.priority =>
              'Every k-th slot goes to the next channel marked in use; the '
                  'rest share the other slots.',
          }, style: text.bodySmall?.copyWith(color: colors.textTertiary)),
          if (s.algorithm == HoppingAlgorithm.priority) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const RwSectionLabel('Channels in use (priority)'),
            const SizedBox(height: AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (final SurveyChannel ch in inUse)
                  FilterChip(
                    label: Text(ch.label),
                    selected: s.priority.contains(ch),
                    onSelected: (_) => c.togglePriority(ch),
                    selectedColor: colors.primary.withValues(alpha: 0.2),
                    checkmarkColor: colors.textAccent,
                    side: BorderSide(color: colors.borderStrong),
                  ),
              ],
            ),
            RwSlider(
              label: 'Priority every k-th slot',
              valueText: 'k = ${s.priorityEvery}',
              value: s.priorityEvery.toDouble(),
              min: kPriorityEveryMin.toDouble(),
              max: kPriorityEveryMax.toDouble(),
              divisions: kPriorityEveryMax - kPriorityEveryMin,
              onChanged: (double v) => c.priorityEvery = v.round(),
              semanticValue: (double v) => 'every ${v.round()} slots',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Walker ──────────────────────────────────────────────────────────────────

Widget _paceSlider(SurveyWalkController c, {bool short = false}) => RwSlider(
  label: short ? 'Pace' : 'Walking pace',
  valueText: fmtPace(c.config.paceMps, c.units),
  value: LengthFormat(c.units).distValue(c.config.paceMps),
  min: _lo(c, kSurveyPaceMin, 0.1),
  max: _hi(c, kSurveyPaceMax, 0.1),
  divisions: ((_hi(c, kSurveyPaceMax, 0.1) - _lo(c, kSurveyPaceMin, 0.1)) * 10)
      .round(),
  onChanged: (double v) => c.paceMps = LengthFormat(c.units).distToMetres(v),
  semanticValue: (double v) =>
      '${v.toStringAsFixed(1)} ${c.units.isMetric ? 'meters' : 'feet'} per '
      'second',
);

Widget _guessSlider(SurveyWalkController c, {bool short = false}) => RwSlider(
  label: short ? 'Guess range' : 'Guess range (accuracy distance)',
  valueText: fmtM(c.config.guessRangeM, c.units),
  value: LengthFormat(c.units).distValue(c.config.guessRangeM),
  min: _lo(c, kGuessRangeMin, 1),
  max: _hi(c, kGuessRangeMax, 1),
  divisions: (_hi(c, kGuessRangeMax, 1) - _lo(c, kGuessRangeMin, 1)).round(),
  onChanged: (double v) =>
      c.guessRangeM = LengthFormat(c.units).distToMetres(v),
  semanticValue: (double v) =>
      '${v.toStringAsFixed(0)} ${LengthFormat(c.units).distUnitSpoken}',
);

/// A slider end in the unit on screen, rounded inward to [step].
double _lo(SurveyWalkController c, double m, double step) =>
    (LengthFormat(c.units).distValue(m) / step - 1e-9).ceilToDouble() * step;

double _hi(SurveyWalkController c, double m, double step) =>
    (LengthFormat(c.units).distValue(m) / step + 1e-9).floorToDouble() * step;

class _WalkerCard extends StatelessWidget {
  const _WalkerCard(this.c, {this.withSliders = true});

  final SurveyWalkController c;
  final bool withSliders;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SurveyPathPreset preset = c.drawing
        ? SurveyPathPreset.custom
        : c.pathPreset;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Walk path',
            field: AppSelect<SurveyPathPreset>(
              value: preset,
              semanticLabel: 'Walk path',
              items: <AppSelectItem<SurveyPathPreset>>[
                for (final SurveyPathPreset p in SurveyPathPreset.values)
                  (p, p == SurveyPathPreset.custom ? 'Draw your own' : p.label),
              ],
              onChanged: (SurveyPathPreset p) => c.pathPreset = p,
            ),
          ),
          if (withSliders) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _paceSlider(c),
            Text(
              c.units.isMetric
                  ? 'Comfortable gait is 1.27 to 1.46 m/s; some vendors ask '
                        'for about 1 m/s.'
                  : 'Comfortable gait is 4.2 to 4.8 ft/s; some vendors ask '
                        'for about 3.3 ft/s.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
            _guessSlider(c),
            Text(
              'How far the map may guess from each sample. About '
              '${c.units.isMetric ? '5 m' : '16 ft'} suits '
              'most indoor buildings. A stretch with no sample within half of it is '
              'white: no data, not no coverage.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

// ── View ────────────────────────────────────────────────────────────────────

class _ViewCard extends StatelessWidget {
  const _ViewCard(this.c);

  final SurveyWalkController c;

  @override
  Widget build(BuildContext context) {
    final SurveyWalkResult r = c.result;
    final SurveyChannel? shown = c.shownChannel;
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: "Show this channel's samples",
            semanticLabel: 'Channel shown',
            field: AppSelect<int>(
              value: shown == null ? -1 : r.indexOf(shown),
              semanticLabel: 'Channel shown',
              items: <AppSelectItem<int>>[
                (-1, 'All channels (shape = band)'),
                for (int i = 0; i < r.channels.length; i++)
                  (i, r.channels[i].label),
              ],
              onChanged: (int i) =>
                  c.shownChannel = i < 0 ? null : r.channels[i],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          RwSwitchRow(
            title: 'Signal along the path',
            subtitle: c.shownIndex == null
                ? 'Pick one channel to see its signal.'
                : 'Average level plus fading, per sample.',
            value: c.showSignal,
            onChanged: (bool v) => c.showSignal = v,
          ),
          if (c.showSignal && c.shownIndex != null)
            RwOutlineButton(
              icon: Icons.casino_outlined,
              label: 'New fading',
              semanticLabel: 'Draw a new random fading pattern',
              onPressed: c.newFading,
            ),
        ],
      ),
    );
  }
}
