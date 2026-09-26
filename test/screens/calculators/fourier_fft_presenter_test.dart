// Presenter-mode test for Fourier and FFT, all four modes (spec 00 "Done
// means": no overflow, no page scroll at the projector sizes; the keys the
// tool declares work). Held at 1920x1080, 1440x900 and 1470x923 (a MacBook
// Air in full screen) in both themes, each mode in its fullest state: the
// five-sine square wave, the weak-neighbor lesson, a race paused part way
// (partial tallies and the status line), and all sixteen OFDM subcarriers
// on, plus Real Wi-Fi HE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_ofdm_state.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_race_state.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_stage.dart';
import 'package:wlan_pros_toolbox/services/audio/tone_engine.dart';
import 'package:wlan_pros_toolbox/services/rf/modulation_math.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_dsp.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_ofdm.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

/// A tone voice that records play and stop, with no audio device.
class _Voice implements ToneEngine {
  bool _playing = false;

  @override
  Future<ToneEngineStatus> init() async => ToneEngineStatus.ready;
  @override
  ToneEngineStatus get status => ToneEngineStatus.ready;
  @override
  bool get isPlaying => _playing;
  @override
  Future<void> playTone({required double hz, required ToneWave wave}) async =>
      _playing = true;
  @override
  Future<void> setFrequency(double hz) async {}
  @override
  Future<void> setWaveform(ToneWave wave) async {}
  @override
  Future<void> setVolume(double zeroToOne) async {}
  @override
  Future<void> stop() async => _playing = false;
  @override
  Future<void> dispose() async {}
}

Future<FourierLabModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  FourierMode mode = FourierMode.waves,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: FourierFftScreen(initialMode: mode, toneEngineFactory: _Voice.new),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('Present'));
  // One frame installs the route; then past the fade. (Not pumpAndSettle:
  // a race playback never settles while it runs.)
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<FourierStage>(find.byType(FourierStage)).model;
}

/// Puts [mode] in its fullest state.
void _fill(FourierLabModel m, FourierMode mode) {
  switch (mode) {
    case FourierMode.waves:
      m.applyPreset(WavePreset.square);
    case FourierMode.fft:
      m.applyLesson(FftLesson.weakNeighbor);
    case FourierMode.race:
      m.race.rewind();
      for (int i = 0; i < 17; i++) {
        m.race.step();
      }
    case FourierMode.ofdm:
      m.ofdm.allOn();
  }
}

void main() {
  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size window in const <Size>[
      Size(1920, 1080),
      Size(1440, 900),
      Size(1470, 923),
    ]) {
      for (final FourierMode mode in FourierMode.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${mode.name}: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final FourierLabModel m = await _present(
            tester,
            window: window,
            theme: theme(),
            mode: mode,
          );
          _fill(m, mode);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        });
      }
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
          'OFDM Real Wi-Fi HE: fits', (WidgetTester tester) async {
        final FourierLabModel m = await _present(
          tester,
          window: window,
          theme: theme(),
          mode: FourierMode.ofdm,
        );
        m.ofdm.setView(OfdmView.real);
        m.ofdm.setNumerology(OfdmNumerology.he);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
      });
    }
  }

  testWidgets('1 to 4 switch modes, and the "?" list follows the mode', (
    WidgetTester tester,
  ) async {
    final FourierLabModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(m.mode, FourierMode.race);
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('RBW up'), findsOneWidget);
    expect(find.text('OFDM is an inverse FFT mode'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(m.mode, FourierMode.fft);
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('FFT size N up'), findsOneWidget);
    expect(find.text('Next window'), findsOneWidget);
    expect(find.text('Play or pause'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(m.mode, FourierMode.waves);
    expect(tester.takeException(), isNull);
  });

  testWidgets('race: Space runs it and it keeps running under presenter '
      'mode; Space pauses, Right steps, R empties, Up widens the RBW', (
    WidgetTester tester,
  ) async {
    final FourierLabModel m = await _present(
      tester,
      window: const Size(1920, 1080),
      mode: FourierMode.race,
    );
    final FourierRaceState r = m.race;
    expect(r.progress, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(r.playing, isTrue);
    // Half the four-second playback: the clock is not muted by the route.
    await tester.pump(const Duration(seconds: 2));
    expect(r.progress, inInclusiveRange(0.4, 0.6));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(r.paused, isTrue);
    final double held = r.progress;
    await tester.pump(const Duration(seconds: 1));
    expect(r.progress, held);
    expect(find.textContaining('Paused: '), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(r.progress, closeTo(held + kRaceStepFraction, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(r.progress, 0);
    expect(r.paused, isTrue);

    expect(r.rbwHz, 100e3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(r.rbwHz, 300e3);
    // A settings change shows the whole new run.
    expect(r.progress, 1);

    // Space again, then let it finish: it settles on the full result.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(r.animating, isFalse);
    expect(r.progress, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waves: Space plays and stops the sound; Up and Down move the '
      'picked sine; R goes back to one sine', (WidgetTester tester) async {
    final FourierLabModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    m.applyPreset(WavePreset.twoClose);
    await tester.pump();
    await tester.tap(find.text('Sine 2'));
    await tester.pump();
    expect(m.editSine, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.parts[1].frequencyHz, 1150);
    expect(m.parts[0].frequencyHz, 1000);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();
    expect(find.text('Stop sound'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('Play sound'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.parts, hasLength(1));
    expect(m.preset, WavePreset.oneSine);
  });

  testWidgets('FFT: Up and Down double and halve N, W steps the window, R '
      'resets the analyzer', (WidgetTester tester) async {
    final FourierLabModel m = await _present(
      tester,
      window: const Size(1920, 1080),
      mode: FourierMode.fft,
    );
    expect(m.n, 256);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.n, 512);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(m.n, 128);
    final SpectrumWindow before = m.window;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(m.window, isNot(before));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.n, 256);
    expect(m.window, SpectrumWindow.hann);
  });

  testWidgets('OFDM: Right walks the highlight, Up raises the modulation, R '
      'resets', (WidgetTester tester) async {
    final FourierLabModel m = await _present(
      tester,
      window: const Size(1920, 1080),
      mode: FourierMode.ofdm,
    );
    expect(m.ofdm.highlight, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.ofdm.highlight, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.ofdm.highlight, 1); // wrapped: +1, +2, +3, back to +1
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.ofdm.modulation, Modulation.qam16);
    m.ofdm.allOn();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.ofdm.modulation, Modulation.qpsk);
    expect(m.ofdm.activeIndices, <int>[1, 2, 3]);
  });
}
