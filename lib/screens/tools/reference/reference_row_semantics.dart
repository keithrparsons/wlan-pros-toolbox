// ReferenceRowSemantics — the shared screen-reader grouping idiom for every
// reference-table row across lib/screens/tools/reference/.
//
// Why this exists (Vera F-02):
// The reference tables render each data row as a Column/Row of independent
// Text nodes. To a sighted user the columns visually belong to one row; to a
// screen-reader user each cell was announced as a *separate* node with no
// signal that "5 GHz", "20 MHz", "36" belong together. The reader could not
// tell where one row ended and the next began.
//
// The fix is a Semantics treatment applied uniformly:
//   Semantics(container: true, label: <row summary keyed on the first column>,
//   excludeSemantics: true) — forces the row to be ONE accessibility node with
//   a coherent spoken label, e.g. "Channel 36: 5 GHz, 20 MHz, UNII-1", and
//   suppresses the per-cell child labels so they are not re-read after the
//   summary. This mirrors the hand-written rows already shipping in this
//   directory (osi_model, reason_codes, roaming, signal_thresholds,
//   wpa_security), now factored into one shared widget for consistency.
//
// For list-style cards whose children are already complete sentences (AP
// placement) or must stay selectable (standards' SelectableText ValueRows), set
// `merge: false`: the card is still announced as one labelled container, but
// the children keep their own semantics and stay individually navigable.
//
// Build the [label] from the row's key column first (the value a user scans by
// — channel number, standard name, reason code), then the remaining columns as
// a comma-joined clause. Use [rowLabel] to assemble that string consistently.
//
// Idempotent and cheap: this is a const-constructible wrapper, so applying it
// to ~200 rows adds no measurable cost and no new tokens.

import 'package:flutter/widgets.dart';

/// Wraps one reference-table data row so a screen reader announces it as a
/// single coherent node labelled by its key column.
///
/// Place it as the outermost widget a per-row builder returns, wrapping the
/// existing Padding/Column/Row tree unchanged.
class ReferenceRowSemantics extends StatelessWidget {
  const ReferenceRowSemantics({
    super.key,
    required this.label,
    required this.child,
    this.merge = true,
  });

  /// The spoken summary for the whole row. Build it with [rowLabel] so every
  /// table reads in the same `<key>: <col>, <col>, …` shape.
  final String label;

  /// The unmodified row content (the visual Column/Row of cells).
  final Widget child;

  /// When true (the default, for true tabular rows split across columns), the
  /// child cells' own semantics are excluded and the row reads as one node with
  /// exactly [label] — the same idiom the hand-written rows in this directory
  /// use (osi_model `_LayerRow`, reason_codes `_CodeRow`, roaming
  /// `_ProtocolBlock`). Using excludeSemantics rather than MergeSemantics avoids
  /// the child Text labels being appended after the explicit summary (which
  /// would double-read every value).
  ///
  /// When false (for list-style cards whose children are already complete
  /// sentences, e.g. AP-placement guidance, or SelectableText ValueRows that
  /// must stay selectable, e.g. standards), the row is announced as one
  /// container labelled by its key column, but the children stay individually
  /// navigable so a reader can step through each line.
  final bool merge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: merge,
      child: child,
    );
  }
}

/// Assembles a consistent row summary: the key column, a colon, then the
/// remaining columns as a comma-separated clause.
///
/// Empty / dash (`—`) / null values are dropped so the reader never hears
/// "dash" or a dangling comma. Example:
/// `rowLabel('Channel 36', ['5 GHz', '20 MHz', 'UNII-1'])`
/// → `"Channel 36: 5 GHz, 20 MHz, UNII-1"`.
String rowLabel(String key, List<String?> columns) {
  final List<String> parts = <String>[];
  for (final String? c in columns) {
    if (c == null) continue;
    final String t = c.trim();
    if (t.isEmpty || t == '—' || t == '-') continue;
    parts.add(t);
  }
  final String head = key.trim();
  if (parts.isEmpty) return head;
  return '$head: ${parts.join(', ')}';
}
