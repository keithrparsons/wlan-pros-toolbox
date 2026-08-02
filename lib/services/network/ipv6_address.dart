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
  /// Accepts the RFC 4291 §2.2 form-3 literal with a trailing dotted quad
  /// (`::ffff:192.0.2.1`), folding it into two hex groups first. That form is
  /// legal IPv6 and is exactly how a mapped or NAT64 address is written in a
  /// log, so rejecting it was a defect, not a limitation.
  ///
  /// Throws [FormatException] on a malformed group layout (more than one "::",
  /// a "::" that fills no groups, a bad dotted tail). Does NOT validate that
  /// each remaining group is hex — callers check that, because the caller's
  /// error message is the useful one.
  static String expand(String literal) {
    final String addr = _foldIpv4Tail(literal);
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

  /// Rewrite a trailing dotted-quad tail as two hex groups, leaving anything
  /// without a tail untouched. `::ffff:192.0.2.1` becomes `::ffff:c000:0201`.
  static String _foldIpv4Tail(String addr) {
    final int lastColon = addr.lastIndexOf(':');
    if (lastColon < 0) return addr;
    final String tail = addr.substring(lastColon + 1);
    if (!tail.contains('.')) return addr;

    final List<String> octets = tail.split('.');
    if (octets.length != 4) {
      throw const FormatException('malformed IPv4 tail');
    }
    int value = 0;
    for (final String o in octets) {
      if (o.isEmpty || o.length > 3 || !RegExp(r'^\d+$').hasMatch(o)) {
        throw const FormatException('malformed IPv4 tail');
      }
      final int n = int.parse(o);
      if (n > 255) throw const FormatException('IPv4 tail octet above 255');
      value = (value << 8) | n;
    }
    String hex4(int v) => v.toRadixString(16).padLeft(4, '0');
    return '${addr.substring(0, lastColon + 1)}'
        '${hex4((value >> 16) & 0xFFFF)}:${hex4(value & 0xFFFF)}';
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
      // The head and tail are built EXPLICITLY around the "::" rather than
      // joined with a placeholder and tidied afterwards. An empty head or tail
      // is exactly what a leading or trailing "::" means, so there is nothing
      // to disambiguate. See [compressPwaParity] for why that distinction is
      // load-bearing.
      String strip(String? p) => BigInt.parse(p!, radix: 16).toRadixString(16);
      final String head = parts.sublist(0, bestStart).map(strip).join(':');
      final String tail = parts
          .sublist(bestStart + bestLen)
          .map(strip)
          .join(':');
      return '$head::$tail';
    }
    return parts
        .map((String? p) => BigInt.parse(p!, radix: 16).toRadixString(16))
        .join(':');
  }

  /// The HISTORICAL compressor, quirk included. Do not use in new code.
  ///
  /// ⚠ THIS FUNCTION PRODUCES TEXT THAT IS NOT A VALID IPv6 ADDRESS when the
  /// longest zero run touches either end of the address:
  ///
  ///     ::1                 →  1
  ///     2001:db8::          →  2001:db8
  ///     fe80::              →  fe80
  ///     ::ffff:c000:201     →  ffff:c000:201
  ///
  /// The cause is the `.replaceAll(RegExp(r'^:|:$'), '')` below: it cannot tell
  /// a join seam from the colon that IS the "::", so it eats half of it. The
  /// behavior is ported from the RF Tools PWA, and `Ipv6SubnetScreen` states a
  /// deliberate field-for-field parity contract with that PWA. Its tests name
  /// the defect out loud ("trailing-run quirk"), so this is a CHOSEN behavior
  /// and not an oversight, and unpicking it changes what a shipped screen
  /// prints. That is a direction call for Keith, not a build call, so this
  /// function preserves the behavior byte-for-byte while [compress] gives new
  /// code the RFC 5952 answer.
  ///
  /// The user-visible consequence, for whoever makes that call: the IPv6
  /// Subnetting screen's Network row currently reads `2001:db8/64` and
  /// `fe80/10`, neither of which is an address anything will accept.
  static String compressPwaParity(String full) {
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
