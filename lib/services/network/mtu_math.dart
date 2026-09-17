// MTU and MSS arithmetic, pure.
//
// THE JOB THIS DOES. A tunnel goes up, small things work, big transfers stall,
// and the cause is almost always that something in the path takes bytes the
// endpoints did not account for. This turns that into arithmetic a person can
// check: what MSS survives a given stack, and what MTU an observed MSS implies.
//
// WHAT IT IS NOT, and the distinction matters because we have a spec for the
// other thing. This is a CALCULATOR: pure arithmetic, every platform including
// web, no sockets. PATH MTU DISCOVERY is a separate, unbuilt tool that actively
// probes a real path, needs bespoke dart:ffi on four platforms, and is gated on
// a spike that has never been run. Its spec is at
// `Deliverables/2026-07-08-vpn-network-tools-buildprep/spec-3-path-mtu.md` and
// shipping this must not be read as having shipped that.
//
// THE MISCONCEPTION THIS EXISTS TO KILL, and it is the reason a Wi-Fi tool
// should carry it rather than a generic network one: THE 802.11 HEADER IS NOT
// SUBTRACTED FROM MTU. Wi-Fi's MAC header is larger than Ethernet's and it sits
// BELOW the IP layer, so it does not come out of the 1500-byte IP MTU. An
// 802.11 MSDU is 2304 bytes precisely so a 1500-byte IP packet fits with room
// to spare. Engineers who know the 802.11 header well are the ones most likely
// to get this wrong, which is why it is stated rather than assumed.

/// One encapsulation layer and what it costs, with the document that says so.
///
/// `bytes` is the byte cost added to the packet. `maxBytes` is set only where
/// the cost is genuinely a range; where it is set the UI must show the range
/// rather than pick a number, because inventing a single figure for a variable
/// overhead is precision theater and we have refused it before.
class MtuOverhead {
  const MtuOverhead({
    required this.id,
    required this.label,
    required this.bytes,
    required this.source,
    this.maxBytes,
    this.note,
  });

  final String id;
  final String label;

  /// Byte cost, or the LOW end when [maxBytes] is set.
  final int bytes;

  /// High end of a genuinely variable cost. Null when the cost is exact.
  final int? maxBytes;

  /// The document the number comes from. Every entry has one.
  final String source;

  final String? note;

  bool get isRange => maxBytes != null && maxBytes != bytes;

  /// How to render the cost: `8` or `56 to 73`.
  String get costLabel => isRange ? '$bytes to $maxBytes' : '$bytes';
}

/// The IP and TCP headers, which are never optional and are handled separately
/// from the tunnels a user chooses.
class MtuMath {
  const MtuMath._();

  /// RFC 791 s3.1, minimum header length, no options.
  static const int ipv4HeaderBytes = 20;

  /// RFC 8200 s3, fixed header. Extension headers add more and are not assumed.
  static const int ipv6HeaderBytes = 40;

  /// RFC 9293 s3.1, no options.
  static const int tcpHeaderBytes = 20;

  /// RFC 7323 s3. The option is 10 bytes and is padded to 12 in practice, which
  /// is the number that actually shows up on the wire.
  static const int tcpTimestampsBytes = 12;

  /// The classic Ethernet payload MTU. Not a header cost: the 14-byte Ethernet
  /// header sits outside the MTU, which is why 1500 is the starting point
  /// rather than 1514.
  static const int ethernetMtu = 1500;

  /// RFC 8200 s5. Every IPv6 link must carry at least this.
  static const int ipv6MinimumMtu = 1280;

  /// RFC 791 s3.2. Every IPv4 host must accept at least this.
  static const int ipv4MinimumReassembly = 576;

  /// Tunnel and link overheads a user can stack. Order is roughly how often
  /// they are met in the field.
  static const List<MtuOverhead> overheads = <MtuOverhead>[
    MtuOverhead(
      id: 'pppoe',
      label: 'PPPoE',
      bytes: 8,
      source: 'RFC 2516 s4',
      note: '6-byte PPPoE header plus the 2-byte PPP protocol field. This is '
          'why so many DSL links run a 1492 MTU.',
    ),
    MtuOverhead(
      id: 'gre',
      label: 'GRE over IPv4',
      bytes: 24,
      source: 'RFC 2784 s2.1 plus RFC 791 s3.1',
      note: '4-byte GRE header plus a 20-byte outer IPv4 header. Optional GRE '
          'checksum and key fields add 4 bytes each and are not assumed here.',
    ),
    MtuOverhead(
      id: 'wireguard4',
      label: 'WireGuard over IPv4',
      bytes: 60,
      source: 'WireGuard protocol paper s5.4, with RFC 791 and RFC 768',
      note: '20-byte outer IPv4 plus 8-byte UDP plus a 32-byte WireGuard data '
          'header. Over IPv6 the outer header is 40 rather than 20, so the '
          'cost is 80.',
    ),
    MtuOverhead(
      id: 'vxlan',
      label: 'VXLAN',
      bytes: 50,
      source: 'RFC 7348 s5',
      note: '14-byte outer Ethernet, 20-byte outer IPv4, 8-byte UDP and an '
          '8-byte VXLAN header.',
    ),
    MtuOverhead(
      id: 'ipsec-esp',
      label: 'IPsec ESP, tunnel mode',
      bytes: 56,
      maxBytes: 73,
      source: 'RFC 4303 s2, with RFC 3602 and RFC 2404',
      note: 'GENUINELY A RANGE, and a tool that prints one number here is '
          'guessing. It moves with the cipher, the integrity algorithm, the '
          'block padding for the payload length, and whether NAT traversal '
          'adds a UDP header. Size for the high end.',
    ),
    MtuOverhead(
      id: 'l2tp',
      label: 'L2TPv2 over UDP',
      bytes: 40,
      source: 'RFC 2661 s3, with RFC 791 and RFC 768',
      note: '20-byte outer IPv4, 8-byte UDP, 6-byte L2TP header, 4-byte PPP. '
          'Commonly paired with IPsec, in which case both costs apply.',
    ),
    MtuOverhead(
      id: 'vlan',
      label: '802.1Q VLAN tag',
      bytes: 0,
      source: 'IEEE 802.1Q, with IEEE 802.3',
      note: 'COSTS NOTHING FROM THE MTU, and it is on this list because people '
            'expect it to. The 4-byte tag extends the Ethernet header, not the '
            'payload, and compliant gear carries a 1522-byte frame so the MTU '
            'stays 1500. It only bites on hardware that cannot do baby giants.',
    ),
  ];

  static MtuOverhead? overheadById(String id) {
    for (final MtuOverhead o in overheads) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Bytes the IP and TCP headers take, before any tunnel.
  static int fixedHeaderBytes({
    required bool ipv6,
    required bool tcpTimestamps,
  }) {
    final int ip = ipv6 ? ipv6HeaderBytes : ipv4HeaderBytes;
    return ip + tcpHeaderBytes + (tcpTimestamps ? tcpTimestampsBytes : 0);
  }

  /// Total tunnel cost for [ids], taking the HIGH end of any range.
  ///
  /// The high end is deliberate. The question a user is asking is "what will
  /// definitely fit", and sizing to the low end of a variable overhead produces
  /// a number that works until the day it does not.
  static int tunnelBytes(Iterable<String> ids) {
    int total = 0;
    for (final String id in ids) {
      final MtuOverhead? o = overheadById(id);
      if (o == null) continue;
      total += o.maxBytes ?? o.bytes;
    }
    return total;
  }

  /// FORWARD. The MSS that survives [linkMtu] once headers and tunnels are paid.
  ///
  /// Returns null when the stack costs more than the link carries, which is a
  /// real answer and not an error: it means TCP cannot pass a single byte of
  /// payload over that combination.
  static int? mssFromMtu({
    required int linkMtu,
    required bool ipv6,
    required bool tcpTimestamps,
    Iterable<String> tunnels = const <String>[],
  }) {
    final int mss = linkMtu -
        tunnelBytes(tunnels) -
        fixedHeaderBytes(ipv6: ipv6, tcpTimestamps: tcpTimestamps);
    return mss > 0 ? mss : null;
  }

  /// INVERSE, and this is the half that teaches. Given an MSS seen working on
  /// the wire, what MTU does the path actually have?
  ///
  /// A capture shows the MSS. It does not show what ate the difference. Running
  /// this against 1500 tells you how many bytes something in the path is
  /// taking, and that number usually names the culprit on sight: 8 is PPPoE,
  /// 24 is GRE, 60 is WireGuard.
  static int mtuFromMss({
    required int mss,
    required bool ipv6,
    required bool tcpTimestamps,
    Iterable<String> tunnels = const <String>[],
  }) {
    return mss +
        tunnelBytes(tunnels) +
        fixedHeaderBytes(ipv6: ipv6, tcpTimestamps: tcpTimestamps);
  }

  /// Bytes unaccounted for between [ethernetMtu] and the MTU an observed [mss]
  /// implies. Zero or negative means nothing is missing.
  static int unexplainedBytes({
    required int mss,
    required bool ipv6,
    required bool tcpTimestamps,
    Iterable<String> tunnels = const <String>[],
  }) {
    return ethernetMtu -
        mtuFromMss(
          mss: mss,
          ipv6: ipv6,
          tcpTimestamps: tcpTimestamps,
          tunnels: tunnels,
        );
  }

  /// Overheads whose cost exactly equals [bytes]. Names a likely culprit for an
  /// unexplained gap WITHOUT asserting it, because several layers share a cost
  /// and a capture cannot tell them apart by size alone.
  static List<MtuOverhead> candidatesForGap(int bytes) {
    if (bytes <= 0) return const <MtuOverhead>[];
    return overheads
        .where((MtuOverhead o) => o.bytes == bytes || o.maxBytes == bytes)
        .toList();
  }

  /// Whether [mtu] is below the floor its IP version guarantees.
  static bool isBelowIpFloor({required int mtu, required bool ipv6}) =>
      ipv6 ? mtu < ipv6MinimumMtu : mtu < ipv4MinimumReassembly;
}
