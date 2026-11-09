// Where the two-pane category view splits (Keith, 2026-11-07, iPhone Duo
// approach C): beside each other by default; on the fold when the Duo is half
// open like a book; tool above, list below when it is half open like a laptop.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/device/fold_state.dart';
import 'package:wlan_pros_toolbox/widgets/pane_split.dart';

FoldState _halfOpen(Rect fold) =>
    FoldState(status: HingeStatus.partiallyOpen, folds: <Rect>[fold]);

void main() {
  test('no fold: list beside the tool, 38% clamped to 320-340', () {
    expect(
      paneSplitFor(const Size(951, 669), FoldState.none),
      const PaneSplit.sideBySide(listWidth: 340),
    );
    expect(
      paneSplitFor(const Size(669, 951), FoldState.none),
      const PaneSplit.sideBySide(listWidth: 320),
    );
    expect(
      paneSplitFor(const Size(870, 600), FoldState.none),
      const PaneSplit.sideBySide(listWidth: 870 * 0.38),
    );
  });

  test(
    'a window under 641 keeps the tool at phone width; the list gives way',
    () {
      expect(
        paneSplitFor(const Size(600, 900), FoldState.none),
        const PaneSplit.sideBySide(listWidth: 279),
      );
    },
  );

  test('half open like a book: the divider sits on the fold', () {
    expect(
      paneSplitFor(
        const Size(951, 669),
        _halfOpen(const Rect.fromLTWH(475, 0, 0, 669)),
      ),
      const PaneSplit.sideBySide(listWidth: 475),
    );
  });

  test('half open like a laptop: tool above the fold, list below', () {
    expect(
      paneSplitFor(
        const Size(669, 951),
        _halfOpen(const Rect.fromLTWH(0, 470, 669, 10)),
      ),
      const PaneSplit.stacked(toolHeight: 470, listHeight: 471),
    );
  });

  test('flat open: a reported fold does not move the split', () {
    expect(
      paneSplitFor(
        const Size(951, 669),
        const FoldState(
          status: HingeStatus.fullyOpen,
          folds: <Rect>[Rect.fromLTWH(475, 0, 0, 669)],
        ),
      ),
      const PaneSplit.sideBySide(listWidth: 340),
    );
  });

  test('a fold far off center never squeezes a pane below 260', () {
    expect(
      paneSplitFor(
        const Size(951, 669),
        _halfOpen(const Rect.fromLTWH(100, 0, 0, 669)),
      ),
      const PaneSplit.sideBySide(listWidth: 260),
    );
    expect(
      paneSplitFor(
        const Size(951, 669),
        _halfOpen(const Rect.fromLTWH(900, 0, 0, 669)),
      ),
      const PaneSplit.sideBySide(listWidth: 690),
    );
  });

  test('a laptop fold near an edge, or outside the window, is ignored', () {
    // Top/bottom Split View on a half-open Duo: the fold can sit at or past
    // the edge of the app's own window.
    for (final Rect fold in <Rect>[
      const Rect.fromLTWH(0, 900, 669, 10),
      const Rect.fromLTWH(0, 40, 669, 10),
      const Rect.fromLTWH(0, 1200, 669, 10),
    ]) {
      expect(
        paneSplitFor(const Size(669, 951), _halfOpen(fold)),
        const PaneSplit.sideBySide(listWidth: 320),
        reason: '$fold',
      );
    }
  });
}
