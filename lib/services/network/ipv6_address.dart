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
// and the PWA agree text-for-text, with one ruled exception:
//
// KEITH'S RULING, 2026-08-02 — ONE COMPRESSOR, AND IT IS THE RFC-CORRECT ONE.
// This file used to carry a second compressor, `compressPwaParity`, which
// reproduced the PWA's behavior of dropping half the "::" whenever the longest
// zero run touched either end of the address ("::1" → "1", "fe80::" → "fe80",
// "::ffff:c000:201" → "ffff:c000:201"). Its dartdoc parked the question as "a
// direction call for Keith, not a build call" and nothing routed it, so the
// IPv6 Subnet screen shipped rows that are not addresses while the transition
// and MAC surfaces on the SAME screen printed the correct form. Vera's gate
// pasted the screen's own Compressed row back into its own field and the app
// answered "Invalid IPv6 address format"
// (Deliverables/2026-08-02-ip-address-math-gate/, HIGH-1).
//
// Keith ruled: switch the Subnet card to [compress]. The parity function had no
// callers left, so it was DELETED rather than left loaded in the drawer. Text
// parity with the PWA is not claimed for compression; the PWA's strings were
// the defect. A decision parked in a dartdoc is invisible to every queue this
// team has, so it is recorded here and in the session log, not in a comment on
// a function nobody reads.
//
// PURE: no Flutter, no dart:io, no I/O. Every function is total or throws
// [FormatException] with a reason; nothing here can block or fail silently.

/// How the text after a "%" was read, and whether the text supports a second
/// reading. A zone index is either a NAME (`en0`, BSD and macOS) or a NUMERIC
/// ifindex (`12`, Windows), and RFC 6874 writes the "%" itself as "%25" inside
/// a URI. Those two conventions collide, and no amount of parsing resolves the
/// collision from the text alone.
///
/// This enum exists so the ambiguity can be CARRIED rather than swallowed. A
/// plain `String?` cannot say "this is one of two readings", so a screen given
/// only a `String?` has no choice but to print a guess as a fact
/// ([[feedback_type_must_express_unknown]]).
enum Ipv6ZoneReading {
  /// One reading only: a name, or digits that cannot be an RFC 6874 escape.
  certain,

  /// A bare `%25`. Read as ifindex 25 — but `%25` is also the URI spelling of
  /// `%`, so the literal may be one whose zone name was truncated away.
  bareTwentyFive,

  /// `%25` followed by digits (`%2512`). Read as the URI escape, so the zone
  /// is `12` — but it is equally a plain ifindex `2512` typed outside a URI.
  escapedDigits,
}

/// A parsed zone index and the reading it rests on.
class Ipv6Zone {
  const Ipv6Zone({
    required this.value,
    required this.reading,
    this.alternate,
  });

  /// The zone as this parser reads it. Display-only: a zone is not part of the
  /// 128 bits, so no computed value depends on which reading is right.
  final String value;

  /// Which reading produced [value], and whether a second one exists.
  final Ipv6ZoneReading reading;

  /// The competing zone text, when the other reading also names a zone.
  /// Null for [Ipv6ZoneReading.certain] (there is no other reading) and for
  /// [Ipv6ZoneReading.bareTwentyFive] (the other reading has no zone at all).
  final String? alternate;

  /// True when the text supports exactly one reading.
  bool get isCertain => reading == Ipv6ZoneReading.certain;
}

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
  /// Also accepts and STRIPS a zone index (`fe80::1%en0`, RFC 4007 §11.2) for
  /// the same reason. See [zoneOf] for why stripping is lossless here and how
  /// to recover the zone for display.
  ///
  /// Throws [FormatException] on a malformed group layout (more than one "::",
  /// a "::" that fills no groups, a bad dotted tail, an empty or repeated zone
  /// index). Does NOT validate that each remaining group is hex — callers check
  /// that, because the caller's error message is the useful one.
  static String expand(String literal) {
    final String addr = _foldIpv4Tail(_stripZone(literal));
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

  /// The zone index on a literal, or null when there is none.
  ///
  /// A zone index (RFC 4007 §11.2) is the `%en0` a link-local address wears in
  /// `ifconfig`, `ip -6 addr`, a macOS log line, or a copied link-local URL. It
  /// names the LOCAL INTERFACE the scope is relative to. It is not part of the
  /// 128 bits, so `fe80::1%en0` and `fe80::1` are the same address and
  /// stripping it cannot change any computed answer.
  ///
  /// Both spellings are handled: the bare `%en0`, and the `%25en0` that RFC
  /// 6874 requires inside a URI (`%25` is a percent-encoded `%`). The returned
  /// zone is the decoded one, so both give `en0`.
  ///
  /// It is NOT discarded silently at the UI layer — the IPv6 screen renders it
  /// on its own row, so a user who typed a zone can see the tool read it.
  ///
  /// STATED AMBIGUITY, because it cannot be resolved from the text alone. See
  /// [Ipv6ZoneReading]. This returns only the reading the parser uses; call
  /// [zoneParse] when the caller has to SHOW the value, so the second reading
  /// travels with it instead of being dropped on the floor.
  ///
  /// Throws [FormatException] on an empty zone (`fe80::1%`, a truncated log
  /// line or a user mid-keystroke) or more than one `%`. Neither is "no zone";
  /// both are a question that was not finished being asked.
  static String? zoneOf(String literal) => zoneParse(literal)?.value;

  /// The zone index on a literal WITH its reading, or null when there is none.
  ///
  /// The decode rule: strip an RFC 6874 `25` prefix ONLY when something follows
  /// it, so `%25` reads as ifindex 25 and `%25en0` reads as `en0`. That is the
  /// right answer in every case except an all-digit zone written in URI form
  /// (`%2512`), and BOTH of the cases it cannot settle are returned as such
  /// rather than presented as fact.
  ///
  /// Throws on the same malformed inputs as [zoneOf].
  static Ipv6Zone? zoneParse(String literal) {
    final int pct = literal.indexOf('%');
    if (pct < 0) return null;
    final String raw = literal.substring(pct + 1);
    if (raw.contains('%')) {
      throw const FormatException('more than one zone index');
    }
    if (raw.isEmpty) throw const FormatException('empty zone index');

    // A bare "%25": ifindex 25, or a URI "%" whose zone name was cut off.
    if (raw == '25') {
      return const Ipv6Zone(
        value: '25',
        reading: Ipv6ZoneReading.bareTwentyFive,
      );
    }

    // RFC 6874's percent-encoded "%", but only when a zone follows it.
    if (raw.length > 2 && raw.startsWith('25')) {
      final bool allDigits = RegExp(r'^\d+$').hasMatch(raw);
      return Ipv6Zone(
        value: raw.substring(2),
        reading: allDigits
            ? Ipv6ZoneReading.escapedDigits
            : Ipv6ZoneReading.certain,
        alternate: allDigits ? raw : null,
      );
    }

    return Ipv6Zone(value: raw, reading: Ipv6ZoneReading.certain);
  }

  /// The literal with any zone index removed. Validates it via [zoneOf] first,
  /// so a malformed zone throws rather than being quietly truncated away.
  static String _stripZone(String literal) {
    final int pct = literal.indexOf('%');
    if (pct < 0) return literal;
    zoneOf(literal); // throws on an empty or repeated zone
    return literal.substring(0, pct);
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
      // to disambiguate — and tidying is exactly what the deleted PWA-parity
      // compressor got wrong (see the header note).
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
