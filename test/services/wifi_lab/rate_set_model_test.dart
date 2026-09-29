// Tests for the rate set builder model (spec 44, "Done means").
//
// Facts: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/evidence/
// 2026-09-29-facts-security-compat-and-rate-set.md section C; Table 10-9
// and 10.6.11 of IEEE Std 802.11-2024 read directly (spec 44, [F]).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_set_model.dart';

RsRate _r(double mbps) => RsRate.ofMbps(mbps)!;

List<RsRate> _rs(List<double> mbps) => <RsRate>[
  for (final double m in mbps) _r(m),
];

int _ack(RateSet s, double mbps) =>
    s.controlResponse(RsEliciting.legacy(_r(mbps))).rate.mbps.round();

void main() {
  group('the rates and the PHYs', () {
    test('12 legacy rates, slowest first, in two families', () {
      expect(RsRate.byRate.map((RsRate r) => r.label).toList(), <String>[
        '1', '2', '5.5', '6', '9', '11', '12', '18', '24', '36', '48', '54', //
      ]);
      expect(RsRate.ofClass(RsModClass.dsss), _rs(<double>[1, 2, 5.5, 11]));
      expect(RsRate.ofClass(RsModClass.ofdm).length, 8);
    });

    test('mandatory sets: OFDM 6, 12, 24; ERP 1, 2, 5.5, 6, 11, 12, 24', () {
      expect(RsPhy.ofdm.mandatory, _rs(<double>[6, 12, 24]));
      expect(RsPhy.erp.mandatory, _rs(<double>[1, 2, 5.5, 6, 11, 12, 24]));
      expect(RsPhy.ofdm.rates.length, 8);
      expect(RsPhy.erp.rates.length, 12);
    });

    test('element octets: basic sets bit 7, units of 500 kb/s (9.4.2.3)', () {
      expect(RsRate.r6.octet(basic: true), 0x8C);
      expect(RsRate.r2.octet(basic: false), 0x04);
      expect(RsRate.r5_5.octet(basic: true), 0x8B);
      expect(RsRate.r54.octet(basic: false), 0x6C);
    });

    test('at most eight octets in Supported Rates, the rest Extended', () {
      final ({List<int> supported, List<int> extended}) o = RateSet.defaults(
        RsPhy.erp,
      ).elementOctets;
      expect(o.supported, <int>[
        0x02,
        0x04,
        0x0B,
        0x8C,
        0x12,
        0x16,
        0x98,
        0x24,
      ]);
      expect(o.extended, <int>[0xB0, 0x48, 0x60, 0x6C]);
      final ({List<int> supported, List<int> extended}) f = RateSet.defaults(
        RsPhy.ofdm,
      ).elementOctets;
      expect(f.supported.length, 8);
      expect(f.extended, isEmpty);
    });
  });

  group('the rate set', () {
    test('defaults: 6, 12, 24 basic, minimum basic 6, beacons at 6', () {
      final RateSet s = RateSet.defaults(RsPhy.ofdm);
      expect(s.basic, _rs(<double>[6, 12, 24]));
      expect(s.minimumBasic, RsRate.r6);
      expect(s.beacon!.rate, RsRate.r6);
      expect(s.beacon!.fromBasic, isTrue);
    });

    test('a tap cycles off, supported, basic', () {
      RateSet s = RateSet.defaults(RsPhy.ofdm);
      expect(s.stateOf(RsRate.r9), RsState.supported);
      s = s.cycle(RsRate.r9);
      expect(s.stateOf(RsRate.r9), RsState.basic);
      s = s.cycle(RsRate.r9);
      expect(s.stateOf(RsRate.r9), RsState.off);
      s = s.cycle(RsRate.r9);
      expect(s.stateOf(RsRate.r9), RsState.supported);
    });

    test('the minimum basic rate is derived: the lowest basic rate', () {
      final RateSet s = RateSet.defaults(
        RsPhy.ofdm,
      ).withState(RsRate.r6, RsState.supported);
      expect(s.minimumBasic, RsRate.r12);
      expect(s.beacon!.rate, RsRate.r12);
    });

    test('withMinimumBasic turns slower rates off and the rate basic', () {
      final RateSet s = RateSet.defaults(
        RsPhy.erp,
      ).withMinimumBasic(RsRate.r24);
      for (final RsRate r in RsPhy.erp.rates) {
        if (r.mbps < 24) expect(s.stateOf(r), RsState.off, reason: r.label);
      }
      expect(s.minimumBasic, RsRate.r24);
      expect(s.stateOf(RsRate.r36), RsState.supported);
    });

    test('an empty basic set is valid: beacons at a mandatory rate '
        '(10.6.5.1)', () {
      final RateSet s = RateSet.of(
        RsPhy.erp,
        basic: const <RsRate>[],
        supported: RsPhy.erp.rates,
      );
      expect(s.minimumBasic, isNull);
      expect(s.beacon!.rate, RsRate.r1);
      expect(s.beacon!.fromBasic, isFalse);
    });

    test('every rate off: no beacon, nobody associates', () {
      final RateSet s = RateSet.of(RsPhy.ofdm, basic: const <RsRate>[]);
      expect(s.isEmpty, isTrue);
      expect(s.beacon, isNull);
      expect(s.ackTable(withHe: true), isEmpty);
      expect(canJoin(s, RsClient.wifi6).verdict, RsVerdict.noRates);
    });

    test('DSSS states survive a trip to 5 GHz and back', () {
      final RateSet two = RateSet.defaults(
        RsPhy.erp,
      ).withState(RsRate.r1, RsState.basic);
      final RateSet five = two.onPhy(RsPhy.ofdm);
      expect(five.stateOf(RsRate.r1), RsState.off);
      expect(five.basic, _rs(<double>[6, 12, 24]));
      expect(five.onPhy(RsPhy.erp).stateOf(RsRate.r1), RsState.basic);
    });
  });

  group('who can associate (status 18, Table 9-80)', () {
    test('a client missing a basic rate is refused with status 18', () {
      final RateSet s = RateSet.of(
        RsPhy.erp,
        basic: _rs(<double>[6, 12, 24]),
        supported: RsPhy.erp.rates,
      );
      final RsAssociation a = canJoin(s, RsClient.erpClass2);
      expect(a.verdict, RsVerdict.refusedBasicRates);
      expect(a.statusCode, 18);
      expect(a.missingBasic, _rs(<double>[12, 24]));
      expect(kStatusRefusedBasicRatesName, 'REFUSED_BASIC_RATES_MISMATCH');
    });

    test('802.11b device vs an OFDM-only basic set: refused, and it cannot '
        'decode the OFDM beacon either', () {
      final RsAssociation a = canJoin(
        RateSet.defaults(RsPhy.erp),
        RsClient.dot11b,
      );
      expect(a.verdict, RsVerdict.refusedBasicRates);
      expect(a.missingBasic, _rs(<double>[6, 12, 24]));
      expect(a.decodesBeacons, isFalse);
    });

    test('802.11b device vs a DSSS basic set: associates', () {
      final RateSet s = RateSet.of(
        RsPhy.erp,
        basic: _rs(<double>[1, 2, 5.5, 11]),
        supported: RsPhy.erp.rates,
      );
      final RsAssociation a = canJoin(s, RsClient.dot11b);
      expect(a.verdict, RsVerdict.associates);
      expect(a.decodesBeacons, isTrue);
      expect(a.statusCode, isNull);
    });

    test('802.11b and 802.11g devices never hear a 5 GHz network', () {
      for (final RsClient c in <RsClient>[
        RsClient.dot11b,
        RsClient.erpClass2,
        RsClient.dot11g,
      ]) {
        expect(
          canJoin(RateSet.defaults(RsPhy.ofdm), c).verdict,
          RsVerdict.otherBand,
          reason: c.label,
        );
      }
      expect(
        canJoin(RateSet.defaults(RsPhy.ofdm), RsClient.wifi6).verdict,
        RsVerdict.associates,
      );
    });

    test('Class 2 ERP device and 54 as the only basic rate (18.1.2 NOTE)', () {
      final RateSet s = RateSet.of(
        RsPhy.erp,
        basic: <RsRate>[RsRate.r54],
        supported: RsPhy.erp.rates,
      );
      expect(canJoin(s, RsClient.erpClass2).missingBasic, <RsRate>[RsRate.r54]);
      expect(canJoin(s, RsClient.dot11g).associates, isTrue);
    });

    test('a required PHY: 802.11g lacks HT, Wi-Fi 6 has it; no code', () {
      final RateSet s = RateSet.defaults(RsPhy.erp);
      final RsAssociation g = canJoin(
        s,
        RsClient.dot11g,
        requirePhy: RsRequiredPhy.ht,
      );
      expect(g.verdict, RsVerdict.lacksRequiredPhy);
      expect(g.statusCode, isNull);
      expect(RsRequiredPhy.ht.selector, 127);
      expect(RsRequiredPhy.he.selector, 122);
      expect(
        canJoin(s, RsClient.wifi6, requirePhy: RsRequiredPhy.he).associates,
        isTrue,
      );
    });
  });

  group('the ACK rate (10.6.6.5.2)', () {
    test('basic {24}: 54 -> 24, 12 -> 12, 6 -> 6 (the MBR is not a floor)', () {
      final RateSet s = RateSet.of(
        RsPhy.ofdm,
        basic: <RsRate>[RsRate.r24],
        supported: RsPhy.ofdm.rates,
      );
      expect(_ack(s, 54), 24);
      expect(_ack(s, 12), 12);
      expect(_ack(s, 6), 6);
      final RsControlResponse r12 = s.controlResponse(
        const RsEliciting.legacy(RsRate.r12),
      );
      expect(r12.fromBasic, isFalse, reason: 'mandatory fallback');
      expect(_ack(s, 18), 12);
      expect(_ack(s, 9), 6);
    });

    test('basic {6, 12, 24}: 18 -> 12, 54 -> 24, 9 -> 6', () {
      final RateSet s = RateSet.defaults(RsPhy.ofdm);
      expect(_ack(s, 18), 12);
      expect(_ack(s, 54), 24);
      expect(_ack(s, 9), 6);
    });

    test('an OFDM frame never gets a DSSS ACK: basic {1, 2, 5.5, 11} and a '
        'frame at 24 answer at 24, the model\'s reading', () {
      final RateSet s = RateSet.of(
        RsPhy.erp,
        basic: _rs(<double>[1, 2, 5.5, 11]),
        supported: RsPhy.erp.rates,
      );
      final RsControlResponse r = s.controlResponse(
        const RsEliciting.legacy(RsRate.r24),
      );
      expect(r.rate, RsRate.r24);
      expect(r.fromBasic, isFalse);
      expect(r.classFilterDecided, isTrue);
      expect(_ack(s, 11), 11);
      expect(
        s.controlResponse(const RsEliciting.legacy(RsRate.r11)).fromBasic,
        isTrue,
      );
    });

    test('a DSSS frame gets a DSSS ACK even with OFDM basic rates', () {
      final RateSet s = RateSet.defaults(RsPhy.erp);
      final RsControlResponse r = s.controlResponse(
        const RsEliciting.legacy(RsRate.r11),
      );
      expect(r.rate, RsRate.r11);
      expect(r.classFilterDecided, isTrue, reason: '6 is basic and <= 11');
      expect(_ack(s, 1), 1);
    });

    test('Table 10-10: the non-HT reference rate', () {
      expect(nonHtReferenceRate('BPSK', '1/2'), 6);
      expect(nonHtReferenceRate('QPSK', '3/4'), 18);
      expect(nonHtReferenceRate('64-QAM', '2/3'), 48);
      expect(nonHtReferenceRate('64-QAM', '5/6'), 54);
      expect(nonHtReferenceRate('1024-QAM', '5/6'), 54);
      expect(() => nonHtReferenceRate('4096-QAM', '3/4'), throwsArgumentError);
    });

    test('HE MCS 7 (64-QAM 5/6) -> 54 -> the highest basic <= 54', () {
      final RateSet s = RateSet.defaults(RsPhy.ofdm);
      final RsControlResponse r = s.controlResponse(kRsHeRows[7]);
      expect(r.eliciting.compareMbps, 54);
      expect(r.rate, RsRate.r24);
      expect(s.controlResponse(kRsHeRows[2]).rate, RsRate.r12);
      expect(s.controlResponse(kRsHeRows[0]).rate, RsRate.r6);
    });

    test('the ACK table covers every rate that is on, then HE 0 to 11', () {
      final RateSet s = RateSet.defaults(RsPhy.ofdm);
      expect(s.ackTable().length, 8);
      expect(s.ackTable(withHe: true).length, 20);
      final RateSet fewer = s.withState(RsRate.r9, RsState.off);
      expect(fewer.ackTable().length, 7);
    });
  });

  test('rate lists read in words', () {
    expect(rsRateList(_rs(<double>[24])), '24 Mbps');
    expect(rsRateList(_rs(<double>[6, 12, 24])), '6, 12 and 24 Mbps');
    expect(rsRateList(const <RsRate>[]), 'none');
  });

  test('verdict wording says associate and names status 18', () {
    final RsAssociation b = canJoin(
      RateSet.defaults(RsPhy.erp),
      RsClient.dot11b,
    );
    expect(rsVerdictHeadline(b), 'Cannot associate');
    expect(
      rsVerdictLine(b),
      'Cannot associate: it cannot decode the OFDM beacons, so it never sees '
      'this network. If it tried, the AP would refuse it with status 18 '
      '(REFUSED_BASIC_RATES_MISMATCH): it lacks 6, 12 and 24 Mbps.',
    );
    final RsAssociation c2 = canJoin(
      RateSet.defaults(RsPhy.erp),
      RsClient.erpClass2,
    );
    expect(rsVerdictHeadline(c2), 'Refused: status 18');
    expect(rsVerdictLine(c2), contains('it lacks 12 and 24 Mbps'));
    for (final RsClient c in RsClient.values) {
      for (final RsPhy p in RsPhy.values) {
        final String line = rsVerdictLine(canJoin(RateSet.defaults(p), c));
        expect(line.toLowerCase(), isNot(contains('join')));
      }
    }
  });
}
