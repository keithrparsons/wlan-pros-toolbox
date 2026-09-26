// Stage for the Wi-Fi Lab Modulation Simulator: the I/Q constellation and the
// carrier strip, over one ModulationSimulatorController.
//
// Two arrangements of the same parts:
//   - phone / desktop screen: two cards in the page's scroll column, exactly
//     as before the 2026-09-26 split;
//   - presenter (PresenterMode.isActive): fills the bounded stage box with no
//     scroll. The constellation square sits beside a large "current symbol"
//     readout (the number the lesson is about, at the headline scale), and
//     the carrier strip runs full width underneath and grows with the room.
//
// Painters get PresenterMode.scaleOf(context), so strokes and markers thicken
// on a projector and are unchanged everywhere else.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'modulation_simulator_controller.dart';
import 'modulation_simulator_painters.dart';
import 'modulation_simulator_parts.dart';

typedef _C = ModulationSimulatorController;

/// Worded empty-state prompt (also what the phone card shows).
const String _kEmptyPrompt =
    'Press Step to send one symbol, or Play to keep sending. Received points '
    'land around the ideal points; the thin lines are the decision boundaries '
    'the receiver uses.';

class ModulationSimulatorStage extends StatelessWidget {
  const ModulationSimulatorStage({super.key, required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return _PresenterStage(controller: controller);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ConstellationCard(controller: controller),
            const SizedBox(height: AppSpacing.sm),
            _WaveformCard(controller: controller, fillHeight: false),
          ],
        );
      },
    );
  }
}

// ── Presenter arrangement ─────────────────────────────────────────────────

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // The carrier strip takes about a third of the height; the
        // constellation square takes what is left.
        final double waveH = (box.maxHeight * 0.34).clamp(240.0, 380.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ui.card(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints top) {
                    final double side = math.min(
                      top.maxHeight,
                      top.maxWidth * 0.5,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: side,
                          height: side,
                          child: _ConstellationPlot(controller: controller),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _CurrentSymbolPanel(controller: controller),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: waveH,
              child: _WaveformCard(controller: controller, fillHeight: true),
            ),
          ],
        );
      },
    );
  }
}

/// The presenter's big readout beside the constellation. The facts match the
/// phone's Readouts card; here they are the lesson, so they are large, and
/// each is a label above its value so a narrow column never wraps a value
/// under its label. In text mode the decoded message is here too: it is what
/// the room watches arrive.
class _CurrentSymbolPanel extends StatelessWidget {
  const _CurrentSymbolPanel({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final _C c = controller;
    final Modulation mod = c.modulation;
    final SimulatedSymbol? cur = c.current;

    Widget stat(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: ui.text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            Text(
              value,
              style: ui.mono.inlineCode.copyWith(
                color: color ?? colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    // In the fullest case (4096-QAM with the probe, text mode after a full
    // pass, on a 900 px window) the panel is taller than the square beside
    // it; it then scales down as one piece rather than clip or scroll.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: box.maxWidth,
          child: _panel(context, ui, colors, scale, c, mod, cur, stat),
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context,
    ModUi ui,
    AppColorScheme colors,
    PresenterScale scale,
    _C c,
    Modulation mod,
    SimulatedSymbol? cur,
    Widget Function(String, String, {Color? color}) stat,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ui.sectionLabel(
          '${mod.label}: ${mod.points} points, ${mod.bitsPerSymbol} '
          'bit${mod.bitsPerSymbol == 1 ? '' : 's'} per symbol. '
          'First used in ${mod.firstUsed}.',
        ),
        const SizedBox(height: AppSpacing.xs),
        if (cur == null)
          ui.note(Icons.touch_app_outlined, _kEmptyPrompt)
        else
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Current symbol',
                  style: ui.text.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    c.bitsSplit(cur.sent.symbol),
                    style: scale
                        .headlineStyle(ui.mono.outputLarge)
                        .copyWith(color: colors.textAccent),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                stat(
                  'Decided as',
                  '${c.bitsSplit(cur.decided.symbol)} '
                      '${cur.isSymbolError ? '(wrong, ${cur.bitErrors} bit${cur.bitErrors == 1 ? '' : 's'} off)' : '(correct)'}',
                  color: cur.isSymbolError ? colors.statusDanger : null,
                ),
                stat(
                  'I, Q',
                  '${_C.signedD(cur.sent.i, 4)}, '
                      '${_C.signedD(cur.sent.q, 4)}',
                ),
                stat(
                  'Amplitude, phase',
                  '${cur.sent.amplitude.toStringAsFixed(4)}, '
                      '${_C.signedD(cur.sent.phase * 180 / math.pi, 1)} deg',
                ),
              ],
            ),
          ),
        if (c.source == BitSource.text && c.frame.symbols.isNotEmpty) ...[
          stat(
            'Message, ${c.messageBits} bits: ${c.textPos} of '
            '${c.frame.symbols.length} symbols'
            '${c.frame.padBits == 0 ? '' : ' (last padded ${c.frame.padBits})'}'
            '${c.passes > 0 ? ', pass ${c.passes + 1}' : ''}',
            c.hasRxSymbols ? c.decodeRx() : '-',
          ),
          if (c.lastFullRx != null) stat('Last full copy', c.lastFullRx!),
        ],
        const SizedBox(height: AppSpacing.xs),
        _ConstellationLegend(controller: controller),
        if (c.sent > 0 && !c.labelAllPoints) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          _ProbeReadout(controller: controller, labelWidth: 96),
        ],
      ],
    );
  }
}

// ── Constellation ─────────────────────────────────────────────────────────

class _ConstellationCard extends StatelessWidget {
  const _ConstellationCard({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final _C c = controller;
    return ui.card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ui.sectionLabel('Constellation (I/Q plane)'),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AspectRatio(
                aspectRatio: 1,
                child: _ConstellationPlot(controller: c),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ConstellationLegend(controller: c),
          const SizedBox(height: AppSpacing.xs),
          if (c.sent == 0)
            ui.note(Icons.touch_app_outlined, _kEmptyPrompt)
          else if (!c.labelAllPoints)
            _ProbeReadout(controller: c),
        ],
      ),
    );
  }
}

class _ConstellationPlot extends StatelessWidget {
  const _ConstellationPlot({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final _C c = controller;
    final Modulation mod = c.modulation;
    final bool labelAll = c.labelAllPoints;
    final SimulatedSymbol? cur = c.current;
    final ConstellationStyle style = ConstellationStyle(
      ideal: colors.textSecondary,
      received: colors.textAccent,
      error: colors.statusDanger,
      boundary: colors.border,
      axis: colors.borderStrong,
      highlight: colors.textPrimary,
      labelStyle: ui.mono.inlineCode.copyWith(
        fontSize: scale.paintFont(AppTextSize.caption),
        color: colors.textSecondary,
      ),
      axisLabelStyle: ui.text.labelMedium!.copyWith(
        fontSize: scale.paintFont(
          ui.text.labelMedium!.fontSize ?? AppTextSize.caption,
        ),
        color: colors.textTertiary,
      ),
      scale: scale,
    );

    final String semantic =
        'Constellation for ${mod.label}: ${mod.points} ideal points. '
        '${c.sent == 0 ? 'No symbols sent yet.' : '${c.sent} received points, ${c.symbolErrors} decided wrong.'}'
        '${cur == null ? '' : ' Current symbol ${ModulationMath.bitString(cur.sent.symbol, mod.bitsPerSymbol)}, ${cur.isSymbolError ? 'decided wrong' : 'decided correctly'}.'}';

    return Semantics(
      label: semantic,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          color: colors.surface2,
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final Size size = Size(box.maxWidth, box.maxHeight);
              final Widget paint = CustomPaint(
                size: size,
                painter: ConstellationPainter(
                  modulation: mod,
                  ideal: ModulationMath.constellation(mod),
                  cloud: c.history,
                  current: cur,
                  probe: c.probe,
                  showBitLabels: labelAll,
                  style: style,
                  revision: c.revision,
                ),
              );
              if (labelAll) return paint;
              return MouseRegion(
                onHover: (PointerHoverEvent e) =>
                    c.probeAt(e.localPosition, size),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails d) =>
                      c.probeAt(d.localPosition, size),
                  child: paint,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConstellationLegend extends StatelessWidget {
  const _ConstellationLegend({required this.controller});

  final ModulationSimulatorController controller;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    return ui.legend(<Widget>[
      ui.legendItem(ui.dot(colors.textSecondary, 3), 'Ideal point'),
      ui.legendItem(ui.dot(colors.textAccent, 3), 'Received'),
      ui.legendItem(
        Icon(Icons.close, size: 14, color: colors.statusDanger),
        'Decided wrong',
      ),
      ui.legendItem(
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.textPrimary, width: 2),
          ),
        ),
        'Current symbol',
      ),
    ]);
  }
}

class _ProbeReadout extends StatelessWidget {
  const _ProbeReadout({required this.controller, this.labelWidth = 136});

  final ModulationSimulatorController controller;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final ConstellationPoint? p = controller.probe;
    if (p == null) {
      return ui.note(
        Icons.ads_click,
        'Too many points to label them all. Tap or hover a point to see '
        'its bits.',
      );
    }
    return ui.row(
      label: 'Point',
      labelWidth: labelWidth,
      value:
          '${controller.bitsSplit(p.symbol)}  (I ${_C.signed(p.levelI)}, '
          'Q ${_C.signed(p.levelQ)})',
    );
  }
}

// ── Waveform ──────────────────────────────────────────────────────────────

class _WaveformCard extends StatelessWidget {
  const _WaveformCard({required this.controller, required this.fillHeight});

  final ModulationSimulatorController controller;

  /// Presenter: the card is given a height and the trace takes what the
  /// labels leave. Phone: the trace is a fixed strip.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final _C c = controller;
    final Modulation mod = c.modulation;
    return ui.card(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          // Fewer, wider slots on a phone so each symbol's bits still fit.
          final int slots = (box.maxWidth / 80).floor().clamp(3, 6);
          final List<SimulatedSymbol> history = c.history;
          final int start = math.max(0, history.length - slots);
          final List<SimulatedSymbol> shown = history.sublist(start);
          final List<ConstellationPoint> pts = <ConstellationPoint>[
            for (final SimulatedSymbol s in shown) s.sent,
          ];
          final String semantic = shown.isEmpty
              ? 'Carrier waveform. No symbols sent yet.'
              : 'Carrier waveform for the last ${shown.length} symbols, '
                    'bits ${shown.map((SimulatedSymbol s) => ModulationMath.bitString(s.sent.symbol, mod.bitsPerSymbol)).join(', ')}.';
          final Widget trace = Semantics(
            label: semantic,
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Container(
                height: fillHeight ? null : 140,
                color: colors.surface2,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: WaveformPainter(
                    symbols: pts,
                    slots: slots,
                    maxAmplitude: ModulationMath.maxAmplitude(mod),
                    revision: c.revision,
                    cyclesPerSymbol: kModCyclesPerSymbol,
                    style: WaveformStyle(
                      iTrace: colors.textSecondary,
                      qTrace: colors.textTertiary,
                      sum: colors.textAccent,
                      boundary: colors.borderStrong,
                      baseline: colors.border,
                      currentBar: colors.primary,
                      scale: scale,
                    ),
                  ),
                ),
              ),
            ),
          );
          final Widget legend = ui.legend(<Widget>[
            ui.legendItem(ui.lineSample(colors.textSecondary, 1), 'I cos(wt)'),
            ui.legendItem(
              ui.lineSample(colors.textTertiary, 1, dashed: true),
              '-Q sin(wt)',
            ),
            ui.legendItem(
              ui.lineSample(colors.textAccent, 3),
              'Sum: the carrier sent',
            ),
          ]);
          final Widget slowed = ui.note(
            Icons.slow_motion_video_outlined,
            'Drawn slowed down: $kModCyclesPerSymbol carrier cycles per '
            'symbol. A real Wi-Fi carrier runs billions of cycles per '
            'second. Each symbol changes only the amplitude and phase.',
          );
          return Column(
            mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ui.sectionLabel('Carrier, last $slots symbols'),
              const SizedBox(height: AppSpacing.xs),
              // Bits above each symbol slot, right-aligned like the traces.
              ExcludeSemantics(
                child: Row(
                  children: <Widget>[
                    for (int s = 0; s < slots; s++)
                      Expanded(
                        child: _SlotBits(
                          controller: c,
                          slot: s,
                          slots: slots,
                          shown: shown,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              if (fillHeight) Expanded(child: trace) else trace,
              const SizedBox(height: AppSpacing.xs),
              if (fillHeight)
                // One row on a projector: the strip keeps the height.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    legend,
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: slowed),
                  ],
                )
              else ...<Widget>[
                legend,
                const SizedBox(height: AppSpacing.xs),
                slowed,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SlotBits extends StatelessWidget {
  const _SlotBits({
    required this.controller,
    required this.slot,
    required this.slots,
    required this.shown,
  });

  final ModulationSimulatorController controller;
  final int slot;
  final int slots;
  final List<SimulatedSymbol> shown;

  @override
  Widget build(BuildContext context) {
    final ModUi ui = ModUi.of(context);
    final AppColorScheme colors = ui.colors;
    final Modulation mod = controller.modulation;
    final int idx = slot - (slots - shown.length);
    if (idx < 0) return const SizedBox(height: AppSpacing.md);
    final bool isCurrent = idx == shown.length - 1;
    final String b = ModulationMath.bitString(
      shown[idx].sent.symbol,
      mod.bitsPerSymbol,
    );
    final String display = mod.bitsPerSymbol > 6
        ? '${b.substring(0, mod.bitsPerAxis)}\n${b.substring(mod.bitsPerAxis)}'
        : b;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: ui.mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          height: 1.2,
          fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
          color: isCurrent ? colors.textAccent : colors.textTertiary,
        ),
      ),
    );
  }
}
