// Phonetic Alphabet reference data — compile-time const, source of truth for the
// data-driven Phonetic Alphabet screen (Tier-1, Pass 2b 2026-06-12).
//
// The native A-Z table carries letter -> NATO spelling word -> Morse. The
// semaphore arm dials and the maritime signal flags are the VISUAL the table
// cannot reproduce cleanly, so they are embedded as a staged plate PNG.
//
// ICAO/NATO OFFICIAL SPELLING: "Alfa" (not Alpha) and "Juliett" (double-t) — the
// f and the double-t are intentional so non-English speakers pronounce them
// correctly. A "common variant" is carried where one exists.
//
// Source: Outside Open phonetic-alphabet poster (v1.2), recreated cleanly. The
// poster covers A-Z only — there are NO digit rows.

/// One letter row: the letter, its ICAO/NATO word, the common variant (empty if
/// none), and its international Morse pattern.
class PhoneticLetter {
  const PhoneticLetter({
    required this.letter,
    required this.word,
    required this.morse,
    this.variant = '',
  });

  /// Roman letter, e.g. `A`.
  final String letter;

  /// ICAO/NATO spelling word, e.g. `Alfa`.
  final String word;

  /// International Morse pattern (`.` dot, `-` dash).
  final String morse;

  /// Common anglicized variant, e.g. `Alpha`; empty string when none.
  final String variant;
}

/// The A-Z phonetic alphabet (ICAO/NATO official spelling).
const List<PhoneticLetter> kPhoneticAlphabet = <PhoneticLetter>[
  PhoneticLetter(letter: 'A', word: 'Alfa', variant: 'Alpha', morse: '.-'),
  PhoneticLetter(letter: 'B', word: 'Bravo', morse: '-...'),
  PhoneticLetter(letter: 'C', word: 'Charlie', morse: '-.-.'),
  PhoneticLetter(letter: 'D', word: 'Delta', morse: '-..'),
  PhoneticLetter(letter: 'E', word: 'Echo', morse: '.'),
  PhoneticLetter(letter: 'F', word: 'Foxtrot', morse: '..-.'),
  PhoneticLetter(letter: 'G', word: 'Golf', morse: '--.'),
  PhoneticLetter(letter: 'H', word: 'Hotel', morse: '....'),
  PhoneticLetter(letter: 'I', word: 'India', morse: '..'),
  PhoneticLetter(
    letter: 'J',
    word: 'Juliett',
    variant: 'Juliet',
    morse: '.---',
  ),
  PhoneticLetter(letter: 'K', word: 'Kilo', morse: '-.-'),
  PhoneticLetter(letter: 'L', word: 'Lima', morse: '.-..'),
  PhoneticLetter(letter: 'M', word: 'Mike', morse: '--'),
  PhoneticLetter(letter: 'N', word: 'November', morse: '-.'),
  PhoneticLetter(letter: 'O', word: 'Oscar', morse: '---'),
  PhoneticLetter(letter: 'P', word: 'Papa', morse: '.--.'),
  PhoneticLetter(letter: 'Q', word: 'Quebec', morse: '--.-'),
  PhoneticLetter(letter: 'R', word: 'Romeo', morse: '.-.'),
  PhoneticLetter(letter: 'S', word: 'Sierra', morse: '...'),
  PhoneticLetter(letter: 'T', word: 'Tango', morse: '-'),
  PhoneticLetter(letter: 'U', word: 'Uniform', morse: '..-'),
  PhoneticLetter(letter: 'V', word: 'Victor', morse: '...-'),
  PhoneticLetter(letter: 'W', word: 'Whiskey', morse: '.--'),
  PhoneticLetter(letter: 'X', word: 'Xray', variant: 'X-ray', morse: '-..-'),
  PhoneticLetter(letter: 'Y', word: 'Yankee', morse: '-.--'),
  PhoneticLetter(letter: 'Z', word: 'Zulu', morse: '--..'),
];

/// Legend lines describing the visual layers on the embedded plate.
const List<String> kPhoneticLegend = <String>[
  'Semaphore: pre-electronic flag letter signals for naval communication. Two '
      'hand flags, one per arm, each held at a fixed bearing.',
  'International Morse code: each letter is a unique pattern of short signals '
      '(dots) and long signals (dashes).',
  'International code of signals (maritime flags): flags used to communicate '
      'letters and messages between ships while keeping radio silence.',
];

/// On-screen note: ICAO spelling + the A-Z-only scope.
const String kPhoneticNote =
    'ICAO/NATO official spelling uses Alfa (not Alpha) and Juliett (double-t) so '
    'the words are pronounced correctly across languages. This reference covers '
    'A to Z; there are no digit rows.';
