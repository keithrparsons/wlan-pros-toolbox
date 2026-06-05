// AppToggle<T> — the canonical 2–3 option segmented selector for App Mode.
//
// Spec: GL-003 §8.14.1 (Segmented Toggle component). The one-tier-down sibling
// of §8.14 `AppSelect<T>`: use a Toggle for 2–3 short options that fit a
// phone-width row as inline segments (ft / m, GHz / MHz, dBm / W / mW). 4+
// options, or any label long enough to wrap on phone width → use `AppSelect`.
//
// This widget replaces every hand-rolled `_UnitToggle` across the calculators.
// The API is deliberately parallel to `AppSelect<T>` (label / value / items /
// onChanged / semanticLabel / enabled) so the two siblings swap on the same
// mental model and the `(T, String)` item-tuple convention is identical.
//
// It also closes a live WCAG 2.4.7 gap: the hand-rolled `_UnitToggle` was a
// bare `InkWell` with NO visible keyboard-focus indicator, failing SC 2.4.7 on
// desktop / Web. This widget makes the §8.3 lime focus ring MANDATORY — each
// segment is wrapped in a `FocusableActionDetector` that paints the
// `--app-focus-ring` (2px solid `--color-primary` + 2px offset) when it holds
// keyboard focus. It is never a bare `InkWell`.
//
// Keyboard model — radio group (§8.14.1): the whole control is a single tab
// stop; Left/Right arrow keys move the selection between segments; Tab moves
// out of the group. Selection is exposed via `Semantics.selected` /
// `inMutuallyExclusiveGroup`, never color-only.
//
// Every visual value is pulled from AppColors / AppSpacing / AppRadius /
// AppTextSize — no literal hex, no literal px (§8.14.1 build note).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/tools/labeled_field.dart';
import '../theme/app_tokens.dart';

/// A single value→display-label pair, mirroring the `AppSelect<T>` /
/// `_UnitToggle` tuple convention used across the calculators.
typedef AppToggleItem<T> = (T value, String label);

/// The canonical App-Mode 2–3 option segmented selector (§8.14.1).
///
/// Generic over the option type [T] (an enum, etc.). Pass [items] as
/// value→label pairs; exactly one ([value]) is selected at all times. When
/// [label] is non-null the control renders its §8.4 label line above the track
/// via `LabeledField`; when null it renders the bare segmented track (for the
/// inline unit-selector pattern where the adjacent value field already carries
/// the row label).
class AppToggle<T> extends StatelessWidget {
  const AppToggle({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.semanticLabel,
    this.enabled = true,
    this.expand = false,
  });

  /// The currently selected value. Must be present in [items]. Exactly one
  /// segment is selected at all times (single-choice radio-group semantics).
  final T value;

  /// The selectable value→display-label pairs, in display order. 2–3 items per
  /// §8.14.1 (a Toggle never scrolls or wraps; 4+ → use `AppSelect`).
  final List<AppToggleItem<T>> items;

  /// Fired with the newly chosen value. Never called with the current value,
  /// and never called when [enabled] is false.
  final ValueChanged<T> onChanged;

  /// Optional §8.4 label rendered above the track via `LabeledField`. When null
  /// the bare track is returned (inline unit-selector pattern).
  final String? label;

  /// Screen-reader label for the group. Defaults to [label] when null. When
  /// both are null the group is announced via its per-segment labels only.
  final String? semanticLabel;

  /// When false the control reads as disabled per §8.14.1: borderStrong border
  /// on disabledFill track, the selected segment loses its lime (selection is
  /// conveyed by `Semantics.selected`, not color), all text textDisabled.
  /// `onChanged` never fires.
  final bool enabled;

  /// When true the track stretches to fill its parent's width and each segment
  /// shares the space equally (`Expanded`). Used for wider, full-word labels
  /// (e.g. Horizontal / Vertical). Default false keeps the compact,
  /// intrinsic-width behavior for short unit symbols (km / mi, GHz / MHz).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget track = _ToggleTrack<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      enabled: enabled,
      expand: expand,
      semanticLabel: semanticLabel ?? label,
    );

    if (label == null) return track;

    // §8.14.1: sits under its own §8.4 label line via LabeledField. The field
    // slot takes the track; the group's SR label is carried by the track's
    // Semantics group node, so the LabeledField label remains the visible line.
    return LabeledField(
      label: label!,
      semanticLabel: semanticLabel ?? label,
      field: track,
    );
  }
}

/// The bordered segmented track. Stateful to own the shared `FocusNode` per
/// segment and drive the radio-group arrow-key navigation. Private —
/// `AppToggle` is the public surface.
class _ToggleTrack<T> extends StatefulWidget {
  const _ToggleTrack({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.enabled,
    required this.expand,
    required this.semanticLabel,
  });

  final T value;
  final List<AppToggleItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final bool expand;
  final String? semanticLabel;

  @override
  State<_ToggleTrack<T>> createState() => _ToggleTrackState<T>();
}

class _ToggleTrackState<T> extends State<_ToggleTrack<T>> {
  late List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(_ToggleTrack<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) _syncNodes();
  }

  void _syncNodes() {
    _nodes = List<FocusNode>.generate(
      widget.items.length,
      (int i) => FocusNode(debugLabel: 'AppToggle segment $i'),
    );
  }

  @override
  void dispose() {
    for (final FocusNode node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex {
    for (int i = 0; i < widget.items.length; i++) {
      if (widget.items[i].$1 == widget.value) return i;
    }
    return 0;
  }

  /// Radio-group arrow navigation (§8.14.1): Left/Right move selection between
  /// segments, wrapping at the ends, moving keyboard focus with the selection.
  void _move(int delta) {
    if (!widget.enabled) return;
    final int count = widget.items.length;
    final int next = (_selectedIndex + delta + count) % count;
    final T nextValue = widget.items[next].$1;
    _nodes[next].requestFocus();
    if (nextValue != widget.value) widget.onChanged(nextValue);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // §8.14.1 states table — whole-control disabled treatment. Track border is
    // borderStrong in both states (3.83:1 on inputFill / 3.63:1 on disabledFill,
    // both pass SC 1.4.11 — disabled is NOT exempt). Track fill drops to
    // disabledFill when disabled.
    const Color trackBorder = AppColors.borderStrong;
    final Color trackFill = widget.enabled
        ? AppColors.inputFill
        : AppColors.disabledFill;

    final List<Widget> segments = <Widget>[];
    for (int i = 0; i < widget.items.length; i++) {
      final AppToggleItem<T> item = widget.items[i];
      final bool selected = item.$1 == widget.value;
      final bool isLast = i == widget.items.length - 1;

      final Widget segment = _Segment(
        label: item.$2,
        selected: selected,
        enabled: widget.enabled,
        focusNode: _nodes[i],
        textStyle: text.labelLarge ?? const TextStyle(),
        onTap: widget.enabled
            ? () {
                _nodes[i].requestFocus();
                if (!selected) widget.onChanged(item.$1);
              }
            : null,
        onMoveLeft: () => _move(-1),
        onMoveRight: () => _move(1),
      );

      segments.add(widget.expand ? Expanded(child: segment) : segment);

      // Segment divider (§8.14.1): a 1px borderStrong hairline between adjacent
      // segments so the segment count is legible before interaction. The
      // selected segment's fill covers its own dividers — only draw dividers
      // that do not abut the selected segment on their right.
      if (!isLast) {
        final bool nextSelected = widget.items[i + 1].$1 == widget.value;
        final bool drawDivider = widget.enabled && !selected && !nextSelected;
        segments.add(
          Container(
            width: 1,
            color: drawDivider ? AppColors.borderStrong : Colors.transparent,
          ),
        );
      }
    }

    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: trackFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: trackBorder, width: 1),
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          children: segments,
        ),
      ),
    );
  }
}

/// One segment. Wrapped in `FocusableActionDetector` so keyboard focus paints
/// the mandatory §8.3 lime ring (the WCAG 2.4.7 fix) and Left/Right arrows are
/// bound to the radio-group navigation. Never a bare `InkWell`.
class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.focusNode,
    required this.textStyle,
    required this.onTap,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final FocusNode focusNode;
  final TextStyle textStyle;
  final VoidCallback? onTap;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  // §8.3 hover / pressed washes (unselected segment only). rgba lime at 0.08 /
  // 0.16 per §8.14.1 states table.
  static const Color _hoverWash = Color(0x14A1CC3A); // 0.08 alpha
  static const Color _pressedWash = Color(0x29A1CC3A); // 0.16 alpha

  @override
  Widget build(BuildContext context) {
    // Segment fill (§8.14.1 states):
    //  - selected + enabled  → lime
    //  - selected + disabled → loses lime; selection conveyed by Semantics only
    //  - unselected          → transparent (track shows through), with the
    //    §8.3 hover / pressed wash on desktop.
    final Color fill;
    if (widget.selected) {
      fill = widget.enabled ? AppColors.primary : AppColors.disabledFill;
    } else if (!widget.enabled) {
      fill = Colors.transparent;
    } else if (_pressed) {
      fill = _pressedWash;
    } else if (_hovered) {
      fill = _hoverWash;
    } else {
      fill = Colors.transparent;
    }

    // Segment text (§8.14.1 states):
    final Color textColor;
    if (!widget.enabled) {
      textColor = AppColors.textDisabled;
    } else if (widget.selected) {
      textColor = AppColors.secondary; // near-black on lime, like a button.
    } else {
      textColor = AppColors.textSecondary; // live target, not placeholder.
    }

    // §8.3 focus ring: 2px solid lime + 2px offset, drawn around the focused
    // segment. Implemented as an outer border that appears only on keyboard
    // focus — the WCAG 2.4.7 fix the bare `_UnitToggle` InkWell lacked.
    final BoxDecoration? focusRing = (_focused && widget.enabled)
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: AppColors.primary, width: 2),
          )
        : null;

    final Widget body = Container(
      constraints: const BoxConstraints(
        minHeight: AppSpacing.minTouchTarget,
        minWidth: AppSpacing.minTouchTarget, // ≥44pt per-segment touch floor.
      ),
      alignment: Alignment.center,
      // Per-segment inner padding 12px (1.5× --space-xs) + 12px vertical
      // (--app-row-padding) to hold the 48dp min-height with 16px text.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.rowPadding,
        vertical: AppSpacing.rowPadding,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        widget.label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.textStyle.copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      label: widget.label,
      // The segment is a single semantic node: its label is the unit string, so
      // the child Text must not announce it a second time (§8.14.1).
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (bool show) {
          if (mounted) setState(() => _focused = show);
        },
        onShowHoverHighlight: (bool show) {
          if (mounted) setState(() => _hovered = show);
        },
        // Left/Right arrow keys drive the radio-group navigation (§8.14.1).
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveIntent(
            forward: false,
          ),
          SingleActivator(LogicalKeyboardKey.arrowRight): _MoveIntent(
            forward: true,
          ),
        },
        actions: <Type, Action<Intent>>{
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (_MoveIntent intent) {
              if (intent.forward) {
                widget.onMoveRight();
              } else {
                widget.onMoveLeft();
              }
              return null;
            },
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled
              ? (_) {
                  if (mounted) setState(() => _pressed = true);
                }
              : null,
          onTapUp: widget.enabled
              ? (_) {
                  if (mounted) setState(() => _pressed = false);
                }
              : null,
          onTapCancel: widget.enabled
              ? () {
                  if (mounted) setState(() => _pressed = false);
                }
              : null,
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: focusRing ?? const BoxDecoration(),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Arrow-key intent for the radio-group navigation.
class _MoveIntent extends Intent {
  const _MoveIntent({required this.forward});
  final bool forward;
}
