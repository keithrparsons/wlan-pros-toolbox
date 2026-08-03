// TransferMath unit tests — the three solves, and the duration formatting.
//
// EXPECTED VALUES, WORKED BEFORE THE ASSERTIONS. The factor of 8 is written
// out on every line on purpose, because it is the thing this tool exists to
// stop people getting wrong.
//
//   1 GB  at 100 Mbps  1e9 bytes × 8 = 8e9 bits ÷ 1e8 = 80 s      → 1 min 20 s
//   1 GiB at 100 Mbps  1,073,741,824 × 8 = 8,589,934,592 bits
//                      ÷ 1e8 = 85.89934592 s                      → 1 min 25.9 s
//                      (the GB/GiB gap is 6 seconds on a 100 Mbps link, which
//                       is exactly why the two units stay separate)
//   700 MB at 8 Mbps   700e6 × 8 = 5.6e9 bits ÷ 8e6 = 700 s       → 11 min 40 s
//   1 GB in 60 s       8e9 ÷ 60 = 133,333,333.33 bits per second
//   100 Mbps for 60 s  1e8 × 60 = 6e9 bits = 750,000,000 bytes
//
// DURATION FORMATTING:
//   0 → 0 s          0.0005 → 0.5 ms      0.25 → 250 ms
//   1 → 1 s          42.5 → 42.5 s        59.96 → 1 min 0 s  (rounds UP a
//                                          branch rather than saying "60.0 s")
//   0.999 → 1 s      (same rule at the ms/s boundary, NOT "999 ms")
//   60 → 1 min 0 s   80 → 1 min 20 s      700 → 11 min 40 s
//   3600 → 1 h 0 min 0 s                  3725 → 1 h 2 min 5 s
//   86400 → 1 d 0 h 0 min                 273906 → 3 d 4 h 5 min
//
// EDGES: a zero rate, a zero window, a negative input, a non-finite input, and
// a transfer long enough that the day count needs thousands separators. Each
// returns null or an honest string rather than an infinity, a NaN, or a
// silently wrong number.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/transfer_math.dart';

const double _bitsPerByte = 8;
const double _gb = 1e9 * _bitsPerByte;
const double _gib = 1073741824 * _bitsPerByte;

void main() {
  group('solve for time', () {
    test('1 GB at 100 Mbps is 80 seconds', () {
      final double? s = TransferMath.seconds(bits: _gb, bitsPerSecond: 100e6);
      expect(s, 80.0);
      expect(TransferMath.formatDuration(s!), '1 min 20 s');
    });

    test('1 GiB is measurably slower than 1 GB on the same link', () {
      final double? gb = TransferMath.seconds(bits: _gb, bitsPerSecond: 100e6);
      final double? gib = TransferMath.seconds(
        bits: _gib,
        bitsPerSecond: 100e6,
      );
      expect(gib, closeTo(85.89934592, 1e-9));
      expect(TransferMath.formatDuration(gib!), '1 min 25.9 s');
      expect(gib - gb!, closeTo(5.89934592, 1e-9));
    });

    test('700 MB over an 8 Mbps link', () {
      final double? s = TransferMath.seconds(
        bits: 700e6 * _bitsPerByte,
        bitsPerSecond: 8e6,
      );
      expect(s, 700.0);
      expect(TransferMath.formatDuration(s!), '11 min 40 s');
    });

    test('a zero or negative rate has no answer, and says so with null', () {
      expect(TransferMath.seconds(bits: _gb, bitsPerSecond: 0), isNull);
      expect(TransferMath.seconds(bits: _gb, bitsPerSecond: -1), isNull);
      expect(
        TransferMath.seconds(bits: _gb, bitsPerSecond: double.nan),
        isNull,
      );
      expect(
        TransferMath.seconds(bits: double.infinity, bitsPerSecond: 1e6),
        isNull,
      );
      expect(TransferMath.seconds(bits: -1, bitsPerSecond: 1e6), isNull);
    });

    test('a zero-size transfer takes no time, which is a real answer', () {
      expect(TransferMath.seconds(bits: 0, bitsPerSecond: 1e6), 0.0);
      expect(TransferMath.formatDuration(0), '0 s');
    });
  });

  group('solve for rate', () {
    test('1 GB in 60 seconds needs 133.33 Mbps', () {
      final double? r = TransferMath.bitsPerSecond(bits: _gb, seconds: 60);
      expect(r, closeTo(133333333.333, 1e-3));
      expect(TransferMath.formatRate(r!), '133,333,333.33 bits per second');
    });

    test('a zero window has no answer', () {
      expect(TransferMath.bitsPerSecond(bits: _gb, seconds: 0), isNull);
      expect(TransferMath.bitsPerSecond(bits: _gb, seconds: -5), isNull);
    });
  });

  group('solve for size', () {
    test('100 Mbps for 60 seconds moves 6e9 bits, which is 750 MB', () {
      final double? b = TransferMath.bits(bitsPerSecond: 100e6, seconds: 60);
      expect(b, 6e9);
      expect(b! / _bitsPerByte, 750e6);
      expect(TransferMath.formatBits(b), '6,000,000,000 bits');
    });

    test('a zero window moves nothing, which is a real answer', () {
      expect(TransferMath.bits(bitsPerSecond: 100e6, seconds: 0), 0.0);
    });

    test('a negative rate has no answer', () {
      expect(TransferMath.bits(bitsPerSecond: -1, seconds: 60), isNull);
    });
  });

  group('formatDuration', () {
    test('sub-second reads in milliseconds', () {
      expect(TransferMath.formatDuration(0.0005), '0.5 ms');
      expect(TransferMath.formatDuration(0.25), '250 ms');
      expect(TransferMath.formatDuration(0.94), '940 ms');
      // 0.999 rounds to 1.0 at one decimal, so it crosses into the seconds
      // branch by the SAME rule that turns 59.96 into "1 min 0 s". My first
      // hand-computed value said "999 ms", which contradicted the rule stated
      // in this file's own header; the test caught it.
      expect(TransferMath.formatDuration(0.999), '1 s');
    });

    test('seconds, minutes, hours, days', () {
      expect(TransferMath.formatDuration(1), '1 s');
      expect(TransferMath.formatDuration(42.5), '42.5 s');
      expect(TransferMath.formatDuration(60), '1 min 0 s');
      expect(TransferMath.formatDuration(80), '1 min 20 s');
      expect(TransferMath.formatDuration(700), '11 min 40 s');
      expect(TransferMath.formatDuration(3600), '1 h 0 min 0 s');
      expect(TransferMath.formatDuration(3725), '1 h 2 min 5 s');
      expect(TransferMath.formatDuration(86400), '1 d 0 h 0 min');
      expect(TransferMath.formatDuration(273906), '3 d 4 h 5 min');
    });

    test('a value that rounds to 60 seconds crosses the branch instead of '
        'printing "60.0 s"', () {
      expect(TransferMath.formatDuration(59.96), '1 min 0 s');
      expect(TransferMath.formatDuration(59.9), '59.9 s');
    });

    test('an absurdly long transfer still reads, with grouped days', () {
      // 1 TB over a 1 kbps link.
      final double? s = TransferMath.seconds(
        bits: 1e12 * _bitsPerByte,
        bitsPerSecond: 1e3,
      );
      expect(s, 8e9);
      expect(TransferMath.formatDuration(s!), startsWith('92,592 d'));
    });

    test('a non-finite or negative duration is honestly unavailable', () {
      expect(TransferMath.formatDuration(double.nan), 'Unavailable');
      expect(TransferMath.formatDuration(double.infinity), 'Unavailable');
      expect(TransferMath.formatDuration(-1), 'Unavailable');
    });
  });

  group('number formatting', () {
    test('whole values group, fractional values keep two decimals', () {
      expect(TransferMath.formatBits(8e9), '8,000,000,000 bits');
      expect(TransferMath.formatBits(1234.5), '1,234.50 bits');
      expect(TransferMath.formatRate(1e8), '100,000,000 bits per second');
    });

    test('extreme magnitudes fall back to exponential rather than a wall of '
        'digits', () {
      expect(TransferMath.formatBits(1e18), contains('e+'));
      expect(TransferMath.formatBits(1e-6), contains('e-'));
    });
  });
}
