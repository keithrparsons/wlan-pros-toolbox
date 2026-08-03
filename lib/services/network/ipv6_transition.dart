// Ipv6Transition — the addresses that carry an IPv4 address inside an IPv6 one,
// decoded both ways.
//
// WHY THIS IS A FIELD TOOL AND NOT A NOVELTY. A WLAN engineer rarely types
// `::ffff:` on purpose, but these addresses turn up unbidden in captures, in
// firewall logs, and in the output of a dual-stack host, and the useful moment
// is "what am I actually looking at". A NAT64 address and a 6to4 address both
// look like noise until you know where the 32 bits are hiding.
//
// WHAT IT DECODES, and the RFC each one comes from:
//   ::ffff:0:0/96   IPv4-mapped        RFC 4291 §2.5.5.2. What a dual-stack
//                                      socket shows for an IPv4 peer.
//   64:ff9b::/96    NAT64 well-known   RFC 6052 §2.1.
//   2002::/16       6to4               RFC 3056. The 32 bits after 2002 are the
//                                      site's IPv4 relay address.
//   2001:0::/32     Teredo             RFC 4380 §4. Two IPv4 addresses and a
//                                      port, and the client half is stored
//                                      INVERTED, which is why a raw read of it
//                                      looks like nonsense.
//   ::/96           IPv4-compatible    RFC 4291 §2.5.5.1, DEPRECATED. Excludes
//                                      :: and ::1, which are not IPv4 at all.
//
// WHAT IT DELIBERATELY DOES NOT DECODE: a NAT64 prefix other than the
// well-known one. RFC 6052 allows a network-specific prefix at /32, /40, /48,
// /56, /64 or /96, and the embedding offset depends on which one, so the same
// 128 bits decode to different IPv4 addresses depending on a prefix length that
// is NOT carried in the address. Guessing would be inventing an answer. The
// screen says so instead.
//
// PURE: no Flutter, no I/O.

import 'ipv6_address.dart';

/// Which transition format an address turned out to be.
enum TransitionKind {
  ipv4Mapped,
  nat64WellKnown,
  sixToFour,
  teredo,
  ipv4Compatible,

  /// A perfectly valid IPv6 address with no IPv4 inside it.
  none,
}

/// The decode of one IPv6 address.
class Ipv6ToIpv4Result {
  const Ipv6ToIpv4Result({
    required this.isValid,
    this.error,
    this.kind = TransitionKind.none,
    this.label,
    this.rfc,
    this.ipv4,
    this.ipv4Role,
    this.teredoServer,
    this.teredoPort,
    this.note,
  });

  const Ipv6ToIpv4Result.invalid(String message)
    : isValid = false,
      error = message,
      kind = TransitionKind.none,
      label = null,
      rfc = null,
      ipv4 = null,
      ipv4Role = null,
      teredoServer = null,
      teredoPort = null,
      note = null;

  final bool isValid;
  final String? error;

  final TransitionKind kind;

  /// Display name of the format, e.g. `NAT64 (well-known prefix)`.
  final String? label;

  /// The document the format is defined in, e.g. `RFC 6052`.
  final String? rfc;

  /// The embedded IPv4 address, or null when there is none.
  final String? ipv4;

  /// What that IPv4 address IS, which differs by format: a peer, a relay, a
  /// client. Naming it stops the number being read as the wrong thing.
  final String? ipv4Role;

  /// Teredo only: the IPv4 address of the Teredo server.
  final String? teredoServer;

  /// Teredo only: the client's external UDP port.
  final int? teredoPort;

  /// A caveat that belongs with this particular decode.
  final String? note;

  bool get hasIpv4 => ipv4 != null;
}

/// The four ways one IPv4 address can be written as IPv6.
class Ipv4ToIpv6Result {
  const Ipv4ToIpv6Result({
    required this.isValid,
    this.error,
    this.mappedDotted,
    this.mappedHex,
    this.mappedExpanded,
    this.compatibleDotted,
    this.sixToFourPrefix,
    this.nat64Dotted,
    this.nat64Hex,
  });

  const Ipv4ToIpv6Result.invalid(String message)
    : isValid = false,
      error = message,
      mappedDotted = null,
      mappedHex = null,
      mappedExpanded = null,
      compatibleDotted = null,
      sixToFourPrefix = null,
      nat64Dotted = null,
      nat64Hex = null;

  final bool isValid;
  final String? error;

  /// `::ffff:192.0.2.1` — the RFC 5952 §5 recommended rendering.
  final String? mappedDotted;

  /// `::ffff:c000:201` — the same address, all hex.
  final String? mappedHex;

  /// The full 8-group form.
  final String? mappedExpanded;

  /// `::192.0.2.1`, deprecated.
  final String? compatibleDotted;

  /// `2002:c000:201::/48` — a PREFIX for a site, not a host address.
  final String? sixToFourPrefix;

  final String? nat64Dotted;
  final String? nat64Hex;
}

/// Decode and encode IPv4-in-IPv6 transition addresses.
class Ipv6Transition {
  const Ipv6Transition._();

  /// Decode [literal]. Accepts any IPv6 form, including the dotted-quad tail.
  static Ipv6ToIpv4Result decode(String literal) {
    final String raw = literal.trim().toLowerCase();
    if (raw.isEmpty) {
      return const Ipv6ToIpv4Result.invalid('Enter an IPv6 address.');
    }

    String expanded;
    try {
      expanded = Ipv6Address.expand(raw);
    } on FormatException {
      return const Ipv6ToIpv4Result.invalid('Invalid IPv6 address format.');
    }
    final List<String> g = expanded.split(':');
    final RegExp hex4 = RegExp(r'^[0-9a-f]{4}$');
    if (g.length != 8 || g.any((String x) => !hex4.hasMatch(x))) {
      return const Ipv6ToIpv4Result.invalid('Invalid IPv6 address format.');
    }
    final List<int> w = <int>[
      for (final String x in g) int.parse(x, radix: 16),
    ];

    String dotted(int hi, int lo) =>
        '${(hi >> 8) & 0xFF}.${hi & 0xFF}.${(lo >> 8) & 0xFF}.${lo & 0xFF}';

    final bool firstFiveZero =
        w[0] == 0 && w[1] == 0 && w[2] == 0 && w[3] == 0 && w[4] == 0;

    // ::ffff:0:0/96 — IPv4-mapped.
    if (firstFiveZero && w[5] == 0xffff) {
      return Ipv6ToIpv4Result(
        isValid: true,
        kind: TransitionKind.ipv4Mapped,
        label: 'IPv4-mapped',
        rfc: 'RFC 4291 §2.5.5.2',
        ipv4: dotted(w[6], w[7]),
        ipv4Role: 'The IPv4 peer',
        note:
            'This is how a dual-stack socket shows an IPv4 peer to an '
            'IPv6 API. It never appears on the wire as an IPv6 packet.',
      );
    }

    // 64:ff9b::/96 — NAT64 well-known prefix.
    if (w[0] == 0x0064 &&
        w[1] == 0xff9b &&
        w[2] == 0 &&
        w[3] == 0 &&
        w[4] == 0 &&
        w[5] == 0) {
      return Ipv6ToIpv4Result(
        isValid: true,
        kind: TransitionKind.nat64WellKnown,
        label: 'NAT64 (well-known prefix)',
        rfc: 'RFC 6052 §2.1',
        ipv4: dotted(w[6], w[7]),
        ipv4Role: 'The IPv4 host being reached through the translator',
        note:
            'Decoded against the well-known 64:ff9b::/96 prefix. A network '
            'may instead use its own NAT64 prefix at /32, /40, /48, /56 or '
            '/64, and the IPv4 bits sit at a different offset in each. That '
            'prefix length is not carried in the address, so an address using '
            'one cannot be decoded without being told which.',
      );
    }

    // 2002::/16 — 6to4.
    if (w[0] == 0x2002) {
      return Ipv6ToIpv4Result(
        isValid: true,
        kind: TransitionKind.sixToFour,
        label: '6to4',
        rfc: 'RFC 3056',
        ipv4: dotted(w[1], w[2]),
        ipv4Role: "The site's IPv4 endpoint",
        note:
            'The 32 bits after 2002 are the IPv4 address of the site that '
            'owns this /48. 6to4 is deprecated for new deployments (RFC 7526) '
            'but still turns up in old configurations.',
      );
    }

    // 2001:0::/32 — Teredo.
    if (w[0] == 0x2001 && w[1] == 0x0000) {
      final int clientHi = (~w[6]) & 0xFFFF;
      final int clientLo = (~w[7]) & 0xFFFF;
      return Ipv6ToIpv4Result(
        isValid: true,
        kind: TransitionKind.teredo,
        label: 'Teredo',
        rfc: 'RFC 4380 §4',
        ipv4: dotted(clientHi, clientLo),
        ipv4Role: "The client's external IPv4 address, after a NAT",
        teredoServer: dotted(w[2], w[3]),
        teredoPort: (~w[5]) & 0xFFFF,
        note:
            'The client address and port are stored INVERTED, every bit '
            'flipped, so a raw read of those groups looks like nonsense. They '
            'are shown here already flipped back.',
      );
    }

    // ::/96 — IPv4-compatible. Excludes :: and ::1, which are not IPv4.
    if (firstFiveZero && w[5] == 0) {
      final bool unspecified = w[6] == 0 && w[7] == 0;
      final bool loopback = w[6] == 0 && w[7] == 1;
      if (!unspecified && !loopback) {
        return Ipv6ToIpv4Result(
          isValid: true,
          kind: TransitionKind.ipv4Compatible,
          label: 'IPv4-compatible (deprecated)',
          rfc: 'RFC 4291 §2.5.5.1',
          ipv4: dotted(w[6], w[7]),
          ipv4Role: 'The IPv4 address this was built from',
          note:
              'This format is deprecated and should not be used in new '
              'work. If you are seeing it, something is old.',
        );
      }
      return Ipv6ToIpv4Result(
        isValid: true,
        label: unspecified ? 'Unspecified (::)' : 'Loopback (::1)',
        note:
            'This is not a transition address. It sits inside the '
            'deprecated IPv4-compatible range numerically, but it means '
            '${unspecified ? 'no address' : 'this host'} and carries no IPv4.',
      );
    }

    return const Ipv6ToIpv4Result(
      isValid: true,
      label: 'No IPv4 inside',
      note:
          'This is an ordinary IPv6 address. None of the transition formats '
          'match it, so there is no IPv4 address hiding in it.',
    );
  }

  /// Write [dottedIpv4] the four ways IPv6 can carry it.
  static Ipv4ToIpv6Result encode(String dottedIpv4) {
    final String s = dottedIpv4.trim();
    if (s.isEmpty) {
      return const Ipv4ToIpv6Result.invalid('Enter an IPv4 address.');
    }
    final List<String> parts = s.split('.');
    if (parts.length != 4) {
      return const Ipv4ToIpv6Result.invalid(
        'Enter a valid IPv4 address, e.g. 192.0.2.1. Four octets, each 0 to '
        '255.',
      );
    }
    int v = 0;
    for (final String p in parts) {
      if (p.isEmpty || p.length > 3 || !RegExp(r'^\d+$').hasMatch(p)) {
        return const Ipv4ToIpv6Result.invalid(
          'Enter a valid IPv4 address, e.g. 192.0.2.1. Four octets, each 0 to '
          '255.',
        );
      }
      final int n = int.parse(p);
      if (n > 255) {
        return const Ipv4ToIpv6Result.invalid('Each octet must be 0 to 255.');
      }
      v = (v << 8) | n;
    }

    final String canonical =
        '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.'
        '${(v >> 8) & 0xFF}.${v & 0xFF}';
    String hex4(int x) => x.toRadixString(16).padLeft(4, '0');
    final String hi = hex4((v >> 16) & 0xFFFF);
    final String lo = hex4(v & 0xFFFF);

    String compressOf(String full) => Ipv6Address.compress(full);
    final String mappedFull = Ipv6Address.expand('::ffff:$hi:$lo');
    final String nat64Full = Ipv6Address.expand('64:ff9b::$hi:$lo');
    final String sixFull = Ipv6Address.expand('2002:$hi:$lo::');

    return Ipv4ToIpv6Result(
      isValid: true,
      mappedDotted: '::ffff:$canonical',
      mappedHex: compressOf(mappedFull),
      mappedExpanded: mappedFull,
      compatibleDotted: '::$canonical',
      sixToFourPrefix: '${compressOf(sixFull)}/48',
      nat64Dotted: '64:ff9b::$canonical',
      nat64Hex: compressOf(nat64Full),
    );
  }
}
