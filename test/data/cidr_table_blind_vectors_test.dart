// BLIND REFERENCE VECTORS vs the shipped CIDR table. Run 2026-09-17.
//
// The 2026-07-11 calculator audit did not clear this table. It never looked at
// it. That is not the same thing, and this file is the difference.
//
// PROVENANCE, which is the whole value: every expected value below was derived
// by Pax from the RFCs while FORBIDDEN from reading this repository. Pax did
// not know how the table was built, so these vectors cannot have been shaped to
// agree with it. Brief and clause-level pins:
//   Deliverables/2026-09-17-addressing-blind-vectors/VECTORS.md
//
// The rows were transcribed by a parser reading that brief's markdown table,
// not by hand. Hand-copying 132 values is where the errors would have entered.
//
// AUTHORITY NOTE, and it corrects a widely repeated belief. These counts are
// pinned to RFC 1122 s3.2.1.3 (part of STD 3), NOT to RFC 1878. Pax found that
// RFC 1878 is Informational, carries no usable-host column at all, has no /0
// row, and has an open erratum (ID 3147) against its subnet table. It is used
// here only as an independent cross-check on netmask and total columns.
//
// The two rows a naive 2^(32-n)-2 formula gets wrong are /31 and /32, where it
// prints 0 and -1. RFC 3021 s2.1: in a point-to-point link with a 31-bit mask
// the two addresses MUST be interpreted as host addresses.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cidr_table_screen.dart';

class _V {
  const _V(this.prefix, this.netmask, this.wildcard, this.total, this.usable);
  final int prefix;
  final String netmask;
  final String wildcard;
  final int total;
  final int usable;
}

const List<_V> _vectors = <_V>[
    _V(0, '0.0.0.0', '255.255.255.255', 4294967296, 4294967294),
    _V(1, '128.0.0.0', '127.255.255.255', 2147483648, 2147483646),
    _V(2, '192.0.0.0', '63.255.255.255', 1073741824, 1073741822),
    _V(3, '224.0.0.0', '31.255.255.255', 536870912, 536870910),
    _V(4, '240.0.0.0', '15.255.255.255', 268435456, 268435454),
    _V(5, '248.0.0.0', '7.255.255.255', 134217728, 134217726),
    _V(6, '252.0.0.0', '3.255.255.255', 67108864, 67108862),
    _V(7, '254.0.0.0', '1.255.255.255', 33554432, 33554430),
    _V(8, '255.0.0.0', '0.255.255.255', 16777216, 16777214),
    _V(9, '255.128.0.0', '0.127.255.255', 8388608, 8388606),
    _V(10, '255.192.0.0', '0.63.255.255', 4194304, 4194302),
    _V(11, '255.224.0.0', '0.31.255.255', 2097152, 2097150),
    _V(12, '255.240.0.0', '0.15.255.255', 1048576, 1048574),
    _V(13, '255.248.0.0', '0.7.255.255', 524288, 524286),
    _V(14, '255.252.0.0', '0.3.255.255', 262144, 262142),
    _V(15, '255.254.0.0', '0.1.255.255', 131072, 131070),
    _V(16, '255.255.0.0', '0.0.255.255', 65536, 65534),
    _V(17, '255.255.128.0', '0.0.127.255', 32768, 32766),
    _V(18, '255.255.192.0', '0.0.63.255', 16384, 16382),
    _V(19, '255.255.224.0', '0.0.31.255', 8192, 8190),
    _V(20, '255.255.240.0', '0.0.15.255', 4096, 4094),
    _V(21, '255.255.248.0', '0.0.7.255', 2048, 2046),
    _V(22, '255.255.252.0', '0.0.3.255', 1024, 1022),
    _V(23, '255.255.254.0', '0.0.1.255', 512, 510),
    _V(24, '255.255.255.0', '0.0.0.255', 256, 254),
    _V(25, '255.255.255.128', '0.0.0.127', 128, 126),
    _V(26, '255.255.255.192', '0.0.0.63', 64, 62),
    _V(27, '255.255.255.224', '0.0.0.31', 32, 30),
    _V(28, '255.255.255.240', '0.0.0.15', 16, 14),
    _V(29, '255.255.255.248', '0.0.0.7', 8, 6),
    _V(30, '255.255.255.252', '0.0.0.3', 4, 2),
    _V(31, '255.255.255.254', '0.0.0.1', 2, 2),
    _V(32, '255.255.255.255', '0.0.0.0', 1, 1),];

void main() {
  test('the table has all 33 rows, /0 through /32, with no gaps', () {
    // Pax's execution note: "If the shipped table has no /0 row and no /31 row,
    // that is a finding in itself and not a pass."
    expect(CidrTableScreen.rows.length, 33);
    expect(
      CidrTableScreen.rows.map((CidrRow r) => r.prefix).toList(),
      List<int>.generate(33, (int i) => i),
    );
  });

  group('132 blind assertions: 33 rows x 4 columns', () {
    for (final _V v in _vectors) {
      test('/${v.prefix}', () {
        final CidrRow r = CidrTableScreen.rows
            .firstWhere((CidrRow x) => x.prefix == v.prefix);
        expect(r.mask, v.netmask, reason: 'netmask at /${v.prefix}');
        expect(r.wildcard, v.wildcard, reason: 'wildcard at /${v.prefix}');
        expect(r.total, v.total, reason: 'total at /${v.prefix}');
        expect(r.usableHosts, v.usable, reason: 'usable hosts at /${v.prefix}');
      });
    }
  });

  test('/31 and /32 carry their exception note, not a bare number', () {
    // The number being right is not enough. A reader who sees "2 usable" at /31
    // with no explanation will assume the table is broken, because every other
    // row is total-minus-two. The note is what makes the right number credible.
    for (final int p in <int>[31, 32]) {
      final CidrRow r =
          CidrTableScreen.rows.firstWhere((CidrRow x) => x.prefix == p);
      expect(r.usableNote, isNotNull, reason: '/$p has no usableNote');
      expect(r.usableNote, isNotEmpty);
    }
  });
}
