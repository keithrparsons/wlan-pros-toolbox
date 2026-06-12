// International Morse code — pure Dart, no Flutter, no audio engine.
//
// Encodes/decodes International Morse (ITU-R M.1677-1): A–Z, 0–9, common
// punctuation, and a handful of named prosigns. The character table and the
// text↔Morse transforms live here and are fully unit-testable with no platform
// dependency. The screen renders these results; the audio engine
// (lib/services/audio/morse_player.dart) consumes the timing model below.
//
// Conventions used throughout:
//   * A character's Morse is a run of '.' (dot / dit) and '-' (dash / dah).
//   * Symbols within a character are written with no separator.
//   * Letters within a word are joined by a single space  (" ").
//   * Words are joined by a slash with spaces             (" / ").
// These are the most widely used display conventions and round-trip cleanly.

/// One row of the International Morse table: a printable character and its
/// dot/dash code. [isProsign] flags the named procedural signals (e.g. SOS),
/// which are off by default in encoding because they are not literal text.
class MorseEntry {
  const MorseEntry({
    required this.character,
    required this.code,
    this.isProsign = false,
    this.name,
  });

  /// The printable character this code maps to ("A", "5", "?"), or the prosign
  /// token (`<SOS>`) when [isProsign] is true.
  final String character;

  /// The dot/dash code, e.g. ".-" for A. Dots are '.', dashes are '-'.
  final String code;

  /// True for the named procedural signals (SOS, AR, …) — not literal text, so
  /// excluded from text→Morse encoding unless explicitly requested.
  final bool isProsign;

  /// Human-readable prosign name ("End of message"), null for ordinary chars.
  final String? name;
}

/// The International Morse standard plus the transforms over it.
class Morse {
  Morse._();

  /// Letter separator inside a word (one space between characters).
  static const String letterGap = ' ';

  /// Word separator (slash flanked by spaces).
  static const String wordGap = ' / ';

  /// The core International Morse table: letters, digits, punctuation. Keyed by
  /// the UPPER-CASE character. Order is meaningful only for [entries] display.
  static const List<MorseEntry> letters = <MorseEntry>[
    MorseEntry(character: 'A', code: '.-'),
    MorseEntry(character: 'B', code: '-...'),
    MorseEntry(character: 'C', code: '-.-.'),
    MorseEntry(character: 'D', code: '-..'),
    MorseEntry(character: 'E', code: '.'),
    MorseEntry(character: 'F', code: '..-.'),
    MorseEntry(character: 'G', code: '--.'),
    MorseEntry(character: 'H', code: '....'),
    MorseEntry(character: 'I', code: '..'),
    MorseEntry(character: 'J', code: '.---'),
    MorseEntry(character: 'K', code: '-.-'),
    MorseEntry(character: 'L', code: '.-..'),
    MorseEntry(character: 'M', code: '--'),
    MorseEntry(character: 'N', code: '-.'),
    MorseEntry(character: 'O', code: '---'),
    MorseEntry(character: 'P', code: '.--.'),
    MorseEntry(character: 'Q', code: '--.-'),
    MorseEntry(character: 'R', code: '.-.'),
    MorseEntry(character: 'S', code: '...'),
    MorseEntry(character: 'T', code: '-'),
    MorseEntry(character: 'U', code: '..-'),
    MorseEntry(character: 'V', code: '...-'),
    MorseEntry(character: 'W', code: '.--'),
    MorseEntry(character: 'X', code: '-..-'),
    MorseEntry(character: 'Y', code: '-.--'),
    MorseEntry(character: 'Z', code: '--..'),
  ];

  /// The ten digits.
  static const List<MorseEntry> digits = <MorseEntry>[
    MorseEntry(character: '1', code: '.----'),
    MorseEntry(character: '2', code: '..---'),
    MorseEntry(character: '3', code: '...--'),
    MorseEntry(character: '4', code: '....-'),
    MorseEntry(character: '5', code: '.....'),
    MorseEntry(character: '6', code: '-....'),
    MorseEntry(character: '7', code: '--...'),
    MorseEntry(character: '8', code: '---..'),
    MorseEntry(character: '9', code: '----.'),
    MorseEntry(character: '0', code: '-----'),
  ];

  /// Common punctuation, per ITU-R M.1677-1.
  static const List<MorseEntry> punctuation = <MorseEntry>[
    MorseEntry(character: '.', code: '.-.-.-'),
    MorseEntry(character: ',', code: '--..--'),
    MorseEntry(character: '?', code: '..--..'),
    MorseEntry(character: "'", code: '.----.'),
    MorseEntry(character: '!', code: '-.-.--'),
    MorseEntry(character: '/', code: '-..-.'),
    MorseEntry(character: '(', code: '-.--.'),
    MorseEntry(character: ')', code: '-.--.-'),
    MorseEntry(character: '&', code: '.-...'),
    MorseEntry(character: ':', code: '---...'),
    MorseEntry(character: ';', code: '-.-.-.'),
    MorseEntry(character: '=', code: '-...-'),
    MorseEntry(character: '+', code: '.-.-.'),
    MorseEntry(character: '-', code: '-....-'),
    MorseEntry(character: '_', code: '..--.-'),
    MorseEntry(character: '"', code: '.-..-.'),
    MorseEntry(character: r'$', code: '...-..-'),
    MorseEntry(character: '@', code: '.--.-.'),
  ];

  /// Named procedural signals. These are NOT literal characters, so they are
  /// excluded from text→Morse by default and shown as an optional reference.
  /// Their tokens use angle-bracket form (`<SOS>`) so they never collide with
  /// ordinary text.
  static const List<MorseEntry> prosigns = <MorseEntry>[
    MorseEntry(
        character: '<SOS>',
        code: '...---...',
        isProsign: true,
        name: 'Distress signal'),
    MorseEntry(
        character: '<AR>',
        code: '.-.-.',
        isProsign: true,
        name: 'End of message'),
    MorseEntry(
        character: '<AS>',
        code: '.-...',
        isProsign: true,
        name: 'Wait'),
    MorseEntry(
        character: '<SK>',
        code: '...-.-',
        isProsign: true,
        name: 'End of contact'),
    MorseEntry(
        character: '<KN>',
        code: '-.--.',
        isProsign: true,
        name: 'Go ahead, specific station'),
    MorseEntry(
        character: '<BT>',
        code: '-...-',
        isProsign: true,
        name: 'New paragraph / break'),
  ];

  /// All ordinary (non-prosign) entries in display order.
  static const List<List<MorseEntry>> _ordinaryGroups = <List<MorseEntry>>[
    letters,
    digits,
    punctuation,
  ];

  /// char → code, for every ordinary (non-prosign) character. Keys are the
  /// upper-case character.
  static final Map<String, String> charToCode = _buildCharToCode();

  /// code → char, the inverse table for decoding ordinary characters.
  static final Map<String, String> codeToChar = _buildCodeToChar();

  static Map<String, String> _buildCharToCode() {
    final Map<String, String> out = <String, String>{};
    for (final List<MorseEntry> group in _ordinaryGroups) {
      for (final MorseEntry e in group) {
        out[e.character] = e.code;
      }
    }
    return out;
  }

  static Map<String, String> _buildCodeToChar() {
    final Map<String, String> out = <String, String>{};
    for (final List<MorseEntry> group in _ordinaryGroups) {
      for (final MorseEntry e in group) {
        out[e.code] = e.character;
      }
    }
    return out;
  }

  /// True if [ch] (a single character) has an ordinary Morse mapping.
  static bool isEncodable(String ch) =>
      charToCode.containsKey(ch.toUpperCase());

  /// Encode plain [text] to Morse. Letters within a word are joined by a single
  /// space; words by " / ". Characters with no Morse mapping are dropped, EXCEPT
  /// runs of whitespace which become a single word gap. Decoding is the inverse
  /// of this, so a round-trip on encodable text is lossless (case folds to
  /// upper, and runs of spaces collapse to one word gap).
  ///
  /// Returns an empty string for empty/all-unmappable input.
  static String encode(String text) {
    final List<String> words = <String>[];
    // Split on any run of whitespace into words; preserve word boundaries.
    for (final String rawWord in text.trim().split(RegExp(r'\s+'))) {
      if (rawWord.isEmpty) continue;
      final List<String> codes = <String>[];
      for (final int rune in rawWord.runes) {
        final String ch = String.fromCharCode(rune).toUpperCase();
        final String? code = charToCode[ch];
        if (code != null) codes.add(code);
      }
      if (codes.isNotEmpty) words.add(codes.join(letterGap));
    }
    return words.join(wordGap);
  }

  /// Decode [morse] (dots/dashes) back to text. Tolerant of the common input
  /// variants a user might type or paste:
  ///   * word separators: "/", "|", or a run of 2+ spaces;
  ///   * letter separators: single spaces;
  ///   * stray whitespace around tokens is ignored.
  /// Unknown codes decode to '?' so the output length tracks the input and the
  /// user can see exactly which symbol failed, rather than silently vanishing.
  ///
  /// Returns an empty string for empty input.
  static String decode(String morse) {
    final String trimmed = morse.trim();
    if (trimmed.isEmpty) return '';

    // Normalize explicit word separators ('/' or '|') to a sentinel, then split
    // remaining runs of whitespace as either letter gaps (single) or, where no
    // explicit separator was used, double-space as a word gap.
    // Strategy: split on the explicit word separators first; within each word,
    // split on whitespace to get letter codes.
    final List<String> words = trimmed
        .split(RegExp(r'\s*[/|]\s*|\s{2,}'))
        .where((String w) => w.trim().isNotEmpty)
        .toList();

    final List<String> outWords = <String>[];
    for (final String word in words) {
      final StringBuffer letters = StringBuffer();
      for (final String token
          in word.trim().split(RegExp(r'\s+'))) {
        if (token.isEmpty) continue;
        letters.write(codeToChar[token] ?? '?');
      }
      if (letters.isNotEmpty) outWords.add(letters.toString());
    }
    return outWords.join(' ');
  }

  /// Whether [input] looks like Morse (only dots, dashes, spaces, and the word
  /// separators) rather than plain text. Used by the screen to auto-route a
  /// pasted string to the right field. Empty input is not Morse.
  static bool looksLikeMorse(String input) {
    final String t = input.trim();
    if (t.isEmpty) return false;
    return RegExp(r'^[.\-/| ]+$').hasMatch(t);
  }

  // ── Timing model (for the audio / flash player) ──────────────────────────
  //
  // Standard Morse timing in "dit units":
  //   * dot           = 1 unit ON
  //   * dash          = 3 units ON
  //   * intra-char gap = 1 unit OFF (between symbols of one character)
  //   * letter gap     = 3 units OFF (between characters)
  //   * word gap       = 7 units OFF (between words)
  // One unit's duration is derived from words-per-minute via the PARIS standard
  // (PARIS = 50 units), so unitMs = 1200 / wpm.

  /// Milliseconds per dit unit at [wordsPerMinute] (PARIS standard).
  static int unitMs(int wordsPerMinute) =>
      (1200 / wordsPerMinute).round();

  /// A single on/off segment of a Morse transmission.
  ///
  /// [on] true → tone/flash is active; false → silence/dark. [units] is the
  /// duration in dit units (multiply by [unitMs] for milliseconds).
  /// Decomposing into segments lets both the audio player and a visual flasher
  /// drive off one timing source.
  static List<MorseSegment> segments(String text) {
    final String code = encode(text);
    if (code.isEmpty) return const <MorseSegment>[];

    final List<MorseSegment> out = <MorseSegment>[];
    // The encoded string uses ' ' between letters and ' / ' between words.
    // Walk it character by character so we emit exact ON/OFF runs.
    final List<String> words = code.split(wordGap);
    for (int w = 0; w < words.length; w++) {
      if (w > 0) out.add(const MorseSegment(on: false, units: 7)); // word gap
      final List<String> chars = words[w].split(letterGap);
      for (int c = 0; c < chars.length; c++) {
        if (c > 0) out.add(const MorseSegment(on: false, units: 3)); // letter
        final String symbols = chars[c];
        for (int s = 0; s < symbols.length; s++) {
          if (s > 0) out.add(const MorseSegment(on: false, units: 1)); // intra
          final bool isDash = symbols[s] == '-';
          out.add(MorseSegment(on: true, units: isDash ? 3 : 1));
        }
      }
    }
    return out;
  }
}

/// A single ON (tone/flash) or OFF (silence/dark) run, measured in dit units.
class MorseSegment {
  const MorseSegment({required this.on, required this.units});

  /// True → tone/light is active for this run; false → silence/dark.
  final bool on;

  /// Duration of the run in dit units (see [Morse.unitMs]).
  final int units;
}
