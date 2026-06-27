// Channel <-> Frequency engine tests.
//
// The verification vectors are paste-from-spec: every (band, channel,
// expected_center_MHz) row, every reverse-lookup disambiguation, and every
// reject from channel-plan.md sec 7. Accuracy is paramount on this tool (it
// carries Keith Parsons's name), so the spec's own vectors are the gate.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';

void main() {
  // Map the spec's "2.4 / 5 / 6" band column onto the enum.
  WifiBand band(num g) {
    if (g == 2.4) return WifiBand.band24;
    if (g == 5) return WifiBand.band5;
    return WifiBand.band6;
  }

  group('channelToFrequency — sec 7 forward vectors', () {
    // (band, channel, expected_center_MHz) — verbatim from channel-plan.md sec 7.
    const List<(num, int, int)> vectors = <(num, int, int)>[
      // 2.4 GHz
      (2.4, 1, 2412),
      (2.4, 6, 2437),
      (2.4, 11, 2462),
      (2.4, 13, 2472),
      (2.4, 14, 2484), // SPECIAL
      // 5 GHz — band edges + UNII boundaries
      (5, 36, 5180),
      (5, 48, 5240),
      (5, 52, 5260),
      (5, 64, 5320),
      (5, 100, 5500),
      (5, 144, 5720),
      (5, 149, 5745),
      (5, 165, 5825),
      (5, 169, 5845),
      (5, 177, 5885),
      // 6 GHz — special, edges, PSC samples
      (6, 2, 5935), // SPECIAL
      (6, 1, 5955),
      (6, 5, 5975),
      (6, 93, 6415),
      (6, 97, 6435),
      (6, 117, 6535),
      (6, 185, 6875),
      (6, 189, 6895),
      // SPEC TYPO: channel-plan.md sec 4.2 / sec 7 list ch 229 = 7075, but that
      // is channel 225. The formula 5950 + 5x229 = 7095, and the adjacent ch 233
      // = 7115 vector confirms it (229 and 233 are 20 MHz apart: 7115 - 20 =
      // 7095). 7095 is the correct, well-known PSC 229 center. Flagged to Pax.
      (6, 229, 7095),
      (6, 233, 7115),
      // Bonded centers — 5 GHz
      (5, 42, 5210),
      (5, 50, 5250),
      (5, 155, 5775),
      // Bonded centers — 6 GHz
      (6, 7, 5985),
      (6, 15, 6025),
      (6, 31, 6105),
      (6, 63, 6265),
    ];

    for (final (num g, int ch, int expected) in vectors) {
      test('${band(g).label} ch $ch -> $expected MHz', () {
        expect(channelToFrequency(band(g), ch), expected);
      });
    }
  });

  group('frequencyToChannel — sec 7 reverse disambiguation', () {
    void expectRev(double mhz, WifiBand b, int ch) {
      final ({WifiBand band, int channel})? r = frequencyToChannel(mhz);
      expect(r, isNotNull, reason: '$mhz should resolve');
      expect(r!.band, b);
      expect(r.channel, ch);
    }

    test('5180 -> (5 GHz, 36)', () => expectRev(5180, WifiBand.band5, 36));
    test('5935 -> (6 GHz, 2) SPECIAL', () => expectRev(5935, WifiBand.band6, 2));
    test('5955 -> (6 GHz, 1)', () => expectRev(5955, WifiBand.band6, 1));
    test('2484 -> (2.4 GHz, 14) SPECIAL',
        () => expectRev(2484, WifiBand.band24, 14));
    test('2412 -> (2.4 GHz, 1)', () => expectRev(2412, WifiBand.band24, 1));

    test('+/-1 MHz snap tolerance (sec 6.5)', () {
      // 5183 -> ch 36 (5180), 5300.4 -> ch 60 (5300) — within tolerance.
      expect(frequencyToChannel(5181)?.channel, 36);
      expect(frequencyToChannel(5300.4)?.channel, 60);
    });
  });

  group('rejects — sec 7 invalid channels for the band', () {
    test('(2.4, 15) -> not a valid primary', () {
      expect(isValid20MhzPrimary(WifiBand.band24, 15), isFalse);
    });
    test('(5, 37) -> bonded-center-not-primary, not a valid primary', () {
      expect(isValid20MhzPrimary(WifiBand.band5, 37), isFalse);
    });
    test('(5, 181) -> spectrum exists but not Wi-Fi usable', () {
      expect(isValid20MhzPrimary(WifiBand.band5, 181), isFalse);
    });
    test('(6, 3) -> bonded center, not a valid primary', () {
      expect(isValid20MhzPrimary(WifiBand.band6, 3), isFalse);
    });
    test('5 GHz rejects 49, 51, 145 (sec 6.6)', () {
      expect(isValid20MhzPrimary(WifiBand.band5, 49), isFalse);
      expect(isValid20MhzPrimary(WifiBand.band5, 51), isFalse);
      expect(isValid20MhzPrimary(WifiBand.band5, 145), isFalse);
    });
  });

  group('frequencyToChannel — off-grid rejects', () {
    test('freq 5187 -> reject (snaps to nothing valid)', () {
      expect(frequencyToChannel(5187), isNull);
    });
    test('out-of-plan low/high reject', () {
      expect(frequencyToChannel(100), isNull);
      expect(frequencyToChannel(8000), isNull);
    });
  });

  group('bondedChannel — verified bonding tables (sec 5.2 / 5.3)', () {
    test('5 GHz 80 MHz on primary 36 -> {36,40,44,48} c42 5210 5170/5250', () {
      final BondedChannel? b = bondedChannel(
        band: WifiBand.band5,
        primaryChannel: 36,
        widthMHz: 80,
      );
      expect(b, isNotNull);
      expect(b!.components, <int>[36, 40, 44, 48]);
      expect(b.centerChannel, 42);
      expect(b.centerFreqMHz, 5210);
      expect(b.lowEdgeMHz, 5170);
      expect(b.highEdgeMHz, 5250);
    });

    test('5 GHz 160 MHz on primary 64 -> c50 5250 5170/5330', () {
      final BondedChannel? b = bondedChannel(
        band: WifiBand.band5,
        primaryChannel: 64,
        widthMHz: 160,
      );
      expect(b, isNotNull);
      expect(b!.centerChannel, 50);
      expect(b.centerFreqMHz, 5250);
      expect(b.lowEdgeMHz, 5170);
      expect(b.highEdgeMHz, 5330);
    });

    test('6 GHz 80 MHz on primary 1 -> {1,5,9,13} c7 5985 5945/6025', () {
      final BondedChannel? b = bondedChannel(
        band: WifiBand.band6,
        primaryChannel: 1,
        widthMHz: 80,
      );
      expect(b, isNotNull);
      expect(b!.components, <int>[1, 5, 9, 13]);
      expect(b.centerChannel, 7);
      expect(b.centerFreqMHz, 5985);
      expect(b.lowEdgeMHz, 5945);
      expect(b.highEdgeMHz, 6025);
    });

    test('6 GHz 160 MHz on primary 1 -> c15 6025 5945/6105', () {
      final BondedChannel? b = bondedChannel(
        band: WifiBand.band6,
        primaryChannel: 1,
        widthMHz: 160,
      );
      expect(b, isNotNull);
      expect(b!.centerChannel, 15);
      expect(b.centerFreqMHz, 6025);
      expect(b.lowEdgeMHz, 5945);
      expect(b.highEdgeMHz, 6105);
    });

    test('2.4 GHz 40 MHz HT40+ on primary 1 -> {1,5} 2422 2402/2442', () {
      final BondedChannel? b = bondedChannel(
        band: WifiBand.band24,
        primaryChannel: 1,
        widthMHz: 40,
      );
      expect(b, isNotNull);
      expect(b!.components, <int>[1, 5]);
      expect(b.centerFreqMHz, 2422);
      expect(b.lowEdgeMHz, 2402);
      expect(b.highEdgeMHz, 2442);
    });

    test('6 GHz 320 MHz on primary 33 returns TWO overlapping placements', () {
      final List<BondedChannel> all = bondedChannels(
        band: WifiBand.band6,
        primaryChannel: 33,
        widthMHz: 320,
      );
      expect(all.length, 2);
      // Centers 31 (6105) and 63 (6265) both contain primary 33.
      expect(all.map((BondedChannel b) => b.centerChannel).toSet(),
          <int>{31, 63});
      expect(all.map((BondedChannel b) => b.centerFreqMHz).toSet(),
          <int>{6105, 6265});
    });

    test('bonded width returns empty for an invalid primary', () {
      expect(
        bondedChannels(band: WifiBand.band5, primaryChannel: 37, widthMHz: 80),
        isEmpty,
      );
    });

    test('320 MHz centers/edges match sec 5.3 (non-overlapping {31,95,159})',
        () {
      // Primary 1 sits only in the center-31 320 MHz channel.
      final List<BondedChannel> all = bondedChannels(
        band: WifiBand.band6,
        primaryChannel: 1,
        widthMHz: 320,
      );
      expect(all.length, 1);
      expect(all.single.centerChannel, 31);
      expect(all.single.centerFreqMHz, 6105);
      expect(all.single.lowEdgeMHz, 5945);
      expect(all.single.highEdgeMHz, 6265);
    });
  });

  group('classification metadata', () {
    test('PSC list is the 15 channels from sec 4.3', () {
      expect(k6Psc, <int>{
        5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229,
      });
    });
    test('UNII sub-band lookup (sec 3.1 / 4.1 boundaries)', () {
      expect(uniiSubBand(WifiBand.band5, 36), 'UNII-1');
      expect(uniiSubBand(WifiBand.band5, 52), 'UNII-2A');
      expect(uniiSubBand(WifiBand.band5, 100), 'UNII-2C');
      expect(uniiSubBand(WifiBand.band5, 149), 'UNII-3');
      expect(uniiSubBand(WifiBand.band5, 169), 'UNII-4');
      expect(uniiSubBand(WifiBand.band6, 93), 'UNII-5');
      expect(uniiSubBand(WifiBand.band6, 97), 'UNII-6');
      expect(uniiSubBand(WifiBand.band6, 117), 'UNII-7');
      expect(uniiSubBand(WifiBand.band6, 189), 'UNII-8');
    });
    test('DFS + UNII-4 flags', () {
      expect(channelFlags(WifiBand.band5, 52).contains('DFS'), isTrue);
      expect(channelFlags(WifiBand.band5, 36).contains('DFS'), isFalse);
      expect(channelFlags(WifiBand.band5, 169).contains('UNII-4'), isTrue);
    });
    test('6 GHz PSC + special-channel flags', () {
      expect(channelFlags(WifiBand.band6, 5).contains('PSC'), isTrue);
      expect(channelFlags(WifiBand.band6, 2).any((String f) => f.contains('Special')),
          isTrue);
    });
  });

  group('valid 20 MHz primary sets', () {
    test('6 GHz primaries = special 2 + (1,5,...,233)', () {
      expect(k6Channels.contains(2), isTrue);
      expect(k6Channels.contains(1), isTrue);
      expect(k6Channels.contains(233), isTrue);
      expect(k6Channels.contains(3), isFalse); // bonded center
      // 1,5,...,233 is 59 channels; + special 2 = 60.
      expect(k6Channels.length, 60);
    });
    test('5 GHz primaries count = 28 (sec 3.1 table)', () {
      expect(k5Channels.length, 28);
    });
  });
}
