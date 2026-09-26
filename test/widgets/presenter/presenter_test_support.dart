// Shared helpers for presenter-layout tests (shell and per-tool).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

/// Records every full-screen call instead of touching a window.
class FakePresenterWindow implements PresenterWindowControl {
  bool full = false;
  final List<bool> calls = <bool>[];

  @override
  bool get supportsFullScreen => true;

  @override
  Future<bool> isFullScreen() async => full;

  @override
  Future<bool> setFullScreen(bool fullScreen) async {
    calls.add(fullScreen);
    full = fullScreen;
    return fullScreen;
  }
}

/// Installs a [FakePresenterWindow] for one test.
FakePresenterWindow installFakeWindow() {
  final PresenterWindowControl previous = PresenterWindow.control;
  final FakePresenterWindow fake = FakePresenterWindow();
  PresenterWindow.control = fake;
  addTearDown(() => PresenterWindow.control = previous);
  return fake;
}

/// Sets the test window to [size] logical pixels at 1x.
void setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Every vertical Scrollable on screen other than the controls panel's own.
/// The presenter layout has no page scroll, so a tool's presenter test
/// expects this to be empty.
List<ScrollableState> pageScrollables(WidgetTester tester) {
  final Finder panel = find.byKey(PresenterLayout.controlsScrollKey);
  final Set<Element> panelScrollables = find
      .descendant(of: panel, matching: find.byType(Scrollable))
      .evaluate()
      .take(1)
      .toSet();
  return tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where(
        (ScrollableState s) =>
            s.widget.axisDirection == AxisDirection.down &&
            !panelScrollables.contains(s.context as Element),
      )
      .where((ScrollableState s) {
        // Only scrollables that can actually move count as a page scroll.
        final ScrollPosition p = s.position;
        return p.hasContentDimensions && p.maxScrollExtent > 0;
      })
      .toList();
}

/// How far the controls panel could scroll (0 means everything fits).
double controlsOverflow(WidgetTester tester) {
  final ScrollableState s = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(PresenterLayout.controlsScrollKey),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  return s.position.maxScrollExtent;
}

/// The painted bounds of [finder] must sit inside the window.
void expectOnScreen(WidgetTester tester, Finder finder, Size window) {
  final RenderBox box = tester.renderObject<RenderBox>(finder);
  final Rect r = box.localToGlobal(Offset.zero) & box.size;
  expect(
    Offset.zero & window,
    predicate<Rect>(
      (Rect w) =>
          r.left >= w.left - 0.5 &&
          r.top >= w.top - 0.5 &&
          r.right <= w.right + 0.5 &&
          r.bottom <= w.bottom + 0.5,
      'contains $r',
    ),
  );
}
