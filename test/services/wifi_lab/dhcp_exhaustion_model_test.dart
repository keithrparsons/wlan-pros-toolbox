// Conference Wi-Fi Runs Out of Addresses: the model's teaching claims.
//
//  1. With the default long lease the /24 pool runs dry mid-morning while
//     the hall holds far fewer devices than the pool has addresses.
//  2. A short lease holds all morning with the same crowd.
//  3. The pool must cover everyone who arrived within one lease time: with a
//     lease longer than the morning, demand is every device that came.
//  4. Devices that rotate their private address come back as new clients,
//     take more addresses and bring the dry time forward.
//  5. RFC 2131 mechanics: renew every half lease while present; after
//     leaving, the address is free one lease after the last renewal.
//  6. Bookkeeping: every device in the hall has an address or is waiting;
//     nothing binds more than the pool.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dhcp_exhaustion_model.dart';

void main() {
  test('pool size: usable hosts minus reserved', () {
    expect(const DxConfig().usableHosts, 254);
    expect(const DxConfig().poolSize, 244);
    expect(const DxConfig(prefix: 20).poolSize, 4084);
    expect(const DxConfig(prefix: 19, reserved: 0).poolSize, 8190);
    expect(const DxConfig().devices, 375);
  });

  test('labels', () {
    expect(dxLeaseLabel(30), '30 min');
    expect(dxLeaseLabel(60), '1 hour');
    expect(dxLeaseLabel(480), '8 hours');
    expect(dxLeaseLabel(1440), '1 day');
    expect(dxLeaseLabel(11520), '8 days');
    expect(dxClock(0), '07:00');
    expect(dxClock(198), '10:18');
  });

  test('the arrival shape sums to 100 and every device arrives', () {
    expect(kDxArrivalShape.reduce((int a, int b) => a + b), 100);
    final DxMorning m = DxMorning(const DxConfig(leaseMinutes: 11520));
    expect(m.identities, 375);
    expect(m.peakDemand, 375);
  });

  test('freeAt: last renewal (every half lease) plus one lease', () {
    // Renewals at 30, 60, 90; left at 100; free at 90 + 60.
    expect(DxMorning.freeAt(0, 100, 60), 150);
    // Left before the first renewal.
    expect(DxMorning.freeAt(0, 20, 60), 60);
    expect(DxMorning.freeAt(10, 100, 1440), 1450);
  });

  group('the defaults', () {
    final DxMorning long = DxMorning(const DxConfig());

    test('a 1-day lease runs dry mid-morning', () {
      expect(long.firstDryMinute, isNotNull);
      expect(dxClock(long.firstDryMinute!), '10:18');
      expect(long.peakWaiting, greaterThan(0));
    });

    test('when it runs dry the hall holds far fewer devices than the pool', () {
      final DxMinute at = long.minutes[long.firstDryMinute!];
      expect(at.devicesHere, lessThan(long.poolSize * 0.7));
      expect(at.heldLeft, greaterThan(0));
      expect(long.why, contains('10:18'));
    });

    test('a 30-minute lease holds all morning', () {
      final DxMorning short = DxMorning(const DxConfig(leaseMinutes: 30));
      expect(short.held, isTrue);
      expect(short.peakWaiting, 0);
      expect(short.peakBound, lessThan(short.poolSize));
      expect(short.why, contains('covers everyone who arrived'));
    });

    test('a /23 holds the same crowd with the same long lease', () {
      expect(DxMorning(const DxConfig(prefix: 23)).held, isTrue);
    });
  });

  test('longer leases never need fewer addresses', () {
    int last = 0;
    for (final int l in kDxLeaseChoices) {
      final int d = DxMorning(DxConfig(leaseMinutes: l)).peakDemand;
      expect(d, greaterThanOrEqualTo(last), reason: dxLeaseLabel(l));
      last = d;
    }
  });

  test('rotation makes new clients and brings the dry time forward', () {
    final DxMorning off = DxMorning(const DxConfig());
    final DxMorning on = DxMorning(const DxConfig(rotation: true));
    expect(on.identities, greaterThan(off.identities));
    expect(on.firstDryMinute!, lessThan(off.firstDryMinute!));
    // A 2-hour lease holds without rotation and fails with it.
    expect(DxMorning(const DxConfig(leaseMinutes: 120)).held, isTrue);
    expect(
      DxMorning(const DxConfig(leaseMinutes: 120, rotation: true)).held,
      isFalse,
    );
    // Rotated-away addresses show up as their own kind.
    expect(on.minutes.any((DxMinute m) => m.heldRotated > 0), isTrue);
    expect(off.minutes.every((DxMinute m) => m.heldRotated == 0), isTrue);
  });

  test('no rotating share means no extra clients', () {
    expect(
      DxMorning(const DxConfig(rotation: true, rotatingShare: 0)).identities,
      375,
    );
  });

  test('bookkeeping holds every minute, with and without rotation', () {
    for (final DxConfig c in <DxConfig>[
      const DxConfig(),
      const DxConfig(rotation: true, leaseMinutes: 60),
      const DxConfig(people: 2000, prefix: 22, rotation: true),
    ]) {
      final DxMorning m = DxMorning(c);
      expect(m.minutes, hasLength(kDxMinutes + 1));
      for (int t = 0; t <= kDxMinutes; t++) {
        final DxMinute x = m.minutes[t];
        expect(x.inUse + x.waiting, x.devicesHere, reason: 't=$t');
        expect(x.bound, lessThanOrEqualTo(m.poolSize));
        final List<DxCell> cells = m.cellsAt(t);
        expect(cells.where((DxCell e) => e == DxCell.inUse).length, x.inUse);
        expect(
          cells.where((DxCell e) => e == DxCell.heldLeft).length,
          x.heldLeft,
        );
      }
    }
  });

  test('deterministic', () {
    final DxMorning a = DxMorning(const DxConfig(rotation: true));
    final DxMorning b = DxMorning(const DxConfig(rotation: true));
    for (int t = 0; t <= kDxMinutes; t++) {
      expect(a.minutes[t].bound, b.minutes[t].bound);
      expect(a.minutes[t].waiting, b.minutes[t].waiting);
    }
  });

  test('copyWith clamps', () {
    const DxConfig c = DxConfig();
    expect(c.copyWith(people: 1).people, kDxMinPeople);
    expect(c.copyWith(reserved: 999).reserved, kDxMaxReserved);
    expect(c.copyWith(rotatingShare: 2).rotatingShare, 1.0);
    expect(c.copyWith(rotationMinutes: 1).rotationMinutes, kDxMinRotation);
  });
}
