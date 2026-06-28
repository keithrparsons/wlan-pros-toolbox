// Hear the Frequency — RF-by-ear teaching tool (hear-frequency).
//
// Turns a frequency into a real-time tone so a Wi-Fi engineer can BUILD RF
// intuition by ear: pitch = frequency, an octave = a doubling, twelve semitones
// of equal temperament, harmonics as integer multiples, and the honest bridge
// to RF (octave thinking and dB thinking are the same logarithmic instinct,
// but an octave is NOT a dB). Spec: Deliverables/2026-06-28-frequency-sound-
// teaching-tool/build-spec.md (Pax, accuracy + feasibility PASS).
//
// AUDIO: all synthesis is behind the [ToneEngine] seam (SoLoudToneEngine). The
// engine inits LAZILY on the first Play tap (web autoplay-policy gesture) and
// is stopped on screen exit / app background so a tone never runs unattended.
// Live octave jumps retune the SOUNDING voice (no click) via setFrequency.
//
// HONESTY (GL-005, baked into copy): an octave is a base-2 FREQUENCY ratio; a
// dB is a base-10 POWER ratio - both logarithmic, NOT the same unit. Audio
// harmonics are WANTED (timbre); RF harmonics are usually UNWANTED (spurious
// emissions) - same integer math, opposite desirability. The screen states
// both plainly and never equates an octave to a dB.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Numerics in DM
// Mono (mono.output*); frequency IDENTIFIERS in Roboto Mono (mono.robotoMono)
// per GL-003 §8.5. No new tokens. ASCII only, no em dash (GL-004).
//
// States (SOP-007 §5):
//   - idle      -> Play enabled, no tone, readout shows the typed frequency
//   - playing   -> Stop shown, live retune on octave/preset/keyboard/wave
//   - empty     -> blank/invalid input: a prompt, transport + copy disabled
//   - error     -> out-of-audible-range: inline note, playback clamped/blocked
//   - unavailable -> engine init failed (no output device / blocked context):
//                    honest non-fatal banner, never a faked tone
//   - disabled  -> octave x2 disabled above 20 kHz, div2 below 20 Hz
//   - interactive -> hover/focus/pressed on every control; visible focus ring

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/music_theory.dart';
import '../../../data/tool_assets.dart';
import '../../../services/audio/tone_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/piano_keyboard.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kHearFrequencyToolId = 'hear-frequency';

/// Above this fundamental, square/triangle harmonics alias near Nyquist, so the
/// tool prefers SINE for high presets (build-spec 1.3.3, verify-by-ear note).
const double _kHighPresetHz = 5000.0;

/// One octave-ladder preset (label + Hz). Each is exactly x2 the previous.
typedef _Preset = ({String label, double hz});

class HearFrequencyScreen extends StatefulWidget {
  const HearFrequencyScreen({super.key, ToneEngine? engine})
      : _injectedEngine = engine;

  /// Test seam: inject a fake engine so widget tests need no audio device.
  final ToneEngine? _injectedEngine;

  @override
  State<HearFrequencyScreen> createState() => _HearFrequencyScreenState();
}

class _HearFrequencyScreenState extends State<HearFrequencyScreen>
    with WidgetsBindingObserver {
  late final ToneEngine _engine;

  final TextEditingController _freqCtrl =
      TextEditingController(text: '440');
  final FocusNode _freqFocus = FocusNode();

  // Interval / ratio explorer inputs (scale-free: log2 of a ratio).
  final TextEditingController _intervalACtrl =
      TextEditingController(text: '2.4');
  final TextEditingController _intervalBCtrl =
      TextEditingController(text: '5');

  ToneWave _wave = ToneWave.triangle;
  double _volume = 0.5;
  bool _isPlaying = false;
  ToneEngineStatus _engineStatus = ToneEngineStatus.idle;
  int? _activeKeyNumber;
  bool _showKeyMath = false;

  static final List<TextInputFormatter> _unsignedDecimal =
      <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  static const List<_Preset> _octaveLadder = <_Preset>[
    (label: 'A2', hz: 110),
    (label: 'A3', hz: 220),
    (label: 'A4', hz: 440),
    (label: 'A5', hz: 880),
    (label: 'A6', hz: 1760),
  ];

  static const List<_Preset> _anchors = <_Preset>[
    (label: 'A440', hz: 440),
    (label: 'Middle C', hz: 261.63),
    (label: 'C5', hz: 523.25),
    (label: '20 Hz', hz: 20),
    (label: '20 kHz', hz: 20000),
  ];

  @override
  void initState() {
    super.initState();
    _engine = widget._injectedEngine ?? SoLoudToneEngine(initialVolume: _volume);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine.dispose();
    _freqCtrl.dispose();
    _freqFocus.dispose();
    _intervalACtrl.dispose();
    _intervalBCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-stop so a tone can never run unattended (build-spec 2.6).
    if (state != AppLifecycleState.resumed && _isPlaying) {
      _stop();
    }
  }

  // ── Parsing / derived state ────────────────────────────────────────────────

  static double? _tryParse(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    final double? v = double.tryParse(s);
    if (v == null || v <= 0 || !v.isFinite) return null;
    return v;
  }

  /// The typed frequency in Hz, or null when blank/invalid.
  double? get _typedHz => _tryParse(_freqCtrl.text);

  /// Whether the typed frequency is inside the audible playback range.
  bool get _inAudibleRange {
    final double? hz = _typedHz;
    return hz != null && hz >= kMinAudibleHz && hz <= kMaxAudibleHz;
  }

  // ── Transport ──────────────────────────────────────────────────────────────

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _stop();
    } else {
      await _play();
    }
  }

  Future<void> _play() async {
    final double? hz = _typedHz;
    if (hz == null || !_inAudibleRange) return;
    final ToneWave wave = _waveFor(hz);
    await _engine.playTone(hz: hz, wave: wave);
    if (!mounted) return;
    setState(() {
      _engineStatus = _engine.status;
      _isPlaying = _engine.status == ToneEngineStatus.ready;
    });
  }

  Future<void> _stop() async {
    await _engine.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _activeKeyNumber = null;
    });
  }

  /// Sine is forced above [_kHighPresetHz] to avoid aliasing; otherwise the
  /// user's selected waveform is honored.
  ToneWave _waveFor(double hz) =>
      hz > _kHighPresetHz ? ToneWave.sine : _wave;

  /// Set the frequency field, retuning live if a tone is sounding. [keyNumber]
  /// highlights a piano key when the source is a key tap.
  Future<void> _setFrequency(double hz, {int? keyNumber, bool play = false}) async {
    final double clamped = hz.clamp(kMinAudibleHz, kMaxAudibleHz);
    _freqCtrl.text = _fmtHz(hz);
    setState(() => _activeKeyNumber = keyNumber);
    if (_isPlaying) {
      // High-frequency aliasing guard also applies on a live retune.
      await _engine.setWaveform(_waveFor(clamped));
      await _engine.setFrequency(clamped);
    } else if (play) {
      await _play();
    }
  }

  Future<void> _octave(double factor) async {
    final double? hz = _typedHz;
    if (hz == null) return;
    await _setFrequency(hz * factor, keyNumber: null);
  }

  Future<void> _onWaveChanged(ToneWave w) async {
    setState(() => _wave = w);
    final double? hz = _typedHz;
    if (_isPlaying && hz != null) {
      await _engine.setWaveform(_waveFor(hz));
    }
  }

  Future<void> _onVolumeChanged(double v) async {
    setState(() => _volume = v);
    await _engine.setVolume(v);
  }

  Future<void> _onKeyTap(Note note) async {
    await _setFrequency(note.frequencyHz, keyNumber: note.keyNumber, play: true);
  }

  Future<void> _onPreset(_Preset p) async {
    // High presets force sine; reflect that in the selector for honesty.
    if (p.hz > _kHighPresetHz && _wave != ToneWave.sine) {
      setState(() => _wave = ToneWave.sine);
    }
    await _setFrequency(p.hz, keyNumber: null, play: true);
  }

  // ── Formatting ──────────────────────────────────────────────────────────────

  static String _fmtHz(double hz) {
    if (hz >= 1000) return hz.toStringAsFixed(hz % 1 == 0 ? 0 : 1);
    return hz.toStringAsFixed(hz % 1 == 0 ? 0 : 2);
  }

  static String _fmt(double v, int decimals) {
    if (!v.isFinite) return '-';
    return v.toStringAsFixed(decimals);
  }

  static String _signedCents(double cents) {
    final String sign = cents >= 0 ? '+' : '';
    return '$sign${cents.toStringAsFixed(1)}';
  }

  // ── Copy payload (GL-003 §8.16) ─────────────────────────────────────────────

  String? _buildCopyText() {
    final double? hz = _typedHz;
    if (hz == null) return null;
    final NearestNote n = MusicTheory.nearestNote(hz);
    final List<Harmonic> harm = MusicTheory.harmonics(hz, count: 5);
    final StringBuffer b = StringBuffer()
      ..writeln('Hear the Frequency')
      ..writeln('Frequency: ${_fmtHz(hz)} Hz')
      ..writeln('Nearest note: ${n.note.label} '
          '(${_signedCents(n.centsOffset)} cents)')
      ..writeln('Octaves from A4 (440 Hz): '
          '${_fmt(n.octavesFromA4, 3)}')
      ..writeln('Harmonics (integer multiples):');
    for (final Harmonic h in harm) {
      b.writeln('  ${h.order}f = ${_fmtHz(h.frequencyHz)} Hz');
    }
    if (hz < kMinAudibleHz || hz > kMaxAudibleHz) {
      b.writeln('(Outside ~20 Hz-20 kHz hearing range; shown for the RF '
          'analogy, not played.)');
    }
    b
      ..writeln()
      ..writeln('An octave is a base-2 frequency ratio; a dB is a base-10 '
          'power ratio. Both are logarithmic, not the same unit.');
    return b.toString().trimRight();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hear the Frequency'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ConceptGraphicBand(
                        toolId: kHearFrequencyToolId,
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic(kHearFrequencyToolId))
                        const SizedBox(height: AppSpacing.md),
                      if (_engineStatus == ToneEngineStatus.unavailable)
                        ...<Widget>[
                          _audioUnavailableBanner(text, mono),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      _transportCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _octaveCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _waveformCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _presetsCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _keyboardCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _harmonicsCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _intervalCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _volumeCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _explainerCard(text, mono),
                      ToolHelpFooter(toolId: kHearFrequencyToolId),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Transport + readout ──────────────────────────────────────────────────────

  Widget _transportCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? hz = _typedHz;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabeledField(
            label: 'Frequency',
            hint: '(Hz, 20 to 20,000)',
            semanticLabel: 'Frequency in hertz',
            field: TextField(
              controller: _freqCtrl,
              focusNode: _freqFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) async {
                setState(() => _activeKeyNumber = null);
                final double? f = _typedHz;
                if (_isPlaying && f != null && _inAudibleRange) {
                  await _engine.setWaveform(_waveFor(f));
                  await _engine.setFrequency(f);
                }
              },
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge
                  .copyWith(fontSize: AppTextSize.fieldNumeric),
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '440'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: _playButton(text),
          ),
          if (hz != null && !_inAudibleRange) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _inlineNote(
              text,
              icon: Icons.info_outline,
              tint: colors.statusWarning,
              message: hz < kMinAudibleHz
                  ? 'Below ~20 Hz, the low edge of hearing. Shown for the RF '
                      'analogy, not played.'
                  : 'Above ~20 kHz, the high edge of hearing (and it declines '
                      'with age). Shown for the RF analogy, not played.',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _readout(text, mono),
        ],
      ),
    );
  }

  Widget _playButton(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final bool canPlay = _inAudibleRange;
    final bool playing = _isPlaying;
    return Semantics(
      button: true,
      label: playing ? 'Stop tone' : 'Play tone',
      child: FilledButton.icon(
        onPressed: canPlay ? _togglePlay : null,
        icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(playing ? 'Stop' : 'Play'),
        style: FilledButton.styleFrom(
          backgroundColor: playing ? colors.accent : colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.disabledFill,
          disabledForegroundColor: colors.textDisabled,
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _readout(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? hz = _typedHz;
    if (hz == null) {
      return _inlineNote(
        text,
        icon: Icons.graphic_eq,
        tint: colors.textTertiary,
        message: 'Enter a frequency and press Play. Higher number, higher '
            'pitch. Double the number to step up one octave.',
      );
    }
    final NearestNote n = MusicTheory.nearestNote(hz);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _resultLabel(text, 'Nearest note'),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          excludeSemantics: true,
          label: 'Nearest note ${n.note.label}, '
              '${_signedCents(n.centsOffset)} cents',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              // Note name is an IDENTIFIER -> Roboto Mono (GL-003 §8.5).
              Text(
                n.note.label,
                style: mono.robotoMono.copyWith(
                  fontSize: AppTextSize.h2,
                  fontWeight: FontWeight.w500,
                  color: colors.textAccent,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${_signedCents(n.centsOffset)} cents',
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _row(text, mono,
            label: 'Octaves from A4',
            value: '${_fmt(n.octavesFromA4, 3)} (440 Hz = 0)'),
        if (n.note.enharmonicName != null)
          _row(text, mono,
              label: 'Also written',
              value:
                  '${n.note.enharmonicName}${n.note.octave} (same pitch in '
                  '12-TET)'),
      ],
    );
  }

  // ── Octave controls ──────────────────────────────────────────────────────────

  Widget _octaveCard(TextTheme text, AppMonoText mono) {
    final double? hz = _typedHz;
    final bool canUp = hz != null && hz * 2 <= kMaxAudibleHz;
    final bool canDown = hz != null && hz / 2 >= kMinAudibleHz;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Octave'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Double the frequency and you go up one octave. The same note, '
            'higher. This doubling is the single most important move - it is '
            'exactly how we step through RF in octaves.',
            style: text.bodySmall?.copyWith(color: context.colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: _octaveButton(
                  text,
                  label: 'div 2 (down)',
                  semantic: 'Halve the frequency, one octave down',
                  enabled: canDown,
                  onTap: () => _octave(0.5),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _octaveButton(
                  text,
                  label: 'x2 (up)',
                  semantic: 'Double the frequency, one octave up',
                  enabled: canUp,
                  onTap: () => _octave(2.0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _octaveButton(
    TextTheme text, {
    required String label,
    required String semantic,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final AppColorScheme colors = context.colors;
    // §8.3: the ENABLED outline-button label is foreground lime (textAccent —
    // lime #A1CC3A in dark, darkened-lime #5A7A1C in light); the DISABLED label
    // dims to textDisabled. The label color is driven off `enabled` here rather
    // than left to the style's disabledForegroundColor, because an explicit
    // color on the child Text overrides the button's resolved foreground — that
    // override is exactly why the disabled state used to render identical to
    // enabled (Vera HIGH-1). Theme-independent: correct in both dark and light.
    final Color labelColor = enabled ? colors.textAccent : colors.textDisabled;
    return Semantics(
      button: true,
      label: semantic,
      enabled: enabled,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          backgroundColor: Colors.transparent,
          // A disabled-fill background dims the whole control so the disabled
          // state is unmistakable, not just a paler label (Vera HIGH-1).
          disabledBackgroundColor: colors.disabledFill,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: 1.5,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
        ),
        child: Text(
          label,
          style: text.labelLarge?.copyWith(
            fontWeight: enabled ? FontWeight.w600 : FontWeight.w500,
            color: labelColor,
          ),
        ),
      ),
    );
  }

  // ── Waveform selector ────────────────────────────────────────────────────────

  Widget _waveformCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? hz = _typedHz;
    final bool forcedSine = hz != null && hz > _kHighPresetHz;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // At the narrowest phone widths (~320px) the full word "Triangle"
          // ellipsizes to "Trian..." inside its equal-width segment, so the
          // wave names abbreviate consistently across the whole set below this
          // track-width breakpoint (Vera MEDIUM-1). The full words return as
          // soon as the segments have room.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              const double kNarrowWaveTrack = 285;
              final bool narrow = c.maxWidth < kNarrowWaveTrack;
              return AppToggle<ToneWave>(
                label: 'Waveform',
                value: forcedSine ? ToneWave.sine : _wave,
                expand: true,
                semanticLabel: 'Waveform',
                enabled: !forcedSine,
                items: <AppToggleItem<ToneWave>>[
                  (ToneWave.sine, narrow ? 'Sin' : 'Sine'),
                  (ToneWave.square, narrow ? 'Sqr' : 'Square'),
                  (ToneWave.triangle, narrow ? 'Tri' : 'Triangle'),
                ],
                onChanged: _onWaveChanged,
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            forcedSine
                ? 'Above 5 kHz the tool uses sine: square and triangle add '
                    'high harmonics that alias (a false buzz) near the top of '
                    'hearing.'
                : 'Same pitch, different timbre - like the difference between '
                    'two instruments playing the same note. The extra edge is '
                    'harmonics (more on those below).',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── Presets ──────────────────────────────────────────────────────────────────

  Widget _presetsCard(TextTheme text, AppMonoText mono) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Octave ladder (each is x2 the last)'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final _Preset p in _octaveLadder)
                _presetChip(text, mono, p, showHz: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _resultLabel(text, 'Anchors'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final _Preset p in _anchors)
                _presetChip(text, mono, p, showHz: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(
    TextTheme text,
    AppMonoText mono,
    _Preset p, {
    required bool showHz,
  }) {
    final AppColorScheme colors = context.colors;
    final bool active = _typedHz != null && (_typedHz! - p.hz).abs() < 0.01;
    return Semantics(
      button: true,
      label: '${p.label}, ${_fmtHz(p.hz)} hertz',
      selected: active,
      excludeSemantics: true,
      child: Material(
        color: active ? colors.primary : colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: () => _onPreset(p),
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: active ? colors.primary : colors.borderStrong,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  p.label,
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: active ? colors.onPrimary : colors.textPrimary,
                  ),
                ),
                if (showHz)
                  Text(
                    '${_fmtHz(p.hz)} Hz',
                    style: mono.inlineCode.copyWith(
                      fontSize: AppTextSize.caption,
                      color:
                          active ? colors.onPrimary : colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Piano keyboard ───────────────────────────────────────────────────────────

  Widget _keyboardCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final List<Note> notes = MusicTheory.chromaticC4toC5;
    final Note? active = _activeKeyNumber == null
        ? null
        : notes.firstWhere((Note n) => n.keyNumber == _activeKeyNumber,
            orElse: () => notes.first);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Piano keyboard (C4 to C5)'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Twelve semitones span one octave: 8 white keys here (C D E F G A '
            'B C) plus 5 black = 13 keys end to end. Tap a key to hear it.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          PianoKeyboard(
            notes: notes,
            activeKeyNumber: _activeKeyNumber,
            onKeyTap: _onKeyTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          // Active-key detail in a readout strip BELOW the keybed (never on the
          // keys) - no-text-overlap rule.
          if (active != null)
            Semantics(
              excludeSemantics: true,
              label: '${active.fullLabel}, '
                  '${active.frequencyHz.toStringAsFixed(2)} hertz',
              child: Row(
                children: <Widget>[
                  Text(
                    active.fullLabel,
                    style: mono.robotoMono.copyWith(color: colors.textAccent),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${active.frequencyHz.toStringAsFixed(2)} Hz',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    'n=${active.keyNumber}, (n-49)/12=${_fmt(MusicTheory.exponentForKey(active.keyNumber), 4)}',
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            )
          else
            Text(
              'White keys are the C-major scale, step pattern W-W-H-W-W-W-H. '
              'The two half-steps (E-F and B-C) are the only gaps with no '
              'black key, which is why the black keys cluster 2 then 3.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Switch(
                value: _showKeyMath,
                onChanged: (bool v) => setState(() => _showKeyMath = v),
                activeThumbColor: colors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Show the semitone math',
                  style:
                      text.labelMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          if (_showKeyMath)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    'Each adjacent key is x${kSemitoneRatio.toStringAsFixed(5)} '
                    '(2^(1/12)).',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SelectableText(
                    'Twelve of those steps = x2 = one octave.',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SelectableText(
                    'f(n) = 440 x 2^((n-49)/12), key 49 = A4 = 440 Hz.',
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Harmonics ────────────────────────────────────────────────────────────────

  Widget _harmonicsCard(TextTheme text, AppMonoText mono) {
    final double hz = _typedHz ?? 440;
    final List<Harmonic> harm = MusicTheory.harmonics(hz, count: 5);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Harmonics (integer multiples of f)'),
          const SizedBox(height: AppSpacing.xs),
          for (final Harmonic h in harm)
            _row(
              text,
              mono,
              label: '${h.order}f',
              value: '${_fmtHz(h.frequencyHz)} Hz',
            ),
          const SizedBox(height: AppSpacing.sm),
          _honestyNote(
            text,
            'Same math, opposite desirability: in music these overtones are '
            'WANTED - they make an instrument\'s timbre. In a radio, a '
            'transmitter\'s nonlinear amplifier produces these same integer '
            'multiples as UNWANTED spurious emissions that filters suppress. '
            'For example, the 2nd harmonic of 2.4 GHz is 4.8 GHz and the 3rd '
            'is 7.2 GHz, both near other Wi-Fi spectrum.',
          ),
        ],
      ),
    );
  }

  // ── Interval / ratio explorer ────────────────────────────────────────────────

  Widget _intervalCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? a = _tryParse(_intervalACtrl.text);
    final double? b = _tryParse(_intervalBCtrl.text);
    final IntervalResult? r = (a != null && b != null && a != b)
        ? MusicTheory.interval(a, b)
        : null;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Interval / ratio explorer'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The ratio between two frequencies is the interval - and it is '
            'scale-free, so the same math works for 440 vs 880 Hz or 2.4 vs 5 '
            'GHz.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(child: _intervalField('A', _intervalACtrl, mono, colors)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _intervalField('B', _intervalBCtrl, mono, colors)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _loadChip(text, '2.4 & 4.8 GHz', 2.4, 4.8),
              _loadChip(text, '2.4 & 5 GHz', 2.4, 5),
              _loadChip(text, '2.4 & 6 GHz', 2.4, 6),
              _loadChip(text, '440 & 880 Hz', 440, 880),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (r == null)
            _inlineNote(
              text,
              icon: Icons.info_outline,
              tint: colors.textTertiary,
              message: 'Enter two different positive frequencies to compare.',
            )
          else ...<Widget>[
            _row(text, mono, label: 'Ratio', value: '${_fmt(r.ratio, 4)} : 1'),
            _row(text, mono,
                label: 'Octaves apart', value: _fmt(r.octaves, 4)),
            _row(text, mono,
                label: 'Semitones apart', value: _fmt(r.semitones, 2)),
            _row(text, mono,
                label: 'Nearest interval',
                value: r.intervalName +
                    (r.centsFromNearest.abs() < 0.05
                        ? ' (exact)'
                        : ' (${_signedCents(r.centsFromNearest)} cents)')),
            const SizedBox(height: AppSpacing.sm),
            _honestyNote(
              text,
              'The same log-ratio instinct underlies dB - but a dB is a '
              'DIFFERENT formula: dB = 10 x log10 of a POWER ratio (20 x for '
              'amplitude). An octave is a base-2 FREQUENCY ratio; a dB is a '
              'base-10 power ratio. They are cousins, not the same unit. An '
              'octave is not 6 dB.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _intervalField(
    String label,
    TextEditingController ctrl,
    AppMonoText mono,
    AppColorScheme colors,
  ) {
    return LabeledField(
      label: 'Frequency $label',
      semanticLabel: 'Interval frequency $label',
      field: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _unsignedDecimal,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: mono.outputMedium.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: colors.textAccent,
        decoration: const InputDecoration(hintText: '0'),
      ),
    );
  }

  Widget _loadChip(TextTheme text, String label, double a, double b) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      button: true,
      label: 'Load $label',
      excludeSemantics: true,
      child: Material(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: () {
            _intervalACtrl.text = _fmtHz(a);
            _intervalBCtrl.text = _fmtHz(b);
            setState(() {});
          },
          child: Container(
            constraints:
                const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colors.borderStrong, width: 1),
            ),
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }

  // ── Volume + safety ──────────────────────────────────────────────────────────

  Widget _volumeCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _resultLabel(text, 'Volume'),
              const Spacer(),
              Text(
                '${(_volume * 100).round()}%',
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          Slider(
            value: _volume,
            onChanged: _onVolumeChanged,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${(_volume * 100).round()}%',
            semanticFormatterCallback: (double v) =>
                'Volume ${(v * 100).round()} percent',
          ),
          _inlineNote(
            text,
            icon: Icons.volume_up_outlined,
            tint: colors.textTertiary,
            message: 'No sound? Check your device is not muted and turn the '
                'volume up. High-frequency tones at high volume are unpleasant '
                'and, sustained, can tire your ears - keep it reasonable, '
                'especially on headphones and above ~8 kHz.',
          ),
        ],
      ),
    );
  }

  // ── Explainer (final copy by Penn, SOP-020) ──────────────────────────────────

  Widget _explainerCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Hear the Frequency: RF intuition you can listen to',
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _para(text,
              'RF frequencies are millions of times too high to hear, so build '
              'the intuition with sound you can hear. The rules are the same.'),
          _para(text,
              'Frequency is pitch. Enter a number, hear the tone. Higher '
              'number, higher pitch.'),
          _para(text,
              'An octave is a doubling. Double the frequency and you hear the '
              'same note, higher: 440 to 880 to 1760. This doubling is the '
              'single most important move, and it is exactly how we step '
              'through RF in octaves.'),
          _para(text,
              'Why 12 keys? Seven white, five black, twelve semitones, each a '
              'x1.05946 step. The piano is a logarithmic ruler for pitch. The '
              'white keys spell C major (W-W-H-W-W-W-H); the two half-steps '
              'E-F and B-C are the gaps with no black key, so the black keys '
              'group 2 then 3.'),
          _para(text,
              'The math behind the keys: f(n) = 440 x 2^((n-49)/12). A4 = 440 '
              'Hz is the world standard (ISO 16). Middle C = 261.63 Hz, its '
              'octave C5 = 523.25 Hz.'),
          _para(text,
              'The RF bridge: octave thinking and dB thinking are the same '
              'logarithmic instinct. The useful range is enormous, so we '
              'compress it. 2.4 GHz to 4.8 GHz is one octave; 5 GHz and 6 GHz '
              'sit in the next octave up.'),
          const SizedBox(height: AppSpacing.xs),
          _honestyNote(
            text,
            'Two honest limits. First, an octave is NOT a dB: an octave is a '
            'base-2 frequency doubling, a dB is a base-10 power ratio. They '
            'are both logarithmic, which is the real bridge, but they are not '
            'the same unit. Second, audio harmonics are wanted (they make '
            'timbre) while RF harmonics are usually unwanted (spurious '
            'emissions). The math transfers; the desirability flips.',
          ),
        ],
      ),
    );
  }

  // ── Shared pieces ────────────────────────────────────────────────────────────

  Widget _audioUnavailableBanner(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.volume_off_outlined, size: 18, color: colors.statusWarning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'No audio output detected. Check that an output device is '
              'connected and your device is not muted, then press Play again. '
              'The math and visuals below still work.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _para(TextTheme text, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        body,
        style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
      ),
    );
  }

  Widget _honestyNote(TextTheme text, String body) {
    final AppColorScheme colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border(
          left: BorderSide(color: colors.primary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.balance_outlined, size: 16, color: colors.textAccent),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              body,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineNote(
    TextTheme text, {
    required IconData icon,
    required Color tint,
    required String message,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: text.bodySmall?.copyWith(color: context.colors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _resultLabel(TextTheme text, String label) {
    final AppColorScheme colors = context.colors;
    return Text(
      label,
      style: text.labelMedium?.copyWith(
        color: colors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }

  Widget _row(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
  }) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              value,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
