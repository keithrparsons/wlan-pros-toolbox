// Ipv6Address — the pure IPv6 text/number primitives, in ONE place.
//
// WHY THIS FILE EXISTS: expand / compress / 128-bit packing were static methods
// on `Ipv6SubnetScreen`. Three new features need them off a widget — the MAC
// bit decoder (to render an EUI-64 link-local), the IPv6 transition-address
// decoder, and their unit tests. Rather than copy the algorithms and let two
// definitions drift, the bodies moved HERE verbatim and the screen's statics
// became thin delegates. This is the same extraction the throughput calculator
// made to `WifiPhyRateService` (see that screen's header): one definition, the
// old call sites unchanged.
//
// Provenance of the algorithms is unchanged — they mirror the RF Tools PWA
// (app.js expandIPv6 / compressIPv6 / bigToFull, line 2155+), so the native app
// and the PWA agree text-for-text.
//
// PURE: no Flutter, no dart:io, no I/O. Every function is total or throws
// [FormatException] with a reason; nothing here can block or fail silently.

/// Pure IPv6 address text and 128-bit integer helpers.
class Ipv6Address {
  const Ipv6Address._();

  /// All 128 bits set.
  static final BigInt mask128 = (BigInt.one << 128) - BigInt.one;

  /// The low 64 bits set.
  static final BigInt mask64 = (BigInt.one << 64) - BigInt.one;

  /// Expand an IPv6 literal to its full 8-group, 4-hex-digit form.
  ///
  /// Throws [FormatException] on a malformed group layout (more than one "::",
  /// a "::" that fills no groups). Does NOT validate that each group is hex —
  /// callers check that, because the caller's error message is the useful one.
  static String expand(String addr) {
    if (addr.contains('::')) {
      // Reject more than one "::" — a split on "::" would silently keep the
      // first two parts and answer a question the user did not ask.
      if ('::'.allMatches(addr).length != 1) {
        throw const FormatException('multiple "::" runs');
      }
      final List<String> halves = addr.split('::');
      final List<String> left = halves[0].isEmpty
          ? <String>[]
          : halves[0].split(':');
      final List<String> right = halves[1].isEmpty
          ? <String>[]
          : halves[1].split(':');
      final int missing = 8 - left.length - right.length;
      if (missing < 1) {
        throw const FormatException('"::" with no zero groups to fill');
      }
      final List<String> mid = List<String>.filled(missing, '0000');
      return <String>[
        ...left,
        ...mid,
        ...right,
      ].map((String g) => g.padLeft(4, '0')).join(':');
    }
    return addr.split(':').map((String g) => g.padLeft(4, '0')).join(':');
  }

  /// Compress a full 8-group form to canonical "::" notation, collapsing the
  /// LONGEST run of all-zero groups (a run of one is never collapsed, per
  /// RFC 5952 §4.2.2).
  static String compress(String full) {
    List<String?> parts = full.split(':').cast<String?>();
    int bestStart = -1, bestLen = 0;
    int curStart = -1, curLen = 0;
    for (int i = 0; i < parts.length; i++) {
      if (parts[i] == '0000') {
        if (curStart < 0) {
          curStart = i;
          curLen = 1;
        } else {
          curLen++;
        }
        if (curLen > bestLen) {
          bestStart = curStart;
          bestLen = curLen;
        }
      } else {
        curStart = -1;
        curLen = 0;
      }
    }

    if (bestLen > 1) {
      parts = <String?>[
        ...parts.sublist(0, bestStart),
        null,
        ...parts.sublist(bestStart + bestLen),
      ];
      final String joined = parts
          .map(
            (String? p) =>
                p == null ? '' : BigInt.parse(p, radix: 16).toRadixString(16),
          )
          .join(':')
          .replaceAll(RegExp(r'^:|:$'), '')
          .replaceFirst(':::', '::');
      return joined.isEmpty ? '::' : joined;
    }
    return parts
        .map((String? p) => BigInt.parse(p!, radix: 16).toRadixString(16))
        .join(':');
  }

  /// Render a 128-bit value to the full 8-group form.
  static String fromBigInt(BigInt n) {
    final BigInt hi = (n >> 64) & mask64;
    final BigInt lo = n & mask64;
    String toHex(BigInt v) {
      final String s = v.toRadixString(16).padLeft(16, '0');
      return <String>[
        s.substring(0, 4),
        s.substring(4, 8),
        s.substring(8, 12),
        s.substring(12, 16),
      ].join(':');
    }

    return '${toHex(hi)}:${toHex(lo)}';
  }

  /// Parse an already-expanded 8-group form to a 128-bit BigInt.
  static BigInt toBigInt(String expanded) {
    final List<String> parts = expanded.split(':');
    BigInt v = BigInt.zero;
    for (final String p in parts) {
      v = (v << 16) | BigInt.parse(p, radix: 16);
    }
    return v;
  }
}
