// DTMF Generator + Telephone Signaling History — Batch 4c, extended 2026-06-11.
//
// Three modes, selected by a §8.14.1 AppToggle segmented control:
//   * DTMF — the original 4×4 Touch-Tone keypad (1-9, *, #, A-D) plus a Play/Stop
//     loop and a sequence player. Unchanged behavior.
//   * Blue Box (MF) — the R1 Multi-Frequency trunk-routing tones (canonical
//     ITU-T digit pairs), KP / ST framing signals, and the 2600 Hz supervisory
//     tone.
//   * Red Box — the US ACTS coin-deposit acknowledgement bursts (nickel / dime /
//     quarter), all 1700 + 2200 Hz, differing only in burst count and timing.
//
// HONESTY IS THE FEATURE (GL-005, and the App Store / brand strategy from the
// 2026-06-11 feasibility brief): the two history modes carry an on-screen note
// stating plainly that these tones do nothing on any modern phone network —
// in-band signaling was retired for out-of-band SS7 in the 1980s-1990s, and ACTS
// payphones are gone. They are telephone signaling history, reproduced for
// education and nostalgia, NOT a working tool. The per-mode help entries
// (dtmf-generator, blue-box, red-box) say the same. No "phreaking" / "hacking"
// wording appears in any user-facing label (brand + App Store framing).
//
// Synthesis is pure Dart (lib/data/dtmf.dart + lib/data/signaling_tones.dart,
// unit-tested); playback is just_audio behind lib/services/audio/dtmf_player.dart.
// GL-008: local audio only — no subprocess, no network, no cleartext HTTP.
//
// GL-003 compliance:
//   * §8.14.1: the mode selector is the canonical AppToggle<ToneMode> segmented
//     control (radio-group semantics, lime selected segment, mandatory focus ring).
//   * §8.3: keypad / signal keys are SECONDARY/OUTLINE buttons (borderStrong
//     outline, transparent fill, lime label), 44pt/48dp touch targets.
//   * §8.13 rule 6 (HARD): the honesty note is NEUTRAL informational context, not
//     a computed verdict, so it uses neutral text tokens on surface1 — NOT a
//     status hue (an info-colored banner here would be exactly the banned
//     decorative-status drift). Lime stays the only active/selected accent.
//   * §8.5: frequency / timing identifiers render in Roboto Mono.
//   * §8.9: each key carries an explicit Semantics label.
//   * §8.8: the active-key flash collapses to 0 ms under reduced motion.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/dtmf.dart';
import '../../../data/signaling_tones.dart';
import '../../../services/audio/dtmf_player.dart';
import '../../../services/network/network_support.dart'
    show NetworkUnavailableReason;
import '../network/network_unavailable_view.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';

/// The three tone modes the screen offers.
enum ToneMode {
  /// Standard DTMF Touch-Tone keypad (the original tool).
  dtmf,

  /// Blue Box — R1 Multi-Frequency trunk signaling + 2600 Hz supervisory tone.
  blueBox,

  /// US Red Box — ACTS coin-deposit acknowledgement bursts.
  redBox,
}

class DtmfGeneratorScreen extends StatefulWidget {
  const DtmfGeneratorScreen({super.key});

  @override
  State<DtmfGeneratorScreen> createState() => _DtmfGeneratorScreenState();
}

class _DtmfGeneratorScreenState extends State<DtmfGeneratorScreen> {
  // Playback is supported on every shipping platform now (iOS/macOS/Android/web
  // via just_audio's first-party backends; Windows via just_audio_windows — see
  // [DtmfPlayer.playbackSupportedOnThisPlatform]). The nullable construction is
  // kept as a defensive seam: if a future platform ever lacks an audio backend
  // and the getter returns false, the player stays null and the screen falls
  // back to the honest platform-unavailable surface instead of a dead keypad.
  final DtmfPlayer? _player = DtmfPlayer.playbackSupportedOnThisPlatform
      ? DtmfPlayer()
      : null;

  // Which of the three modes is active.
  ToneMode _mode = ToneMode.dtmf;

  // ─── DTMF mode state ────────────────────────────────────────────────────────
  // The currently-selected key (the one the Play/Stop toggle will loop, and the
  // last one tapped). Defaults to "5", the center key.
  String _selectedLabel = '5';

  // Whether the continuous Play/Stop loop is on.
  bool _looping = false;

  // The user types a string of DTMF characters (e.g. 8675309) and plays it as
  // tones in order. Non-DTMF characters are ignored on play.
  final TextEditingController _seqCtrl = TextEditingController();

  // True while a sequence is playing; gates the Stop affordance.
  bool _playingSeq = false;

  // ─── Signaling-history mode state ───────────────────────────────────────────
  // The last signaling signal played, for the readout. Null until one is tapped.
  SignalingTone? _lastSignal;

  @override
  void dispose() {
    _seqCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

  // ─── DTMF helpers ───────────────────────────────────────────────────────────

  /// The DTMF keys parsed from the sequence field, in order. Non-DTMF
  /// characters are dropped; letters are upper-cased (A-D are valid keys).
  List<DtmfKey> get _sequenceKeys {
    final List<DtmfKey> out = <DtmfKey>[];
    for (final String ch in _seqCtrl.text.toUpperCase().split('')) {
      final DtmfKey? k = Dtmf.keyFor(ch);
      if (k != null) out.add(k);
    }
    return out;
  }

  DtmfKey get _selectedKey => Dtmf.keyFor(_selectedLabel)!;

  Future<void> _playSequence() async {
    final DtmfPlayer? player = _player;
    if (player == null) return; // Playback gated off on this platform.
    final List<DtmfKey> keys = _sequenceKeys;
    if (keys.isEmpty) return;
    if (_looping) {
      setState(() => _looping = false);
    }
    setState(() => _playingSeq = true);
    await player.playSequence(keys, shouldContinue: () => _playingSeq);
    if (!mounted) return;
    setState(() => _playingSeq = false);
  }

  Future<void> _stopSequence() async {
    setState(() => _playingSeq = false);
    await _player?.stop();
  }

  Future<void> _onKeyTap(String label) async {
    final DtmfPlayer? player = _player;
    if (player == null) return; // Playback gated off on this platform.
    final DtmfKey? key = Dtmf.keyFor(label);
    if (key == null) return;
    setState(() {
      _selectedLabel = label;
    });
    if (_looping) {
      await player.startContinuous(key);
    } else {
      await player.playTone(key);
    }
  }

  Future<void> _toggleLoop() async {
    final DtmfPlayer? player = _player;
    if (player == null) return; // Playback gated off on this platform.
    if (_looping) {
      setState(() => _looping = false);
      await player.stop();
    } else {
      setState(() => _looping = true);
      await player.startContinuous(_selectedKey);
    }
  }

  // ─── Mode switching ─────────────────────────────────────────────────────────

  void _onModeChanged(ToneMode mode) {
    if (mode == _mode) return;
    // Switch the UI immediately, then stop anything in flight (a DTMF loop or
    // sequence) so the audio session never lingers across a mode change. The
    // stop is fire-and-forget: the mode swap must not wait on the audio plugin
    // (which has no headless backend and would otherwise stall the swap).
    setState(() {
      _mode = mode;
      _looping = false;
      _playingSeq = false;
      _lastSignal = null;
    });
    unawaited(_player?.stop() ?? Future<void>.value());
  }

  // ─── Signaling-history handler ──────────────────────────────────────────────

  Future<void> _onSignalTap(SignalingTone tone) async {
    setState(() => _lastSignal = tone);
    await _player?.playSignalingTone(tone);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DTMF Generator'),
        toolbarHeight: 64,
      ),
      body: _player == null
          // Defensive only: every shipping platform now has an audio backend, so
          // this branch is not reached in practice. If a future platform ever
          // lacks one, show the honest platform-unavailable surface rather than a
          // keypad whose tones cannot play (GL-008).
          ? const SafeArea(
              top: false,
              child: NetworkUnavailableView(
                toolName: 'DTMF Generator',
                reason: NetworkUnavailableReason.platformApiMissing,
                icon: Icons.volume_off_outlined,
                headline: 'Tone playback is not available on this platform',
                message:
                    'The DTMF Generator plays generated audio tones, and the '
                    'audio engine it uses has no backend on this platform. The '
                    'tone frequencies shown are still correct. Every other tool '
                    'works normally here.',
              ),
            )
          : _buildPlayable(text),
    );
  }

  Widget _buildPlayable(TextTheme text) {
    return SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _modeSelector(),
                  const SizedBox(height: AppSpacing.md),
                  ..._modeBody(text),
                  ToolHelpFooter(toolId: _helpIdForMode),
                ],
              ),
            ),
          ),
        ),
    );
  }

  /// The help entry the footer opens depends on the active mode, so each mode's
  /// honest history is one tap away.
  String get _helpIdForMode {
    switch (_mode) {
      case ToneMode.dtmf:
        return 'dtmf-generator';
      case ToneMode.blueBox:
        return 'blue-box';
      case ToneMode.redBox:
        return 'red-box';
    }
  }

  /// §8.14.1 segmented selector across the three modes.
  Widget _modeSelector() {
    return AppToggle<ToneMode>(
      value: _mode,
      semanticLabel: 'Tone mode',
      expand: true,
      items: const <AppToggleItem<ToneMode>>[
        (ToneMode.dtmf, 'DTMF'),
        (ToneMode.blueBox, 'Blue Box'),
        (ToneMode.redBox, 'Red Box'),
      ],
      onChanged: (ToneMode m) => _onModeChanged(m),
    );
  }

  /// The body for the active mode.
  List<Widget> _modeBody(TextTheme text) {
    switch (_mode) {
      case ToneMode.dtmf:
        return _dtmfBody(text);
      case ToneMode.blueBox:
        return _signalingBody(
          text,
          tones: SignalingTones.blueBox,
          title: 'Blue Box — Multi-Frequency signaling',
          intro:
              'The R1 MF tones a long-distance switch once used to route a call, '
              'plus the 2600 Hz tone that meant the trunk was idle. Tap a signal '
              'to hear it.',
          columns: 4,
        );
      case ToneMode.redBox:
        return _signalingBody(
          text,
          tones: SignalingTones.redBox,
          title: 'Red Box — US coin tones',
          intro:
              'The dual-tone bursts an ACTS payphone sent up the line to report a '
              'coin drop. All three are 1700 + 2200 Hz; only the burst count and '
              'timing differ. Tap a coin to hear it.',
          columns: 3,
        );
    }
  }

  // ─── DTMF body ──────────────────────────────────────────────────────────────

  List<Widget> _dtmfBody(TextTheme text) {
    return <Widget>[
      _dtmfSelectionCard(text),
      const SizedBox(height: AppSpacing.md),
      _keypad(text),
      const SizedBox(height: AppSpacing.md),
      _playStopToggle(text),
      const SizedBox(height: AppSpacing.md),
      _sequenceCard(text),
    ];
  }

  /// Shows the selected key and its two component frequencies — the "what am I
  /// hearing" readout.
  Widget _dtmfSelectionCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final DtmfKey key = _selectedKey;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Semantics(
            label: 'Selected key',
            value: key.label,
            excludeSemantics: true,
            child: Text(
              key.label,
              style: text.headlineMedium?.copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Dual-tone frequencies',
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${key.lowHz.toStringAsFixed(0)} Hz '
                  '+ ${key.highHz.toStringAsFixed(0)} Hz',
                  style: mono.robotoMono.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The 4×4 DTMF keypad.
  Widget _keypad(TextTheme text) {
    return Column(
      children: <Widget>[
        for (int r = 0; r < Dtmf.grid.length; r++) ...<Widget>[
          if (r > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              for (int c = 0; c < Dtmf.grid[r].length; c++) ...<Widget>[
                if (c > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _ToneKeyButton(
                    label: Dtmf.grid[r][c],
                    semanticLabel: 'DTMF key ${Dtmf.grid[r][c]}',
                    selected: Dtmf.grid[r][c] == _selectedLabel,
                    onTap: () => _onKeyTap(Dtmf.grid[r][c]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// The single primary lime Play/Stop toggle. Loops the selected key's tone.
  Widget _playStopToggle(TextTheme text) {
    return FilledButton.icon(
      onPressed: _toggleLoop,
      icon: Icon(_looping ? Icons.stop : Icons.play_arrow),
      label: Text(
        _looping
            ? 'Stop (${_selectedKey.label})'
            : 'Play (${_selectedKey.label})',
      ),
    );
  }

  /// Pre-load a string of digits, then play the whole sequence in order.
  Widget _sequenceCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final int count = _sequenceKeys.length;
    final bool hasDigits = count > 0;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Play a sequence',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Type a string of digits (e.g. 867-5309) and play it as tones in '
            'order.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _seqCtrl,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Da-d*#]')),
            ],
            keyboardType: TextInputType.phone,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: colors.textAccent,
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '8675309',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: !hasDigits && !_playingSeq
                ? null
                : (_playingSeq ? _stopSequence : _playSequence),
            icon: Icon(_playingSeq ? Icons.stop : Icons.play_arrow),
            label: Text(
              _playingSeq
                  ? 'Stop'
                  : hasDigits
                      ? 'Play sequence ($count)'
                      : 'Play sequence',
            ),
          ),
        ],
      ),
    );
  }

  // ─── Signaling-history body (Blue Box / Red Box) ────────────────────────────

  List<Widget> _signalingBody(
    TextTheme text, {
    required List<SignalingTone> tones,
    required String title,
    required String intro,
    required int columns,
  }) {
    return <Widget>[
      _historyNote(text),
      const SizedBox(height: AppSpacing.md),
      _signalReadout(text),
      const SizedBox(height: AppSpacing.md),
      _signalIntro(text, title: title, intro: intro),
      const SizedBox(height: AppSpacing.sm),
      _signalPad(tones, columns: columns),
    ];
  }

  /// The honest, plain-language note that these tones do nothing today. §8.13
  /// rule 6 (HARD): this is neutral context, NOT a verdict, so it uses neutral
  /// text on surface1 — never a status hue / info-colored banner.
  Widget _historyNote(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.history_edu_outlined,
            size: 24,
            color: colors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Telephone signaling history',
                  style: text.labelLarge?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'These tones do nothing on any modern phone network. The '
                  'in-band signaling they reproduce was retired when carriers '
                  'moved call control to out-of-band SS7 signaling in the '
                  '1980s-1990s, and the coin-tone payphones are gone. They are '
                  'here for historical and educational interest only.',
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "What am I hearing" readout for the last signaling signal played. Empty
  /// state before the first tap.
  Widget _signalReadout(TextTheme text) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final SignalingTone? tone = _lastSignal;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: tone == null
          ? Text(
              'Tap a signal below to hear it.',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
            )
          : Row(
              children: <Widget>[
                Semantics(
                  label: 'Selected signal',
                  value: tone.label,
                  excludeSemantics: true,
                  child: Text(
                    tone.label,
                    style: text.headlineSmall?.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${tone.frequencyLabel}  ·  ${tone.timingLabel}',
                        style: mono.robotoMono
                            .copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        tone.description,
                        style: text.bodySmall
                            ?.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _signalIntro(
    TextTheme text, {
    required String title,
    required String intro,
  }) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          intro,
          style: text.labelMedium?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }

  /// A wrap of signal keys, [columns] per row, each a §8.3 outline key.
  Widget _signalPad(List<SignalingTone> tones, {required int columns}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Even columns with the §8.3 8px gutter between them.
        final double gutter = AppSpacing.xs;
        final double keyWidth =
            (constraints.maxWidth - gutter * (columns - 1)) / columns;
        return Wrap(
          spacing: gutter,
          runSpacing: gutter,
          children: <Widget>[
            for (final SignalingTone tone in tones)
              SizedBox(
                width: keyWidth,
                child: _ToneKeyButton(
                  label: tone.label,
                  semanticLabel: '${tone.label} signal',
                  selected: identical(_lastSignal, tone) ||
                      (_lastSignal?.label == tone.label &&
                          _lastSignal?.family == tone.family),
                  onTap: () => _onSignalTap(tone),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A single tone key: a §8.3 SECONDARY/OUTLINE button (borderStrong outline,
/// transparent fill, lime label). When selected, the border + label go lime
/// (the active/selected role, §8.3 — never a status hue). The whole square is
/// the 44pt/48dp tap target. An explicit Semantics label names the key for
/// screen readers (§8.9). Under reduced motion the press feedback is 0 ms (§8.8).
///
/// Shared by all three modes — the DTMF keypad, the Blue Box MF pad, and the
/// Red Box coin pad — so they are visually and behaviorally identical keys.
class _ToneKeyButton extends StatelessWidget {
  const _ToneKeyButton({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final Color borderColor =
        selected ? colors.textAccent : colors.borderStrong;
    final double borderWidth = selected ? 2 : 1;

    return Semantics(
      button: true,
      label: semanticLabel,
      selected: selected,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected
              ? colors.textAccent.withValues(alpha: 0.08)
              : Colors.transparent,
          foregroundColor: colors.textAccent,
          side: BorderSide(color: borderColor, width: borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          minimumSize: const Size(
            AppSpacing.minTouchTarget,
            AppSpacing.minTouchTarget + AppSpacing.xs, // 56 — comfortable key
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          animationDuration: reduceMotion ? Duration.zero : AppMotion.fast,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Short glyphs (DTMF digits, MF digits, KP/ST) keep the large keypad
          // type; multi-character word labels (Nickel / Quarter, "2600") step
          // down so they fit a narrower key without truncating.
          style: (label.length <= 2 ? text.headlineSmall : text.titleMedium)
              ?.copyWith(
            color: colors.textAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
