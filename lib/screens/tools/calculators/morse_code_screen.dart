// Morse Code — live bidirectional Text ↔ Morse encoder/decoder.
//
// Two linked fields: type plain text and the Morse appears below; type or paste
// dots/dashes and the decoded text appears below. Whichever field the user last
// edited is the source of truth; the other is the derived (read-only) result so
// the two never fight. A visual dot/dash chip strip renders the encoded code,
// the §8.16 AppCopyAction copies the active result, and an optional sidetone
// plays the message as audio (reusing the DTMF just_audio seam).
//
// GL-003 compliance:
//   * §8.16 copy affordance in the AppBar; its textBuilder returns null until a
//     result exists, so it renders disabled+unfocusable when both fields empty.
//   * §8.5 the Morse code string is an IDENTIFIER → Roboto Mono.
//   * §8.13 rule 6: lime (--color-primary) is the active/selected accent on the
//     direction toggle and the Play button ACTIVE state — never a status hue;
//     this is a state, not a verdict, so no status-success green.
//   * §8.9 explicit Semantics on the dot/dash visual strip and the Play control.
//   * §8.8 the Play button's icon swap is the only motion; no reduced-motion
//     hazard (no looping animation).
//   * Pure logic lives in lib/data/morse.dart (unit-tested); audio in
//     lib/services/audio/morse_player.dart.

import 'package:flutter/material.dart';

import '../../../data/morse.dart';
import '../../../services/audio/morse_player.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';

/// Which field the user is currently driving. The other field is derived.
enum _Direction { textToMorse, morseToText }

class MorseCodeScreen extends StatefulWidget {
  const MorseCodeScreen({super.key});

  @override
  State<MorseCodeScreen> createState() => _MorseCodeScreenState();
}

class _MorseCodeScreenState extends State<MorseCodeScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final MorsePlayer _player = MorsePlayer();

  _Direction _direction = _Direction.textToMorse;
  bool _showProsigns = false;
  bool _playing = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Derived values ──────────────────────────────────────────────────────

  /// The encoded Morse for the current text input (text→Morse direction).
  String get _encodedMorse => Morse.encode(_inputCtrl.text);

  /// The decoded text for the current Morse input (Morse→text direction).
  String get _decodedText => Morse.decode(_inputCtrl.text);

  /// The result string for the active direction (what the bottom card shows and
  /// what Copy / Play act on). Empty when there is nothing to show.
  String get _result => _direction == _Direction.textToMorse
      ? _encodedMorse
      : _decodedText;

  bool get _hasInput => _inputCtrl.text.trim().isNotEmpty;
  bool get _hasResult => _result.isNotEmpty;

  /// The Morse code string for the audio player and the visual strip. In
  /// text→Morse it is the encoded result; in Morse→text it is the user's own
  /// (cleaned) Morse input so the strip mirrors what they typed.
  String get _morseForDisplay =>
      _direction == _Direction.textToMorse ? _encodedMorse : _inputCtrl.text;

  /// The plain text the audio player should sound out. In text→Morse it is the
  /// raw input; in Morse→text it is the decoded text.
  String get _textForAudio =>
      _direction == _Direction.textToMorse ? _inputCtrl.text : _decodedText;

  // ── Copy payload (§8.16) ────────────────────────────────────────────────

  String? _buildCopyText() {
    if (!_hasResult) return null;
    final String fromLabel =
        _direction == _Direction.textToMorse ? 'Text' : 'Morse';
    final String toLabel =
        _direction == _Direction.textToMorse ? 'Morse' : 'Text';
    return '$fromLabel: ${_inputCtrl.text.trim()}\n$toLabel: $_result';
  }

  // ── Handlers ────────────────────────────────────────────────────────────

  void _onInputChanged(String _) => setState(() {});

  void _setDirection(_Direction d) {
    if (d == _direction) return;
    // Swap so the user's prior RESULT becomes the new input — a "swap" gesture
    // that keeps their content rather than clearing it.
    setState(() {
      _inputCtrl.text = _result;
      _direction = d;
      _inputCtrl.selection =
          TextSelection.collapsed(offset: _inputCtrl.text.length);
    });
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      setState(() => _playing = false);
      await _player.stop();
      return;
    }
    final String text = _textForAudio.trim();
    if (text.isEmpty) return;
    setState(() => _playing = true);
    await _player.play(text);
    if (!mounted) return;
    setState(() => _playing = false);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Morse Code'),
        toolbarHeight: 64,
        // §8.16 — copy the active conversion; disabled until a result exists.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.contentMaxWidth,
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
                      _directionToggle(text),
                      const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _visualStripCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _prosignCard(text, mono),
                      ToolHelpFooter(toolId: 'morse-code'),
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

  /// The direction toggle: Text → Morse  /  Morse → Text. Two segmented buttons;
  /// the active one is lime (§8.13 rule 6 — active state, not a verdict).
  Widget _directionToggle(TextTheme text) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _DirectionButton(
            label: 'Text → Morse',
            selected: _direction == _Direction.textToMorse,
            onTap: () => _setDirection(_Direction.textToMorse),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _DirectionButton(
            label: 'Morse → Text',
            selected: _direction == _Direction.morseToText,
            onTap: () => _setDirection(_Direction.morseToText),
          ),
        ),
      ],
    );
  }

  /// The single source-of-truth input field. Its label and styling switch with
  /// the active direction; in Morse→Text mode the field renders mono (the input
  /// is an identifier-shaped dot/dash string, §8.5).
  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool morseInput = _direction == _Direction.morseToText;
    final String label = morseInput ? 'Morse (dots and dashes)' : 'Text';
    final String hint = morseInput ? '... --- ...' : 'SOS';

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
            label,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _inputCtrl,
            autocorrect: !morseInput,
            enableSuggestions: !morseInput,
            minLines: 2,
            maxLines: 4,
            cursorColor: colors.textAccent,
            // Morse input is an identifier → Roboto Mono (§8.5). Plain text uses
            // the theme default sans.
            style: morseInput
                ? mono.robotoMono.copyWith(color: colors.textPrimary)
                : text.bodyMedium?.copyWith(color: colors.textPrimary),
            onChanged: _onInputChanged,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }

  /// The derived result, plus the Play sidetone control. The result string is
  /// Morse (mono) in text→Morse, and plain text in Morse→text.
  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool morseResult = _direction == _Direction.textToMorse;
    final String label = morseResult ? 'Morse' : 'Text';

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              _PlayButton(
                playing: _playing,
                enabled: _hasInput && _textForAudio.trim().isNotEmpty,
                onTap: _togglePlay,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_hasResult)
            SelectableText(
              _result,
              style: morseResult
                  ? mono.robotoMono.copyWith(
                      color: colors.textPrimary,
                      height: 1.6,
                    )
                  : text.bodyLarge?.copyWith(color: colors.textPrimary),
            )
          else
            Text(
              morseResult
                  ? 'Type text above to see its Morse code.'
                  : 'Type or paste dots and dashes above to decode.',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }

  /// A visual dot/dash strip — each symbol rendered as a filled dot or a dash
  /// bar, grouped by letter, so the code is legible as shapes, not just glyphs.
  Widget _visualStripCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final String code = _morseForDisplay.trim();

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
            'Visual code',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (code.isEmpty || !Morse.looksLikeMorse(code))
            Text(
              'The dot-and-dash view appears here once there is Morse to show.',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
            )
          else
            _MorseVisualStrip(code: code),
        ],
      ),
    );
  }

  /// Optional prosign reference, collapsed by default. Toggling it open lists
  /// the named procedural signals (SOS, AR, …) with their codes and meanings.
  Widget _prosignCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;

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
          Semantics(
            button: true,
            label: _showProsigns ? 'Hide prosigns' : 'Show prosigns',
            toggled: _showProsigns,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _showProsigns = !_showProsigns),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'Prosigns (procedural signals)',
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Icon(
                      _showProsigns
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: colors.textTertiary,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showProsigns) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            for (final MorseEntry e in Morse.prosigns)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        e.character,
                        style: text.bodyMedium?.copyWith(
                          color: colors.textAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            e.code,
                            style: mono.robotoMono
                                .copyWith(color: colors.textPrimary),
                          ),
                          if (e.name != null)
                            Text(
                              e.name!,
                              style: text.bodySmall
                                  ?.copyWith(color: colors.textTertiary),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One segmented direction button. Active → lime border + lime text + lime
/// wash (§8.13 rule 6: lime is the active state, not a status hue). Idle →
/// borderStrong outline + secondary text. The whole control is ≥48dp tall.
class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
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

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected
              ? colors.textAccent.withValues(alpha: 0.08)
              : Colors.transparent,
          foregroundColor:
              selected ? colors.textAccent : colors.textSecondary,
          side: BorderSide(
            color: selected ? colors.textAccent : colors.borderStrong,
            width: selected ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        ),
        child: Text(
          label,
          style: text.labelLarge?.copyWith(
            color: selected ? colors.textAccent : colors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// The Play / Stop sidetone control — a §8.3 secondary/outline icon+label
/// button. ACTIVE (playing) → lime (§8.13 rule 6). Disabled when there is no
/// text to sound out (textDisabled, dropped from focus).
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.enabled,
    required this.onTap,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color fg = !enabled
        ? colors.textDisabled
        : (playing ? colors.textAccent : colors.textSecondary);

    return Semantics(
      button: true,
      enabled: enabled,
      label: playing ? 'Stop audio' : 'Play audio',
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(
            color: !enabled
                ? colors.disabledFill
                : (playing ? colors.textAccent : colors.borderStrong),
            width: playing ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
        icon: Icon(playing ? Icons.stop : Icons.volume_up_outlined,
            size: 20, color: fg),
        label: Text(
          playing ? 'Stop' : 'Play',
          style: text.labelLarge?.copyWith(color: fg),
        ),
      ),
    );
  }
}

/// Renders a Morse code string as filled-dot and dash-bar shapes, grouped by
/// letter (single space) and word (slash). Wraps to multiple lines. The whole
/// strip carries one Semantics label so a screen reader hears the code, not a
/// flood of per-shape nodes.
class _MorseVisualStrip extends StatelessWidget {
  const _MorseVisualStrip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final List<Widget> letters = <Widget>[];

    // Split into words on the slash separator, then letters on single space.
    final List<String> words = code
        .split(RegExp(r'\s*[/|]\s*'))
        .where((String w) => w.trim().isNotEmpty)
        .toList();

    for (int w = 0; w < words.length; w++) {
      if (w > 0) {
        letters.add(_WordGap(color: colors.textTertiary));
      }
      for (final String token in words[w].trim().split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        letters.add(_LetterGlyphs(symbols: token, color: colors.textAccent));
      }
    }

    return Semantics(
      label: 'Morse code: $code',
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: letters,
      ),
    );
  }
}

/// The dot/dash shapes for one letter, packed tight.
class _LetterGlyphs extends StatelessWidget {
  const _LetterGlyphs({required this.symbols, required this.color});

  final String symbols;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < symbols.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.xxs),
          symbols[i] == '-'
              ? _Dash(color: color)
              : _Dot(color: color),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}

/// A visible word break in the visual strip — a slash glyph in muted ink.
class _WordGap extends StatelessWidget {
  const _WordGap({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text('/',
        style: text.titleMedium?.copyWith(color: color) ??
            TextStyle(color: color));
  }
}
