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

import '../../../data/dtmf.dart';
import '../../../services/audio/dtmf_player.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';

class DtmfGeneratorScreen extends StatefulWidget {
  const DtmfGeneratorScreen({super.key});

  @override
  State<DtmfGeneratorScreen> createState() => _DtmfGeneratorScreenState();
}

class _DtmfGeneratorScreenState extends State<DtmfGeneratorScreen> {
  final DtmfPlayer _player = DtmfPlayer();

  // The currently-selected key (the one the Play/Stop toggle will loop, and the
  // last one tapped). Defaults to "5", the center key.
  String _selectedLabel = '5';

  // Whether the continuous Play/Stop loop is on.
  bool _looping = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  DtmfKey get _selectedKey => Dtmf.keyFor(_selectedLabel)!;

  // ─── Handlers ───────────────────────────────────────────────────────────────

  Future<void> _onKeyTap(String label) async {
    final DtmfKey? key = Dtmf.keyFor(label);
    if (key == null) return;
    setState(() {
      _selectedLabel = label;
      // Tapping a key during a continuous loop retargets the loop to the new key.
    });
    if (_looping) {
      await _player.startContinuous(key);
    } else {
      await _player.playTone(key);
    }
  }

  Future<void> _toggleLoop() async {
    if (_looping) {
      setState(() => _looping = false);
      await _player.stop();
    } else {
      setState(() => _looping = true);
      await _player.startContinuous(_selectedKey);
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
      body: SafeArea(
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
                  ToolHelpFooter(toolId: 'dtmf-generator'),
                ],
              ),
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
