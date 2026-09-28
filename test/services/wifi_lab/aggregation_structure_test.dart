// The frame-structure view's teaching claims (Airtime Anatomy, 1.11.0):
//   - corrupting one A-MPDU subframe resends exactly that subframe's bytes;
//   - corrupting one A-MSDU subframe resends the whole A-MSDU;
//   - byte totals include delimiters, headers, padding and FCS;
//   - the A-MPDU arrangement is the same aggregate the time view draws.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/aggregation_structure.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';

void main() {
  // HE 32 aggregated: 1,500-byte MSDUs, CCMP (16), 6 GHz HE.
  final AirtimeScenario he32 = AirtimePreset.he32.scenario;

  group('A-MPDU: one bad subframe', () {
    test('resends exactly that subframe, and the bitmap marks only it', () {
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.ampdu,
      );
      expect(a.unitCount, 32);
      // MPDU = 26 + 16 + 1500 + 4 = 1546; subframe = 4 + 1546 + 2 pad = 1552.
      expect(a.units[5].mpduBytes, 1546);
      expect(a.units[5].bytes, 1552);

      final CorruptionOutcome o = a.corrupt(5);
      expect(o.failedUnit, 5);
      expect(o.resentBytes, a.units[5].bytes);
      expect(o.resentBytes, 1552);
      expect(o.resentMsdus, 1);
      expect(o.usesBlockAck, isTrue);
      expect(o.blockAckBitmap, hasLength(32));
      expect(o.blockAckBitmap!.where((bool b) => !b), hasLength(1));
      expect(o.blockAckBitmap![5], isFalse);
      expect(o.resentBytes, lessThan(a.psduBytes));
    });

    test('holds for every subframe position and every PHY that aggregates', () {
      for (final AirtimePhy phy in <AirtimePhy>[
        AirtimePhy.ht,
        AirtimePhy.vht,
        AirtimePhy.he,
      ]) {
        for (final int n in <int>[2, 7, 64]) {
          final AggregateStructure a = buildAggregateStructure(
            he32.copyWith(phy: phy, framesAggregated: n, payloadBytes: 333),
            AggregationKind.ampdu,
          );
          for (int i = 0; i < n; i++) {
            final CorruptionOutcome o = a.corrupt(i);
            expect(o.failedUnit, i);
            expect(o.resentBytes, a.units[i].bytes);
            expect(o.blockAckBitmap![i], isFalse);
          }
        }
      }
    });
  });

  group('A-MSDU: one bad subframe', () {
    test('resends the whole A-MSDU, with no ACK to say which one', () {
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.amsdu,
        msdusPerAmsdu: 3,
      );
      expect(a.unitCount, 1);
      expect(a.msduCount, 3);
      for (int m = 0; m < 3; m++) {
        final CorruptionOutcome o = a.corrupt(m);
        expect(o.failedUnit, 0);
        expect(o.resentBytes, a.psduBytes);
        expect(o.resentMsdus, 3);
        expect(o.usesBlockAck, isFalse);
        expect(o.blockAckBitmap, isNull);
      }
    });

    test('an A-MPDU of A-MSDUs resends the one A-MSDU that holds it', () {
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.ampduOfAmsdus,
        msdusPerAmsdu: 3,
      );
      expect(a.unitCount, 32);
      expect(a.msduCount, 96);
      // MSDU 7 (0-based) sits in A-MPDU subframe 2, with MSDUs 6 and 8.
      final CorruptionOutcome o = a.corrupt(7);
      expect(o.failedUnit, 2);
      expect(o.resentMsdus, 3);
      expect(o.resentBytes, a.units[2].bytes);
      expect(o.blockAckBitmap![2], isFalse);
      expect(o.blockAckBitmap!.where((bool b) => !b), hasLength(1));
    });
  });

  group('byte totals', () {
    test('an A-MPDU counts delimiters, headers, padding and FCS', () {
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.ampdu,
      );
      final StructureTotals t = a.totals;
      expect(t[StructurePartKind.delimiter], 32 * 4);
      expect(t[StructurePartKind.macHeader], 32 * 26);
      expect(t[StructurePartKind.security], 32 * 16);
      expect(t[StructurePartKind.msdu], 32 * 1500);
      expect(t[StructurePartKind.fcs], 32 * 4);
      expect(t[StructurePartKind.ampduPadding], 32 * 2);
      expect(t.total, 49664);
      expect(t.total, a.psduBytes);
      expect(t.overhead, 49664 - 48000);
    });

    test('an A-MSDU: one header, 14-byte subframe headers, pad all but the '
        'last, one FCS', () {
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.amsdu,
        msdusPerAmsdu: 3,
      );
      final StructureTotals t = a.totals;
      expect(t[StructurePartKind.macHeader], 26);
      expect(t[StructurePartKind.fcs], 4);
      expect(t[StructurePartKind.security], 16);
      expect(t[StructurePartKind.subframeHeader], 3 * 14);
      // 14 + 1500 = 1514 pads 2 to 1516, twice; the last is not padded.
      expect(t[StructurePartKind.amsduPadding], 2 * 2);
      expect(a.units.single.mpduBytes, 26 + 16 + 1516 + 1516 + 1514 + 4);
      // HE sends even one MPDU as an A-MPDU: 4-byte delimiter, pad to 4.
      expect(t[StructurePartKind.delimiter], 4);
      expect(a.psduBytes, 4 + 4592);
      expect(a.psduBytes % 4, 0);
      expect(t.total, a.psduBytes);
    });

    test('padding always lands a unit on a 4-byte boundary', () {
      for (final int payload in <int>[64, 65, 66, 67, 1500, 2304]) {
        for (final AggregationKind k in AggregationKind.values) {
          final AggregateStructure a = buildAggregateStructure(
            he32.copyWith(payloadBytes: payload, framesAggregated: 4),
            k,
          );
          for (final StructureUnit u in a.units) {
            expect(u.bytes % 4, 0, reason: '$k, $payload bytes');
          }
          expect(a.totals.total, a.psduBytes);
        }
      }
    });

    test('HT with one MPDU sends it bare: no delimiter, no padding', () {
      final AggregateStructure a = buildAggregateStructure(
        he32.copyWith(
          band: AirtimeBand.ghz5,
          phy: AirtimePhy.ht,
          framesAggregated: 1,
          payloadBytes: 1001,
        ),
        AggregationKind.singleMpdu,
      );
      expect(a.inAmpdu, isFalse);
      expect(a.totals[StructurePartKind.delimiter], 0);
      expect(a.psduBytes, 26 + 16 + 1001 + 4);
    });

    test('Legacy offers only a single MPDU', () {
      final AirtimeScenario legacy = AirtimePreset.legacy6.scenario;
      expect(
        aggregationSupported(AirtimePhy.legacy, AggregationKind.amsdu),
        isFalse,
      );
      expect(
        () => buildAggregateStructure(legacy, AggregationKind.ampdu),
        throwsArgumentError,
      );
      final AggregateStructure a = buildAggregateStructure(
        legacy,
        AggregationKind.singleMpdu,
      );
      expect(a.psduBytes, computeAirtime(legacy).psduBytes);
      expect(a.corrupt(0).usesBlockAck, isFalse);
    });
  });

  group('the structure and time views describe the same aggregate', () {
    test('the A-MPDU arrangement has the time view\'s PSDU and PPDU', () {
      for (final AirtimePreset p in AirtimePreset.values) {
        final AirtimeScenario s = p.scenario;
        final AirtimeResult r = computeAirtime(s);
        final AggregationKind k = s.phy == AirtimePhy.legacy
            ? AggregationKind.singleMpdu
            : AggregationKind.ampdu;
        final AggregateStructure a = buildAggregateStructure(s, k);
        expect(a.psduBytes, r.psduBytes, reason: p.label);
        expect(
          ppduTenthsForPsdu(r, a.psduBytes),
          r.ppduTenths,
          reason: p.label,
        );
        expect(a.usesBlockAck, r.usesBlockAck, reason: p.label);
      }
    });

    test('across PHYs, frame counts, payloads and encryption', () {
      for (final AirtimePhy phy in <AirtimePhy>[
        AirtimePhy.ht,
        AirtimePhy.vht,
        AirtimePhy.he,
      ]) {
        for (final int n in <int>[1, 2, 16, 64]) {
          for (final int payload in <int>[64, 1500, 2304]) {
            for (final int enc in <int>[0, 16]) {
              final AirtimeScenario s = AirtimeScenario(
                band: AirtimeBand.ghz5,
                phy: phy,
                widthMhz: 40,
                mcs: 7,
                payloadBytes: payload,
                framesAggregated: n,
                encryptionBytes: enc,
                guardInterval: phy == AirtimePhy.he
                    ? GuardInterval.gi08
                    : GuardInterval.gi04,
              );
              final AirtimeResult r = computeAirtime(s);
              final AggregateStructure a = buildAggregateStructure(
                s,
                AggregationKind.ampdu,
              );
              final String why = '${phy.shortLabel} n=$n $payload B enc=$enc';
              expect(a.psduBytes, r.psduBytes, reason: why);
              expect(
                ppduTenthsForPsdu(r, r.psduBytes),
                r.ppduTenths,
                reason: why,
              );
            }
          }
        }
      }
    });

    test('a resend is timed with the same PHY arithmetic', () {
      final AirtimeResult r = computeAirtime(he32);
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.ampdu,
      );
      final int retry = ppduTenthsForPsdu(r, a.corrupt(0).resentBytes);
      // One 1,552-byte subframe at 16,333 bits per symbol is one symbol:
      // preamble 50.4 + 13.6 = 64 us.
      expect(retry, 640);
      expect(retry, lessThan(r.ppduTenths));
    });
  });
}
