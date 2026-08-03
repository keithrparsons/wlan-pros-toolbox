// IpBlockMath unit tests — range ⇄ CIDR, VLSM allocation, and summarization.
//
// EXPECTED VALUES, WORKED BY HAND BEFORE THE ASSERTIONS WERE WRITTEN.
//
// ── prefixForHosts (classic reservation: network + broadcast) ──────────────
//   1 → /32 (single host route)   2 → /30 (2 usable)    3 → /29 (6 usable)
//   254 → /24                     255 → /23             500 → /23 (510)
//   510 → /23                     511 → /22             0 → null
//   4,294,967,294 → /0            4,294,967,295 → null (IPv4 has no such block)
//
// ── rangeToCidr ────────────────────────────────────────────────────────────
//   10.4.16.0 .. 10.4.31.255      → 10.4.16.0/20  (exactly aligned, ONE block)
//   192.168.1.1 .. 192.168.1.6    → 192.168.1.1/32, 192.168.1.2/31,
//                                    192.168.1.4/31, 192.168.1.6/32
//                                    (a range that is NOT CIDR-aligned; the
//                                     honest answer is four blocks, not an
//                                     error and not a wrong single block)
//   10.0.0.5 .. 10.0.0.5          → 10.0.0.5/32
//   0.0.0.0 .. 255.255.255.255    → 0.0.0.0/0     (the 2^32 case)
//   start > end                   → [] (the caller writes the message)
//
// ── VLSM: parent 10.20.0.0/22 (1024 addresses, 10.20.0.0–10.20.3.255) ──────
//   Staff 500 → /23  10.20.0.0/23    first 10.20.0.1  last 10.20.1.254
//   Guest 200 → /24  10.20.2.0/24    first 10.20.2.1  last 10.20.2.254
//   IoT   100 → /25  10.20.3.0/25    first 10.20.3.1  last 10.20.3.126
//   PtP     2 → /30  10.20.3.128/30  first 10.20.3.129 last 10.20.3.130
//   used 512+256+128+4 = 900, free 124
//   free blocks 10.20.3.132/30, .136/29, .144/28, .160/27, .192/26
//              (4 + 8 + 16 + 32 + 64 = 124 ✓)
//
// ── Summarization ─────────────────────────────────────────────────────────
//   10.0.0.0/24 + 10.0.1.0/24  → supernet 10.0.0.0/23, exact [10.0.0.0/23],
//                                 extra 0
//   10.0.0.0/25 + 10.0.0.128/25 → the classic pair, exact [10.0.0.0/24]
//   10.0.0.0/24 + 10.0.0.128/25 → overlapping, counted once: exact
//                                 [10.0.0.0/24], covered 256
//   10.0.0.0/24 + 10.0.3.0/24  → supernet 10.0.0.0/22 (1024), covered 512,
//                                 EXTRA 512, gaps [10.0.1.0/24, 10.0.2.0/24]
//   10.0.0.0/8 + 192.168.0.0/16 → supernet 0.0.0.0/0, covered 16,842,752,
//                                 extra 4,278,124,544
//
// EDGES DELIBERATELY COVERED (not the happy path): a /31 and a /32 in the
// output rows, a range that is not CIDR-aligned, the whole 2^32 space, a
// requirement bigger than the parent, a requirement that overflows the parent
// after others fit, host bits set on an input network, a bare address read as
// a /32, overlapping inputs, adjacent inputs, and a per-line parse error that
// must not take the whole list down with it.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ip_block_math.dart';
import 'package:wlan_pros_toolbox/services/network/subnet_calc_service.dart';

int _ip(String s) => SubnetCalcService.parseIpv4ToInt(s)!;

List<String> _cidrs(List<Ipv4Block> b) =>
    b.map((Ipv4Block x) => x.cidr).toList();

void main() {
  group('prefixForHosts', () {
    test('classic reservation, boundary by boundary', () {
      expect(IpBlockMath.prefixForHosts(1), 32);
      expect(IpBlockMath.prefixForHosts(2), 30);
      expect(IpBlockMath.prefixForHosts(3), 29);
      expect(IpBlockMath.prefixForHosts(254), 24);
      expect(IpBlockMath.prefixForHosts(255), 23);
      expect(IpBlockMath.prefixForHosts(500), 23);
      expect(IpBlockMath.prefixForHosts(510), 23);
      expect(IpBlockMath.prefixForHosts(511), 22);
    });

    test('rejects zero and anything IPv4 cannot hold', () {
      expect(IpBlockMath.prefixForHosts(0), isNull);
      expect(IpBlockMath.prefixForHosts(-1), isNull);
      expect(IpBlockMath.prefixForHosts(4294967294), 0);
      expect(IpBlockMath.prefixForHosts(4294967295), isNull);
    });
  });

  group('rangeToCidr', () {
    test('an exactly-aligned range is one block', () {
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.4.16.0'), _ip('10.4.31.255'))),
        <String>['10.4.16.0/20'],
      );
    });

    test('a range that is NOT CIDR-aligned yields the minimal set', () {
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('192.168.1.1'), _ip('192.168.1.6'))),
        <String>[
          '192.168.1.1/32',
          '192.168.1.2/31',
          '192.168.1.4/31',
          '192.168.1.6/32',
        ],
      );
    });

    test('a single address is a /32', () {
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.0.0.5'), _ip('10.0.0.5'))),
        <String>['10.0.0.5/32'],
      );
    });

    test('the whole address space is one /0 (the 2^32 case)', () {
      final List<Ipv4Block> b = IpBlockMath.rangeToCidr(
        _ip('0.0.0.0'),
        _ip('255.255.255.255'),
      );
      expect(_cidrs(b), <String>['0.0.0.0/0']);
      expect(b.single.size, 4294967296);
    });

    test('a reversed range yields nothing rather than a wrong answer', () {
      expect(
        IpBlockMath.rangeToCidr(_ip('10.0.0.10'), _ip('10.0.0.1')),
        isEmpty,
      );
    });

    // THE BROADCAST BOUNDARY. 10.0.0.254 is the last usable host of a /24,
    // 10.0.0.255 is that /24's broadcast, and 10.0.1.0 is the next network
    // address. A range written across those three is the everyday case when
    // someone hands you "everything from here to there" out of a DHCP scope
    // or a firewall object, and it is where an off-by-one shows up first.
    // rangeToCidr works on the address space and does not treat network or
    // broadcast addresses as special, which is the correct behavior here: the
    // caller asked which blocks COVER these addresses, not which of them a
    // host may be assigned.
    test('a range straddling a broadcast boundary is covered exactly', () {
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.0.0.254'), _ip('10.0.1.1'))),
        <String>['10.0.0.254/31', '10.0.1.0/31'],
      );
      // And the asymmetric version, which cannot pair up so neatly.
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.0.0.255'), _ip('10.0.1.0'))),
        <String>['10.0.0.255/32', '10.0.1.0/32'],
        reason: 'a broadcast and the next network address are not adjacent '
            'under alignment, so they cannot merge into one /31',
      );
    });

    test('an exact /31 and an exact /30 each collapse to one block', () {
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.0.0.4'), _ip('10.0.0.5'))),
        <String>['10.0.0.4/31'],
      );
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.0.0.4'), _ip('10.0.0.7'))),
        <String>['10.0.0.4/30'],
      );
      // Shifted off its boundary by one, the same span cannot be one block.
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('10.0.0.5'), _ip('10.0.0.6'))),
        <String>['10.0.0.5/32', '10.0.0.6/32'],
      );
    });

    // THE TOP OF THE SPACE. The walk advances with `cur += sizeOfPrefix(...)`,
    // so a range ending at 255.255.255.255 pushes the cursor to 2^32, one past
    // anything 32 bits can hold. The loop must end on the `cur <= end` test
    // before that value ever reaches a bitwise operator, because bitwise ops
    // are 32-bit on the web build and 2^32 masks down to 0 there — which would
    // restart the walk at 0.0.0.0 and hang. This asserts termination as much
    // as it asserts the answer.
    test('a range that ends at 255.255.255.255 terminates and is exact', () {
      expect(
        _cidrs(
          IpBlockMath.rangeToCidr(
            _ip('255.255.255.250'),
            _ip('255.255.255.255'),
          ),
        ),
        <String>['255.255.255.250/31', '255.255.255.252/30'],
      );
      expect(
        _cidrs(
          IpBlockMath.rangeToCidr(
            _ip('255.255.255.255'),
            _ip('255.255.255.255'),
          ),
        ),
        <String>['255.255.255.255/32'],
      );
      // The bottom of the space, for the same reason at the other end.
      expect(
        _cidrs(IpBlockMath.rangeToCidr(_ip('0.0.0.0'), _ip('0.0.0.0'))),
        <String>['0.0.0.0/32'],
      );
    });

    test('the blocks tile the range exactly, with no gap and no overlap', () {
      final List<Ipv4Block> b = IpBlockMath.rangeToCidr(
        _ip('172.16.5.3'),
        _ip('172.16.9.200'),
      );
      int cursor = _ip('172.16.5.3');
      for (final Ipv4Block block in b) {
        expect(block.network, cursor);
        cursor = block.lastAddress + 1;
      }
      expect(cursor - 1, _ip('172.16.9.200'));
    });
  });

  group('parseNetworkList', () {
    test('the four accepted shapes all parse', () {
      final List<ParsedNetworkLine> l = IpBlockMath.parseNetworkList(
        '10.0.0.0/24\n'
        '10.0.1.0 255.255.255.0\n'
        '10.0.2.0/255.255.255.0\n'
        '10.0.3.5\n',
      );
      expect(l.map((ParsedNetworkLine x) => x.block?.cidr).toList(), <String>[
        '10.0.0.0/24',
        '10.0.1.0/24',
        '10.0.2.0/24',
        '10.0.3.5/32',
      ]);
    });

    test('blank lines, # comments, and comma-separated entries', () {
      final List<ParsedNetworkLine> l = IpBlockMath.parseNetworkList(
        '# site A\n\n10.0.0.0/24, 10.0.1.0/24\n\n',
      );
      expect(l.length, 2);
      expect(l.every((ParsedNetworkLine x) => x.error == null), isTrue);
    });

    test('host bits are masked off AND flagged, never silently changed', () {
      final ParsedNetworkLine l = IpBlockMath.parseNetworkList(
        '10.0.0.37/24',
      ).single;
      expect(l.block!.cidr, '10.0.0.0/24');
      expect(l.hostBitsWereSet, isTrue);
    });

    test('a bad line carries its own line number and does not sink the '
        'good ones', () {
      final List<ParsedNetworkLine> l = IpBlockMath.parseNetworkList(
        '10.0.0.0/24\n'
        '10.0.999.0/24\n'
        '10.0.2.0/33\n'
        '10.0.3.0/255.0.255.0\n'
        '10.0.4.0/24\n',
      );
      expect(l.length, 5);
      expect(l[0].error, isNull);
      expect(l[1].error, contains('not a valid IPv4 address'));
      expect(l[1].lineNumber, 2);
      expect(l[2].error, contains('0 to 32'));
      expect(l[3].error, contains('contiguous'));
      expect(l[4].error, isNull);
    });
  });

  group('parseRequirements', () {
    test('name and count in the shapes a person types', () {
      final List<
        ({int lineNumber, String raw, String? name, int? hosts, String? error})
      >
      r = IpBlockMath.parseRequirements(
        'Staff 500\n'
        'Guest,200\n'
        'IoT: 100\n'
        '50\n'
        'Floor 3 AV 40\n',
      );
      expect(r.map((dynamic x) => x.name).toList(), <String>[
        'Staff',
        'Guest',
        'IoT',
        'Subnet 4',
        'Floor 3 AV',
      ]);
      expect(r.map((dynamic x) => x.hosts).toList(), <int>[
        500,
        200,
        100,
        50,
        40,
      ]);
    });

    test('a line with no count, and a count of zero, are both rejected', () {
      final List<
        ({int lineNumber, String raw, String? name, int? hosts, String? error})
      >
      r = IpBlockMath.parseRequirements('Staff\n0\n');
      expect(r[0].error, contains('host count'));
      expect(r[1].error, contains('at least 1 host'));
    });
  });

  group('VLSM', () {
    test(
      'the worked example carves largest-first and reports the leftover',
      () {
        final VlsmResult r = IpBlockMath.vlsm(
          parentCidr: '10.20.0.0/22',
          requirementsText: 'Staff 500\nGuest 200\nIoT 100\nPtP 2\n',
        );
        expect(r.isValid, isTrue);
        expect(r.parent!.cidr, '10.20.0.0/22');
        expect(r.allocations.length, 4);

        expect(r.allocations[0].name, 'Staff');
        expect(r.allocations[0].block!.cidr, '10.20.0.0/23');
        expect(r.allocations[0].block!.firstHost, '10.20.0.1');
        expect(r.allocations[0].block!.lastHost, '10.20.1.254');
        expect(r.allocations[0].block!.broadcast, '10.20.1.255');
        expect(r.allocations[0].block!.usableHosts, 510);

        expect(r.allocations[1].block!.cidr, '10.20.2.0/24');
        expect(r.allocations[2].block!.cidr, '10.20.3.0/25');
        expect(r.allocations[2].block!.lastHost, '10.20.3.126');

        // The point-to-point link: a /30, with 2 usable and a real broadcast.
        expect(r.allocations[3].block!.cidr, '10.20.3.128/30');
        expect(r.allocations[3].block!.usableHosts, 2);
        expect(r.allocations[3].block!.firstHost, '10.20.3.129');
        expect(r.allocations[3].block!.lastHost, '10.20.3.130');
        expect(r.allocations[3].block!.broadcast, '10.20.3.131');

        expect(r.usedAddresses, 900);
        expect(r.freeAddresses, 124);
        expect(_cidrs(r.freeBlocks), <String>[
          '10.20.3.132/30',
          '10.20.3.136/29',
          '10.20.3.144/28',
          '10.20.3.160/27',
          '10.20.3.192/26',
        ]);
        // The free blocks add up to the free count.
        expect(
          r.freeBlocks.fold<int>(0, (int a, Ipv4Block b) => a + b.size),
          124,
        );
      },
    );

    test('input order does not matter: the carve sorts largest first', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '10.20.0.0/22',
        requirementsText: 'PtP 2\nIoT 100\nStaff 500\nGuest 200\n',
      );
      expect(
        _cidrs(r.allocations.map((VlsmAllocation a) => a.block!).toList()),
        <String>[
          '10.20.0.0/23',
          '10.20.2.0/24',
          '10.20.3.0/25',
          '10.20.3.128/30',
        ],
      );
    });

    test('a 2-host request raises the RFC 3021 note, and only then', () {
      final VlsmResult withPtp = IpBlockMath.vlsm(
        parentCidr: '10.0.0.0/24',
        requirementsText: 'PtP 2\n',
      );
      expect(withPtp.notes.single, contains('RFC 3021'));

      final VlsmResult without = IpBlockMath.vlsm(
        parentCidr: '10.0.0.0/24',
        requirementsText: 'Staff 100\n',
      );
      expect(without.notes, isEmpty);
    });

    test('a 1-host request gets a /32 and says what that costs', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '10.0.0.0/24',
        requirementsText: 'Loopback 1\n',
      );
      expect(r.allocations.single.block!.cidr, '10.0.0.0/32');
      expect(r.allocations.single.block!.usableHosts, 1);
      expect(r.notes.single, contains('no room for a gateway'));
    });

    test('a requirement bigger than the parent is refused BY NAME, and the '
        'ones that fit still compute', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '192.168.1.0/24',
        requirementsText: 'Campus 500\nOffice 100\n',
      );
      expect(r.isValid, isTrue);
      expect(r.allocations[0].name, 'Campus');
      expect(r.allocations[0].isAllocated, isFalse);
      expect(r.allocations[0].unallocatedReason, contains('needs a /23'));
      expect(r.allocations[0].unallocatedReason, contains('only a /24'));
      // The one that fits is still placed.
      expect(r.allocations[1].block!.cidr, '192.168.1.0/25');
    });

    test('a requirement that overflows AFTER others fit says the block ran '
        'out', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '192.168.1.0/24',
        requirementsText: 'A 200\nB 100\n',
      );
      expect(r.allocations[0].block!.cidr, '192.168.1.0/24');
      expect(r.allocations[1].isAllocated, isFalse);
      expect(r.allocations[1].unallocatedReason, contains('ran out'));
      expect(r.freeBlocks, isEmpty);
      expect(r.freeAddresses, 0);
    });

    test('a /32 parent still carves and leaves nothing', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '10.0.0.7/32',
        requirementsText: '1\n',
      );
      expect(r.allocations.single.block!.cidr, '10.0.0.7/32');
      expect(r.freeBlocks, isEmpty);
    });

    test('no requirements yet: the whole parent is free, not an error', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '10.20.0.0/22',
        requirementsText: '',
      );
      expect(r.isValid, isTrue);
      expect(r.allocations, isEmpty);
      expect(_cidrs(r.freeBlocks), <String>['10.20.0.0/22']);
      expect(r.freeAddresses, 1024);
    });

    test('a bad requirement line is reported with its line number and the '
        'rest still allocate', () {
      final VlsmResult r = IpBlockMath.vlsm(
        parentCidr: '10.20.0.0/22',
        requirementsText: 'Staff 500\nnope\nGuest 200\n',
      );
      expect(r.lineErrors.single.lineNumber, 2);
      expect(r.allocations.length, 2);
    });

    test('an empty or malformed parent is a whole-form error', () {
      expect(
        IpBlockMath.vlsm(parentCidr: '', requirementsText: '100').error,
        contains('carving up'),
      );
      expect(
        IpBlockMath.vlsm(
          parentCidr: '10.0.0.0/24\n10.0.1.0/24',
          requirementsText: '100',
        ).error,
        contains('one parent block'),
      );
      expect(
        IpBlockMath.vlsm(
          parentCidr: '10.0.0.999/24',
          requirementsText: '100',
        ).error,
        contains('not a valid IPv4 address'),
      );
    });
  });

  group('summarize', () {
    test('two adjacent /24s summarize exactly, with no over-coverage', () {
      final SummaryResult r = IpBlockMath.summarize('10.0.0.0/24\n10.0.1.0/24');
      expect(r.isValid, isTrue);
      expect(r.supernet!.cidr, '10.0.0.0/23');
      expect(_cidrs(r.exactBlocks), <String>['10.0.0.0/23']);
      expect(r.coveredAddresses, 512);
      expect(r.extraAddresses, 0);
      expect(r.extraBlocks, isEmpty);
    });

    test('the classic pair of /25s becomes one /24', () {
      final SummaryResult r = IpBlockMath.summarize(
        '10.0.0.0/25\n10.0.0.128/25',
      );
      expect(_cidrs(r.exactBlocks), <String>['10.0.0.0/24']);
      expect(r.extraAddresses, 0);
    });

    test('overlapping inputs are counted once, not twice', () {
      final SummaryResult r = IpBlockMath.summarize(
        '10.0.0.0/24\n10.0.0.128/25',
      );
      expect(r.coveredAddresses, 256);
      expect(_cidrs(r.exactBlocks), <String>['10.0.0.0/24']);
    });

    test('a gapped pair: the supernet covers 512 addresses NOBODY asked for, '
        'and the gaps are enumerated', () {
      final SummaryResult r = IpBlockMath.summarize('10.0.0.0/24\n10.0.3.0/24');
      expect(r.supernet!.cidr, '10.0.0.0/22');
      expect(r.supernetAddresses, 1024);
      expect(r.coveredAddresses, 512);
      expect(r.extraAddresses, 512);
      expect(_cidrs(r.extraBlocks), <String>['10.0.1.0/24', '10.0.2.0/24']);
      expect(_cidrs(r.exactBlocks), <String>['10.0.0.0/24', '10.0.3.0/24']);
    });

    test('two far-apart networks collapse to a default route, which is the '
        'whole point of showing the extra count', () {
      final SummaryResult r = IpBlockMath.summarize(
        '10.0.0.0/8\n192.168.0.0/16',
      );
      expect(r.supernet!.cidr, '0.0.0.0/0');
      expect(r.supernetAddresses, 4294967296);
      expect(r.coveredAddresses, 16842752);
      expect(r.extraAddresses, 4278124544);
    });

    test('one network summarizes to itself', () {
      final SummaryResult r = IpBlockMath.summarize('192.168.5.0/24');
      expect(r.supernet!.cidr, '192.168.5.0/24');
      expect(_cidrs(r.exactBlocks), <String>['192.168.5.0/24']);
      expect(r.extraAddresses, 0);
      expect(r.extraBlocks, isEmpty);
    });

    test('the whole space as an input does not overflow', () {
      final SummaryResult r = IpBlockMath.summarize('0.0.0.0/0\n10.0.0.0/8');
      expect(r.supernet!.cidr, '0.0.0.0/0');
      expect(r.coveredAddresses, 4294967296);
      expect(r.extraAddresses, 0);
    });

    test('order of the input lines does not change the answer', () {
      final SummaryResult a = IpBlockMath.summarize('10.0.3.0/24\n10.0.0.0/24');
      final SummaryResult b = IpBlockMath.summarize('10.0.0.0/24\n10.0.3.0/24');
      expect(a.supernet, b.supernet);
      expect(_cidrs(a.exactBlocks), _cidrs(b.exactBlocks));
      expect(a.extraAddresses, b.extraAddresses);
    });

    test('nothing valid yet is an error, not an empty success', () {
      expect(IpBlockMath.summarize('').isValid, isFalse);
      final SummaryResult r = IpBlockMath.summarize('nonsense');
      expect(r.isValid, isFalse);
      expect(r.lineErrors, isNotEmpty);
    });

    test('a bad line is reported but the good lines still summarize', () {
      final SummaryResult r = IpBlockMath.summarize(
        '10.0.0.0/24\nnope\n10.0.1.0/24',
      );
      expect(r.isValid, isTrue);
      expect(r.lineErrors.single.lineNumber, 2);
      expect(r.supernet!.cidr, '10.0.0.0/23');
    });
  });
}
