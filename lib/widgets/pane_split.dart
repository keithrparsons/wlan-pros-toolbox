// Where the two-pane category view splits (Keith, 2026-11-07, iPhone Duo).
//
// Side by side by default, the list 38% of the width clamped to 260-340. When
// the Duo is half open, Apple's guidance is to keep content off the fold
// (Deliverables/2026-11-07-toolbox-iphone-duo/toolbox-iphone-duo--RESEARCH.md,
// section 3), so the split moves to it: a fold running top to bottom (a book)
// becomes the divider; a fold running across (a laptop) puts the tool above
// it and the list below. Flat open, the fold is not in the way and the plain
// split stands.

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../services/device/fold_state.dart';

/// Narrowest the list or the tool pane may get beside each other.
const double kMinPaneWidth = 260;

/// Shortest the tool or the list may get above and below a laptop fold. A
/// fold closer to an edge than this (or outside the window, in a top/bottom
/// Split View) leaves the plain side-by-side split.
const double kMinStackedPaneHeight = 200;

/// Width of the divider between the panes.
const double kPaneDividerWidth = 1;

@immutable
class PaneSplit {
  const PaneSplit.sideBySide({required this.listWidth})
    : stacked = false,
      toolHeight = 0,
      listHeight = 0;

  const PaneSplit.stacked({required this.toolHeight, required this.listHeight})
    : stacked = true,
      listWidth = 0;

  /// Tool above, list below (a laptop pose), rather than side by side.
  final bool stacked;
  final double listWidth;
  final double toolHeight;
  final double listHeight;

  @override
  bool operator ==(Object other) =>
      other is PaneSplit &&
      other.stacked == stacked &&
      other.listWidth == listWidth &&
      other.toolHeight == toolHeight &&
      other.listHeight == listHeight;

  @override
  int get hashCode => Object.hash(stacked, listWidth, toolHeight, listHeight);

  @override
  String toString() => stacked
      ? 'PaneSplit.stacked(tool $toolHeight, list $listHeight)'
      : 'PaneSplit.sideBySide(list $listWidth)';
}

PaneSplit paneSplitFor(Size window, FoldState fold) {
  final double maxList = window.width - kMinPaneWidth - kPaneDividerWidth;
  if (fold.status == HingeStatus.partiallyOpen && fold.folds.isNotEmpty) {
    final Rect f = fold.folds.first;
    if (f.height >= f.width) {
      return PaneSplit.sideBySide(
        listWidth: f.left.clamp(kMinPaneWidth, maxList),
      );
    }
    final double toolHeight = f.top;
    final double listHeight = window.height - f.bottom;
    if (toolHeight >= kMinStackedPaneHeight &&
        listHeight >= kMinStackedPaneHeight) {
      return PaneSplit.stacked(toolHeight: toolHeight, listHeight: listHeight);
    }
  }
  return PaneSplit.sideBySide(
    listWidth: (window.width * 0.38).clamp(kMinPaneWidth, 340),
  );
}
