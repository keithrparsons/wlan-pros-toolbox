// BLIND REFERENCE VECTORS vs the shipped VLSM planner. Run 2026-09-17.
//
// Derived by Pax from the RFCs without sight of this repository. Brief:
//   Deliverables/2026-09-17-addressing-blind-vectors/VECTORS.md section 6
//
// Pax named C2 as the discriminating case before knowing anything about our
// implementation: parent 192.0.2.0/24 with requirements 126, 126, 2. The usable
// sum is 254 against a parent's 254, so a planner that checks feasibility by
// summing hosts says yes and then cannot allocate. Two /25 blocks consume all
// 256 addresses and the /30 has nowhere to go.
//
// All addresses are RFC 5737 documentation space.
//
// ONE DELIBERATE DIVERGENCE FROM THE BRIEF, recorded rather than smoothed over.
// Pax expected C2 to report feasible = false for the whole carve. This planner
// instead allocates what fits and reports the failing requirement with its
// reason, on the stated grounds that "failing the whole carve because the last
// VLAN overflowed would hide the four that fit" (ip_block_math.dart:596-598).
// That is a better answer than the brief asked for, and it satisfies the thing
// C2 was actually testing: the third requirement must NOT be given a block.
// The assertions below test that, not the flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ip_block_math.dart';

VlsmResult _carve(String parent, List<int> hosts) => IpBlockMath.vlsm(
      parentCidr: parent,
      requirementsText: hosts.join('\n'),
    );

List<String> _cidrs(VlsmResult r) => r.allocations
    .where((VlsmAllocation a) => a.isAllocated)
    .map((VlsmAllocation a) => a.block!.cidr)
    .toList();

void main() {
  test('C1: exact fit, seven subnets, zero waste', () {
    final VlsmResult r =
        _carve('192.0.2.0/24', <int>[126, 62, 30, 14, 6, 2, 2]);
    expect(r.isValid, isTrue, reason: r.error);
    expect(_cidrs(r), <String>[
      '192.0.2.0/25',
      '192.0.2.128/26',
      '192.0.2.192/27',
      '192.0.2.224/28',
      '192.0.2.240/29',
      '192.0.2.248/30',
      '192.0.2.252/30',
    ]);
    expect(r.freeAddresses, 0, reason: '128+64+32+16+8+4+4 = 256 exactly');
  });

  test('C2 THE DISCRIMINATOR: 126+126+2 must not all be allocated', () {
    final VlsmResult r = _carve('192.0.2.0/24', <int>[126, 126, 2]);
    expect(r.isValid, isTrue, reason: r.error);

    // The two /25s fit and consume the entire parent.
    expect(_cidrs(r), <String>['192.0.2.0/25', '192.0.2.128/25']);

    // The 2-host requirement is the one that cannot be placed, and the planner
    // must SAY so rather than silently dropping it or inventing space.
    final VlsmAllocation third =
        r.allocations.firstWhere((VlsmAllocation a) => a.requestedHosts == 2);
    expect(third.isAllocated, isFalse,
        reason: 'a naive sum-of-hosts feasibility check allocates here and is '
            'wrong: 254 usable fits in 254, but 128+128+4 does not fit in 256');
    expect(third.unallocatedReason, isNotNull);
    expect(third.unallocatedReason, isNotEmpty);

    expect(r.freeAddresses, 0);
  });

  test('C3: the easy infeasible case, which even a naive sum catches', () {
    final VlsmResult r = _carve('192.0.2.0/24', <int>[126, 62, 62, 30]);
    final Iterable<VlsmAllocation> unplaced =
        r.allocations.where((VlsmAllocation a) => !a.isAllocated);
    expect(unplaced, isNotEmpty, reason: '128+64+64+32 = 288 > 256');
  });

  test('C4 and C5: 254 fits the parent whole, 255 does not fit at all', () {
    final VlsmResult fits = _carve('192.0.2.0/24', <int>[254]);
    expect(_cidrs(fits), <String>['192.0.2.0/24']);
    expect(fits.freeAddresses, 0);

    final VlsmResult over = _carve('192.0.2.0/24', <int>[255]);
    expect(over.allocations.first.isAllocated, isFalse,
        reason: '255 usable needs a /23; this is C4 plus one');
  });

  test('C6: ascending input is still allocated largest first', () {
    // The order the user types is not the order the blocks can sit in.
    final VlsmResult r = _carve('192.0.2.0/24', <int>[2, 126, 62]);
    expect(_cidrs(r), <String>[
      '192.0.2.0/25',
      '192.0.2.128/26',
      '192.0.2.192/30',
    ]);
    expect(r.freeAddresses, 60, reason: '256 - 128 - 64 - 4 = 60');
  });

  test('C9: two /25s, the second exact-fit case', () {
    final VlsmResult r = _carve('192.0.2.0/24', <int>[126, 126]);
    expect(_cidrs(r), <String>['192.0.2.0/25', '192.0.2.128/25']);
    expect(r.freeAddresses, 0);
  });

  test('C10: a parent that is not on a /24 boundary is honored as given', () {
    final VlsmResult r = _carve('192.0.2.128/25', <int>[62, 30, 14]);
    expect(_cidrs(r), <String>[
      '192.0.2.128/26',
      '192.0.2.192/27',
      '192.0.2.224/28',
    ]);
    expect(r.freeAddresses, 16, reason: '128 - 64 - 32 - 16 = 16');
  });

  test('C11: host bits set on the parent are masked, not rejected', () {
    // RFC 4632 s3.1. Pax marked the masking-versus-refusing choice as her own
    // judgment; what must not happen is a wrong base address.
    final VlsmResult r = _carve('192.0.2.5/24', <int>[62]);
    expect(r.isValid, isTrue, reason: r.error);
    expect(r.parent?.cidr, '192.0.2.0/24');
    expect(_cidrs(r), <String>['192.0.2.0/26']);
  });
}
