// Telephone signaling history — pure-Dart tone tables for the DTMF tool's
// "Telephone Signaling History" modes (Blue Box / Red Box).
//
// HONESTY IS THE FEATURE (GL-005). These reproduce the in-band signaling tones
// that 20th-century phone networks once acted on:
//   * Blue Box — R1 Multi-Frequency (MF) trunk-routing tones + the 2600 Hz
//     supervisory ("trunk idle") tone.
//   * US Red Box — the dual-tone coin-deposit acknowledgement bursts an ACTS
//     payphone sent up the line for a nickel / dime / quarter.
// They do NOTHING on any modern phone network. Call-control signaling moved
// out of the voice band onto a separate data channel (CCIS, then SS7) in the
// 1980s-1990s, and ACTS payphones are effectively extinct. The switch no longer
// listens for these tones in the audio path. They are reproduced here for
// historical and educational interest only — telephone signaling history, not a
// working tool. Every user-facing surface states this plainly.
//
// SYNTHESIS: this file owns only the DATA (frequencies, durations, burst
// patterns) plus a thin pure-PCM synthesizer that reuses the exact same
// dual-sine + click-suppression math as [Dtmf.synthesize] and the same WAV
// wrapper [Dtmf.wavFromPcm]. Nothing here touches Flutter or the audio engine,
// so it is unit-testable with no platform dependency — identical to dtmf.dart.
//
// SAMPLE RATE: 8000 Hz is sufficient. The highest component in either mode is
// the Red Box 2200 Hz tone (Blue Box maxes at the 2600 Hz seize tone), both
// well under the 4000 Hz Nyquist limit, so they reproduce cleanly.
//
// SOURCES (per the 2026-06-11 feasibility brief):
//   * Blue Box MF pairs: ITU-T / Wikipedia "Multi-frequency signaling"
//     canonical assignment by frequency membership (NOT the ToneGenerator repo's
//     differing digit ordering). KP = 1100+1700, ST = 1500+1700, 2600 = single.
//   * US Red Box: 1700+2200 Hz; nickel = one 66 ms burst; dime = two 66 ms
//     bursts 66 ms apart; quarter = five 33 ms bursts 33 ms apart.
//     (Wikipedia "Red box (phreaking)", corroborated.)

import 'dart:math' as math;
import 'dart:typed_data';

import 'dtmf.dart';

/// Which historical signaling family a [SignalingTone] belongs to. Used to
/// group the on-screen pads and to pick the right help entry.
enum SignalingFamily {
  /// R1 Multi-Frequency trunk signaling + the 2600 Hz supervisory tone.
  blueBox,

  /// US ACTS payphone coin-deposit acknowledgement bursts.
  redBox,
}

/// One historical signaling signal: a label, one or two component frequencies,
/// and a burst pattern (how many bursts, how long each, and the gap between
/// them). A single steady tone is `bursts == 1` with `gapMs == 0`; the 2600 Hz
/// supervisory tone is a single-frequency ([highHz] == null) single burst.
///
/// This is the §pure-data shape the brief specified: a frequency pair plus a
/// (burst, duration, gap) timing — fed through the same synth path DTMF uses.
class SignalingTone {
  const SignalingTone({
    required this.label,
    required this.family,
    required this.lowHz,
    this.highHz,
    required this.burstMs,
    this.bursts = 1,
    this.gapMs = 0,
    required this.description,
  });

  /// Short pad label as shown to the user ("1".."0", "KP", "ST", "2600",
  /// "Nickel", "Dime", "Quarter").
  final String label;

  /// Which historical family this belongs to (drives grouping + help).
  final SignalingFamily family;

  /// First / low component frequency (Hz). Always present.
  final double lowHz;

  /// Second / high component frequency (Hz), or null for a single-tone signal
  /// (the 2600 Hz supervisory tone).
  final double? highHz;

  /// Duration of each individual burst (ms).
  final int burstMs;

  /// How many bursts make up this signal (1 for a single steady tone; 2 for a
  /// dime; 5 for a quarter).
  final int bursts;

  /// Silent gap between consecutive bursts (ms). Zero for a single-burst tone.
  final int gapMs;

  /// One-line plain-language description of what this signal historically did,
  /// for the on-screen readout and screen-reader value (GL-005: honest).
  final String description;

  /// Whether this is a single-frequency signal (the 2600 Hz seize tone).
  bool get isSingleFrequency => highHz == null;

  /// Human-readable frequency readout, e.g. "700 Hz + 1100 Hz" or "2600 Hz".
  String get frequencyLabel {
    final String low = '${lowHz.toStringAsFixed(0)} Hz';
    final double? high = highHz;
    if (high == null) return low;
    return '$low + ${high.toStringAsFixed(0)} Hz';
  }

  /// Human-readable timing readout, e.g. "66 ms" or "5 × 33 ms, 33 ms apart".
  String get timingLabel {
    if (bursts <= 1) return '$burstMs ms';
    return '$bursts × $burstMs ms, $gapMs ms apart';
  }
}

/// The Blue Box (R1 Multi-Frequency) and US Red Box tone tables, plus a pure
/// PCM synthesizer for them. Mirrors [Dtmf]'s structure exactly.
class SignalingTones {
  SignalingTones._();

  /// Shared sample rate with the DTMF engine (8000 Hz telephony band).
  static const int sampleRate = Dtmf.sampleRate;

  /// The six R1 MF frequencies, low to high (Hz). Each MF signal is a pair.
  static const List<double> mfFrequencies = <double>[
    700,
    900,
    1100,
    1300,
    1500,
    1700,
  ];

  /// Per-MF-digit burst duration (ms). Historically MF digits ran ~60-75 ms;
  /// 100 ms is a clean, clearly-audible simplification for a museum playback,
  /// matching the reference implementation.
  static const int mfBurstMs = 100;

  /// Blue Box — the R1 MF routing tones, KP / ST framing signals, and the
  /// 2600 Hz supervisory tone. Digit pairs use the ITU-T / Wikipedia canonical
  /// assignment by frequency membership (the brief's flagged correct table),
  /// NOT the ToneGenerator repo's differing ordering.
  static final List<SignalingTone> blueBox = <SignalingTone>[
    _mf('1', 700, 900),
    _mf('2', 700, 1100),
    _mf('3', 900, 1100),
    _mf('4', 700, 1300),
    _mf('5', 900, 1300),
    _mf('6', 1100, 1300),
    _mf('7', 700, 1500),
    _mf('8', 900, 1500),
    _mf('9', 1100, 1500),
    _mf('0', 1300, 1500),
    const SignalingTone(
      label: 'KP',
      family: SignalingFamily.blueBox,
      lowHz: 1100,
      highHz: 1700,
      burstMs: 100,
      description: 'Key Pulse: marked the start of the routing digits.',
    ),
    const SignalingTone(
      label: 'ST',
      family: SignalingFamily.blueBox,
      lowHz: 1500,
      highHz: 1700,
      burstMs: 100,
      description: 'Start: marked the end of the routing digits.',
    ),
    const SignalingTone(
      label: '2600',
      family: SignalingFamily.blueBox,
      lowHz: 2600,
      burstMs: 600,
      description:
          'Supervisory tone: signaled an idle trunk, the sound a long-'
          'distance switch once read as "this line is free."',
    ),
  ];

  /// US Red Box — the ACTS coin-deposit acknowledgement bursts. All three are
  /// the 1700 + 2200 Hz dual tone; only the burst count and timing differ.
  static const List<SignalingTone> redBox = <SignalingTone>[
    SignalingTone(
      label: 'Nickel',
      family: SignalingFamily.redBox,
      lowHz: 1700,
      highHz: 2200,
      burstMs: 66,
      bursts: 1,
      gapMs: 0,
      description: '5 cents: one 66 ms burst.',
    ),
    SignalingTone(
      label: 'Dime',
      family: SignalingFamily.redBox,
      lowHz: 1700,
      highHz: 2200,
      burstMs: 66,
      bursts: 2,
      gapMs: 66,
      description: '10 cents: two 66 ms bursts, 66 ms apart.',
    ),
    SignalingTone(
      label: 'Quarter',
      family: SignalingFamily.redBox,
      lowHz: 1700,
      highHz: 2200,
      burstMs: 33,
      bursts: 5,
      gapMs: 33,
      description: '25 cents: five 33 ms bursts, 33 ms apart.',
    ),
  ];

  /// Build a two-frequency MF signal with the standard 100 ms burst.
  static SignalingTone _mf(String label, double a, double b) => SignalingTone(
        label: label,
        family: SignalingFamily.blueBox,
        lowHz: a,
        highHz: b,
        burstMs: SignalingTones.mfBurstMs,
        description: 'MF routing digit $label ($a + $b Hz).',
      );

  /// Synthesize the raw 16-bit signed little-endian mono PCM for [tone]: each
  /// burst is [tone.burstMs] of the (one- or two-) sine sum with a 5 ms
  /// click-suppression ramp on each end (identical math to [Dtmf.synthesize]),
  /// separated by [tone.gapMs] of silence, repeated [tone.bursts] times.
  static Int16List synthesize(
    SignalingTone tone, {
    int sampleRate = SignalingTones.sampleRate,
  }) {
    final int burstSamples = (sampleRate * tone.burstMs / 1000).round();
    final int gapSamples = (sampleRate * tone.gapMs / 1000).round();
    final int total = tone.bursts * burstSamples +
        (tone.bursts - 1).clamp(0, tone.bursts) * gapSamples;

    final Int16List out = Int16List(total);

    final double twoPiLow = 2 * math.pi * tone.lowHz / sampleRate;
    final double? high = tone.highHz;
    final double twoPiHigh =
        high == null ? 0 : 2 * math.pi * high / sampleRate;
    // Single tone uses full 0.95 amplitude; a two-tone sum uses 0.5 + 0.5 so
    // the sum never clips — same headroom rule as the DTMF synth.
    final double amp = tone.isSingleFrequency ? 0.95 : 0.5;

    final int rampSamples = math.min(
      (sampleRate * 5 / 1000).round(),
      burstSamples ~/ 2,
    );

    int cursor = 0;
    for (int b = 0; b < tone.bursts; b++) {
      for (int i = 0; i < burstSamples; i++) {
        double sample = amp * math.sin(twoPiLow * i);
        if (high != null) sample += amp * math.sin(twoPiHigh * i);

        double gain = 1.0;
        if (rampSamples > 0) {
          if (i < rampSamples) {
            gain = i / rampSamples;
          } else if (i >= burstSamples - rampSamples) {
            gain = (burstSamples - 1 - i) / rampSamples;
          }
        }

        final int value =
            (sample * gain * (tone.isSingleFrequency ? 1.0 : 0.95) * 32767)
                .round();
        out[cursor++] = value.clamp(-32768, 32767);
      }
      // Inter-burst silence (already zero-filled), advance the cursor.
      if (b < tone.bursts - 1) cursor += gapSamples;
    }
    return out;
  }

  /// Convenience: the playable WAV bytes for [tone], reusing the DTMF WAV
  /// wrapper so the audio engine decodes it with no codec.
  static Uint8List wavForTone(
    SignalingTone tone, {
    int sampleRate = SignalingTones.sampleRate,
  }) {
    final Int16List pcm = synthesize(tone, sampleRate: sampleRate);
    return Dtmf.wavFromPcm(pcm, sampleRate: sampleRate);
  }
}
