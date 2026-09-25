// Widget and model tests for the Fourier and FFT screen (Wi-Fi Lab, part 1).
//
// The DSP has its own tests (test/services/wifi_lab/fourier_dsp_test.dart).
// These check that the screen drives it: the Waves mode edits the signal, the
// FFT mode's readouts follow Fs, N and the window, the lessons set things up,
// the sound follows the signal through a fake ToneEngine, and the layout holds
// at phone width in both themes with no sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fourier_fft_stage.dart';
import 'package:wlan_pros_toolbox/services/audio/tone_engine.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/fourier_dsp.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Records calls; reports ready (or unavailable) like a real engine would.
class _FakeVoice implements ToneEngine {
  _FakeVoice({this.works = true});

  final bool works;
  ToneEngineStatus _status = ToneEngineStatus.idle;
  bool _playing = false;
  double? hz;
  double volume = 0;
  int plays = 0;
  int stops = 0;
  bool disposed = false;

  @override
  Future<ToneEngineStatus> init() async =>
      _status = works ? ToneEngineStatus.ready : ToneEngineStatus.unavailable;

  @override
  ToneEngineStatus get status => _status;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> playTone({required double hz, required ToneWave wave}) async {
    if (!works) {
      _status = ToneEngineStatus.unavailable;
      return;
    }
    _status = ToneEngineStatus.ready;
    _playing = true;
    this.hz = hz;
    plays++;
  }

  @override
  Future<void> setFrequency(double hz) async => this.hz = hz;

  @override
  Future<void> setWaveform(ToneWave wave) async {}

  @override
  Future<void> setVolume(double zeroToOne) async => volume = zeroToOne;

  @override
  Future<void> stop() async {
    _playing = false;
    stops++;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _VoiceBank {
  _VoiceBank({this.works = true});
  final bool works;
  final List<_FakeVoice> made = <_FakeVoice>[];
  ToneEngine make() {
    final _FakeVoice v = _FakeVoice(works: works);
    made.add(v);
    return v;
  }

  List<_FakeVoice> get playing =>
      made.where((_FakeVoice v) => v.isPlaying).toList();
}

Widget _host({
  ThemeData? theme,
  _VoiceBank? bank,
  FourierMode mode = FourierMode.waves,
}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: FourierFftScreen(
    toneEngineFactory: (bank ?? _VoiceBank()).make,
    initialMode: mode,
  ),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pickFromSelect(
  WidgetTester tester,
  String current,
  String option,
) async {
  await tester.ensureVisible(find.text(current).first);
  await tester.tap(find.text(current).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  group('model', () {
    test('editing a sine makes the preset custom and clears the lesson', () {
      final FourierLabModel m = FourierLabModel()
        ..applyLesson(FftLesson.betweenBins);
      expect(m.lesson, FftLesson.betweenBins);
      m.updateSine(0, m.parts[0].copyWith(amplitude: 0.5));
      expect(m.preset, WavePreset.custom);
      expect(m.lesson, FftLesson.free);
    });

    test(
      'the square-wave preset is odd harmonics 1, 1/3 ... 1/9 of 200 Hz',
      () {
        final FourierLabModel m = FourierLabModel()
          ..applyPreset(WavePreset.square);
        expect(m.parts.map((SineComponent p) => p.frequencyHz), <double>[
          200,
          600,
          1000,
          1400,
          1800,
        ]);
        for (int i = 0; i < 5; i++) {
          expect(m.parts[i].amplitude, closeTo(1 / (2 * i + 1), 1e-12));
        }
      },
    );

    test('N stays within 64 .. 4096 and halving halves the capture', () {
      final FourierLabModel m = FourierLabModel()..setN(64);
      expect(m.canHalveN, isFalse);
      m.halveN();
      expect(m.n, 64);
      m.setN(4096);
      expect(m.canDoubleN, isFalse);
      m.doubleN();
      expect(m.n, 4096);
      m.setN(256);
      final double t = m.analysis.captureSeconds;
      m.halveN();
      expect(m.analysis.captureSeconds, t / 2);
    });

    test('the FFT is cached until an input changes', () {
      final FourierLabModel m = FourierLabModel();
      final SpectrumAnalysis a = m.analysis;
      expect(identical(a, m.analysis), isTrue);
      m.setWindow(SpectrumWindow.flatTop);
      expect(identical(a, m.analysis), isFalse);
    });

    test('never more than five sines, never fewer than one', () {
      final FourierLabModel m = FourierLabModel();
      for (int i = 0; i < 10; i++) {
        m.addSine();
      }
      expect(m.parts.length, kMaxSines);
      for (int i = 0; i < 10; i++) {
        m.removeSine(0);
      }
      expect(m.parts.length, 1);
    });
  });

  testWidgets('opens in Waves with one 1 kHz sine and both plots labelled', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 2400));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Fourier and FFT'), findsOneWidget);
    expect(find.text('Sines (1 of 5)'), findsOneWidget);
    expect(find.text('1 kHz'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Spectrum lines: 1 kHz at 0\.0 dB')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Time trace over 10 milliseconds')),
      findsOneWidget,
    );
    // Stage and controls are separate widgets (presenter layout later).
    expect(find.byType(FourierStage), findsOneWidget);
    expect(find.byType(FourierControls), findsOneWidget);
    expect(find.byType(FourierModeSelector), findsOneWidget);
  });

  testWidgets('Add stops at five sines with a note; the last sine cannot be '
      'removed', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pump();

    final Finder removeFirst = find.ancestor(
      of: find.byTooltip('Remove Sine 1'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(removeFirst).onPressed, isNull);

    for (int i = 0; i < 4; i++) {
      await _tapText(tester, 'Add a sine');
    }
    expect(find.text('Sines (5 of 5)'), findsOneWidget);
    expect(find.textContaining('Five sines is the most'), findsOneWidget);
    final Finder add = find.widgetWithText(OutlinedButton, 'Add a sine');
    expect(tester.widget<OutlinedButton>(add).onPressed, isNull);

    await tester.ensureVisible(find.byTooltip('Remove Sine 5'));
    await tester.tap(find.byTooltip('Remove Sine 5'));
    await tester.pumpAndSettle();
    expect(find.text('Sines (4 of 5)'), findsOneWidget);
    expect(find.text('Your own mix'), findsOneWidget);
  });

  testWidgets('square-wave preset puts five lines in the spectrum', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pump();
    await _pickFromSelect(tester, 'One sine', 'Square wave (odd harmonics)');
    expect(find.text('Sines (5 of 5)'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Spectrum lines: 200 Hz at 0\.0 dB; 600 Hz at -9\.5 dB'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('FFT readouts follow N and the window', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host());
    await tester.pump();
    await _tapText(tester, 'FFT');

    expect(find.text('100 Hz (Fs/N)'), findsOneWidget);
    expect(find.text('10 ms (N/Fs)'), findsOneWidget);
    expect(find.text('1.50 bins'), findsOneWidget);
    expect(find.text('150 Hz'), findsOneWidget);
    expect(find.textContaining('-32 dB published'), findsOneWidget);

    await _tapText(tester, 'Halve N');
    expect(find.text('200 Hz (Fs/N)'), findsOneWidget);
    expect(find.text('5 ms (N/Fs)'), findsOneWidget);

    await _pickFromSelect(tester, 'Hann (-32 dB)', 'Rectangular (-13 dB)');
    expect(find.text('1.00 bins'), findsOneWidget);
    expect(find.text('200 Hz'), findsOneWidget); // RBW = 1.00 x 200 Hz
  });

  testWidgets('Halve N is disabled at 64 and Double N at 4096', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host(mode: FourierMode.fft));
    await tester.pump();
    await _tapText(tester, 'Halve N');
    await _tapText(tester, 'Halve N');
    expect(find.text('400 Hz (Fs/N)'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Halve N'),
          )
          .onPressed,
      isNull,
    );
    for (int i = 0; i < 6; i++) {
      await _tapText(tester, 'Double N');
    }
    expect(find.text('6.25 Hz (Fs/N)'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Double N'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('160 ms (N/Fs)'), findsOneWidget); // 4096 / 25.6 kHz
  });

  testWidgets('the between-bins lesson reads low with Rectangular and true '
      'with Flat top', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host(mode: FourierMode.fft));
    await tester.pump();
    await _pickFromSelect(tester, 'Free play', 'Tone between bins');
    expect(
      // 3.92 dB is the window's scalloping loss; the tone's negative-
      // frequency image nudges the reading to 3.8.
      find.text('-3.8 dB at 2.1 kHz; true 0.0 dB at 2.05 kHz'),
      findsOneWidget,
    );
    await _pickFromSelect(tester, 'Rectangular (-13 dB)', 'Flat top (-88 dB)');
    expect(find.textContaining('0.0 dB at 2'), findsOneWidget);
    expect(find.textContaining('true 0.0 dB at 2.05 kHz'), findsOneWidget);
  });

  testWidgets('the Wi-Fi card shows 312.5 kHz / 3.2 us and 78.125 kHz / '
      '12.8 us', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host(mode: FourierMode.fft));
    await tester.pump();
    expect(find.text('312.5 kHz'), findsOneWidget);
    expect(find.text('3.2 µs'), findsOneWidget);
    expect(find.text('78.125 kHz'), findsOneWidget);
    expect(find.text('12.8 µs'), findsOneWidget);
  });

  group('sound', () {
    testWidgets('Play starts one voice per audible sine and follows the '
        'signal; leaving Waves stops it', (WidgetTester tester) async {
      await _setSize(tester, const Size(800, 4000));
      final _VoiceBank bank = _VoiceBank();
      await tester.pumpWidget(_host(bank: bank));
      await tester.pump();

      await _pickFromSelect(tester, 'One sine', 'Two close tones');
      await _tapText(tester, 'Play sound');
      expect(bank.playing.length, 2);
      expect(
        bank.playing.map((_FakeVoice v) => v.hz),
        containsAll(<double>[1000, 1100]),
      );
      // Two tones of amplitude 1 share the 0.5 budget.
      expect(bank.playing.first.volume, closeTo(0.25, 1e-9));
      expect(find.text('Stop sound'), findsOneWidget);

      await _pickFromSelect(tester, 'Two close tones', 'One sine');
      await tester.pumpAndSettle();
      expect(bank.playing.length, 1);
      expect(bank.playing.single.hz, 1000);

      await _tapText(tester, 'FFT');
      expect(bank.playing, isEmpty);
    });

    testWidgets('an unavailable engine shows the banner and no tone', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(800, 3000));
      final _VoiceBank bank = _VoiceBank(works: false);
      await tester.pumpWidget(_host(bank: bank));
      await tester.pump();
      await _tapText(tester, 'Play sound');
      expect(find.textContaining('No audio output detected'), findsOneWidget);
      expect(bank.playing, isEmpty);
      expect(find.text('Play sound'), findsOneWidget);
    });

    testWidgets('all amplitudes at zero disables Play and says why', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(800, 3000));
      await tester.pumpWidget(_host());
      await tester.pump();
      final Finder amp = find.byType(Slider).at(1);
      await tester.ensureVisible(amp);
      await tester.drag(amp, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(find.text('0.00 (off)'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Play sound'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('nothing to play'), findsOneWidget);
      // Once under the spectrum (stage), once in the sound card (controls).
      expect(find.textContaining('Every amplitude is zero'), findsNWidgets(2));
    });

    testWidgets('disposing the screen disposes every voice', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(800, 3000));
      final _VoiceBank bank = _VoiceBank();
      await tester.pumpWidget(_host(bank: bank));
      await tester.pump();
      await _tapText(tester, 'Play sound');
      expect(bank.made, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(bank.made.every((_FakeVoice v) => v.disposed), isTrue);
    });
  });

  for (final (String, ThemeData Function()) theme
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final FourierMode mode in FourierMode.values) {
      testWidgets('390 px, ${theme.$1}, ${mode.label}: no overflow, no '
          'sideways scroll', (WidgetTester tester) async {
        await _setSize(tester, const Size(390, 900));
        await tester.pumpWidget(_host(theme: theme.$2(), mode: mode));
        await tester.pumpAndSettle();
        if (mode == FourierMode.waves) {
          await _pickFromSelect(
            tester,
            'One sine',
            'Square wave (odd harmonics)',
          );
        } else {
          await _pickFromSelect(
            tester,
            'Free play',
            'Weak neighbor 40 dB down',
          );
        }
        expect(tester.takeException(), isNull);
        final ScrollableState s = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(s.position.axis, Axis.vertical);
        // Nothing in the page scrolls sideways.
        for (final ScrollableState each in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          if (each.position.axis == Axis.horizontal) {
            expect(each.position.maxScrollExtent, 0);
          }
        }
      });
    }
  }
}
