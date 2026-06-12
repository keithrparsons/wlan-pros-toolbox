// DTMF Generator — Batch 4c.
//
// A 4×4 DTMF keypad (1-9, *, #, A-D) plus a single primary lime Play/Stop
// toggle. Tapping a key plays its dual-tone (low-group + high-group sine sum,
// 200 ms); the Play/Stop toggle loops the currently-selected key's tone until
// stopped. Synthesis is pure Dart (lib/data/dtmf.dart, unit-tested); playback is
// just_audio behind lib/services/audio/dtmf_player.dart.
//
// GL-003 compliance:
//   * §8.3 keypad keys are SECONDARY/OUTLINE buttons (borderStrong outline,
//     transparent fill, lime text) — NOT a second hue. They render at the 44pt
//     iOS / 48dp Android minimum touch target and never shrink below it on phone
//     width; the grid uses a --space-xs (8px) gutter.
//   * The digit labels are IBM Plex Sans (the theme's default sans), per §8.3.
//   * §8.13 rule 6: the Play/Stop toggle uses LIME (--color-primary) for the
//     ACTIVE state — lime is the active/selected accent, NOT a status-success
//     hue. A status color would be wrong here (this is a state, not a verdict).
//   * §8.9: each key carries an explicit Semantics label ("DTMF key 5") because
//     the glyph alone is not a sufficient SR label.
//   * §8.8: under prefers-reduced-motion the active-key flash collapses to 0 ms.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/dtmf.dart';
import '../../../services/audio/dtmf_player.dart';
import '../../../services/network/network_support.dart'
    show NetworkUnavailableReason;
import '../network/network_unavailable_view.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';

class DtmfGeneratorScreen extends StatefulWidget {
  const DtmfGeneratorScreen({super.key});

  @override
  State<DtmfGeneratorScreen> createState() => _DtmfGeneratorScreenState();
}

class _DtmfGeneratorScreenState extends State<DtmfGeneratorScreen> {
  // Playback is gated off where just_audio has no first-party implementation
  // (Windows — see [DtmfPlayer.playbackSupportedOnThisPlatform]). The player is
  // lazily constructed ONLY when playback is supported, so an unsupported
  // platform never instantiates a just_audio AudioPlayer (which would fail to
  // load a missing native backend). On Windows the screen renders the honest
  // platform-unavailable surface instead of the keypad.
  final DtmfPlayer? _player = DtmfPlayer.playbackSupportedOnThisPlatform
      ? DtmfPlayer()
      : null;

  // The currently-selected key (the one the Play/Stop toggle will loop, and the
  // last one tapped). Defaults to "5", the center key.
  String _selectedLabel = '5';

  // Whether the continuous Play/Stop loop is on.
  bool _looping = false;

  // ─── Sequence mode (BF6-1) ─────────────────────────────────────────────────
  // The user types a string of DTMF characters (e.g. 8675309) and plays it
  // as tones in order. Non-DTMF characters are ignored on play (and stripped by
  // the input formatter), so a pasted phone number with spaces/dashes still
  // works.
  final TextEditingController _seqCtrl = TextEditingController();

  // True while a sequence is playing; gates the Stop affordance and cancels the
  // in-flight playSequence via the shouldContinue callback.
  bool _playingSeq = false;

  @override
  void dispose() {
    _seqCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

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

  Future<void> _playSequence() async {
    final DtmfPlayer? player = _player;
    if (player == null) return; // Playback gated off on this platform.
    final List<DtmfKey> keys = _sequenceKeys;
    if (keys.isEmpty) return;
    // A running loop and a sequence are mutually exclusive — stop the loop first.
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

  DtmfKey get _selectedKey => Dtmf.keyFor(_selectedLabel)!;

  // ─── Handlers ───────────────────────────────────────────────────────────────

  Future<void> _onKeyTap(String label) async {
    final DtmfPlayer? player = _player;
    if (player == null) return; // Playback gated off on this platform.
    final DtmfKey? key = Dtmf.keyFor(label);
    if (key == null) return;
    setState(() {
      _selectedLabel = label;
      // Tapping a key during a continuous loop retargets the loop to the new key.
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
          // Playback is honestly gated off where just_audio has no first-party
          // backend (Windows). Reuse the shared platform-unavailable surface
          // rather than show a keypad whose tones cannot play (GL-008).
          ? const SafeArea(
              top: false,
              child: NetworkUnavailableView(
                toolName: 'DTMF Generator',
                reason: NetworkUnavailableReason.platformApiMissing,
                icon: Icons.volume_off_outlined,
                headline: 'Tone playback is not available on Windows yet',
                message:
                    'The DTMF Generator plays generated audio tones, and the '
                    'audio engine it uses has no Windows support yet. The tone '
                    'frequencies are still correct — playback will arrive in a '
                    'later Windows update. Every other tool works normally here.',
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
                  _selectionCard(text),
                  const SizedBox(height: AppSpacing.md),
                  _keypad(text),
                  const SizedBox(height: AppSpacing.md),
                  _playStopToggle(text),
                  const SizedBox(height: AppSpacing.md),
                  _sequenceCard(text),
                  ToolHelpFooter(toolId: 'dtmf-generator'),
                ],
              ),
            ),
          ),
        ),
    );
  }

  /// Shows the selected key and its two component frequencies — the "what am I
  /// hearing" readout. Frequencies are neutral data (no verdict), so no status
  /// hue; the key label is lime as the active/selected cue (§8.3).
  Widget _selectionCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
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
                  style: text.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The 4×4 keypad. Each row is a Row of square keys; a --space-xs (8px) gutter
  /// separates them (§8.3). Keys are flexible-width so they fill the column but
  /// never shrink below the 44pt/48dp floor (enforced by the min-height in
  /// _DtmfKeyButton and by capping the keypad to a sane max width).
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
                  child: _DtmfKeyButton(
                    label: Dtmf.grid[r][c],
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

  /// The single primary lime Play/Stop toggle (§8.3 primary button; §8.13 rule
  /// 6: lime = active state, not a status hue). Loops the selected key's tone.
  Widget _playStopToggle(TextTheme text) {
    return FilledButton.icon(
      onPressed: _toggleLoop,
      icon: Icon(_looping ? Icons.stop : Icons.play_arrow),
      label: Text(
        _looping ? 'Stop (${_selectedKey.label})' : 'Play (${_selectedKey.label})',
      ),
    );
  }

  /// BF6-1 — pre-load a string of digits, then play the whole sequence in order.
  /// The field is an identifier input (digits/*/#/A-D) rendered in Roboto Mono
  /// (GL-003 §8.5 identifier rule). The Play button becomes Stop while playing.
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
            // Only DTMF characters are meaningful; allow the user to type the
            // common ones (and paste a number) — non-DTMF chars are dropped on
            // play, and the formatter keeps the field to the valid set.
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Da-d*#]')),
            ],
            keyboardType: TextInputType.phone,
            autocorrect: false,
            enableSuggestions: false,
            cursorColor: colors.textAccent,
            // Identifier string → Roboto Mono (§8.5).
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '8675309',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            // Disabled until there is at least one valid DTMF character.
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
}

/// A single keypad key: a §8.3 SECONDARY/OUTLINE button (borderStrong outline,
/// transparent fill, lime label). When it is the selected key, the border and
/// label go lime (the active/selected role, §8.3 — never a status hue). The
/// digit label is IBM Plex Sans (the theme's default sans). The whole square is
/// the 44pt/48dp tap target. An explicit Semantics label names the key for
/// screen readers (§8.9). Under reduced motion the press feedback is 0 ms (§8.8).
class _DtmfKeyButton extends StatelessWidget {
  const _DtmfKeyButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ??
        false;

    final Color borderColor =
        selected ? colors.textAccent : colors.borderStrong;
    final double borderWidth = selected ? 2 : 1;

    return Semantics(
      button: true,
      // §8.9 explicit label — the glyph alone is not a sufficient SR label.
      label: 'DTMF key $label',
      selected: selected,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          // §8.3 secondary/outline: transparent fill, borderStrong outline, lime
          // text. Selected → lime border + lime fill wash.
          backgroundColor: selected
              ? colors.textAccent.withValues(alpha: 0.08)
              : Colors.transparent,
          foregroundColor: colors.textAccent,
          side: BorderSide(color: borderColor, width: borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          // §8.3 touch target: at least 48dp tall; a square-ish key.
          minimumSize: const Size(
            AppSpacing.minTouchTarget,
            AppSpacing.minTouchTarget + AppSpacing.xs, // 56 — comfortable key
          ),
          padding: EdgeInsets.zero,
          // §8.8: collapse the press animation to 0 ms under reduced motion.
          animationDuration:
              reduceMotion ? Duration.zero : AppMotion.fast,
        ),
        child: Text(
          label,
          style: text.headlineSmall?.copyWith(
            // IBM Plex Sans (theme default), lime label (§8.3 secondary text).
            color: colors.textAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
