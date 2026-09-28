// Airtime Anatomy service tests (Wi-Fi Classroom).
//
// The reference is the WLAN Pros Airtime Calculator workbook (myPKA
// Deliverables/2026-09-25-wlanpros-airtime-calculator), whose four default
// scenarios this port must reproduce to the decimal. Every expected value in
// the first group was read off that workbook's calculated cells, not derived
// from this code.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/aggregation_structure.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';

AirtimeResult _run(AirtimePreset p) => computeAirtime(p.scenario);

void main() {
  group('the four spreadsheet defaults, row by row', () {
    test('Legacy 6 Mbps', () {
      final AirtimeResult r = _run(AirtimePreset.legacy6);
      expect(r.sifsUs, 16);
      expect(r.slotUs, 9);
      expect(r.signalExtensionUs, 0);
      expect(r.aifsn, 3);
      expect(r.cwMin, 15);
      expect(r.mcsRow, isNull);
      expect(r.dataSubcarriers, 48);
      expect(r.bitsPerSymbol, 24);
      expect(r.symbolUs, 4);
      expect(r.phyRateMbps, 6);
      expect(r.ltfCount, 0);
      expect(r.mpduBytes, 1546);
      expect(r.subframeBytes, 1552);
      expect(r.framesSent, 1);
      expect(r.psduBytes, 1546);
      expect(r.dataSymbols, 517);
      expect(r.preambleUs, 20);
      expect(r.dataUs, 2068);
      expect(r.ppduUs, 2088);
      expect(r.ackUs, 28);
      expect(r.blockAckUs, 32);
      expect(r.rtsUs, 28);
      expect(r.ctsUs, 28);
      expect(r.segments.map((TxopSegment s) => s.us).toList(), <double>[
        43,
        67.5,
        0,
        20,
        2068,
        16,
        28,
      ]);
      expect(r.totalUs, 2242.5);
      expect(r.payloadBits, 12000);
      expect(r.throughputMbps, closeTo(5.35117056856187, 1e-12));
      expect(r.efficiency, closeTo(0.891861761426979, 1e-12));
      expect(r.dataShare, closeTo(0.922185061315496, 1e-12));
      expect(r.check, AirtimeCheck.ok);
      expect(r.check.message, 'OK');
    });

    test('VHT one frame', () {
      final AirtimeResult r = _run(AirtimePreset.vhtOne);
      expect(r.mcsRow!.bitsPerSubcarrier, 8);
      expect(r.mcsRow!.codingRate, closeTo(0.833333333333333, 1e-12));
      expect(r.dataSubcarriers, 234);
      expect(r.bitsPerSymbol, 3120);
      expect(r.symbolUs, 3.6);
      expect(r.phyRateMbps, closeTo(866.666666666667, 1e-9));
      expect(r.phyRateMbps.toStringAsFixed(2), '866.67');
      expect(r.ltfCount, 2);
      expect(r.psduBytes, 1552);
      expect(r.dataSymbols, 4);
      expect(r.preambleUs, 44);
      expect(r.dataUs, 16);
      expect(r.ppduUs, 60);
      expect(r.segments.map((TxopSegment s) => s.us).toList(), <double>[
        43,
        67.5,
        0,
        44,
        16,
        16,
        28,
      ]);
      // One frame gets a normal ACK, even as a VHT single-MPDU A-MPDU.
      expect(r.segment(TxopSegmentKind.ack).label, 'ACK');
      expect(r.usesBlockAck, isFalse);
      expect(r.totalUs, 214.5);
      expect(r.throughputMbps, closeTo(55.944055944056, 1e-11));
      expect(r.efficiency, closeTo(55.944055944056 / 866.666666666667, 1e-12));
      expect(r.dataShare, closeTo(0.0745920745920746, 1e-12));
      expect(r.check, AirtimeCheck.ok);
    });

    test('VHT 32 aggregated', () {
      final AirtimeResult r = _run(AirtimePreset.vht32);
      expect(r.bitsPerSymbol, 3120);
      expect(r.phyRateMbps.toStringAsFixed(2), '866.67');
      expect(r.framesSent, 32);
      expect(r.psduBytes, 49664);
      expect(r.dataSymbols, 128);
      expect(r.dataUs, 464);
      expect(r.ppduUs, 508);
      expect(r.totalUs, 666.5);
      expect(r.payloadBits, 384000);
      expect(r.throughputMbps, closeTo(576.144036009002, 1e-12));
      expect(r.efficiency, closeTo(0.664781580010387, 1e-12));
      expect(r.dataShare, closeTo(0.696174043510878, 1e-12));
      expect(r.check, AirtimeCheck.ok);
    });

    test('HE 32 aggregated', () {
      final AirtimeResult r = _run(AirtimePreset.he32);
      expect(r.mcsRow!.bitsPerSubcarrier, 10);
      expect(r.dataSubcarriers, 980);
      expect(r.bitsPerSymbol, 16333);
      expect(r.symbolUs, 13.6);
      expect(r.phyRateMbps, closeTo(1200.95588235294, 1e-9));
      expect(r.phyRateMbps.toStringAsFixed(2), '1200.96');
      expect(r.ltfCount, 2);
      expect(r.psduBytes, 49664);
      expect(r.dataSymbols, 25);
      expect(r.preambleUs, 50.4);
      expect(r.dataUs, 340);
      expect(r.ppduUs, 390.4);
      expect(r.segments.map((TxopSegment s) => s.us).toList(), <double>[
        43,
        67.5,
        0,
        50.4,
        340,
        16,
        32,
      ]);
      expect(r.totalUs, 548.9);
      expect(r.throughputMbps, closeTo(699.580980142102, 1e-12));
      expect(r.efficiency, closeTo(0.582520132855727, 1e-12));
      expect(r.dataShare, closeTo(0.61942065950082, 1e-12));
      expect(r.check, AirtimeCheck.ok);
    });

    test('segments are contiguous and sum to the total', () {
      for (final AirtimePreset p in AirtimePreset.values) {
        final AirtimeResult r = _run(p);
        int at = 0;
        for (final TxopSegment s in r.segments) {
          expect(s.startTenths, at, reason: '${p.label} ${s.label}');
          at += s.tenths;
        }
        expect(at, r.totalTenths);
      }
    });
  });

  group('band rules and the Check row', () {
    test('20 MHz VHT MCS 9, 1 stream is not a valid combination', () {
      final AirtimeResult r = computeAirtime(
        const AirtimeScenario(
          phy: AirtimePhy.vht,
          widthMhz: 20,
          mcs: 9,
          streams: 1,
        ),
      );
      expect(r.bitsPerSymbol, closeTo(346.6667, 1e-4));
      expect(r.check, AirtimeCheck.invalidCombination);
      expect(r.check.message, 'Not a valid MCS/width/stream combination');
    });

    test('6 GHz with VHT is flagged', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.vhtOne.scenario.copyWith(band: AirtimeBand.ghz6),
      );
      expect(r.check, AirtimeCheck.sixGhzRequiresHe);
      expect(r.check.message, '6 GHz requires HE');
    });

    test('2.4 GHz legacy ACK at 24 Mbps is 34 us (28 + 6 extension)', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(band: AirtimeBand.ghz24),
      );
      expect(r.sifsUs, 10);
      expect(r.signalExtensionUs, 6);
      expect(r.ackUs, 34);
      expect(r.segment(TxopSegmentKind.ack).us, 34);
      // AIFS uses the 10 us SIFS; the data portion carries the extension.
      expect(r.segment(TxopSegmentKind.aifs).us, 37);
      expect(r.dataUs, 2068 + 6);
      // Share excludes the signal extension.
      expect(r.dataShare, closeTo(2068 / r.totalUs, 1e-12));
      expect(r.check, AirtimeCheck.ok);
    });

    test('VHT at 2.4 GHz is flagged', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.vhtOne.scenario.copyWith(band: AirtimeBand.ghz24),
      );
      expect(r.check, AirtimeCheck.vhtIs5GhzOnly);
    });

    test('6 GHz is checked before 2.4 GHz rules, as in the sheet', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(
          band: AirtimeBand.ghz6,
          widthMhz: 40,
        ),
      );
      expect(r.check, AirtimeCheck.sixGhzRequiresHe);
    });

    test('Legacy wider than 20 MHz is flagged', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(widthMhz: 40),
      );
      expect(r.check, AirtimeCheck.legacyIs20MhzOnly);
    });

    test('HT limits: MCS 8, 5 streams, 80 MHz each flagged', () {
      const AirtimeScenario ht = AirtimeScenario(
        phy: AirtimePhy.ht,
        widthMhz: 40,
        mcs: 7,
        streams: 2,
        guardInterval: GuardInterval.gi08,
      );
      expect(computeAirtime(ht).check, AirtimeCheck.ok);
      expect(computeAirtime(ht.copyWith(mcs: 8)).check, AirtimeCheck.htLimits);
      expect(
        computeAirtime(ht.copyWith(streams: 5)).check,
        AirtimeCheck.htLimits,
      );
      expect(
        computeAirtime(ht.copyWith(widthMhz: 80)).check,
        AirtimeCheck.htLimits,
      );
      // HT above 4 streams has no LTF count in the table; it reads as 0.
      expect(computeAirtime(ht.copyWith(streams: 5)).ltfCount, 0);
    });

    test('VHT MCS 10 is flagged', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.vhtOne.scenario.copyWith(mcs: 10),
      );
      expect(r.check, AirtimeCheck.vhtMcsLimit);
    });

    test('a PPDU over 5.484 ms is flagged', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(payloadBytes: 2304),
      );
      // 2304 + 46 bytes at 6 Mbps: 20 + 4 x 785 = 3160 us, still legal.
      expect(r.check, AirtimeCheck.ok);
      final AirtimeResult big = computeAirtime(
        const AirtimeScenario(
          phy: AirtimePhy.vht,
          widthMhz: 20,
          mcs: 0,
          streams: 1,
          guardInterval: GuardInterval.gi08,
          framesAggregated: 16,
        ),
      );
      expect(big.ppduUs, greaterThan(5484));
      expect(big.check, AirtimeCheck.ppduTooLong);
    });
  });

  group('individual rules', () {
    test('HT single frame is not aggregated and gets an ACK', () {
      final AirtimeResult r = computeAirtime(
        const AirtimeScenario(
          phy: AirtimePhy.ht,
          widthMhz: 20,
          mcs: 7,
          streams: 1,
          guardInterval: GuardInterval.gi08,
        ),
      );
      expect(r.psduBytes, r.mpduBytes);
      expect(r.usesBlockAck, isFalse);
      expect(r.segment(TxopSegmentKind.ack).label, 'ACK');
      // HT-mixed: 20 + 8 + 4 + 4 x 1 LTF.
      expect(r.preambleUs, 36);
      // 52 x 6 x 5/6 = 260 bits per symbol.
      expect(r.bitsPerSymbol, 260);
    });

    test('short GI rounds the data portion up to a 4 us boundary', () {
      final AirtimeResult r = computeAirtime(
        const AirtimeScenario(
          phy: AirtimePhy.ht,
          widthMhz: 20,
          mcs: 7,
          streams: 1,
          guardInterval: GuardInterval.gi04,
        ),
      );
      // ceil((16 + 8 x 1546 + 6) / 260) = 48 symbols; 3.6 x 48 = 172.8,
      // rounded up to 176.
      expect(r.dataSymbols, 48);
      expect(r.dataUs, 176);
    });

    test('HE packet extension adds to the data portion', () {
      final AirtimeResult base = _run(AirtimePreset.he32);
      final AirtimeResult pe = computeAirtime(
        AirtimePreset.he32.scenario.copyWith(hePacketExtensionUs: 16),
      );
      expect(pe.dataUs, base.dataUs + 16);
      expect(pe.totalUs, closeTo(base.totalUs + 16, 1e-9));
      // The extension is padding: it is not counted as data symbols.
      expect(pe.dataShare, closeTo(340 / pe.totalUs, 1e-12));
    });

    test('HE rounds data bits per symbol down (80 MHz, MCS 11, 1 stream)', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.he32.scenario.copyWith(streams: 1),
      );
      expect(r.bitsPerSymbol, 8166);
    });

    test('HE-LTF is 2x (6.4 + GI) below 3.2 us GI, 4x (16 us) at 3.2', () {
      final AirtimeResult gi16 = computeAirtime(
        AirtimePreset.he32.scenario.copyWith(guardInterval: GuardInterval.gi16),
      );
      // 20 + 4 + 8 + 4 + 2 x (6.4 + 1.6) = 52.
      expect(gi16.preambleUs, 52);
      final AirtimeResult gi32 = computeAirtime(
        AirtimePreset.he32.scenario.copyWith(guardInterval: GuardInterval.gi32),
      );
      // HE, 2 streams, GI 3.2: 20 + 4 + 8 + 4 + 2 x 16 = 68.
      expect(gi32.preambleUs, 68);
      expect(gi32.symbolUs, 16);
      expect(
        gi32.segment(TxopSegmentKind.preamble).formula,
        contains('4x HE-LTF'),
      );
    });

    test('Block Ack only when two or more frames are sent', () {
      for (final AirtimePhy phy in AirtimePhy.values) {
        final AirtimeScenario base = AirtimePreset.he32.scenario.copyWith(
          band: phy == AirtimePhy.he ? AirtimeBand.ghz6 : AirtimeBand.ghz5,
          phy: phy,
          widthMhz: phy == AirtimePhy.legacy
              ? 20
              : (phy == AirtimePhy.ht ? 40 : 80),
          mcs: 7,
          guardInterval: GuardInterval.gi08,
        );
        final AirtimeResult one = computeAirtime(
          base.copyWith(framesAggregated: 1),
        );
        expect(one.usesBlockAck, isFalse, reason: phy.label);
        expect(one.segment(TxopSegmentKind.ack).us, 28, reason: phy.label);
        final AirtimeResult two = computeAirtime(
          base.copyWith(framesAggregated: 2),
        );
        // Legacy never aggregates.
        final bool legacy = phy == AirtimePhy.legacy;
        expect(two.usesBlockAck, !legacy, reason: phy.label);
        expect(
          two.segment(TxopSegmentKind.ack).us,
          legacy ? 28 : 32,
          reason: phy.label,
        );
      }
    });

    test('RTS/CTS adds RTS + SIFS + CTS + SIFS', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.vht32.scenario.copyWith(rtsCts: true),
      );
      expect(r.segment(TxopSegmentKind.rtsCts).us, 28 + 16 + 28 + 16);
      expect(r.totalUs, 666.5 + 88);
    });

    test('access category sets AIFS and the average backoff', () {
      final AirtimeResult vo = computeAirtime(
        AirtimePreset.vhtOne.scenario.copyWith(
          accessCategory: AirtimeAccessCategory.vo,
        ),
      );
      expect(vo.segment(TxopSegmentKind.aifs).us, 34);
      expect(vo.segment(TxopSegmentKind.backoff).us, 13.5);
      final AirtimeResult bk = computeAirtime(
        AirtimePreset.vhtOne.scenario.copyWith(
          accessCategory: AirtimeAccessCategory.bk,
        ),
      );
      expect(bk.segment(TxopSegmentKind.aifs).us, 79);
    });

    test('control rate changes every control frame', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(controlRateMbps: 6),
      );
      // 20 + 4 x ceil(134 / 24) = 44.
      expect(r.ackUs, 44);
      // Block Ack: 20 + 4 x ceil(278 / 24) = 68.
      expect(controlFrameTenths(32, 6, 0), 680);
    });

    test('Legacy ignores MCS, streams, GI and aggregation', () {
      final AirtimeResult a = _run(AirtimePreset.legacy6);
      final AirtimeResult b = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(
          mcs: 11,
          streams: 4,
          guardInterval: GuardInterval.gi04,
          framesAggregated: 32,
          hePacketExtensionUs: 16,
        ),
      );
      expect(b.totalTenths, a.totalTenths);
      expect(b.framesSent, 1);
    });

    test('open network drops the 16 encryption bytes', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.legacy6.scenario.copyWith(encryptionBytes: 0),
      );
      expect(r.mpduBytes, 1530);
    });

    test('every formula string names its result', () {
      final AirtimeResult r = computeAirtime(
        AirtimePreset.he32.scenario.copyWith(rtsCts: true),
      );
      for (final TxopSegment s in r.segments) {
        expect(
          s.formula,
          contains('${formatTenthsUs(s.tenths)} µs'),
          reason: s.label,
        );
      }
    });
  });

  test('formatTenthsUs', () {
    expect(formatTenthsUs(430), '43');
    expect(formatTenthsUs(675), '67.5');
    expect(formatTenthsUs(504), '50.4');
    expect(formatTenthsUs(0), '0');
  });

  // Keith, 2026-09-27: "yes refuse it too". The time view's Check refuses
  // any aggregate the structure view marks over a pinned maximum, using the
  // same limit functions, so the two views cannot disagree.
  group('the Check enforces the standard size limits', () {
    const AirtimeScenario ht40 = AirtimeScenario(
      phy: AirtimePhy.ht,
      widthMhz: 40,
      mcs: 7,
    );

    test('HT 64 x 1,500 bytes (99,328) is refused, with the reason', () {
      final AirtimeResult r = computeAirtime(
        ht40.copyWith(framesAggregated: 64),
      );
      // Well inside 5.484 ms, so only the size limit can refuse it.
      expect(r.ppduTenths, 26920);
      expect(r.psduBytes, 99328);
      expect(r.check, AirtimeCheck.ampduTooLong);
      expect(r.check.isOk, isFalse);
      expect(r.check.hasAirtime, isTrue);
      expect(
        r.checkMessage,
        'A-MPDU (aggregate MPDU) is 99,328 bytes, over the HT (802.11n) '
        'maximum of 65,535 bytes: send fewer frames',
      );
    });

    // Keith, 2026-09-28, question I3: when an aggregate is over both the
    // time limit and a size limit, the Check names both. The time test runs
    // first, so before this the size limit went unmentioned.
    test('HT 20 MHz MCS 0, 64 x 1,500 bytes breaks both limits and the '
        'Check names both', () {
      final AirtimeResult r = computeAirtime(
        const AirtimeScenario(
          phy: AirtimePhy.ht,
          widthMhz: 20,
          mcs: 0,
          framesAggregated: 64,
        ),
      );
      expect(r.ppduUs, greaterThan(5484));
      expect(r.psduBytes, 99328);
      expect(r.check, AirtimeCheck.ppduTooLong);
      expect(r.check.hasAirtime, isTrue);
      expect(r.exceedsTimeAndSize, isTrue);
      expect(r.sizeRefusal!.kind, AggregationLimitKind.ampdu);
      expect(
        r.checkMessage,
        'PPDU exceeds 5.484 ms, and the A-MPDU (aggregate MPDU) is 99,328 '
        'bytes, over the HT (802.11n) maximum of 65,535 bytes: send fewer '
        'frames',
      );
    });

    test('over the time limit only: the Check names the time limit alone', () {
      final AirtimeResult r = computeAirtime(
        const AirtimeScenario(
          phy: AirtimePhy.vht,
          widthMhz: 20,
          mcs: 0,
          streams: 1,
          guardInterval: GuardInterval.gi08,
          framesAggregated: 16,
        ),
      );
      expect(r.check, AirtimeCheck.ppduTooLong);
      expect(r.sizeRefusal, isNull);
      expect(r.exceedsTimeAndSize, isFalse);
      expect(r.checkMessage, 'PPDU exceeds 5.484 ms: send fewer frames');
    });

    test('HT 32 x 1,500 bytes is under every cap and its numbers are '
        'unchanged', () {
      final AirtimeResult r = computeAirtime(
        ht40.copyWith(framesAggregated: 32),
      );
      expect(r.check, AirtimeCheck.ok);
      expect(r.checkMessage, 'OK');
      // Pinned from the base commit 9fc55b06, before the size check.
      expect(r.psduBytes, 49664);
      expect(r.dataSymbols, 368);
      expect(r.ppduTenths, 13680);
      expect(r.totalTenths, 15265);
    });

    test('the four spreadsheet defaults still pass', () {
      for (final AirtimePreset p in AirtimePreset.values) {
        expect(_run(p).check, AirtimeCheck.ok, reason: p.label);
      }
    });

    test('the time view refuses exactly when the structure view marks the '
        'A-MPDU arrangement over a maximum', () {
      for (final AirtimePhy phy in AirtimePhy.values) {
        for (final int payload in <int>[64, 512, 1000, 1500, 2304]) {
          for (final int n in <int>[1, 2, 16, 32, 64]) {
            final AirtimeScenario s = AirtimeScenario(
              band: phy == AirtimePhy.he ? AirtimeBand.ghz6 : AirtimeBand.ghz5,
              phy: phy,
              widthMhz: phy == AirtimePhy.legacy
                  ? 20
                  : phy == AirtimePhy.ht
                  ? 40
                  : 80,
              mcs: phy == AirtimePhy.ht ? 7 : 9,
              payloadBytes: payload,
              framesAggregated: n,
            );
            final AirtimeResult r = computeAirtime(s);
            final AggregateStructure st = buildAggregateStructure(
              s,
              phy == AirtimePhy.legacy
                  ? AggregationKind.singleMpdu
                  : AggregationKind.ampdu,
            );
            final bool over = checkAggregationLimits(st).any(
              (AggregationLimitCheck c) => c.verdict == LimitVerdict.exceeds,
            );
            if (r.check == AirtimeCheck.ppduTooLong) {
              // Over the time limit: the size refusal is still reported
              // exactly when the structure view marks it (Keith, I3).
              expect(
                r.sizeRefusal != null,
                over,
                reason: '${phy.shortLabel} $payload B x $n: ${r.checkMessage}',
              );
              expect(r.exceedsTimeAndSize, over);
              continue;
            }
            expect(
              r.check.isOk,
              !over,
              reason: '${phy.shortLabel} $payload B x $n: ${r.checkMessage}',
            );
          }
        }
      }
    });
  });
}
