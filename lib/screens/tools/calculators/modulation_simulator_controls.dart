// Controls for the Wi-Fi Lab Modulation Simulator, over one
// ModulationSimulatorController:
//   - ModulationPicker            the modulation select
//   - ModulationSimulatorControls transport, SNR, speed, bit source, message
//   - ModulationReadouts          the readouts and EVM cards
//   - ModulationExplainer         the "What you are seeing" prose
// The phone screen stacks them around the stage in the original order. The
// presenter panel uses the first three; there ModulationReadouts shows the
// run counts and the EVM, and folds the constellation facts and the 802.11
// limit table behind one disclosure so the panel fits without scrolling.
//
// States (SOP-007 §5) are the screen's, unchanged: empty (nothing sent),
// running, paused (default), error (empty message disables sending),
// disabled (Step / +100 while playing or with no message; Reset with nothing
// to clear), interactive (themed Material controls, global focus ring).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'modulation_simulator_controller.dart';
import 'modulation_simulator_parts.dart';

typedef _C = ModulationSimulatorController;

/// Presenter label column: wide enough for the scaled labels on one line.
const double _kPresenterLabelWidth = 170;

// ── Modulation selector ───────────────────────────────────────────────────

class ModulationPicker extends StatelessWidget {
  const ModulationPicker({super.key, required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final ModUi ui = ModUi.of(context);
        final Modulation mod = controller.modulation;
        return ui.card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _ModulationSelect(controller: controller),
              // In presenter mode the stage heading carries this line.
              if (!PresenterMode.isActive(context)) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${mod.points} points, ${mod.bitsPerSymbol} '
                  'bit${mod.bitsPerSymbol == 1 ? '' : 's'} per symbol. '
                  'First used in ${mod.firstUsed}.',
                  style: ui.text.bodySmall?.copyWith(
                    color: ui.colors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The modulation select itself, shared by [ModulationPicker] (phone) and
/// the presenter controls card.
class _ModulationSelect extends StatelessWidget {
  const _ModulationSelect({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    // Seven options: GL-003 §8.14 routes 4+ options to AppSelect, not a
    // segmented toggle (which never wraps and caps at 3).
    return LabeledField(
      label: 'Modulation',
      semanticLabel: 'Modulation',
      field: AppSelect<Modulation>(
        value: controller.modulation,
        semanticLabel: 'Modulation',
        items: <AppSelectItem<Modulation>>[
          for (final Modulation m in Modulation.values)
            (
              m,
              '${m.label} (${m.bitsPerSymbol} '
                  'bit${m.bitsPerSymbol == 1 ? '' : 's'} per symbol)',
            ),
        ],
        onChanged: controller.setModulation,
      ),
    );
  }
}

// ── Transport and inputs ──────────────────────────────────────────────────

class ModulationSimulatorControls extends StatelessWidget {
  const ModulationSimulatorControls({super.key, required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final bool can = c.canSend;
    final bool playing = c.playing;
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bool presenting = PresenterMode.isActive(context);
    final TextStyle? buttonText = ui.text.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );

    List<Widget> buttons({
      EdgeInsetsGeometry? padding,
      bool icons = true,
    }) => <Widget>[
      Semantics(
        button: true,
        label: playing ? 'Pause' : 'Play',
        excludeSemantics: true,
        child: FilledButton.icon(
          onPressed: can ? c.togglePlay : null,
          icon: icons
              ? Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded)
              : null,
          label: Text(playing ? 'Pause' : 'Play', maxLines: 1, softWrap: false),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            disabledBackgroundColor: colors.disabledFill,
            disabledForegroundColor: colors.textDisabled,
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            padding: padding,
            textStyle: buttonText,
          ),
        ),
      ),
      ui.outlined(
        label: 'Step',
        icon: Icons.skip_next_rounded,
        semantic: 'Step: send one symbol',
        enabled: can && !playing,
        onTap: c.step,
        padding: padding,
        showIcon: icons,
      ),
      ui.outlined(
        label: '+$kModBurst',
        icon: Icons.fast_forward_rounded,
        semantic: 'Send $kModBurst symbols at once',
        enabled: can && !playing,
        onTap: c.burst,
        padding: padding,
        showIcon: icons,
      ),
      ui.outlined(
        label: 'Reset',
        icon: Icons.restart_alt_rounded,
        semantic: 'Reset: clear received points and counts',
        enabled: c.sent > 0,
        onTap: c.reset,
        padding: padding,
        showIcon: icons,
      ),
    ];
    const Widget gap = SizedBox(width: AppSpacing.xs);
    Widget twoRows(List<Widget> b) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: b[0]),
            gap,
            Expanded(child: b[1]),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(child: b[2]),
            gap,
            Expanded(child: b[3]),
          ],
        ),
      ],
    );
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // In presenter mode the select joins this card (one card, not
          // two, so the panel fits).
          if (presenting) ...<Widget>[
            _ModulationSelect(controller: c),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (!presenting)
            twoRows(buttons())
          else
            // One row when four buttons fit at the presenter text size,
            // measured from the widest label; two rows otherwise.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                const EdgeInsets dense = EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                );
                final TextScaler scaler = MediaQuery.textScalerOf(context);
                double widest = 0;
                for (final String l in <String>[
                  'Pause',
                  'Step',
                  '+$kModBurst',
                  'Reset',
                ]) {
                  final TextPainter tp = TextPainter(
                    text: TextSpan(text: l, style: buttonText),
                    textDirection: TextDirection.ltr,
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout();
                  if (tp.width > widest) widest = tp.width;
                  tp.dispose();
                }
                // Per button: label + dense padding, plus 18 px icon and an
                // 8 px gap when the icons fit too.
                bool fits(double each) =>
                    4 * each + 3 * AppSpacing.xs <= box.maxWidth;
                final double bare = widest + dense.horizontal;
                final bool icons = fits(bare + 18 + AppSpacing.xs);
                if (!icons && !fits(bare)) return twoRows(buttons());
                final List<Widget> b = buttons(padding: dense, icons: icons);
                return Row(
                  children: <Widget>[
                    Expanded(child: b[0]),
                    gap,
                    Expanded(child: b[1]),
                    gap,
                    Expanded(child: b[2]),
                    gap,
                    Expanded(child: b[3]),
                  ],
                );
              },
            ),
          if (reduceMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            ui.note(
              Icons.motion_photos_off_outlined,
              'Reduced motion is on, so nothing moves until you ask. Step '
              'sends one symbol at a time.',
            ),
          ],
          SizedBox(height: presenting ? AppSpacing.sm : AppSpacing.md),
          Row(
            children: <Widget>[
              ui.sectionLabel('Signal-to-noise ratio (SNR)'),
              const Spacer(),
              Text(
                '${_C.db(c.snrDb)} dB',
                style: ui.mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          Slider(
            value: c.snrDb,
            min: kModSnrMin,
            max: kModSnrMax,
            divisions: 90,
            onChanged: c.setSnr,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${_C.db(c.snrDb)} dB',
            semanticFormatterCallback: (double v) => 'SNR ${_C.db(v)} dB',
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<SimSpeed>(
            label: 'Speed (symbols per second)',
            value: c.speed,
            expand: true,
            items: <AppToggleItem<SimSpeed>>[
              for (final SimSpeed s in SimSpeed.values) (s, s.label),
            ],
            onChanged: c.setSpeed,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<BitSource>(
            label: 'Bits to send',
            value: c.source,
            expand: true,
            items: const <AppToggleItem<BitSource>>[
              (BitSource.random, 'Random'),
              (BitSource.text, 'Your text'),
            ],
            onChanged: c.setSource,
          ),
          if (c.source == BitSource.text) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _TextSection(controller: c),
          ],
        ],
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final SymbolFrame frame = c.frame;
    final int bits = c.messageBits;
    final String rxSoFar = c.hasRxSymbols ? c.decodeRx() : '';
    final Modulation mod = c.modulation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledField(
          label: 'Message',
          hint: '(sent as UTF-8 bits)',
          semanticLabel: 'Message to send',
          field: TextField(
            controller: c.textCtrl,
            onChanged: c.onTextChanged,
            maxLength: kModMaxTextLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            // The presenter panel drops the character counter line; the
            // limit is still enforced.
            buildCounter: PresenterMode.isActive(context)
                ? (
                    BuildContext _, {
                    required int currentLength,
                    required bool isFocused,
                    required int? maxLength,
                  }) => null
                : null,
            autocorrect: false,
            enableSuggestions: false,
            style: ui.text.bodyLarge?.copyWith(color: colors.textPrimary),
            cursorColor: colors.textAccent,
            decoration: const InputDecoration(hintText: 'Type a message'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (frame.symbols.isEmpty)
          ui.note(
            Icons.edit_outlined,
            'Type a message to send it, or switch to Random bits.',
            tint: colors.statusWarning,
          )
        else if (PresenterMode.isActive(context))
          // The size, the progress and the decoded text are on the stage.
          const SizedBox.shrink()
        else ...<Widget>[
          Text(
            '${bits ~/ 8} bytes = $bits bits = ${frame.symbols.length} '
            'symbols of ${mod.bitsPerSymbol} '
            'bit${mod.bitsPerSymbol == 1 ? '' : 's'}. '
            '${frame.padBits == 0 ? 'No padding needed.' : 'The last symbol is padded with ${frame.padBits} zero bit${frame.padBits == 1 ? '' : 's'}.'}',
            style: ui.text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          ui.row(
            label: 'Progress',
            value:
                '${c.textPos} of ${frame.symbols.length} symbols sent'
                '${c.passes > 0 ? ', pass ${c.passes + 1}' : ''}',
          ),
          ui.row(
            label: 'Received so far',
            value: rxSoFar.isEmpty ? '-' : rxSoFar,
          ),
          if (c.lastFullRx != null)
            ui.row(label: 'Last full copy', value: c.lastFullRx!),
        ],
      ],
    );
  }
}

// ── Readouts and EVM ──────────────────────────────────────────────────────

class ModulationReadouts extends StatelessWidget {
  const ModulationReadouts({super.key, required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return _PresenterReadouts(controller: controller);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ReadoutsCard(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            _EvmCard(controller: controller),
          ],
        );
      },
    );
  }
}

/// The run counts shared by the phone card and the presenter panel.
List<Widget> _countRows(ModUi ui, _C c, {double labelWidth = 136}) {
  return <Widget>[
    ui.row(label: 'Symbols sent', value: '${c.sent}', labelWidth: labelWidth),
    ui.row(
      label: 'Symbol errors',
      labelWidth: labelWidth,
      value: c.sent == 0
          ? '-'
          : '${c.symbolErrors} (${(100 * c.symbolErrors / c.sent).toStringAsFixed(2)}%)',
    ),
    ui.row(
      label: 'Bit errors',
      labelWidth: labelWidth,
      value: c.bitsSent == 0
          ? '-'
          : '${c.bitErrors} of ${c.bitsSent} '
                '(${(100 * c.bitErrors / c.bitsSent).toStringAsFixed(3)}%)',
    ),
  ];
}

List<Widget> _factRows(ModUi ui, _C c, {double labelWidth = 136}) {
  return <Widget>[
    ui.row(
      label: 'Bits per symbol',
      value: '${c.modulation.bitsPerSymbol}',
      labelWidth: labelWidth,
    ),
    ui.row(
      label: 'Levels per axis',
      value: c.levelsText(),
      labelWidth: labelWidth,
    ),
    ui.row(label: 'Scale (K_MOD)', value: c.kModText(), labelWidth: labelWidth),
  ];
}

String _measuredText(_C c, double? measured) => measured == null
    ? 'send symbols first'
    : '${_C.db(measured)} dB (${_C.pct(measured)}%) '
          'over ${c.sent} symbol${c.sent == 1 ? '' : 's'}';

class _PresenterReadouts extends StatelessWidget {
  const _PresenterReadouts({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final _C c = controller;
    final double theory = c.theoryEvmDb;
    final double? measured = c.measuredEvmDb;
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Short values, one line each at the presenter scale.
          ui.row(
            label: 'Symbol errors',
            labelWidth: _kPresenterLabelWidth,
            value: c.sent == 0
                ? 'none sent yet'
                : '${c.symbolErrors} of ${c.sent} '
                      '(${(100 * c.symbolErrors / c.sent).toStringAsFixed(2)}%)',
          ),
          ui.row(
            label: 'Bit errors',
            labelWidth: _kPresenterLabelWidth,
            value: c.bitsSent == 0
                ? '-'
                : '${c.bitErrors} of ${c.bitsSent} '
                      '(${(100 * c.bitErrors / c.bitsSent).toStringAsFixed(3)}%)',
          ),
          ui.row(
            label: 'EVM measured',
            labelWidth: _kPresenterLabelWidth,
            value: measured == null
                ? 'send symbols first'
                : '${_C.db(measured)} dB (${_C.pct(measured)}%)',
            emphasize: measured != null,
          ),
          ui.row(
            label: 'EVM theory',
            labelWidth: _kPresenterLabelWidth,
            value: '${_C.db(theory)} dB = -SNR',
          ),
          PresenterDisclosure(
            title: '${c.modulation.label} facts and 802.11 EVM limits',
            children: <Widget>[
              ..._factRows(ui, c, labelWidth: _kPresenterLabelWidth),
              const SizedBox(height: AppSpacing.xs),
              for (final EvmRequirement r in ModulationMath.requiredEvm(
                c.modulation,
              ))
                _RequirementRow(requirement: r, evmDb: theory),
              const SizedBox(height: AppSpacing.xs),
              ui.note(
                Icons.info_outline,
                'Transmit EVM limits are the transmitter\'s required '
                'accuracy, not a receiver sensitivity threshold.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadoutsCard extends StatelessWidget {
  const _ReadoutsCard({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final _C c = controller;
    final SimulatedSymbol? cur = c.current;
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionLabel('Readouts'),
          const SizedBox(height: AppSpacing.xs),
          ..._factRows(ui, c),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: cur == null
                ? ui.note(
                    Icons.info_outline,
                    'The current symbol appears here once you send one.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ui.row(
                        label: 'Current bits',
                        value: c.bitsSplit(cur.sent.symbol),
                        emphasize: true,
                      ),
                      ui.row(
                        label: 'I, Q',
                        value:
                            '${_C.signedD(cur.sent.i, 4)}, '
                            '${_C.signedD(cur.sent.q, 4)}',
                      ),
                      ui.row(
                        label: 'Amplitude, phase',
                        value:
                            '${cur.sent.amplitude.toStringAsFixed(4)}, '
                            '${_C.signedD(cur.sent.phase * 180 / math.pi, 1)} deg',
                      ),
                      ui.row(
                        label: 'Decided as',
                        value:
                            '${c.bitsSplit(cur.decided.symbol)} '
                            '${cur.isSymbolError ? '(wrong, ${cur.bitErrors} bit${cur.bitErrors == 1 ? '' : 's'} off)' : '(correct)'}',
                        valueColor: cur.isSymbolError
                            ? colors.statusDanger
                            : null,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._countRows(ui, c),
        ],
      ),
    );
  }
}

class _EvmCard extends StatelessWidget {
  const _EvmCard({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final _C c = controller;
    final double theory = c.theoryEvmDb;
    final double? measured = c.measuredEvmDb;
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionLabel('Error vector magnitude (EVM)'),
          const SizedBox(height: AppSpacing.xs),
          ui.row(
            label: 'Measured',
            value: _measuredText(c, measured),
            emphasize: measured != null,
          ),
          ui.row(
            label: 'Theory',
            value: '${_C.db(theory)} dB (${_C.pct(theory)}%) = -SNR',
          ),
          const SizedBox(height: AppSpacing.sm),
          ui.sectionLabel('802.11 transmit EVM limit, ${c.modulation.label}'),
          const SizedBox(height: AppSpacing.xxs),
          for (final EvmRequirement r in ModulationMath.requiredEvm(
            c.modulation,
          ))
            _RequirementRow(requirement: r, evmDb: theory),
          const SizedBox(height: AppSpacing.xs),
          ui.note(
            Icons.info_outline,
            'These limits are the transmitter\'s required accuracy (how '
            'cleanly a radio must build each point), not a receiver '
            'sensitivity threshold. Meets or misses compares them with the '
            'EVM this SNR produces.',
          ),
        ],
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement, required this.evmDb});

  final EvmRequirement requirement;
  final double evmDb;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final EvmRequirement r = requirement;
    final bool ok = ModulationMath.meetsRequirement(evmDb, r.requiredDb);
    final Color tone = ok ? colors.statusSuccess : colors.statusDanger;
    final String verdict = ok ? 'Meets' : 'Misses';
    return Semantics(
      label:
          'Coding rate ${r.codingRates}, limit ${_C.db(r.requiredDb)} dB, '
          '$verdict at ${_C.db(evmDb)} dB',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Rate ${r.codingRates}',
                style: ui.text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            Text(
              '${_C.db(r.requiredDb)} dB',
              style: ui.mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 18,
              color: tone,
            ),
            const SizedBox(width: AppSpacing.xxs),
            // Fits the verdict word at any text scale.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: Text(
                verdict,
                style: ui.text.labelLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class ModulationExplainer extends StatelessWidget {
  const ModulationExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final TextStyle? body = ui.text.bodyMedium?.copyWith(
      color: ui.colors.textSecondary,
    );
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionLabel('What you are seeing'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each group of bits picks one point on the I/Q plane. The point\'s '
            'distance from the center sets the carrier\'s amplitude, and its '
            'angle sets the phase. That one amplitude and phase is held for '
            'one symbol, then the next group of bits picks the next point.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Higher orders carry more bits per symbol by packing the points '
            'closer together. Noise pushes each received point off its ideal '
            'spot; once it crosses a decision boundary the receiver picks a '
            'neighbor. Neighbors are Gray coded, so that usually costs one bit.',
            style: body,
          ),
        ],
      ),
    );
  }
}
