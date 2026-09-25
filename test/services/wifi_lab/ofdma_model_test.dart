// Tests for the OFDMA Resource Units model (Wi-Fi Lab).
//
// Anchors: the RU table and the worked example in the wave-3 research brief,
// §6 (myPKA Deliverables/2026-09-25-wifi-lab-wave3-research/brief.md), and
// spec 19's "Done means".

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/ofdma_model.dart';

OfdmaResult _run(
  int width,
  List<RuSize> sizes, {
  int payload = 200,
  int mcs = 7,
}) => computeOfdma(
  OfdmaScenario(
    widthMhz: width,
    ruSizes: sizes,
    payloadBytes: payload,
    mcs: mcs,
  ),
);

void main() {
  group('RU table (brief §6)', () {
    // tones, data, pilot, then counts at 20/40/80/160 (null = n/a).
    const Map<RuSize, (int, int, int, List<int?>)> brief =
        <RuSize, (int, int, int, List<int?>)>{
          RuSize.ru26: (26, 24, 2, <int?>[9, 18, 37, 74]),
          RuSize.ru52: (52, 48, 4, <int?>[4, 8, 16, 32]),
          RuSize.ru106: (106, 102, 4, <int?>[2, 4, 8, 16]),
          RuSize.ru242: (242, 234, 8, <int?>[1, 2, 4, 8]),
          RuSize.ru484: (484, 468, 16, <int?>[null, 1, 2, 4]),
          RuSize.ru996: (996, 980, 16, <int?>[null, null, 1, 2]),
          RuSize.ru2x996: (1992, 1960, 32, <int?>[null, null, null, 1]),
        };

    test('data + pilot split for every RU', () {
      for (final MapEntry<RuSize, (int, int, int, List<int?>)> e
          in brief.entries) {
        expect(e.key.tones, e.value.$1, reason: e.key.label);
        expect(e.key.dataTones, e.value.$2, reason: e.key.label);
        expect(e.key.pilotTones, e.value.$3, reason: e.key.label);
        expect(e.key.dataTones + e.key.pilotTones, e.key.tones);
      }
    });

    test('every count per width', () {
      for (final MapEntry<RuSize, (int, int, int, List<int?>)> e
          in brief.entries) {
        for (int i = 0; i < 4; i++) {
          final int w = OfdmaTonePlan.widthsMhz[i];
          expect(
            OfdmaTonePlan.count(e.key, w),
            e.value.$4[i],
            reason: '${e.key.label}-tone at $w MHz',
          );
        }
      }
    });

    test('52-tone at 160 MHz is 32, not the 34 one source printed', () {
      expect(OfdmaTonePlan.count(RuSize.ru52, 160), 32);
    });

    test('the derived positions reproduce every count, without overlap', () {
      for (final int w in OfdmaTonePlan.widthsMhz) {
        for (final RuSize s in RuSize.values) {
          final List<RuSpan> p = OfdmaTonePlan.positions(w, s);
          expect(p.length, OfdmaTonePlan.count(s, w) ?? 0, reason: '$s $w');
          for (int i = 0; i < p.length; i++) {
            expect(p[i].length, s.slots);
            expect(p[i].end <= OfdmaTonePlan.slots(w), isTrue);
            for (int j = i + 1; j < p.length; j++) {
              expect(p[i].overlaps(p[j]), isFalse, reason: '$s $w $i $j');
            }
          }
        }
      }
    });

    test('the 20 MHz center slot is 26-tone only', () {
      expect(OfdmaTonePlan.positionAt(20, RuSize.ru26, 4), const RuSpan(4, 1));
      expect(OfdmaTonePlan.positionAt(20, RuSize.ru52, 4), isNull);
      expect(OfdmaTonePlan.positionAt(20, RuSize.ru106, 4), isNull);
      // Two 106-tone RUs plus the center 26-tone RU fill 20 MHz.
      expect(
        OfdmaTonePlan.fits(20, <RuSize>[
          RuSize.ru106,
          RuSize.ru106,
          RuSize.ru26,
        ]),
        isTrue,
      );
    });

    test('fit rules', () {
      expect(
        OfdmaTonePlan.fits(20, List<RuSize>.filled(9, RuSize.ru26)),
        isTrue,
      );
      expect(
        OfdmaTonePlan.fits(20, List<RuSize>.filled(5, RuSize.ru52)),
        isFalse,
      );
      expect(
        OfdmaTonePlan.fits(20, <RuSize>[
          RuSize.ru106,
          RuSize.ru52,
          RuSize.ru52,
          RuSize.ru26,
        ]),
        isTrue,
      );
      expect(OfdmaTonePlan.fits(20, <RuSize>[RuSize.ru484]), isFalse);
      expect(OfdmaTonePlan.largestEqualFit(20, 4), RuSize.ru52);
      expect(OfdmaTonePlan.largestEqualFit(20, 5), RuSize.ru26);
      expect(OfdmaTonePlan.largestEqualFit(80, 1), RuSize.ru996);
      expect(OfdmaTonePlan.fullChannel(160), RuSize.ru2x996);
    });
  });

  group('worked example (brief §6): 4 STAs, 200 B, 20 MHz, MCS 7, 1 SS', () {
    final OfdmaResult r = _run(20, List<RuSize>.filled(4, RuSize.ru52));

    test('SU is about 916 µs, reusing the Airtime Anatomy service', () {
      expect(r.suTxopTenths, 2289); // 228.9 µs per TXOP
      expect(r.su.totalUs, closeTo(916, 10));
      expect(r.su.totalTenths, 9156);
    });

    test('DL OFDMA is about 403 µs', () {
      expect(r.check, OfdmaCheck.ok);
      expect(r.sigB.symbols, 5); // the brief's estimate, now computed
      expect(r.dataSymbolsDl, <int>[9, 9, 9, 9]);
      final OfdmaSegment pre = r.dl!.segments.firstWhere(
        (OfdmaSegment s) => s.kind == OfdmaSegmentKind.preamble,
      );
      expect(pre.tenths, 632); // 63.2 µs
      final OfdmaSegment ack = r.dl!.segments.last;
      expect(ack.tenths, 912); // brief: about 91 µs
      expect(r.dl!.totalUs, closeTo(403, 10));
    });

    test('UL OFDMA is about 408 µs', () {
      final List<OfdmaSegment> s = r.ul!.segments;
      expect(
        s
            .firstWhere((OfdmaSegment x) => x.kind == OfdmaSegmentKind.trigger)
            .tenths,
        400, // 52 B at 24 Mbps = 40 µs
      );
      expect(s.last.tenths, 480); // Multi-STA BA about 48 µs
      expect(r.ul!.totalUs, closeTo(408, 10));
    });

    test('OFDMA is about 2.2 times less airtime; the win is overhead', () {
      expect(r.ratio(OfdmaMode.dl), closeTo(2.27, 0.05));
      expect(r.ratio(OfdmaMode.ul), closeTo(2.24, 0.05));
      final Map<OfdmaPart, int> saved = r.savings(OfdmaMode.dl)!;
      expect(saved[OfdmaPart.contention], 3315); // three fewer contentions
      expect(saved[OfdmaPart.preamble]! > 0, isTrue);
      expect(saved[OfdmaPart.acks]! > 0, isTrue);
      // Not a faster PHY: the data itself takes LONGER on narrow RUs.
      expect(saved[OfdmaPart.data]! < 0, isTrue);
    });

    test('estimates are flagged', () {
      final Set<OfdmaAssumption> flagged = <OfdmaAssumption>{
        for (final OfdmaTimeline t in <OfdmaTimeline>[r.su, r.dl!, r.ul!])
          for (final OfdmaSegment s in t.segments)
            if (s.estimate != null) s.estimate!,
      };
      expect(
        flagged,
        containsAll(<OfdmaAssumption>[
          OfdmaAssumption.suBlockAck,
          OfdmaAssumption.sigB,
          OfdmaAssumption.dlAck,
          OfdmaAssumption.trigger,
          OfdmaAssumption.multiStaBa,
        ]),
      );
    });
  });

  group('one client, full-channel RU: OFDMA is no better than SU', () {
    for (final int w in OfdmaTonePlan.widthsMhz) {
      for (final int payload in <int>[200, 1500]) {
        test('$w MHz, $payload B', () {
          final OfdmaResult r = _run(w, <RuSize>[
            OfdmaTonePlan.fullChannel(w),
          ], payload: payload);
          expect(r.check, OfdmaCheck.ok);
          expect(r.dl!.totalTenths >= r.su.totalTenths, isTrue);
          expect(r.ul!.totalTenths >= r.su.totalTenths, isTrue);
          expect(r.ratio(OfdmaMode.dl)! <= 1, isTrue);
        });
      }
    }
  });

  test('SU data matches the Airtime Anatomy service exactly', () {
    final OfdmaResult r = _run(40, List<RuSize>.filled(3, RuSize.ru106));
    final AirtimeResult a = computeAirtime(
      const AirtimeScenario(
        phy: AirtimePhy.he,
        widthMhz: 40,
        mcs: 7,
        streams: 1,
        guardInterval: GuardInterval.gi08,
        payloadBytes: 200,
      ),
    );
    final OfdmaSegment d = r.su.segments.firstWhere(
      (OfdmaSegment s) => s.kind == OfdmaSegmentKind.data,
    );
    expect(d.tenths, a.dataTenths);
    expect(r.suTxopTenths, a.totalTenths - a.ackTenths + a.blockAckTenths);
  });

  test('DL data is set by the slowest RU', () {
    final OfdmaResult r = _run(20, <RuSize>[
      RuSize.ru106,
      RuSize.ru52,
      RuSize.ru26,
    ]);
    final OfdmaSegment d = r.dl!.segments.firstWhere(
      (OfdmaSegment s) => s.kind == OfdmaSegmentKind.data,
    );
    // 2032 bits: 106-tone 510 b/sym -> 4, 52-tone 240 -> 9, 26-tone 120 -> 17.
    expect(r.dataSymbolsDl, <int>[4, 9, 17]);
    expect(d.lanes, <int>[4 * 136, 9 * 136, 17 * 136]);
    expect(d.tenths, 17 * 136);
  });

  test('HE-SIG-B grows with users and width', () {
    expect(sigBLength(20, 1).symbols, 2); // 18 + 31 = 49 bits
    expect(sigBLength(20, 9).symbols, 10); // 18 + 4x52 + 31 = 257 bits
    expect(sigBLength(40, 4).contentChannels, 2);
    expect(sigBLength(40, 4).symbols, 3); // 18 + 52 = 70 bits
    expect(sigBLength(80, 1).commonBits, 27);
    expect(sigBLength(160, 1).commonBits, 43);
  });

  test('checks', () {
    expect(
      _run(20, List<RuSize>.filled(5, RuSize.ru52)).check,
      OfdmaCheck.doesNotFit,
    );
    expect(_run(20, <RuSize>[RuSize.ru484]).check, OfdmaCheck.ruTooWide);
    final OfdmaResult big = _run(
      20,
      List<RuSize>.filled(4, RuSize.ru52),
      mcs: 11,
    );
    expect(big.check, OfdmaCheck.mcsNeedsFullRu);
    expect(big.dl, isNull);
    expect(big.ratio(OfdmaMode.dl), isNull);
    // SU is still drawn.
    expect(big.su.totalTenths > 0, isTrue);
    expect(_run(20, <RuSize>[RuSize.ru242], mcs: 11).check, OfdmaCheck.ok);
  });

  test('a 1,500-byte frame on a 26-tone RU at MCS 0 breaks the PPDU limit', () {
    final OfdmaResult r = _run(
      20,
      <RuSize>[RuSize.ru26],
      payload: 1500,
      mcs: 0,
    );
    expect(r.dl!.ppduTooLong, isTrue);
    expect(r.ratio(OfdmaMode.dl), isNull);
  });

  test('client letters', () {
    expect(clientLetter(0), 'A');
    expect(clientLetter(17), 'R');
  });
}
