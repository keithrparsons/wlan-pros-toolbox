// Widget smoke tests for the "Hear the Frequency" screen + piano keyboard.
//
// A fake ToneEngine is injected so the tests need no real audio device: it
// records calls and reports itself ready, exactly as a working engine would.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/music_theory.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/hear_frequency_screen.dart';
import 'package:wlan_pros_toolbox/services/audio/tone_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/piano_keyboard.dart';

/// Records engine calls; reports ready so the screen behaves as if audio works.
class _FakeToneEngine implements ToneEngine {
  ToneEngineStatus _status = ToneEngineStatus.idle;
  bool _playing = false;
  double? lastHz;
  ToneWave? lastWave;
  int playCount = 0;
  int stopCount = 0;
  int retuneCount = 0;

  @override
  Future<ToneEngineStatus> init() async => _status = ToneEngineStatus.ready;

  @override
  ToneEngineStatus get status => _status;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> playTone({required double hz, required ToneWave wave}) async {
    _status = ToneEngineStatus.ready;
    _playing = true;
    lastHz = hz;
    lastWave = wave;
    playCount++;
  }

  @override
  Future<void> setFrequency(double hz) async {
    lastHz = hz;
    retuneCount++;
  }

  @override
  Future<void> setWaveform(ToneWave wave) async => lastWave = wave;

  @override
  Future<void> setVolume(double zeroToOne) async {}

  @override
  Future<void> stop() async {
    _playing = false;
    stopCount++;
  }

  @override
  Future<void> dispose() async {}
}

Widget _host(_FakeToneEngine engine) => MaterialApp(
      theme: AppTheme.dark(),
      home: HearFrequencyScreen(engine: engine),
    );

void main() {
  group('HearFrequencyScreen', () {
    testWidgets('renders the title, transport, presets, and piano keyboard',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(_FakeToneEngine()));
      await tester.pump();

      expect(find.text('Hear the Frequency'), findsWidgets);
      expect(find.text('Play'), findsOneWidget);
      expect(find.byType(PianoKeyboard), findsOneWidget);
      // Octave controls.
      expect(find.text('x2 (up)'), findsOneWidget);
      expect(find.text('div 2 (down)'), findsOneWidget);
      // The default 440 readout resolves to A4.
      expect(find.text('A4'), findsWidgets);
    });

    testWidgets('Play starts a tone at the typed frequency, Stop ends it',
        (WidgetTester tester) async {
      final _FakeToneEngine engine = _FakeToneEngine();
      await tester.pumpWidget(_host(engine));
      await tester.pump();

      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(engine.playCount, 1);
      expect(engine.lastHz, 440);
      expect(engine.lastWave, ToneWave.sine); // default waveform
      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(engine.stopCount, 1);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('x2 octave button doubles the frequency field',
        (WidgetTester tester) async {
      final _FakeToneEngine engine = _FakeToneEngine();
      await tester.pumpWidget(_host(engine));
      await tester.pump();

      await tester.tap(find.text('x2 (up)'));
      await tester.pump();
      // 440 -> 880 in the field.
      expect(find.widgetWithText(TextField, '880'), findsOneWidget);
    });

    testWidgets('out-of-range input blocks playback and shows the inline note',
        (WidgetTester tester) async {
      final _FakeToneEngine engine = _FakeToneEngine();
      await tester.pumpWidget(_host(engine));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '30000');
      await tester.pump();
      expect(find.textContaining('high edge of hearing'), findsOneWidget);

      // Play is disabled (the button's onPressed is null), so a tap does nothing.
      final FilledButton play = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Play'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(play.onPressed, isNull);
    });

    testWidgets('tapping a piano key plays its note frequency',
        (WidgetTester tester) async {
      final _FakeToneEngine engine = _FakeToneEngine();
      await tester.pumpWidget(_host(engine));
      await tester.pump();

      // Find the middle-C white key by its semantics label, scroll it into
      // view (it sits below the fold in the test viewport), then tap it.
      final Note middleC = MusicTheory.noteForKey(40); // C4 261.63
      final Finder key = find.bySemanticsLabel(
        RegExp('${middleC.label}, ${middleC.frequencyHz.toStringAsFixed(2)}'),
      );
      await tester.ensureVisible(key);
      await tester.pump();
      await tester.tap(key);
      await tester.pump();
      expect(engine.playCount, greaterThanOrEqualTo(1));
      expect(engine.lastHz, closeTo(261.63, 0.01));
    });
  });

  group('PianoKeyboard', () {
    testWidgets('renders all 13 keys C4..C5 as semantic buttons',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: PianoKeyboard(
              notes: MusicTheory.chromaticC4toC5,
              onKeyTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      // 13 InkWell keys.
      expect(find.byType(InkWell), findsNWidgets(13));
    });
  });
}
