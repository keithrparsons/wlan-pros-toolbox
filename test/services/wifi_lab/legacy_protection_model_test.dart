// Tests for the Legacy Protection Cost model (Wi-Fi Classroom, spec 39).
//
// Every number here is from the spec's "Done means" list and its tables
// (myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/39-legacy-
// protection.md), which carry the research brief's figures (wave 4 brief,
// section L). They are acceptance tests: if the model disagrees, the model
// is rechecked, not the number.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dsss_timing.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/legacy_protection_model.dart';

int _ctsUs(DsssRate r, DsssPreamble p) =>
    dsssTxTimeUs(AirtimeConstants.ctsBytes, r, preamble: p);

double _protUs(ProtectionKind k, ProtectionRate r, DsssPreamble p) =>
    protectionTiming(ProtectionChoice(kind: k, rate: r, preamble: p)).totalUs;

void main() {
  group('802.11b frame timing (clause 18.3.4)', () {
    test('CTS at 1 Mb/s long preamble takes 304 us', () {
      expect(_ctsUs(DsssRate.r1, DsssPreamble.long), 304);
    });

    test('CTS at 11 Mb/s takes 203 us long and 107 us short', () {
      expect(_ctsUs(DsssRate.r11, DsssPreamble.long), 203);
      expect(_ctsUs(DsssRate.r11, DsssPreamble.short), 107);
    });

    test('the whole CTS row: 2 and 5.5 Mb/s, long and short', () {
      expect(_ctsUs(DsssRate.r2, DsssPreamble.long), 248);
      expect(_ctsUs(DsssRate.r2, DsssPreamble.short), 152);
      expect(_ctsUs(DsssRate.r5_5, DsssPreamble.long), 213);
      expect(_ctsUs(DsssRate.r5_5, DsssPreamble.short), 117);
    });

    test('the 11 Mb/s payload rounds up: 10.18 -> 11 us', () {
      // 14 bytes x 8 / 11 Mb/s = 10.18 us.
      expect(AirtimeConstants.ctsBytes * 8 / 11, closeTo(10.18, 0.01));
      expect(dsssPayloadUs(AirtimeConstants.ctsBytes, 110), 11);
    });

    test('1 Mb/s short preamble is unavailable, with the reason', () {
      expect(DsssRate.r1.allows(DsssPreamble.short), isFalse);
      for (final DsssRate r in <DsssRate>[
        DsssRate.r2,
        DsssRate.r5_5,
        DsssRate.r11,
      ]) {
        expect(r.allows(DsssPreamble.short), isTrue, reason: r.label);
      }
      const ProtectionChoice bad = ProtectionChoice(
        rate: ProtectionRate.r1,
        preamble: DsssPreamble.short,
      );
      expect(bad.isAvailable, isFalse);
      expect(
        bad.unavailableReason,
        '802.11b defines short preamble only for 2, 5.5 and 11 Mb/s.',
      );
      expect(() => protectionTiming(bad), throwsArgumentError);
      expect(
        () => dsssTxTimeUs(14, DsssRate.r1, preamble: DsssPreamble.short),
        throwsArgumentError,
      );
    });

    test('a config never holds 1 Mb/s short: it falls back to long', () {
      final LpConfig c = const LpConfig().copyWith(
        protection: const ProtectionChoice(
          rate: ProtectionRate.r1,
          preamble: DsssPreamble.short,
        ),
      );
      expect(c.protection.preamble, DsssPreamble.long);
      expect(c.protection.isAvailable, isTrue);
    });
  });

  group('protection exchanges', () {
    test('CTS-to-self adds the 10 us SIFS', () {
      expect(
        _protUs(ProtectionKind.ctsToSelf, ProtectionRate.r1, DsssPreamble.long),
        304 + 10,
      );
      expect(
        _protUs(
          ProtectionKind.ctsToSelf,
          ProtectionRate.r11,
          DsssPreamble.long,
        ),
        203 + 10,
      );
      expect(
        _protUs(
          ProtectionKind.ctsToSelf,
          ProtectionRate.r11,
          DsssPreamble.short,
        ),
        107 + 10,
      );
    });

    test('RTS + SIFS + CTS + SIFS at 2 Mb/s: 540 us long, 348 us short', () {
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r2, DsssPreamble.long),
        540,
      );
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r2, DsssPreamble.short),
        348,
      );
    });

    test('the rest of the RTS/CTS row', () {
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r1, DsssPreamble.long),
        676,
      );
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r5_5, DsssPreamble.long),
        455,
      );
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r5_5, DsssPreamble.short),
        263,
      );
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r11, DsssPreamble.long),
        430,
      );
      expect(
        _protUs(ProtectionKind.rtsCts, ProtectionRate.r11, DsssPreamble.short),
        238,
      );
    });

    test('OFDM contrast: CTS at 6 Mb/s = 44 + 6 us, about 60 with SIFS', () {
      final ProtectionTiming t = protectionTiming(
        const ProtectionChoice(rate: ProtectionRate.ofdm6),
      );
      expect(t.ctsUs, 50);
      expect(t.totalUs, 60);
    });

    test('Up and Down step the seven pairs that exist, slowest first', () {
      final List<(ProtectionRate, DsssPreamble)> order = dsssStepOrder();
      expect(order, hasLength(7));
      expect(order.first, (ProtectionRate.r1, DsssPreamble.long));
      expect(order.last, (ProtectionRate.r11, DsssPreamble.short));
      expect(order.contains((ProtectionRate.r1, DsssPreamble.short)), isFalse);
    });
  });

  group('the data frame reuses Airtime Anatomy', () {
    test('1500 bytes at 54 Mb/s, 2.4 GHz, open network = 254 us', () {
      final LpCycle c = kLpCeilingCases.first.spec.let(computeCycle);
      expect((c.data.preambleTenths + c.data.dataTenths) / 10, 254);
      expect(c.data.ackUs, 34);
      expect(c.data.sifsUs, 10);
    });
  });

  group('ceiling table (CWmin 15 unless stated)', () {
    const List<(double, double)> expected = <(double, double)>[
      (393.5, 30.5),
      (498, 24.1),
      (615, 19.5),
      (711, 16.9),
      (812, 14.8),
      (972, 12.3),
    ];
    for (int i = 0; i < expected.length; i++) {
      test('row ${i + 1}: ${kLpCeilingCases[i].label}', () {
        final LpCycle c = computeCycle(kLpCeilingCases[i].spec);
        expect(c.cycleUs, closeTo(expected[i].$1, 1));
        expect(c.payloadRateMbps, closeTo(expected[i].$2, 0.1));
      });
    }

    test('the default scenario is row 5: 30.5 falls to 14.8 Mb/s', () {
      final LpResult r = computeLegacyProtection(const LpConfig());
      expect(r.baseline.cycleUs, 393.5);
      expect(r.cycle.cycleUs, 812);
      expect(ceilingRowOf(r), 4);
      expect(r.lostShare, closeTo(0.515, 0.005));
    });

    test('the costs add up: slot, CWmin, protection', () {
      final LpResult r = computeLegacyProtection(
        const LpConfig(cwMin: LpCwMin.cw31),
      );
      expect(r.slotAddedTenths, 1045);
      expect(r.cwAddedTenths, 1600);
      expect(r.protectionTenths, 3140);
      expect(
        r.baseline.totalTenths +
            r.slotAddedTenths +
            r.cwAddedTenths +
            r.protectionTenths,
        r.cycle.totalTenths,
      );
      expect(r.cycle.cycleUs, 972);
    });
  });

  group('triggers', () {
    test('associated sets NonERP_Present and Use_Protection and forces the '
        'long slot', () {
      final LpResult r = computeLegacyProtection(
        const LpConfig(associated: true),
      );
      expect(r.erp.nonErpPresent, isTrue);
      expect(r.erp.useProtection, isTrue);
      expect(r.longSlot, isTrue);
      expect(r.cycle.spec.slotUs, 20);
      expect(r.cycle.protection, isNotNull);
    });

    test('heard sets Use_Protection only and never forces the long slot', () {
      for (final NeighborPolicy p in NeighborPolicy.values) {
        final LpResult r = computeLegacyProtection(
          LpConfig(associated: false, heard: true, policy: p),
        );
        expect(r.erp.nonErpPresent, isFalse);
        expect(r.erp.useProtection, isTrue);
        expect(r.erp.barkerPreambleMode, isFalse);
        expect(r.longSlot, isFalse);
        expect(r.cycle.spec.slotUs, 9);
        expect(r.slotAddedTenths, 0);
      }
    });

    test('heard on another channel: only an AP that reacts to adjacent '
        'channels protects', () {
      final LpResult own = computeLegacyProtection(
        const LpConfig(
          associated: false,
          heard: true,
          neighborChannel: NeighborChannel.other,
          policy: NeighborPolicy.ownOnly,
        ),
      );
      expect(own.erp.useProtection, isFalse);
      expect(own.cycle.protection, isNull);
      final LpResult adj = computeLegacyProtection(
        const LpConfig(
          associated: false,
          heard: true,
          neighborChannel: NeighborChannel.other,
          policy: NeighborPolicy.adjacentToo,
        ),
      );
      expect(adj.erp.useProtection, isTrue);
      expect(adj.cycle.spec.slotUs, 9);
    });

    test('Barker_Preamble_Mode: set when the associated device cannot use '
        'short preamble', () {
      expect(erpBits(const LpConfig()).barkerPreambleMode, isTrue);
      expect(
        erpBits(
          const LpConfig(oldDeviceShortPreamble: true),
        ).barkerPreambleMode,
        isFalse,
      );
    });

    test('nothing old: no bits, modern-only cycle, nothing lost', () {
      final LpResult r = computeLegacyProtection(
        const LpConfig(associated: false),
      );
      expect(
        r.erp,
        const ErpBits(
          nonErpPresent: false,
          useProtection: false,
          barkerPreambleMode: false,
        ),
      );
      expect(r.cycle.totalTenths, r.baseline.totalTenths);
      expect(r.lostShare, 0);
    });

    test('CWmin 31 applies only while an 802.11b device is associated', () {
      final LpResult r = computeLegacyProtection(
        const LpConfig(associated: false, cwMin: LpCwMin.cw31),
      );
      expect(r.cycle.spec.cwMin, 15);
      expect(r.cwAddedTenths, 0);
    });

    test('HT Protection reads 3 with an older station associated and 0 with '
        'only matching 802.11n stations', () {
      expect(computeLegacyProtection(const LpConfig()).ht.value, 3);
      expect(
        computeLegacyProtection(const LpConfig(associated: false)).ht.value,
        0,
      );
      expect(
        computeLegacyProtection(
          const LpConfig(associated: false, heard: true),
        ).ht.value,
        1,
      );
    });
  });

  test('deterministic: same config, same result', () {
    final LpResult a = computeLegacyProtection(const LpConfig());
    final LpResult b = computeLegacyProtection(const LpConfig());
    expect(a.cycle.totalTenths, b.cycle.totalTenths);
    expect(a.erp, b.erp);
    expect(a.windowUs, b.windowUs);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
