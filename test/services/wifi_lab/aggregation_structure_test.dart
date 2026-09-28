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

  group('limits Pax pinned (RESEARCH-BRIEF Part 3)', () {
    void trips(AggregationLimitCheck Function(int) f, int cap) {
      expect(f(cap).verdict, isNot(LimitVerdict.exceeds), reason: '$cap');
      expect(f(cap + 1).verdict, LimitVerdict.exceeds, reason: '${cap + 1}');
    }

    test('HT A-MSDU: 3,839, then 7,935', () {
      trips(checkHtAmsdu, 7935);
      expect(checkHtAmsdu(3839).verdict, LimitVerdict.ok);
      expect(checkHtAmsdu(3840).verdict, LimitVerdict.needsLargerSetting);
      expect(checkHtAmsdu(3840).smallestFitting, 7935);
    });

    test('VHT MPDU: 3,895, 7,991, 11,454', () {
      trips(checkVhtMpdu, 11454);
      expect(checkVhtMpdu(3895).verdict, LimitVerdict.ok);
      expect(checkVhtMpdu(3896).smallestFitting, 7991);
      expect(checkVhtMpdu(7992).smallestFitting, 11454);
      expect(checkVhtMpdu(11455).smallestFitting, isNull);
    });

    test('an MPDU in an HT A-MPDU: 4,095 (12-bit length field)', () {
      trips(checkHtMpduInAmpdu, 4095);
      expect(
        (1 << AggregationLimits.htDelimiterLengthBits) - 1,
        AggregationLimits.htMpduInAmpdu,
      );
    });

    test('A-MPDU: HT 65,535, VHT 1,048,575, HE 6,500,631', () {
      trips((int b) => checkAmpdu(AirtimePhy.ht, b)!, 65535);
      trips((int b) => checkAmpdu(AirtimePhy.vht, b)!, 1048575);
      trips((int b) => checkAmpdu(AirtimePhy.he, b)!, 6500631);
      expect(checkAmpdu(AirtimePhy.legacy, 1 << 30), isNull);
    });

    test('PPDU duration: 5.484 ms for HT, VHT and HE', () {
      for (final AirtimePhy phy in <AirtimePhy>[
        AirtimePhy.ht,
        AirtimePhy.vht,
        AirtimePhy.he,
      ]) {
        trips((int t) => checkPpduTime(phy, t)!, 54840);
      }
      expect(checkPpduTime(AirtimePhy.legacy, 1 << 30), isNull);
    });

    test('an A-MSDU inside an HT A-MPDU caps at 4,065', () {
      expect(AggregationLimits.htAmsduInAmpdu(0), 4065);
      // Three 1,339-byte MSDUs: 1,356 + 1,356 + 1,353 = 4,065 exactly.
      AirtimeScenario ht(int payload) => AirtimeScenario(
        phy: AirtimePhy.ht,
        widthMhz: 40,
        mcs: 7,
        payloadBytes: payload,
        framesAggregated: 2,
        encryptionBytes: 0,
      );
      AggregationLimitCheck mpduCheck(int payload) {
        final AggregateStructure a = buildAggregateStructure(
          ht(payload),
          AggregationKind.ampduOfAmsdus,
          msdusPerAmsdu: 3,
        );
        expect(a.inAmpdu, isTrue);
        return checkAggregationLimits(a).firstWhere(
          (AggregationLimitCheck c) =>
              c.kind == AggregationLimitKind.htMpduInAmpdu,
        );
      }

      final AggregateStructure at = buildAggregateStructure(
        ht(1339),
        AggregationKind.ampduOfAmsdus,
        msdusPerAmsdu: 3,
      );
      expect(at.units.first.amsduBytes, 4065);
      expect(at.units.first.mpduBytes, 4095);
      expect(mpduCheck(1339).verdict, isNot(LimitVerdict.exceeds));
      // One byte more per MSDU: the A-MSDU is 4,066, the MPDU 4,096.
      expect(mpduCheck(1340).value, 4096);
      expect(mpduCheck(1340).verdict, LimitVerdict.exceeds);
      // The same A-MSDU sent on its own is inside HT's 7,935 cap.
      final AggregateStructure alone = buildAggregateStructure(
        ht(1340).copyWith(framesAggregated: 1),
        AggregationKind.amsdu,
        msdusPerAmsdu: 3,
      );
      expect(alone.inAmpdu, isFalse);
      final List<AggregationLimitCheck> c = checkAggregationLimits(alone);
      expect(c.single.kind, AggregationLimitKind.htAmsdu);
      expect(c.single.verdict, LimitVerdict.needsLargerSetting);
    });

    test('the default HT 64-frame A-MPDU is over 65,535 and says so', () {
      final AggregateStructure a = buildAggregateStructure(
        AirtimeScenario(
          phy: AirtimePhy.ht,
          widthMhz: 40,
          mcs: 7,
          framesAggregated: 64,
        ),
        AggregationKind.ampdu,
      );
      final AggregationLimitCheck amp = checkAggregationLimits(a).firstWhere(
        (AggregationLimitCheck c) => c.kind == AggregationLimitKind.ampdu,
      );
      expect(amp.value, 64 * 1552);
      expect(amp.verdict, LimitVerdict.exceeds);
    });

    test('HE 32 aggregated is inside every checked limit', () {
      final AirtimeResult r = computeAirtime(he32);
      final AggregateStructure a = buildAggregateStructure(
        he32,
        AggregationKind.ampdu,
      );
      final List<AggregationLimitCheck> c = checkAggregationLimits(
        a,
        ppduTenths: r.ppduTenths,
      );
      expect(c.map((AggregationLimitCheck x) => x.kind), <AggregationLimitKind>[
        AggregationLimitKind.ampdu,
        AggregationLimitKind.ppduTime,
      ]);
      expect(
        c.every((AggregationLimitCheck x) => x.verdict == LimitVerdict.ok),
        isTrue,
      );
    });
  });
}
