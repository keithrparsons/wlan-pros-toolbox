// The controls for Why a Busy Line Lags (Wi-Fi Classroom): the one switch
// (smart queue management off or on), the line's technology, the playhead,
// and where the numbers come from. Reads and writes a
// [LatencyUnderLoadController]; owns no state, so a presenter layout can
// place it beside [LatencyUnderLoadStage].
//
// THE ONE CONTROL (research brief, candidate 1) is the SQM switch. The line
// picker is a setting beside it: it swaps which FCC-measured technology the
// trace follows (Cable by default), so a class can see that DSL suffers most.
//
// States (SOP-007 §5):
//   - fresh       -> cable, SQM off, the whole run drawn and stopped at its
//                    end
//   - empty       -> not reachable: the run always has a trace
//   - error       -> not reachable: every input is a two- or three-way
//                    toggle or a bounded slider, and the model is pure
//   - disabled    -> nothing disables: every control works in every state
//   - loading     -> not reachable: no I/O
//   - interactive -> themed Material controls with the global focus ring
//
// PRESENTER (PresenterMode.isActive): the switch, the line and the playhead
// stay out; the sources fold into a PresenterDisclosure, so the panel fits
// at 1440x900 with no scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/latency_under_load_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'latency_under_load_controller.dart';
import 'multicast_basic_rate_controls.dart' show McSlider;

/// Where the numbers come from, in words. Shown in the controls and pinned
/// by a test so the labels never drift from the model.
String lulSourcesText(LulLine l) =>
    'Idle: the FCC\'s measured range for ${l.inSentence} ISPs, '
    '${lulMs(l.idleLowMs)} to ${lulMs(l.idleHighMs)} (Measuring Broadband '
    'America, 13th report, 2022 test period); the trace uses the middle, '
    '${lulMs(l.idleMs)}. SQM off: the FCC\'s latency under upload load, '
    'read by eye from its chart, about ${lulMs(l.busyLowMs)} to '
    '${lulMs(l.busyHighMs)} across ISPs; the trace uses the middle ISP, '
    'about ${lulMs(l.busyMs)}. SQM on: illustrative, idle plus the 5 ms '
    'default target of FQ-CoDel (RFC 8290); no published consumer '
    'measurement was found. The timing and the shape of the climb are '
    'illustrative too.';

class LatencyUnderLoadControls extends StatelessWidget {
  const LatencyUnderLoadControls({super.key, required this.controller});

  final LatencyUnderLoadController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final SizedBox gap = SizedBox(
          height: presenting ? AppSpacing.xs : AppSpacing.sm,
        );
        final Widget sources = _Sources(controller: controller);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Switch(controller: controller, compact: presenting),
            gap,
            _Setting(controller: controller, compact: presenting),
            gap,
            if (presenting)
              PresenterDisclosure(
                title: 'Where the numbers come from',
                children: <Widget>[sources],
              )
            else
              AirtimeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const AirtimeSectionTitle('Where the numbers come from'),
                    const SizedBox(height: AppSpacing.xs),
                    sources,
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── The switch ──────────────────────────────────────────────────────────────

class _Switch extends StatelessWidget {
  const _Switch({required this.controller, required this.compact});

  final LatencyUnderLoadController controller;

  /// The presenter arrangement: fewer notes.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool on = controller.config.sqm;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<bool>(
            label: 'Smart queue management (SQM)',
            semanticLabel: 'Smart queue management',
            value: on,
            expand: true,
            items: const <AppToggleItem<bool>>[(false, 'Off'), (true, 'On')],
            onChanged: (bool v) => controller.sqm = v,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            on
                ? 'On: the router keeps its own queue short and sends each '
                      'conversation in turn, so the call no longer waits '
                      'behind the upload.'
                : 'Off: the call\'s packets join the back of the same queue '
                      'as the upload.',
            style: note,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'One such method is FQ-CoDel (flow queue controlled delay, '
              'RFC 8290), which keeps queues short and isolates low-rate '
              'traffic such as video calls from bulk transfers. In the '
              'presenter, Up and Down switch it on and off.',
              style: note,
            ),
          ],
        ],
      ),
    );
  }
}

// ── The line and the playhead ───────────────────────────────────────────────

class _Setting extends StatelessWidget {
  const _Setting({required this.controller, required this.compact});

  final LatencyUnderLoadController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final LulConfig c = controller.config;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<LulLine>(
            label: 'The home line',
            semanticLabel: 'The home line\'s technology',
            value: c.line,
            expand: true,
            items: <AppToggleItem<LulLine>>[
              for (final LulLine l in LulLine.values) (l, l.label),
            ],
            onChanged: (LulLine l) => controller.line = l,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'DSL is digital subscriber line, over the telephone wires. The '
              'FCC found the jump from idle to busy most pronounced on DSL.',
              style: note,
            ),
          ],
          SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
          ValueListenableBuilder<double>(
            valueListenable: controller.timeS,
            builder: (BuildContext context, double t, _) => McSlider(
              label: 'Time into the run',
              valueText: '${t.toStringAsFixed(1)} s',
              value: t,
              min: 0,
              max: kLulRunS,
              divisions: (kLulRunS * 2).round(),
              onChanged: controller.seek,
              semanticValue: (double v) =>
                  '${v.toStringAsFixed(1)} seconds, '
                  '${lulMs(lulLatencyMs(c.line, sqm: c.sqm, tS: v))}',
            ),
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Or drag across the chart. The upload runs from '
              '${kLulUploadStartS.round()} s to ${kLulUploadEndS.round()} s.',
              style: note,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sources ─────────────────────────────────────────────────────────────────

class _Sources extends StatelessWidget {
  const _Sources({required this.controller});

  final LatencyUnderLoadController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Text(
      lulSourcesText(controller.config.line),
      style: text.bodySmall?.copyWith(color: colors.textTertiary),
    );
  }
}
