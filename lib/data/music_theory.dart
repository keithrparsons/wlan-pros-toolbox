// Music theory — pure-Dart equal-temperament math for the "Hear the Frequency"
// RF-by-ear teaching tool (hear-frequency). No Flutter, no audio engine, no
// platform dependency, so every value here is unit-testable from an in-memory
// call (mirrors dtmf.dart / signaling_tones.dart).
//
// SINGLE SOURCE OF TRUTH: every note frequency is COMPUTED from the standard
// 12-tone equal-temperament (12-TET) formula. Nothing is transcribed from a
// table, so there is no copy error to drift. The spec's published C4->C5 table
// is reproduced ONLY in the unit test as a golden baseline that this code must
// reproduce to 2 decimals.
//
// VERIFIED VALUES (Pax build-spec 2026-06-28, GL-005):
//   f(n) = 440 * 2^((n - 49) / 12)    n = piano key number, key 49 = A4 = 440 Hz
//   Semitone ratio 2^(1/12) = 1.0594630943592953
//   A4 = 440 Hz is ISO 16. Middle C (C4) = 261.63 Hz. C5 = 523.25 Hz.
//   12 semitones per octave; octave ratio = exactly 2.
//
// ANALOGY HONESTY (baked into the RF-bridge helpers, GL-005): an octave is a
// base-2 FREQUENCY ratio; a dB is a base-10 POWER ratio. They are both
// logarithmic ratio measures (the real, teachable bridge) but they are NOT the
// same unit. This file never converts an octave to a dB. Audio harmonics and
// RF harmonics share the same integer-multiple math (2f, 3f, ...) but audio
// overtones are WANTED (timbre) while RF harmonics are usually UNWANTED
// (spurious emissions) - the desirability flips; the math does not.

import 'dart:math' as math;

/// log base 2.
double _log2(double x) => math.log(x) / math.ln2;

/// The audible range clamp for PLAYBACK, per the build-spec safety guardrail
/// (Pax 2.6). Frequencies outside this are never driven to the speaker; a
/// number above it may still be DISPLAYED for the RF analogy, clearly labeled.
const double kMinAudibleHz = 20.0;
const double kMaxAudibleHz = 20000.0;

/// Concert-pitch reference: A4 = 440 Hz (ISO 16). Piano key number of A4.
const double kA4Hz = 440.0;
const int kA4KeyNumber = 49;

/// Piano key numbers for the on-screen one-octave keyboard, C4 -> C5.
const int kC4KeyNumber = 40;
const int kC5KeyNumber = 52;

/// 12-TET semitone ratio, 2^(1/12). Exposed for the keyboard's "x1.05946"
/// step label.
final double kSemitoneRatio = math.pow(2.0, 1.0 / 12.0).toDouble();

/// The twelve pitch-class names indexed from C (index 0). Sharps are the
/// primary spelling; flats are the enharmonic equivalent (true ONLY in equal
/// temperament - analogy-limit 3).
const List<String> _pitchClassSharp = <String>[
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];
const List<String> _pitchClassFlat = <String>[
  'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
];

/// Whether a pitch class (0..11 from C) is a black key on the piano.
const List<bool> _isBlackPitchClass = <bool>[
  false, true, false, true, false, false, true, false, true, false, true,
  false,
];

/// A single named note: its piano key number, its frequency, and its name.
class Note {
  const Note({
    required this.keyNumber,
    required this.frequencyHz,
    required this.name,
    required this.octave,
    required this.isBlack,
    required this.enharmonicName,
  });

  /// Piano key number (A0 = 1, A4 = 49, C4 = 40, C5 = 52).
  final int keyNumber;

  /// Equal-tempered frequency in Hz, computed from [MusicTheory.frequencyForKey].
  final double frequencyHz;

  /// Primary (sharp-spelled) name without the octave digit, e.g. "C", "C#".
  final String name;

  /// Scientific-pitch octave number (C4 = middle C).
  final int octave;

  /// Whether this is a black key on the keyboard.
  final bool isBlack;

  /// The flat spelling for a black key (e.g. "Db" for "C#"); null for white
  /// keys. Same frequency as [name] in 12-TET (enharmonic equivalence).
  final String? enharmonicName;

  /// Name with octave, e.g. "C4", "A#4".
  String get label => '$name$octave';

  /// Both enharmonic spellings with octave for a black key, e.g. "C#4 / Db4";
  /// the plain [label] for a white key.
  String get fullLabel =>
      enharmonicName == null ? label : '$name$octave / $enharmonicName$octave';
}

/// A harmonic of a fundamental: its integer order and frequency.
typedef Harmonic = ({int order, double frequencyHz});

/// The result of comparing two frequencies as a musical interval plus the
/// honest octave / log framing.
class IntervalResult {
  const IntervalResult({
    required this.ratio,
    required this.octaves,
    required this.semitones,
    required this.nearestSemitones,
    required this.intervalName,
    required this.centsFromNearest,
  });

  /// f2 / f1 with f2 >= f1, so ratio >= 1.
  final double ratio;

  /// log2(ratio) - octaves apart (r = 2 -> 1.0, r = 4 -> 2.0).
  final double octaves;

  /// 12 * log2(ratio) - semitones apart (may be fractional).
  final double semitones;

  /// [semitones] rounded to the nearest integer - the equal-tempered interval.
  final int nearestSemitones;

  /// The nearest-equal-tempered interval name (e.g. "perfect fifth", "octave").
  final String intervalName;

  /// How far the real ratio sits from the nearest tempered interval, in cents
  /// (100 cents = one semitone). 0 means an exact tempered interval.
  final double centsFromNearest;
}

/// The nearest-note result for an arbitrary frequency (for the live readout).
class NearestNote {
  const NearestNote({
    required this.note,
    required this.centsOffset,
    required this.octavesFromA4,
  });

  /// The closest equal-tempered note.
  final Note note;

  /// Signed cents from that note (+ sharp, - flat); 0 means dead on.
  final double centsOffset;

  /// log2(f / 440) - signed octaves above (+) or below (-) A4.
  final double octavesFromA4;
}

/// Pure equal-temperament + RF-bridge math. All static; no state.
class MusicTheory {
  MusicTheory._();

  // ─── Core equal-temperament formula ───────────────────────────────────────

  /// f(n) = 440 * 2^((n - 49) / 12). The single source of truth for every note
  /// frequency. [keyNumber] is the piano key number (A4 = 49).
  static double frequencyForKey(int keyNumber) =>
      kA4Hz * math.pow(2.0, (keyNumber - kA4KeyNumber) / 12.0).toDouble();

  /// The exponent (n - 49) / 12 shown beside a key in the semitone-math overlay.
  static double exponentForKey(int keyNumber) =>
      (keyNumber - kA4KeyNumber) / 12.0;

  /// Build the [Note] for a piano [keyNumber] (name, octave, black/white,
  /// enharmonic spelling, frequency).
  static Note noteForKey(int keyNumber) {
    // MIDI note = key + 20 (A4 key 49 -> MIDI 69). Pitch class 0 = C.
    final int midi = keyNumber + 20;
    final int pc = midi % 12;
    final int octave = (midi ~/ 12) - 1;
    final bool black = _isBlackPitchClass[pc];
    return Note(
      keyNumber: keyNumber,
      frequencyHz: frequencyForKey(keyNumber),
      name: _pitchClassSharp[pc],
      octave: octave,
      isBlack: black,
      enharmonicName: black ? _pitchClassFlat[pc] : null,
    );
  }

  /// The 13 notes C4 -> C5 inclusive that drive the on-screen keyboard.
  static List<Note> get chromaticC4toC5 => <Note>[
        for (int k = kC4KeyNumber; k <= kC5KeyNumber; k++) noteForKey(k),
      ];

  /// The seven WHITE-key notes of C4 -> C5 (the C-major scale C D E F G A B C).
  static List<Note> get whiteKeysC4toC5 =>
      chromaticC4toC5.where((Note n) => !n.isBlack).toList();

  /// The five BLACK-key notes of C4 -> C5 (grouped 2 then 3 on the keyboard).
  static List<Note> get blackKeysC4toC5 =>
      chromaticC4toC5.where((Note n) => n.isBlack).toList();

  // ─── Octave moves (the core "doubling = one octave" demo) ──────────────────

  /// One octave UP is exactly x2 the frequency.
  static double octaveUp(double hz) => hz * 2.0;

  /// One octave DOWN is exactly the frequency / 2.
  static double octaveDown(double hz) => hz / 2.0;

  // ─── Nearest-note readout (arbitrary frequency -> note + cents) ────────────

  /// The closest equal-tempered note to [hz], the signed cents offset, and the
  /// signed octaves from A4. [hz] must be > 0.
  static NearestNote nearestNote(double hz) {
    final double midiFloat = 69.0 + 12.0 * _log2(hz / kA4Hz);
    final int nearestMidi = midiFloat.round();
    final double cents = (midiFloat - nearestMidi) * 100.0;
    final int keyNumber = nearestMidi - 20;
    return NearestNote(
      note: noteForKey(keyNumber),
      centsOffset: cents,
      octavesFromA4: _log2(hz / kA4Hz),
    );
  }

  // ─── Harmonics (integer multiples, the RF spurious-emission tie-in) ────────

  /// The first [count] harmonics of [fundamentalHz] starting at the fundamental
  /// itself (order 1 = f, order 2 = 2f, ...). The same integer-multiple math
  /// that, in a transmitter, shows up as harmonics / spurious emissions
  /// (analogy-limit 2: wanted timbre vs unwanted emission).
  static List<Harmonic> harmonics(double fundamentalHz, {int count = 5}) =>
      <Harmonic>[
        for (int order = 1; order <= count; order++)
          (order: order, frequencyHz: fundamentalHz * order),
      ];

  // ─── Interval / ratio explorer ─────────────────────────────────────────────

  /// Interval names indexed by semitone count 0..12 (nearest tempered interval).
  static const List<String> _intervalNames = <String>[
    'unison',
    'minor second',
    'major second',
    'minor third',
    'major third',
    'perfect fourth',
    'tritone',
    'perfect fifth',
    'minor sixth',
    'major sixth',
    'minor seventh',
    'major seventh',
    'octave',
  ];

  /// Name the interval for a (non-negative) semitone count, folding octaves:
  /// e.g. 12 -> "octave", 19 -> "perfect fifth + 1 octave".
  static String intervalNameForSemitones(int semitones) {
    if (semitones < 0) return 'descending';
    final int octaves = semitones ~/ 12;
    final int within = semitones % 12;
    final String base = _intervalNames[within];
    if (octaves == 0) return base;
    if (within == 0) {
      return octaves == 1 ? 'octave' : '$octaves octaves';
    }
    final String oct = octaves == 1 ? '1 octave' : '$octaves octaves';
    return '$base + $oct';
  }

  /// Compare two frequencies as a musical interval. Order-independent: the
  /// larger over the smaller, so [ratio] >= 1. Both must be > 0.
  static IntervalResult interval(double a, double b) {
    final double hi = math.max(a, b);
    final double lo = math.min(a, b);
    final double ratio = hi / lo;
    final double octaves = _log2(ratio);
    final double semis = 12.0 * octaves;
    final int nearest = semis.round();
    return IntervalResult(
      ratio: ratio,
      octaves: octaves,
      semitones: semis,
      nearestSemitones: nearest,
      intervalName: intervalNameForSemitones(nearest),
      centsFromNearest: (semis - nearest) * 100.0,
    );
  }

  // ─── RF bridge (computed, VERIFIED - Pax 2.4) ──────────────────────────────

  /// Octaves between two frequencies of ANY magnitude (Hz or GHz - log2 is
  /// scale-free). Used by the Wi-Fi-band bridge: octavesBetween(2.4, 4.8) = 1.0.
  static double octavesBetween(double f1, double f2) =>
      _log2(math.max(f1, f2) / math.min(f1, f2));
}
