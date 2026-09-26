// Tests for the Wi-Fi Classroom presenter shell (lib/widgets/presenter/), against
// the "Done means" of myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 00-presenter-layout.md:
//   - the layout at 1920x1080 and 1440x900 shows stage and controls with no
//     page scroll;
//   - Esc exits (and restores the window);
//   - Space and Right arrow call the tool's actions; unsupported keys do
//     nothing;
//   - the Present button is hidden on phone-sized windows and shown on
//     desktop ones;
//   - state set before entering is still set inside presenter mode and after
//     exiting (tested on the Modulation pilot, whose state is real).
// Plus: entering asks for full screen, F toggles it, "?" lists only the keys
// the tool supports, and a focused text field keeps its keys.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/modulation_simulator_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/theme_controller.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import 'presenter_test_support.dart';

class _Counter {
  int play = 0;
  int step = 0;
  int reset = 0;
  int up = 0;
  int down = 0;
}

/// A home screen with one button that opens a presenter layout.
Widget _app({
  required PresenterActions actions,
  ThemeData? theme,
  Widget? controls,
  ThemeController? themeController,
}) {
  final Widget app = MaterialApp(
    theme: theme ?? AppTheme.dark(),
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openPresenter(
              context,
              toolRoute: '/tools/test',
              builder: (_) => PresenterLayout(
                title: 'Test Tool',
                stage: const ColoredBox(
                  color: Color(0x00000000),
                  child: SizedBox.expand(child: Text('STAGE')),
                ),
                controls:
                    controls ??
                    const Column(
                      children: <Widget>[
                        Text('CONTROLS'),
                        TextField(key: ValueKey<String>('field')),
                      ],
                    ),
                actions: actions,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  if (themeController == null) return app;
  return ThemeControllerScope(controller: themeController, child: app);
}

PresenterActions _actions(_Counter c) => PresenterActions(
  playPause: () => c.play++,
  step: () => c.step++,
  reset: () => c.reset++,
  sliderDown: () => c.down++,
  sliderUp: () => c.up++,
  sliderLabel: 'Test slider',
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final Size window in const <Size>[
    Size(1920, 1080),
    Size(1440, 900),
    // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
    Size(1470, 923),
  ]) {
    testWidgets('at ${window.width.toInt()}x${window.height.toInt()} stage and '
        'controls show side by side with no page scroll', (
      WidgetTester tester,
    ) async {
      setWindow(tester, window);
      installFakeWindow();
      await tester.pumpWidget(_app(actions: PresenterActions.none));
      await _open(tester);

      expect(find.text('STAGE'), findsOneWidget);
      expect(find.text('CONTROLS'), findsOneWidget);
      final Rect stage = tester.getRect(find.byKey(PresenterLayout.stageKey));
      final Rect controls = tester.getRect(
        find.byKey(PresenterLayout.controlsKey),
      );
      // Stage left, controls right, the stage about two-thirds.
      expect(stage.right, lessThan(controls.left));
      expect(stage.width / window.width, closeTo(0.64, 0.06));
      // Stage fills the height below the bar.
      expect(stage.bottom, greaterThan(window.height - 40));
      expect(pageScrollables(tester), isEmpty);
      expect(controlsOverflow(tester), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('entering asks for full screen; Esc exits and restores it', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    final FakePresenterWindow win = installFakeWindow();
    await tester.pumpWidget(_app(actions: PresenterActions.none));
    await _open(tester);
    expect(win.calls, <bool>[true]);
    expect(find.text('STAGE'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('STAGE'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(win.calls, <bool>[true, false]);
  });

  testWidgets('a window already full screen is left full screen on exit', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    final FakePresenterWindow win = installFakeWindow()..full = true;
    await tester.pumpWidget(_app(actions: PresenterActions.none));
    await _open(tester);
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(win.calls, isEmpty);
    expect(win.full, isTrue);
  });

  testWidgets('F toggles full screen and stays in presenter mode', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    final FakePresenterWindow win = installFakeWindow();
    await tester.pumpWidget(_app(actions: PresenterActions.none));
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(win.full, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(win.full, isTrue);
    expect(find.text('STAGE'), findsOneWidget);
  });

  testWidgets('Space, Right, R, Up/Down and brackets call the tool actions', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    final _Counter c = _Counter();
    await tester.pumpWidget(_app(actions: _actions(c)));
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.play, 1);
    expect(c.step, 2);
    expect(c.reset, 1);
    expect(c.up, 2);
    expect(c.down, 2);
  });

  testWidgets('keys a tool does not declare do nothing', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final _Counter c = _Counter();
    await tester.pumpWidget(
      _app(actions: PresenterActions(step: () => c.step++)),
    );
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.step, 1);
    expect(find.text('STAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcuts never fire with Cmd held (Cmd+R stays the system)', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final _Counter c = _Counter();
    await tester.pumpWidget(_app(actions: _actions(c)));
    await _open(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(c.reset, 0);
  });

  testWidgets('a focused text field keeps Space; Esc leaves it, then exits', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final _Counter c = _Counter();
    await tester.pumpWidget(_app(actions: _actions(c)));
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey<String>('field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.play, 0);
    expect(c.reset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('STAGE'), findsOneWidget, reason: 'first Esc leaves');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(c.play, 1, reason: 'keys are back once the field is left');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('STAGE'), findsNothing);
  });

  testWidgets('? lists only the keys the tool declares; Esc closes it first', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final _Counter c = _Counter();
    await tester.pumpWidget(
      _app(actions: PresenterActions(step: () => c.step++)),
    );
    await _open(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.byKey(PresenterLayout.shortcutsKey), findsOneWidget);
    expect(find.text('Right arrow'), findsOneWidget);
    expect(find.text('Space'), findsNothing);
    expect(find.text('R'), findsNothing);
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(PresenterLayout.shortcutsKey), findsNothing);
    expect(find.text('STAGE'), findsOneWidget);
  });

  testWidgets('the Shortcuts button opens the same list', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    await tester.pumpWidget(_app(actions: _actions(_Counter())));
    await _open(tester);
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('Test slider up'), findsOneWidget);
    expect(find.text('Play or pause'), findsOneWidget);
  });

  testWidgets('the top bar fades after the delay and returns on movement', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    await tester.pumpWidget(_app(actions: PresenterActions.none));
    await _open(tester);
    double opacity() => tester
        .widget<AnimatedOpacity>(find.byKey(PresenterLayout.barKey))
        .opacity;
    expect(opacity(), 1);
    await tester.pump(kPresenterBarHideDelay + const Duration(seconds: 1));
    expect(opacity(), 0);
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: const Offset(400, 400));
    await mouse.moveTo(const Offset(420, 420));
    await tester.pump();
    expect(opacity(), 1);
    await mouse.removePointer();
    await tester.pumpAndSettle(kPresenterBarHideDelay);
  });

  testWidgets('the theme toggle flips light and dark', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final ThemeController themes = ThemeController(initialMode: ThemeMode.dark);
    await tester.pumpWidget(
      _app(actions: PresenterActions.none, themeController: themes),
    );
    await _open(tester);
    // The host app here is not wired to the controller's mode, so this checks
    // the call, not the repaint (main.dart owns that wiring).
    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(themes.mode, ThemeMode.light);
  });

  group('Present button', () {
    Widget host() => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(
          actions: <Widget>[
            PresentButton(
              toolRoute: '/tools/test',
              builder: (_) => const PresenterLayout(
                title: 'T',
                stage: SizedBox(),
                controls: SizedBox(),
              ),
            ),
          ],
        ),
      ),
    );

    for (final (Size size, bool shown) in <(Size, bool)>[
      (const Size(390, 844), false), // phone, portrait
      (const Size(932, 430), false), // large phone, landscape
      (const Size(700, 900), false), // narrow window
      (const Size(800, 600), true), // the macOS default window
      (const Size(1024, 768), true),
      (const Size(1920, 1080), true),
    ]) {
      testWidgets('${shown ? 'shown' : 'hidden'} at '
          '${size.width.toInt()}x${size.height.toInt()}', (
        WidgetTester tester,
      ) async {
        setWindow(tester, size);
        await tester.pumpWidget(host());
        expect(find.text('Present'), shown ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('opens the presenter route by name', (
      WidgetTester tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      installFakeWindow();
      final List<String?> pushed = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          navigatorObservers: <NavigatorObserver>[_NameObserver(pushed.add)],
          home: Scaffold(
            appBar: AppBar(
              actions: <Widget>[
                PresentButton(
                  toolRoute: '/tools/test',
                  builder: (_) => const PresenterLayout(
                    title: 'T',
                    stage: SizedBox(),
                    controls: SizedBox(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      expect(pushed.last, '/tools/test/present');
      expect(find.byType(PresenterLayout), findsOneWidget);
    });
  });

  testWidgets('state set before entering holds inside presenter and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const ModulationSimulatorScreen(seed: 1),
      ),
    );
    await tester.pumpAndSettle();
    // Set a scene on the normal screen: two symbols and SNR 10 dB.
    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.tap(find.text('Step'));
    await tester.pump();
    final ModulationSimulatorController c = tester
        .widget<ModulationSimulatorStage>(find.byType(ModulationSimulatorStage))
        .controller;
    c.setSnr(10);
    c.step();
    await tester.pump();
    expect(c.sent, 1);

    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsOneWidget);
    expect(find.text('10.0 dB'), findsOneWidget);
    expect(find.textContaining(' of 1 ('), findsOneWidget); // symbol errors

    // Change it while presenting.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.snrDb, 11);
    expect(c.sent, 0, reason: 'changing SNR clears the run, as on the phone');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.sent, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(find.text('11.0 dB'), findsOneWidget);
    expect(c.sent, 1);
  });
}

class _NameObserver extends NavigatorObserver {
  _NameObserver(this.onPush);

  final void Function(String?) onPush;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onPush(route.settings.name);
}
