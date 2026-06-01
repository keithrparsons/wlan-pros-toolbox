// AppSelect<T> — the canonical single-choice selector for App Mode.
//
// Spec: GL-003 §8.14 (Select / Dropdown component). This widget replaces every
// per-calculator hand-rolled `DropdownButton` (the former `_UnitMenu`,
// `_cableSelectorField`, and the K-factor dropdown). One reusable generic
// control ends the drift the spec calls out.
//
// When to use Select vs Toggle (§8.14): use this Select for 4+ options, or
// labels long enough to wrap on phone width (cable types, the seven length
// units, the four K-factor labels). Use the segmented `_UnitToggle` for 2–3
// short options (ft/m, GHz/MHz, dBm/W/mW). The Select is the default for
// anything that does not trivially fit as 2–3 chips.
//
// Every visual value is pulled from AppColors / AppSpacing / AppRadius /
// AppTextSize — no literal hex, no literal px (§8.14 build note).
//
// Anatomy (§8.14): a bordered control on `AppColors.inputFill`, idle border
// `borderStrong` 1px, focus/open border `primary` 2px, control radius
// `AppRadius.control`. The value label is flex and ellipsizes (`isExpanded`);
// the trailing chevron is `Icons.expand_more`, flipping to `expand_less` while
// the menu is open. The popped menu sits on `AppColors.surface2` with the card
// radius, selected item in lime `primary`. Error state swaps the border to
// `AppColors.statusDanger` and renders the message in the §8.4 helper slot.
//
// Accessibility (§8.14): designed to sit inside the `LabeledField` primitive
// (label above, semantic association). The control node carries
// `Semantics(label, button: true, value: <current selection display>)` so
// VoiceOver / TalkBack announce the field name, role, and current value.

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A single value→display-label pair, mirroring the `_UnitToggle` tuple
/// convention already used across the calculators.
typedef AppSelectItem<T> = (T value, String label);

/// The canonical App-Mode single-choice selector (§8.14).
///
/// Generic over the option type [T] (an enum, a `String` cable type, etc.).
/// Pass [items] as value→label pairs; the matching label for [value] renders in
/// the control. Wrap in `LabeledField` for the visible label-above-field line
/// and screen-reader association; pass that same label here as [semanticLabel]
/// so the control announces its name, role, and current value.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.semanticLabel,
    this.enabled = true,
    this.errorText,
    this.minWidth,
  });

  /// The currently selected value. Must be present in [items].
  final T value;

  /// The selectable value→display-label pairs, in display order.
  final List<AppSelectItem<T>> items;

  /// Fired with the newly chosen value. Never called with the current value.
  final ValueChanged<T> onChanged;

  /// Screen-reader label for the control (the field's purpose, e.g.
  /// "From unit"). Announced together with the current selection as the
  /// `Semantics.value`. Defaults to nothing extra when null — provide it (or
  /// rely on a wrapping `LabeledField`) so the control is never announced
  /// nameless.
  final String? semanticLabel;

  /// When false the control reads as disabled per §8.14: disabledFill fill +
  /// border, textDisabled value text and chevron (3.58:1 — not exempt from
  /// contrast). `onChanged` never fires.
  final bool enabled;

  /// When non-null the control swaps to the §8.13/§8.4 error treatment:
  /// `statusDanger` 2px border plus this message rendered in the helper slot
  /// below (never color-only — §8.13 rule 2).
  final String? errorText;

  /// Optional minimum control width. The compact unit-symbol selects use 88px
  /// (the §8.14 floor that fits "nmi"/"GHz"); full-width selects pass null and
  /// take the row width via the surrounding `Expanded`/`Flexible`.
  final double? minWidth;

  /// Resolve the display label for [value] from [items]; falls back to the raw
  /// `toString()` only if the value is somehow absent (defensive — items should
  /// always contain it).
  String get _displayLabel {
    for (final AppSelectItem<T> item in items) {
      if (item.$1 == value) return item.$2;
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasError = errorText != null;

    // §8.14 state table — border + foreground per enabled / error / idle.
    final Color borderColor;
    final double borderWidth;
    final Color fillColor;
    final Color valueColor;
    final Color chevronColor;

    if (!enabled) {
      // §8.14 States table (border corrected 2026-06-01, Vera finding #4): the
      // disabled border is `borderStrong` (#808080) = 3.63:1 on the #2A2A2A
      // disabled fill (SC 1.4.11), not `disabledFill` — that was ~1.1:1,
      // imperceptible, leaving the disabled control with no visible boundary.
      borderColor = AppColors.borderStrong;
      borderWidth = 1;
      fillColor = AppColors.disabledFill;
      valueColor = AppColors.textDisabled;
      chevronColor = AppColors.textDisabled;
    } else if (hasError) {
      borderColor = AppColors.statusDanger;
      borderWidth = 2;
      fillColor = AppColors.inputFill;
      valueColor = AppColors.textPrimary;
      chevronColor = AppColors.textSecondary;
    } else {
      borderColor = AppColors.borderStrong;
      borderWidth = 1;
      fillColor = AppColors.inputFill;
      valueColor = AppColors.textPrimary;
      chevronColor = AppColors.textSecondary;
    }

    // The value text style: §8.4 field text — body / IBM Plex Sans / textPrimary
    // (weight 500 acceptable for short unit symbols, matching the prior
    // `_UnitMenu`). Disabled / error recolor handled via `valueColor`.
    final TextStyle valueStyle = (text.labelLarge ?? const TextStyle())
        .copyWith(color: valueColor);

    final Widget control = _SelectControl<T>(
      value: value,
      items: items,
      enabled: enabled,
      onChanged: onChanged,
      fillColor: fillColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      valueStyle: valueStyle,
      chevronColor: chevronColor,
      minWidth: minWidth,
      menuItemStyle: (text.bodyLarge ?? const TextStyle()).copyWith(
        color: AppColors.textPrimary,
      ),
      selectedItemStyle: (text.bodyLarge ?? const TextStyle()).copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w500,
      ),
    );

    // Semantics: announce name, button role, and current selection value.
    final Widget semantic = Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      value: _displayLabel,
      child: control,
    );

    if (!hasError) return semantic;

    // §8.13 rule 2 — never color-only. The danger border is paired with a text
    // error message in the §8.4 helper slot below the control.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        semantic,
        const SizedBox(height: AppSpacing.xs),
        Text(
          errorText!,
          style: (text.labelSmall ?? const TextStyle()).copyWith(
            color: AppColors.statusDanger,
          ),
        ),
      ],
    );
  }
}

/// The bordered control + popped menu. Stateful only to track whether the menu
/// is open so the chevron can flip (`expand_more` → `expand_less`) and the
/// border can switch to the §8.14 "open" treatment (2px lime), mirroring the
/// keyboard-focus treatment. Kept private — `AppSelect` is the public surface.
class _SelectControl<T> extends StatefulWidget {
  const _SelectControl({
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    required this.valueStyle,
    required this.chevronColor,
    required this.minWidth,
    required this.menuItemStyle,
    required this.selectedItemStyle,
  });

  final T value;
  final List<AppSelectItem<T>> items;
  final bool enabled;
  final ValueChanged<T> onChanged;

  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final TextStyle valueStyle;
  final Color chevronColor;
  final double? minWidth;
  final TextStyle menuItemStyle;
  final TextStyle selectedItemStyle;

  @override
  State<_SelectControl<T>> createState() => _SelectControlState<T>();
}

class _SelectControlState<T> extends State<_SelectControl<T>> {
  bool _open = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // §8.14 "open" / focus: a 2px lime border replaces the idle border while
    // the menu is open OR the control holds keyboard focus — but never override
    // the error border (the parent passes statusDanger at 2px and we must keep
    // the failing state visible). Error is signalled by borderWidth == 2 with a
    // non-primary color, so only promote to lime when the resting border is the
    // idle borderStrong.
    final bool isIdleBorder = widget.borderColor == AppColors.borderStrong;
    final bool active = widget.enabled && (_open || _focused) && isIdleBorder;

    final Color effectiveBorder = active
        ? AppColors.primary
        : widget.borderColor;
    final double effectiveWidth = active ? 2 : widget.borderWidth;

    return Container(
      constraints: BoxConstraints(
        minHeight: AppSpacing.minTouchTarget,
        minWidth: widget.minWidth ?? 0,
      ),
      decoration: BoxDecoration(
        color: widget.fillColor,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: effectiveBorder, width: effectiveWidth),
      ),
      // §8.14 horizontal padding 16px (--space-sm) so a Select and a text field
      // in the same row align on their inner content edge. Vertical padding via
      // the 48dp min-height + DropdownButton's own layout.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: DropdownButtonHideUnderline(
        child: Focus(
          onFocusChange: (bool hasFocus) {
            if (!mounted) return;
            setState(() {
              _focused = hasFocus;
              // The menu closes when focus leaves the control (selection,
              // tap-outside, or Escape all defocus it), so reset the open flag
              // here too — this is what flips the chevron back to expand_more
              // even when the menu is dismissed without a selection.
              if (!hasFocus) _open = false;
            });
          },
          child: DropdownButton<T>(
            value: widget.value,
            isExpanded: true,
            // Menu surface: §8.1 surface2, §8.11 card radius (the menu is a
            // separate container, so it takes the card curve, not the control's).
            dropdownColor: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
            // Chevron flips while open (§8.14). 24px nav-icon affordance.
            icon: Icon(
              _open ? Icons.expand_less : Icons.expand_more,
              color: widget.chevronColor,
            ),
            iconSize: AppSpacing.md, // 24px == --app-icon-nav
            style: widget.valueStyle,
            focusColor: Colors.transparent,
            // Cap the open menu to ~5 rows then scroll (§8.14 sizing).
            menuMaxHeight: AppSpacing.minTouchTarget * 5,
            onTap: widget.enabled
                ? () {
                    if (mounted) setState(() => _open = true);
                  }
                : null,
            onChanged: widget.enabled
                ? (T? next) {
                    if (mounted) setState(() => _open = false);
                    if (next != null && next != widget.value) {
                      widget.onChanged(next);
                    }
                  }
                : null,
            // selectedItemBuilder paints the closed-state value with ellipsis so
            // a long label (cable type) never overflows the bounded control.
            selectedItemBuilder: (BuildContext context) {
              return widget.items.map((AppSelectItem<T> item) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.valueStyle,
                  ),
                );
              }).toList();
            },
            items: widget.items.map((AppSelectItem<T> item) {
              final bool selected = item.$1 == widget.value;
              return DropdownMenuItem<T>(
                value: item.$1,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: selected
                            ? widget.selectedItemStyle
                            : widget.menuItemStyle,
                      ),
                    ),
                    // Selected row carries a lime check glyph in addition to the
                    // lime text — the active/selected role (§8.14), distinct
                    // from a status verdict.
                    if (selected)
                      const Icon(
                        Icons.check,
                        size: AppSpacing.sm, // 16px == --app-icon-sm
                        color: AppColors.primary,
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
