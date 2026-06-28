// PianoKeyboard — an interactive one-octave (C4 -> C5, 13 keys) keyboard for the
// "Hear the Frequency" tool. Renders the correct geometry: 8 white keys
// (C D E F G A B C) + 5 black keys grouped 2-then-3, with the two half-steps
// E-F and B-C drawn as the gaps WITH NO black key. Tapping a key calls
// [onKeyTap]; the [activeKeyNumber] key is highlighted in brand lime.
//
// TOKENS (GL-003): key CONTENT colors are the brand neutrals - white keys use
// AppColors.neutral0 (#FFFFFF, GL-003 §2 Neutral 0) and black keys use
// AppColors.secondary (#1A1A1A, GL-003 §2 Secondary), because a piano's
// white/black keys are domain content (like a chessboard), not arbitrary UI
// chrome. The active highlight is colors.primary (lime, the only app accent);
// borders use colors.borderStrong so each key boundary clears SC 1.4.11.
//
// NO TEXT OVER ELEMENTS (feedback_graphics_no_text_overlap): only the white-key
// letter sits inside a key, centered low in its own key region where it
// overlaps nothing. The active note's full detail (name + Hz + exponent) is
// shown by the PARENT in a readout strip below the keybed, never on the keys.
//
// ACCESSIBILITY: every key is a focusable, keyboard-activatable button
// (InkWell + Semantics) with a spoken label ("C4, 261.63 hertz"). Tab reaches
// each key; Enter/Space plays it; the focus ring is visible.

import 'package:flutter/material.dart';

import '../data/music_theory.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// White/black key content colors - the brand neutrals (GL-003 §2).
const Color _kWhiteKey = AppColors.neutral0; // #FFFFFF
const Color _kBlackKey = AppColors.secondary; // #1A1A1A

/// The white-key letter ink and the black-key active-label ink.
const Color _kWhiteKeyInk = AppColors.secondary; // dark letter on white key

class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({
    super.key,
    required this.notes,
    required this.onKeyTap,
    this.activeKeyNumber,
    this.height = 168,
  });

  /// The 13 notes C4 -> C5 inclusive (from [MusicTheory.chromaticC4toC5]).
  final List<Note> notes;

  /// Called with the tapped note.
  final ValueChanged<Note> onKeyTap;

  /// The currently highlighted key number, or null for none.
  final int? activeKeyNumber;

  /// Keybed height in logical pixels.
  final double height;

  /// White-key indices (0..7) after which a black key sits: C# D# - gap - F# G#
  /// A#. The gaps after index 2 (E->F) and index 7 (B->C) carry no black key.
  static const Set<int> _blackAfterWhite = <int>{0, 1, 3, 4, 5};

  @override
  Widget build(BuildContext context) {
    final List<Note> whites =
        notes.where((Note n) => !n.isBlack).toList(growable: false);
    final List<Note> blacks =
        notes.where((Note n) => n.isBlack).toList(growable: false);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double width = c.maxWidth;
        final int whiteCount = whites.length; // 8 for C4..C5
        final double whiteW = width / whiteCount;
        final double blackW = whiteW * 0.62;
        final double blackH = height * 0.62;

        // Map each black note to the x of its left edge, by walking the
        // white-after indices in order (the black list is already low->high).
        final List<int> slots = _blackAfterWhite.toList()..sort();
        final List<Widget> blackKeys = <Widget>[];
        for (int i = 0; i < blacks.length && i < slots.length; i++) {
          final int whiteIdx = slots[i];
          final double left = (whiteIdx + 1) * whiteW - blackW / 2;
          blackKeys.add(
            Positioned(
              left: left,
              top: 0,
              width: blackW,
              height: blackH,
              child: _Key(
                note: blacks[i],
                isBlack: true,
                active: blacks[i].keyNumber == activeKeyNumber,
                onTap: () => onKeyTap(blacks[i]),
              ),
            ),
          );
        }

        return SizedBox(
          height: height,
          width: width,
          child: Stack(
            children: <Widget>[
              // White keys row.
              Row(
                children: <Widget>[
                  for (final Note w in whites)
                    SizedBox(
                      width: whiteW,
                      height: height,
                      child: _Key(
                        note: w,
                        isBlack: false,
                        active: w.keyNumber == activeKeyNumber,
                        onTap: () => onKeyTap(w),
                      ),
                    ),
                ],
              ),
              // Black keys overlaid.
              ...blackKeys,
            ],
          ),
        );
      },
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.note,
    required this.isBlack,
    required this.active,
    required this.onTap,
  });

  final Note note;
  final bool isBlack;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color base = isBlack ? _kBlackKey : _kWhiteKey;
    final Color fill = active ? colors.primary : base;
    // Letter ink: dark on white / lime-pressed keys, light on black keys.
    final Color ink =
        isBlack ? (active ? AppColors.secondary : Colors.white) : _kWhiteKeyInk;

    final BorderRadius radius = BorderRadius.vertical(
      bottom: Radius.circular(isBlack ? AppRadius.control : AppRadius.card),
    );

    return Semantics(
      button: true,
      label: '${note.fullLabel}, ${note.frequencyHz.toStringAsFixed(2)} hertz',
      selected: active,
      excludeSemantics: true,
      child: Padding(
        // 1px gutter so adjacent white keys read as separate keys.
        padding: EdgeInsets.all(isBlack ? 0 : 1),
        child: Material(
          color: fill,
          // A visible key boundary that clears SC 1.4.11 on every surface.
          // (Material asserts shape XOR borderRadius, so the rounding lives on
          // the shape; InkWell keeps its own borderRadius for the splash clip.)
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: colors.borderStrong, width: 1),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            // Only WHITE keys carry a letter, low and centered in their own
            // region (no overlap with any line or neighbor label).
            child: isBlack
                ? const SizedBox.expand()
                : Align(
                    alignment: const Alignment(0, 0.82),
                    child: Text(
                      // Show the octave digit only on the two C anchors so the
                      // row reads C4 ... C5 without crowding every white key.
                      note.name == 'C' ? note.label : note.name,
                      style: TextStyle(
                        fontFamily: 'Roboto Mono',
                        fontSize: AppTextSize.caption,
                        fontWeight: FontWeight.w500,
                        color: active ? AppColors.secondary : ink,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
