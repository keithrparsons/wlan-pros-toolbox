// Building blocks shared by the two tools over the one frame model
// (lib/services/wifi_lab/frame_journey_model.dart): Down the Stack, Across the
// Air, Up the Other Side (down-the-stack) and A Frame's Journey
// (frame-journey). The header hues, a PDU strip of labeled pieces, a labeled
// slider, a switch row, a choice button and a two-column readout table. Theme
// tokens only; the card and section title are Airtime Anatomy's, as the other
// Classroom tools use them.
//
// HEADER HUES (GL-003 §8.15.2, Keith 2026-09-25). Which header a byte belongs
// to IS the lesson (ports, IP addresses, MAC addresses), so each header kind
// takes one member of the Wi-Fi Classroom family (lib/theme/
// wifi_lab_client_palette.dart, contrast measured there): transport orange,
// IPv4 blue, the 802.11 header and its LLC/SNAP teal, Ethernet purple. The
// FCS takes its frame's hue. Data and bits stay neutral. Color never carries
// the meaning alone: every piece prints its name and byte count.
//
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Palette slot per header kind; null draws the piece neutral.
int? _slot(FjPart p, {bool ethernetFcs = false}) => switch (p) {
  FjPart.transport => 1,
  FjPart.ip => 6,
  FjPart.llcSnap || FjPart.wifiHeader => 4,
  FjPart.ethHeader => 7,
  FjPart.fcs => ethernetFcs ? 7 : 4,
  FjPart.data || FjPart.bits => null,
};

/// The fill and ink of one piece.
({Color fill, Color ink}) fjPieceColors(
  FjPart p,
  AppColorScheme colors, {
  bool ethernetFcs = false,
}) {
  final int? s = _slot(p, ethernetFcs: ethernetFcs);
  if (s == null) return (fill: colors.surface3, ink: colors.textPrimary);
  final WifiLabClientStyle st = WifiLabClientPalette.of(s, colors);
  return (fill: st.hue, ink: st.onHue);
}

/// The hue that marks a header kind in painted drawings (lines, outlines).
Color fjPartHue(FjPart p, AppColorScheme colors) {
  final int? s = _slot(p);
  return s == null
      ? colors.textSecondary
      : WifiLabClientPalette.of(s, colors).hue;
}

/// Spells out every abbreviation the pieces show, as a legend line.
String fjPieceLegend(List<FjPiece> pieces) {
  final Set<FjPart> parts = pieces.map((FjPiece p) => p.part).toSet();
  final List<String> out = <String>[];
  for (final FjPiece p in pieces) {
    if (p.part == FjPart.transport) {
      final String t = p.label.split(' ').first;
      out.add(
        t == 'TCP'
            ? 'TCP: Transmission Control Protocol'
            : 'UDP: User Datagram Protocol',
      );
    }
  }
  if (parts.contains(FjPart.ip)) out.add('IPv4: Internet Protocol version 4');
  if (parts.contains(FjPart.llcSnap)) {
    out.add('LLC/SNAP: logical link control and subnetwork access protocol');
  }
  if (parts.contains(FjPart.fcs)) out.add('FCS: frame check sequence');
  return out.join('. ');
}

/// A row of labeled pieces, outermost first: what the PDU looks like now.
/// Pieces this step added or changed get a heavy outline and the word "new".
class FjPduStrip extends StatelessWidget {
  const FjPduStrip({
    super.key,
    required this.pieces,
    this.changed = const <FjPart>{},
    this.action = FjAction.none,
  });

  final List<FjPiece> pieces;
  final Set<FjPart> changed;
  final FjAction action;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool eth = pieces.any((FjPiece p) => p.part == FjPart.ethHeader);
    final bool marks = action == FjAction.add || action == FjAction.change;
    return Semantics(
      label:
          'Now: ${pieces.map((FjPiece p) => p.label).join(', ')}'
          '${marks && changed.isNotEmpty ? '. New or changed: ${changed.map((FjPart p) => p.label).join(', ')}' : ''}',
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final FjPiece p in pieces)
            _Piece(
              piece: p,
              colors: fjPieceColors(p.part, colors, ethernetFcs: eth),
              marked: marks && changed.contains(p.part),
              mono: mono,
              outline: colors.primary,
              edge: p.part == FjPart.data || p.part == FjPart.bits
                  ? colors.borderStrong
                  : null,
            ),
        ],
      ),
    );
  }
}

class _Piece extends StatelessWidget {
  const _Piece({
    required this.piece,
    required this.colors,
    required this.marked,
    required this.mono,
    required this.outline,
    this.edge,
  });

  /// A visible edge for neutral pieces (their fill is close to the card's).
  final Color? edge;

  final FjPiece piece;
  final ({Color fill, Color ink}) colors;
  final bool marked;
  final AppMonoText mono;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: marked ? outline : (edge ?? colors.fill),
          width: scale.strokeWidth(marked ? 3 : 1),
        ),
      ),
      child: Text(
        marked ? '${piece.label}  new' : piece.label,
        style: mono.inlineCode.copyWith(
          color: colors.ink,
          fontWeight: marked ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// A two-column table of name / value readouts.
class FjReadoutTable extends StatelessWidget {
  const FjReadoutTable({
    super.key,
    required this.rows,
    this.highlight,
    this.fitValues = false,
  });

  final List<(String, String)> rows;

  /// Size the value column to its widest value (MAC addresses must not wrap)
  /// and let the names wrap instead.
  final bool fitValues;

  /// Row names whose value is drawn in the accent (the thing that changed).
  final Set<String>? highlight;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return Table(
      columnWidths: fitValues
          ? const <int, TableColumnWidth>{
              0: FlexColumnWidth(),
              1: IntrinsicColumnWidth(),
            }
          : const <int, TableColumnWidth>{
              0: FlexColumnWidth(1.1),
              1: FlexColumnWidth(1.4),
            },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        for (final (String name, String value) in rows)
          TableRow(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Padding(
                  padding: EdgeInsets.only(
                    right: fitValues ? AppSpacing.xs : 0,
                  ),
                  child: Text(name, style: label),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: mono.inlineCode.copyWith(
                    color: (highlight?.contains(name) ?? false)
                        ? colors.textAccent
                        : colors.textPrimary,
                    fontWeight: (highlight?.contains(name) ?? false)
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A labeled slider with its value on the right.
class FjSlider extends StatelessWidget {
  const FjSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.semanticValue,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;

  /// Null for a continuous slider (the bit picker has thousands of values).
  final int? divisions;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final String Function(double v) semanticValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool enabled = onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: enabled ? colors.textSecondary : colors.textDisabled,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                valueText,
                textAlign: TextAlign.right,
                style: mono.inlineCode.copyWith(
                  color: enabled ? colors.textPrimary : colors.textDisabled,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: semanticValue,
          ),
        ),
      ],
    );
  }
}

/// A switch with its title; the whole row toggles.
class FjSwitchRow extends StatelessWidget {
  const FjSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable outlined button, filled when selected.
class FjChoiceButton extends StatelessWidget {
  const FjChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          backgroundColor: selected ? colors.primary : null,
          foregroundColor: selected ? colors.onPrimary : colors.textPrimary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Play, step back, step, reset: the transport row both tools use.
class FjTransportRow extends StatelessWidget {
  const FjTransportRow({
    super.key,
    required this.playing,
    required this.atStart,
    required this.atEnd,
    required this.onPlay,
    required this.onBack,
    required this.onStep,
    required this.onReset,
    this.compact = false,
  });

  /// Icon buttons with tooltips (the presenter panel; the keys do the same).
  final bool compact;

  final bool playing;
  final bool atStart;
  final bool atEnd;
  final VoidCallback onPlay;
  final VoidCallback onBack;
  final VoidCallback onStep;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    ButtonStyle style() => OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppSpacing.minTouchTarget),
      foregroundColor: colors.textPrimary,
    );
    if (compact) {
      Widget b(IconData i, String tip, VoidCallback? on) => IconButton.outlined(
        onPressed: on,
        tooltip: tip,
        icon: Icon(i, semanticLabel: tip),
        style: IconButton.styleFrom(
          foregroundColor: colors.textPrimary,
          minimumSize: const Size(
            AppSpacing.minTouchTarget,
            AppSpacing.minTouchTarget,
          ),
        ),
      );
      return Row(
        children: <Widget>[
          b(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            playing ? 'Pause' : 'Play',
            onPlay,
          ),
          const SizedBox(width: AppSpacing.xs),
          b(Icons.skip_previous_rounded, 'Back', atStart ? null : onBack),
          const SizedBox(width: AppSpacing.xs),
          b(Icons.skip_next_rounded, 'Step', atEnd ? null : onStep),
          const SizedBox(width: AppSpacing.xs),
          b(Icons.replay_rounded, 'Reset', onReset),
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: onPlay,
          style: style(),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(playing ? 'Pause' : 'Play'),
        ),
        OutlinedButton.icon(
          onPressed: atStart ? null : onBack,
          style: style(),
          icon: const Icon(Icons.skip_previous_rounded),
          label: const Text('Back'),
        ),
        OutlinedButton.icon(
          onPressed: atEnd ? null : onStep,
          style: style(),
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('Step'),
        ),
        OutlinedButton.icon(
          onPressed: onReset,
          style: style(),
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Reset'),
        ),
      ],
    );
  }
}
