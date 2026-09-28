// The controls for Band Steering (Wi-Fi Classroom): play, step and reset, the
// walking path, the readouts, the predict-then-reveal question, the AP's
// steering mode, its refusal tolerance and its deauthentication timings, the
// client profile and its random-address toggle, and the extra 5 GHz wall
// loss. Reads and writes a
// [BandSteeringController]; owns no state, so a presenter layout can place
// it beside [BandSteeringStage].
//
// ILLUSTRATIVE VALUES (spec 38), each labeled where it is set: the extra
// 5 GHz wall loss, the refusal tolerance, the AP's power and path-loss
// exponent, the -82 dBm hearing floor, the transition-request repeat, the
// deauthentication rescan time and retry interval, the 1 m per second walk
// the deauthentication timings count on, and the model choices behind
// Client A's join and Client B's score. Keith confirmed the defaults and
// ruled deauthentication in on 2026-09-27, so nothing is labeled
// provisional any more.
//
// States (SOP-007 §5):
//   - fresh       -> Client A, steering off, edge to AP, client at the edge
//                    on 2.4 GHz
//   - empty       -> "Not connected" on the stage, with the reason (lost
//                    signal, or refused with nowhere else to go)
//   - error       -> not reachable: the model is pure and total
//   - disabled    -> the refusal tolerance slider is disabled, with a note,
//                    outside authentication refusal; the two
//                    deauthentication timing sliders show only under
//                    deauthentication; Reveal shows only once the question
//                    is asked
//   - loading     -> not reachable: the walk is computed synchronously
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): the band, the reason and the gauges
// are on the stage; readouts and notes fold into PresenterDisclosures, and
// short inputs pair up, so the panel fits at 1440x900 with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/band_steering_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../labeled_field.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'band_steering_controller.dart';
import 'band_steering_parts.dart';

/// What each steering mode does, in plain words.
String bsModeNote(
  SteeringMode m, [
  UnitSystem u = UnitSystem.metric,
]) => switch (m) {
  SteeringMode.off =>
    'The AP answers every probe and accepts every client on both bands.',
  SteeringMode.probeSuppression =>
    'The AP stops answering broadcast probe requests on 2.4 GHz from a '
        'client it has heard on 5 GHz. Probes that name the network are '
        'still answered, and 2.4 GHz beacons still go out. One open-source '
        'implementation warns that this can cause connection problems and '
        'slow down finding the AP.',
  SteeringMode.authRefusal =>
    'The AP refuses authentication on 2.4 GHz from a client it has heard on '
        '5 GHz. Clients retry, so a client that cannot use 5 GHz keeps '
        'trying 2.4 GHz. The same implementation gives the same warning, '
        'and adds that it slows down connecting.',
  SteeringMode.transitionRequest =>
    'After the client joins 2.4 GHz, the AP sends a BSS (basic service set) '
        'Transition Management request, from the 802.11v amendment: a '
        '"please move" message naming the 5 GHz network. The client '
        'accepts or declines; it is not forced. Repeated every '
        '${LengthFormat(u).dist(kBsBtmRepeatSteps.toDouble(), decimals: 0)} '
        'walked (illustrative).',
  SteeringMode.deauthentication =>
    'The AP sends a deauthentication to a client on 2.4 GHz that it has '
        'heard on 5 GHz. The client is disconnected and its traffic stops '
        'while it rescans. It still chooses where to go back: if 5 GHz is '
        'below its entry level, or its rules prefer 2.4 GHz, it comes right '
        'back to 2.4 GHz, and the AP deauthenticates it again.',
};

/// The standing note under deauthentication: what it is, and what it is not.
const String kBsDeauthNote =
    'Deauthentication is a standard frame, but using it to steer is vendor '
    'behavior, not a steering mechanism the 802.11 standard defines. No '
    'published source gives its timings, so the rescan time and the retry '
    'interval are illustrative. A client using PMF (Protected Management '
    'Frames, 802.11w) ignores an unprotected deauthentication from anyone '
    'but its AP; the AP\'s own is protected and still works.';

/// Each client's published rule set, in plain words.
String bsProfileNote(ClientProfile p) => switch (p) {
  ClientProfile.a =>
    'One published rule set. Holds its network until the signal drops below '
        '-70 dBm, then looks; another network must be 8 dB stronger while '
        'it is sending (12 dB when idle; this tool uses 8). No band rule: it '
        'ranks by Wi-Fi generation, channel width, how busy the channel is '
        'and how many clients it has. Model choice (illustrative): it joins '
        '5 GHz, the wider channel here, when 5 GHz is at or above -70 dBm.',
  ClientProfile.b =>
    'One published rule set; device makers can change every number. Will '
        'not join below -80 dBm on 2.4 GHz or -77 dBm on 5 GHz. Does not '
        're-run selection while its link is above -73 dBm on 2.4 GHz or '
        '-70 dBm on 5 GHz. Scores by a throughput estimate, plus a bonus '
        'for the network it is on (estimate and bonus size illustrative).',
  ClientProfile.c =>
    'No published band rule. Modeled as joining the strongest signal and '
        'staying until the signal is lost. Answers transition requests if '
        'its driver supports them.',
};

class BandSteeringControls extends StatelessWidget {
  const BandSteeringControls({super.key, required this.controller});

  final BandSteeringController controller;

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
              _Transport(controller: controller),
              gap,
              _Predict(controller: controller, compact: true),
              gap,
              _Inputs(controller: controller, compact: true),
              PresenterDisclosure(
                title: 'All readouts',
                children: <Widget>[_Readouts(controller: controller)],
              ),
              PresenterDisclosure(
                title: 'Model notes',
                children: <Widget>[_Notes(controller: controller)],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Transport(controller: controller),
            gap,
            _Readouts(controller: controller),
            gap,
            _Predict(controller: controller, compact: false),
            gap,
            _Inputs(controller: controller, compact: false),
            gap,
            _Notes(controller: controller),
          ],
        );
      },
    );
  }
}

// ── Play, step, reset and the path ──────────────────────────────────────────

class _Transport extends StatelessWidget {
  const _Transport({required this.controller});

  final BandSteeringController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final BandSteeringController c = controller;
    ButtonStyle style() => OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      foregroundColor: colors.textPrimary,
    );
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: c.togglePlay,
                style: style(),
                icon: Icon(
                  c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(c.playing ? 'Pause' : 'Walk'),
              ),
              OutlinedButton.icon(
                onPressed: c.atEnd ? null : c.stepOnce,
                style: style(),
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(
                  'Step '
                  '${LengthFormat(UnitSystemScope.systemOf(context)).dist(1)}',
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.reset,
                style: style(),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<WalkPath>(
            label: PresenterMode.isActive(context) ? null : 'Walking path',
            semanticLabel: 'Walking path',
            value: c.config.path,
            expand: true,
            items: <AppToggleItem<WalkPath>>[
              for (final WalkPath p in WalkPath.values) (p, p.label),
            ],
            onChanged: (WalkPath p) => c.path = p,
          ),
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

class _Readouts extends StatelessWidget {
  const _Readouts({required this.controller});

  final BandSteeringController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final BsStep s = controller.step;
    final BsConfig c = controller.config;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle value = mono.inlineCode.copyWith(color: colors.textPrimary);

    TableRow row(String name, String v) => TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(name, style: label),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Text(v, textAlign: TextAlign.end, style: value),
        ),
      ],
    );

    String heard(double r) => bsHears(r) ? bsDbm(r) : '${bsDbm(r)}, not heard';

    final String btm = c.mode != SteeringMode.transitionRequest
        ? 'not sent in this mode'
        : s.btm?.label ?? 'none yet';
    final String refusals = c.mode != SteeringMode.authRefusal
        ? 'none in this mode'
        : '${s.refusalsTotal} (the AP gives in after ${c.refusalTolerance})';
    final bool deauth = c.mode == SteeringMode.deauthentication;
    final String deauths = !deauth
        ? 'none in this mode'
        : '${s.deauthsTotal} (back on 2.4 GHz ${s.returnsTo24} '
              '${s.returnsTo24 == 1 ? 'time' : 'times'})';
    final String outage = !deauth
        ? 'none in this mode'
        : '${s.outageS} s (illustrative)';
    final String traffic = s.trafficFlowing
        ? 'flowing'
        : s.inOutage
        ? 'stopped: deauthenticated'
        : 'stopped: not connected';

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.3),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              row('Client is on', s.band?.label ?? 'not connected'),
              row(
                'Distance from the AP',
                LengthFormat(
                  UnitSystemScope.systemOf(context),
                ).dist(s.distanceM, decimals: 0),
              ),
              row('Signal on 2.4 GHz', heard(s.rssi24)),
              row('Signal on 5 GHz', heard(s.rssi5)),
              row(
                'AP has matched this client on 5 GHz',
                s.trackedOn5 ? 'yes' : 'no',
              ),
              row('Transition request answer', btm),
              row('Authentication refusals so far', refusals),
              row('Client traffic', traffic),
              row('Deauthentications so far', deauths),
              row('Time without traffic from deauthentications', outage),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Why: ${s.why}',
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

  final BandSteeringController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final BsQuestion q = controller.question;
    final TextStyle body =
        text.bodyMedium?.copyWith(color: colors.textPrimary) ??
        TextStyle(color: colors.textPrimary);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          const Expanded(child: AirtimeSectionTitle('Predict, then reveal')),
          if (compact && q == BsQuestion.asking)
            FilledButton.icon(
              onPressed: controller.reveal,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal'),
            )
          else if (q != BsQuestion.idle)
            IconButton(
              onPressed: controller.dismissQuestion,
              tooltip: 'Close the question',
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(kBsQuestionText, style: body),
    ];

    switch (q) {
      case BsQuestion.idle:
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
              'Loads the question: steering off, edge to AP, the client at '
              'the edge. Reveal walks it in.',
              style: note,
            ),
          ],
        ]);
      case BsQuestion.asking:
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final BsGuess g in BsGuess.values)
                BsChoiceButton(
                  label: g.label,
                  selected: controller.guess == g,
                  onPressed: () => controller.guess = g,
                ),
            ],
          ),
          if (!compact) const SizedBox(height: AppSpacing.xs),
          if (!compact)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: controller.reveal,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Reveal'),
              ),
            ),
        ]);
      case BsQuestion.revealed:
        final ({BsBand? a, BsBand? b}) ans = controller.questionAnswer;
        final bool moves = ans.a == BsBand.ghz5 || ans.b == BsBand.ghz5;
        final BsGuess? g = controller.guess;
        final BsGuess right = moves ? BsGuess.yes : BsGuess.no;
        children.addAll(<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            moves
                ? 'Yes, under these settings.'
                : 'No. Under Client A\'s and Client B\'s published rules, it '
                      'stays on 2.4 GHz all the way to the AP.',
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
          if (g != null)
            Text(
              g == right
                  ? 'The class picked "${g.label}": right.'
                  : 'The class picked "${g.label}".',
              style: body,
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Why: at the edge, 5 GHz is too weak to join, so the client '
              'joins 2.4 GHz. Walking in, 2.4 GHz climbs above the level '
              'where the client looks again (-70 dBm for Client A, -73 dBm '
              'for Client B) before 5 GHz ever gets strong enough to win. A '
              'strong signal is a reason to stay, not to move.',
              style: note,
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

// ── Inputs ──────────────────────────────────────────────────────────────────

class _Inputs extends StatelessWidget {
  const _Inputs({required this.controller, required this.compact});

  final BandSteeringController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final BandSteeringController m = controller;
    final BsConfig c = m.config;
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

    final Widget mode = LabeledField(
      label: 'AP steering',
      field: AppSelect<SteeringMode>(
        value: c.mode,
        items: <AppSelectItem<SteeringMode>>[
          for (final SteeringMode s in SteeringMode.values) (s, s.label),
        ],
        onChanged: (SteeringMode s) => m.mode = s,
        semanticLabel: 'AP steering',
      ),
    );

    final bool refusing = c.mode == SteeringMode.authRefusal;
    final Widget tolerance = BsSlider(
      label: 'Refusals a client tolerates (illustrative)',
      valueText: '${c.refusalTolerance}',
      value: c.refusalTolerance.toDouble(),
      min: kBsMinTolerance.toDouble(),
      max: kBsMaxTolerance.toDouble(),
      divisions: kBsMaxTolerance - kBsMinTolerance,
      onChanged: refusing ? (double v) => m.refusalTolerance = v.round() : null,
      semanticValue: (double v) => '${v.round()} refusals',
    );

    final bool deauth = c.mode == SteeringMode.deauthentication;
    final Widget rescan = BsSlider(
      label: 'Client rescan time (illustrative)',
      valueText: '${c.rescanS} s',
      value: c.rescanS.toDouble(),
      min: kBsMinRescanS.toDouble(),
      max: kBsMaxRescanS.toDouble(),
      divisions: kBsMaxRescanS - kBsMinRescanS,
      onChanged: (double v) => m.rescanS = v.round(),
      semanticValue: (double v) => '${v.round()} seconds',
    );
    final Widget retry = BsSlider(
      label: 'AP retry interval (illustrative)',
      valueText: '${c.retryS} s',
      value: c.retryS.toDouble(),
      min: kBsMinRetryS.toDouble(),
      max: kBsMaxRetryS.toDouble(),
      divisions: kBsMaxRetryS - kBsMinRetryS,
      onChanged: (double v) => m.retryS = v.round(),
      semanticValue: (double v) => '${v.round()} seconds',
    );

    final Widget profile = AppToggle<ClientProfile>(
      label: compact ? null : 'Client',
      semanticLabel: 'Client profile',
      value: c.profile,
      expand: true,
      items: <AppToggleItem<ClientProfile>>[
        for (final ClientProfile p in ClientProfile.values) (p, p.label),
      ],
      onChanged: (ClientProfile p) => m.profile = p,
    );

    final Widget random = BsSwitchRow(
      title: 'Client uses a random address while scanning',
      value: c.randomScanAddress,
      onChanged: (bool v) => m.randomScanAddress = v,
    );

    final Widget driver = BsSwitchRow(
      title: 'Client C\'s driver supports transition requests',
      value: c.driverSupportsBtm,
      onChanged: (bool v) => m.driverSupportsBtm = v,
    );

    final Widget loss = BsSlider(
      label: 'Extra 5 GHz wall loss (illustrative)',
      valueText: '${c.extra5LossDb.toStringAsFixed(0)} dB',
      value: c.extra5LossDb,
      min: kBsMinExtraLossDb,
      max: kBsMaxExtraLossDb,
      divisions: (kBsMaxExtraLossDb - kBsMinExtraLossDb).round(),
      onChanged: (double v) => m.extra5LossDb = v.roundToDouble(),
      semanticValue: (double v) => '${v.round()} decibels',
    );

    if (compact) {
      return AirtimeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            mode,
            gap,
            profile,
            gap,
            random,
            // Only transition requests read the driver switch; hiding it in
            // the other modes keeps the panel from scrolling.
            if (c.profile == ClientProfile.c &&
                c.mode == SteeringMode.transitionRequest)
              driver,
            gap,
            pair(loss, deauth ? rescan : tolerance),
            // The rescan time sets the outage the class sees; the retry
            // interval folds away so the panel fits with no scroll.
            if (deauth)
              PresenterDisclosure(
                title: 'AP retry interval: ${c.retryS} s (illustrative)',
                children: <Widget>[retry],
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('The AP'),
              const SizedBox(height: AppSpacing.xs),
              mode,
              const SizedBox(height: AppSpacing.xs),
              Text(
                bsModeNote(c.mode, UnitSystemScope.systemOf(context)),
                style: note,
              ),
              gap,
              tolerance,
              Text(
                refusing
                    ? 'How many refusals a client puts up with is not '
                          'published anywhere; after this many the AP lets it '
                          'in.'
                    : 'Only used with authentication refusal.',
                style: note,
              ),
              if (deauth) ...<Widget>[
                gap,
                rescan,
                Text(
                  'How long the client is off the air after each '
                  'deauthentication, rescanning and associating again. Its '
                  'traffic is zero for all of it.',
                  style: note,
                ),
                const SizedBox(height: AppSpacing.xs),
                retry,
                Text(
                  'How long the AP lets the client stay on 2.4 GHz before it '
                  'deauthenticates it, the first time and every time it '
                  'comes back.',
                  style: note,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(kBsDeauthNote, style: note),
              ],
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('The client'),
              const SizedBox(height: AppSpacing.xs),
              profile,
              const SizedBox(height: AppSpacing.xs),
              Text(bsProfileNote(c.profile), style: note),
              gap,
              random,
              Text(
                'The AP recognizes a dual-band client by seeing the same MAC '
                '(media access control) address on both radios. Platforms '
                'document scanning from random addresses when not '
                'connected, so the AP loses track of the client and probe '
                'suppression and authentication refusal stop applying to it.',
                style: note,
              ),
              if (c.profile == ClientProfile.c) ...<Widget>[gap, driver],
            ],
          ),
        ),
        gap,
        AirtimeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('The floor'),
              const SizedBox(height: AppSpacing.xs),
              loss,
              Text(
                'Free space alone makes 5 GHz '
                '${bsFreeSpaceGapDb.toStringAsFixed(1)} dB weaker than '
                '2.4 GHz at every distance (5.5 against 2.437 GHz); walls '
                'usually add more.',
                style: note,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Model notes ─────────────────────────────────────────────────────────────

class _Notes extends StatelessWidget {
  const _Notes({required this.controller});

  final BandSteeringController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One dual-band AP sending ${kBsEirpDbm.toStringAsFixed(0)} dBm on '
            'both bands, path-loss exponent '
            '${kBsExponent.toStringAsFixed(1)}, the same log-distance model '
            'as Roaming Walk (both illustrative). Nothing is heard below '
            '${kBsHearFloorDbm.toStringAsFixed(0)} dBm (illustrative), and '
            'the AP hears the client wherever the client hears the AP. No '
            'fading: the same settings give the same walk.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Channel widths 20 MHz on 2.4 GHz and 80 MHz on 5 GHz '
            '(illustrative). The AP remembers a client it heard on 5 GHz for '
            'the whole walk. A scan sends one broadcast probe per band.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Deauthentication timings count the walk at '
            '${LengthFormat(UnitSystemScope.systemOf(context)).dist(1)} each '
            'second (illustrative).',
            style: body,
          ),
          if (PresenterMode.isActive(context) &&
              controller.config.mode == SteeringMode.deauthentication) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(kBsDeauthNote, style: body),
          ],
        ],
      ),
    );
  }
}
