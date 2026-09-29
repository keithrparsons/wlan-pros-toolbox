// The ACK rate follows the BSS basic rate set (IEEE 802.11-2024 10.6.6.5.2,
// p.1944): the highest basic rate not faster than the frame being
// acknowledged, in the same modulation class; if none, the highest mandatory
// rate of the PHY not faster than it. Keith's ruling 8, 2026-09-29: the old
// rule picked from 6, 12, 24 whatever the basic set was.
//
// Facts: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/evidence/
// 2026-09-29-facts-security-compat-and-rate-set.md, section C4 and C5.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_utilization_model.dart';

void main() {
  group('the ACK rate follows the basic rate set', () {
    test('basic 6 only: every ACK goes at 6 Mb/s, even after 54', () {
      for (final int r in AirtimeConstants.legacyRatesMbps) {
        expect(
          cuControlRateFor(r, basicRates: CuBasicRates.only6),
          6,
          reason: 'data at $r',
        );
      }
    });

    test('all eight rates basic: the ACK goes at the data rate', () {
      for (final int r in AirtimeConstants.legacyRatesMbps) {
        expect(
          cuControlRateFor(r, basicRates: CuBasicRates.allOfdm),
          r,
          reason: 'data at $r',
        );
      }
    });

    test('basic 24 only: below 24 no basic rate fits, so the highest '
        'mandatory rate not faster answers (12 -> 12, 9 -> 6)', () {
      expect(cuControlRateFor(54, basicRates: CuBasicRates.only24), 24);
      expect(cuControlRateFor(24, basicRates: CuBasicRates.only24), 24);
      expect(cuControlRateFor(18, basicRates: CuBasicRates.only24), 12);
      expect(cuControlRateFor(12, basicRates: CuBasicRates.only24), 12);
      expect(cuControlRateFor(9, basicRates: CuBasicRates.only24), 6);
      expect(cuControlRateFor(6, basicRates: CuBasicRates.only24), 6);
    });

    test('802.11b basic set: no OFDM basic rate, so the mandatory OFDM rates '
        'answer an OFDM frame (the model\'s reading of the class rule)', () {
      expect(cuControlRateFor(54, basicRates: CuBasicRates.dsss), 24);
      expect(cuControlRateFor(18, basicRates: CuBasicRates.dsss), 12);
      expect(cuControlRateFor(6, basicRates: CuBasicRates.dsss), 6);
    });

    test('the default (6, 12, 24) keeps the spec 37 numbers', () {
      expect(const CuConfig().basicRates, CuBasicRates.mandatory);
      expect(cuControlRateFor(54), 24);
      expect(CuTiming(54, 1500).ackTenths, 340);
    });

    test('the timing uses the basic set: an ACK at 6 Mb/s is longer', () {
      final CuTiming fast = CuTiming(54, 1500);
      final CuTiming slow = CuTiming(54, 1500, basicRates: CuBasicRates.only6);
      expect(slow.ackTenths, controlFrameTenths(14, 6, 6));
      expect(slow.ackTenths, greaterThan(fast.ackTenths));
    });

    test('the channel run takes the basic set from its config', () {
      expect(
        CuSim(const CuConfig(basicRates: CuBasicRates.only6)).timing.ackTenths,
        500,
      );
      expect(CuSim(const CuConfig()).timing.ackTenths, 340);
    });
  });
}
