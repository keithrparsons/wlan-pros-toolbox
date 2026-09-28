// One frame model shared by two Wi-Fi Classroom tools (1.11.0):
//
//   - Down the Stack, Across the Air, Up the Other Side (down-the-stack):
//     a laptop on Wi-Fi sends to a wired server through an AP and a router.
//     The data goes down the laptop's stack (port, IP address, MAC address,
//     bits), crosses the air as RF, and climbs each device only as far as
//     that device needs: the AP to the data link layer, the router to the
//     network layer, the server all the way up. IP addresses stay end to end
//     (no NAT); MAC addresses change on every hop. Plus the four
//     To DS / From DS cases and what Addresses 1 to 4 mean.
//   - A Frame's Journey (frame-journey): the bottom layer of the first tool,
//     opened up. The SAME air frame (the Laptop-to-AP hop) is turned into
//     bits and RF, crosses a distance, is decoded, gets a radiotap header if
//     the receiver is capturing, passes or fails its FCS check, and only
//     after SIFS is acknowledged. Flip one bit and the FCS fails, no ACK
//     comes back and the sender retries.
//
// Pure Dart, deterministic, no Flutter import: the tests exercise every
// teaching claim here.
//
// SOURCES (Pax, myPKA Deliverables/2026-09-27-classroom-interferer-and-ds-
// sources/RESEARCH-BRIEF.md, Part 2). IEEE 802.11-2020 body text was not read;
// clause numbers come from the standard's own table of contents.
//   - Address fields by To DS / From DS: 802.11-2020 clause 9.3.2.1 (Format of
//     Data frames) and 9.2.4.3 (Address fields). The table number inside
//     9.3.2.1 is deliberately NOT printed (unverified). Values agree across
//     the CWAP study guide (mrncciew) and networkacademy.io.
//   - Address 3 is the ROUTER's MAC when the server is on another subnet: the
//     laptop resolves its default gateway. networkacademy.io + RFC 1812 s1.
//   - The AP is a bridge: it drops the 802.11 header, turns LLC/SNAP back into
//     an EtherType and forwards with the laptop's MAC as the source (RFC 1042).
//   - The router strips and rebuilds layer 2, decrements TTL (RFC 791 s1.4)
//     and recomputes the header checksum (RFC 1812 s4.2.2.5). IP addresses
//     stay end to end only without NAT.
//   - Header sizes: TCP 20 (RFC 9293 s3.1), UDP 8 (RFC 768), IPv4 20
//     (RFC 791 s3.1), LLC/SNAP 8 (RFC 1042), 802.11 MAC header 24 with three
//     addresses and 30 with four, +2 for QoS Control (26 / 32), FCS 4
//     (clause 9.2.4.8). Ethernet 14 + FCS 4 (IEEE 802.3; Pax flagged it as
//     not re-read).
//   - FCS: 32-bit CRC over the MAC header and frame body (9.2.4.8). ACK only
//     for a valid FCS; no ACK means the sender retries (10.3.2.2, 10.3.2.11).
//   - SIFS: 16 us at 5 and 6 GHz; 10 us at 2.4 GHz plus a 6 us signal
//     extension after ERP-OFDM and HT PPDUs (ERP SIFS 18.4.5; signal
//     extension 10.3.8).
//   - Radiotap: a pseudo-header added by the capturing driver, never sent over
//     the air (Intuitibits 2015; OpenBSD ieee80211_radiotap(9)). TSFT bit 0,
//     rate bit 2 (500 kb/s units), channel bit 3, antenna signal dBm bit 5,
//     MCS bit 19.
//
// ILLUSTRATIVE (labeled on screen and in help): every MAC address, the
// laptop's source port, the starting TTL of 64, the sequence number, the
// Duration field, the payload bytes, the transmit power, the MCS in the
// radiotap view and the TSF timer value. IP addresses come from the ranges
// RFC 5737 reserves for documentation.
//
// ASCII only, no em dashes (GL-004).

import 'dart:typed_data';

import 'fspl_math.dart';

// ── Header sizes (bytes) ─────────────────────────────────────────────────────

/// TCP header without options (RFC 9293 s3.1).
const int kTcpHeaderBytes = 20;

/// UDP header (RFC 768).
const int kUdpHeaderBytes = 8;

/// IPv4 header without options (RFC 791 s3.1).
const int kIpv4HeaderBytes = 20;

/// LLC (3 bytes: AA AA 03) + SNAP (5 bytes: OUI 00-00-00 + EtherType),
/// RFC 1042.
const int kLlcSnapBytes = 8;

/// 802.11 MAC header, three addresses, no QoS Control: 2+2+6+6+6+2.
const int kMacHeader3AddrBytes = 24;

/// The fourth address, present only when To DS and From DS are both 1.
const int kAddress4Bytes = 6;

/// QoS Control, present in every QoS Data frame.
const int kQosControlBytes = 2;

/// 802.11 FCS: a 32-bit CRC (clause 9.2.4.8).
const int kFcsBytes = 4;

/// Ethernet (802.3) header: destination 6 + source 6 + EtherType 2.
const int kEthernetHeaderBytes = 14;

/// Ethernet FCS.
const int kEthernetFcsBytes = 4;

/// Payload sizes the tools offer. 1460 fills a 1500-byte IPv4 packet under
/// TCP; the other two are illustrative.
const List<int> kFjPayloadChoices = <int>[100, 500, 1460];

/// Default payload.
const int kFjDefaultPayload = 1460;

/// 802.11 MAC header size.
int macHeaderBytes({required bool qos, required bool fourAddress}) =>
    kMacHeader3AddrBytes +
    (qos ? kQosControlBytes : 0) +
    (fourAddress ? kAddress4Bytes : 0);

/// Transport protocol.
enum FjTransport {
  tcp('TCP', 'Transmission Control Protocol', kTcpHeaderBytes, 6),
  udp('UDP', 'User Datagram Protocol', kUdpHeaderBytes, 17);

  const FjTransport(this.label, this.long, this.headerBytes, this.ipProtocol);

  final String label;

  /// Spelled out.
  final String long;
  final int headerBytes;

  /// The IPv4 Protocol field value (6 TCP, 17 UDP).
  final int ipProtocol;
}

/// Every size along the way, for one payload.
class FjSizes {
  const FjSizes({
    required this.payload,
    required this.transport,
    required this.qos,
    required this.fourAddress,
  });

  final int payload;
  final FjTransport transport;
  final bool qos;
  final bool fourAddress;

  int get transportHeader => transport.headerBytes;
  int get ipHeader => kIpv4HeaderBytes;
  int get llcSnap => kLlcSnapBytes;
  int get macHeader => macHeaderBytes(qos: qos, fourAddress: fourAddress);
  int get fcs => kFcsBytes;

  /// Transport header + data.
  int get segment => payload + transportHeader;

  /// IPv4 header + segment.
  int get packet => segment + ipHeader;

  /// MSDU (MAC service data unit): LLC/SNAP + packet.
  int get msdu => packet + llcSnap;

  /// MPDU (MAC protocol data unit): MAC header + MSDU + FCS.
  int get mpdu => macHeader + msdu + fcs;

  /// The same packet on Ethernet: 14 + packet + 4.
  int get ethernetFrame => kEthernetHeaderBytes + packet + kEthernetFcsBytes;

  int get mpduBits => mpdu * 8;
  int get ethernetBits => ethernetFrame * 8;
}

// ── Addresses ───────────────────────────────────────────────────────────────

/// A 48-bit MAC address as six bytes.
class Mac {
  const Mac(this.text);

  /// Colon-separated lowercase hex, "02:00:00:00:00:10".
  final String text;

  List<int> get bytes => <int>[
    for (final String p in text.split(':')) int.parse(p, radix: 16),
  ];

  @override
  bool operator ==(Object other) => other is Mac && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => text;
}

/// One device (or one interface of the router).
class FjDevice {
  const FjDevice({
    required this.name,
    required this.phrase,
    required this.mac,
    this.ip,
  });

  final String name;

  /// How a sentence names it ("the router's LAN interface").
  final String phrase;
  final Mac mac;

  /// Dotted IPv4, or null for the AP (a bridge: its radio has no role at
  /// layer 3 here).
  final String? ip;

  @override
  String toString() => name;
}

/// Parses dotted IPv4 into four bytes.
List<int> ipv4Bytes(String dotted) => <int>[
  for (final String p in dotted.split('.')) int.parse(p),
];

/// True when [a] and [b] share the first [prefix] bits.
bool sameSubnet(String a, String b, int prefix) {
  int v(String s) =>
      ipv4Bytes(s).fold<int>(0, (int acc, int x) => (acc << 8) | x);
  final int mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  return (v(a) & mask) == (v(b) & mask);
}

/// Where a host sends a frame at layer 2 for [dstIp]: to the destination
/// itself when it is on the same subnet, else to its default gateway. This
/// is why Address 3 holds the router's MAC in the laptop-to-server example.
Mac layer2NextHop({
  required String srcIp,
  required int prefix,
  required String dstIp,
  required Mac dstMac,
  required Mac gatewayMac,
}) => sameSubnet(srcIp, dstIp, prefix) ? dstMac : gatewayMac;

/// The scene's devices. All MAC addresses are illustrative; the IP addresses
/// come from the RFC 5737 documentation ranges. The laptop's LAN is
/// 192.0.2.0/24; the server's other subnet is 198.51.100.0/24.
class FjScene {
  FjScene._();

  static const int lanPrefix = 24;

  static const FjDevice laptop = FjDevice(
    name: 'Laptop',
    phrase: 'the laptop',
    mac: Mac('02:00:00:00:00:10'),
    ip: '192.0.2.10',
  );

  /// The AP's radio. Its MAC is the BSSID.
  static const FjDevice ap = FjDevice(
    name: 'AP',
    phrase: 'the AP',
    mac: Mac('02:00:00:00:00:a1'),
  );

  static const FjDevice routerLan = FjDevice(
    name: 'Router, LAN side',
    phrase: "the router's LAN interface",
    mac: Mac('02:00:00:00:00:01'),
    ip: '192.0.2.1',
  );

  static const FjDevice routerOther = FjDevice(
    name: 'Router, server side',
    phrase: "the router's server-side interface",
    mac: Mac('02:00:00:00:00:02'),
    ip: '198.51.100.1',
  );

  /// The server on another subnet (the main example).
  static const FjDevice server = FjDevice(
    name: 'Server',
    phrase: 'the server',
    mac: Mac('02:00:00:00:00:20'),
    ip: '198.51.100.20',
  );

  /// The same server moved onto the laptop's own LAN (the contrast case).
  static const FjDevice serverSameLan = FjDevice(
    name: 'Server',
    phrase: 'the server',
    mac: Mac('02:00:00:00:00:20'),
    ip: '192.0.2.20',
  );

  /// A second client, for the To DS 0 / From DS 0 case.
  static const FjDevice tablet = FjDevice(
    name: 'Tablet',
    phrase: 'the tablet',
    mac: Mac('02:00:00:00:00:11'),
    ip: '192.0.2.11',
  );

  /// A mesh AP's radio, for the To DS 1 / From DS 1 case.
  static const FjDevice meshAp = FjDevice(
    name: 'Mesh AP',
    phrase: 'the mesh AP',
    mac: Mac('02:00:00:00:00:b1'),
  );

  /// The root AP's backhaul radio, for the To DS 1 / From DS 1 case.
  static const FjDevice rootAp = FjDevice(
    name: 'Root AP',
    phrase: 'the root AP',
    mac: Mac('02:00:00:00:00:a1'),
  );

  /// The laptop's ephemeral source port (illustrative).
  static const int laptopPort = 51000;

  /// The server's port: 443, the web (HTTPS) port.
  static const int serverPort = 443;

  /// Starting TTL (illustrative; operating systems differ).
  static const int startTtl = 64;
}

/// The roles an address field can play.
enum AddrRole {
  ra('RA', 'receiver address', 'the radio that must receive this frame'),
  ta('TA', 'transmitter address', 'the radio that sent this frame'),
  da('DA', 'destination address', 'where the frame is finally going'),
  sa('SA', 'source address', 'where the frame first came from'),
  bssid(
    'BSSID',
    'basic service set identifier',
    'the AP radio\'s MAC for this network',
  );

  const AddrRole(this.short, this.long, this.meaning);

  final String short;
  final String long;
  final String meaning;
}

/// The four combinations of the To DS and From DS bits.
enum DsCase {
  none(
    0,
    0,
    'To DS 0, From DS 0',
    'Station to station with no distribution system between them; '
        'management frames use this layout too',
  ),
  fromDs(
    0,
    1,
    'To DS 0, From DS 1',
    'AP to client: the frame comes from the distribution system (DS)',
  ),
  toDs(
    1,
    0,
    'To DS 1, From DS 0',
    'Client to AP: the frame goes to the distribution system; most uplink '
        'traffic',
  ),
  both(
    1,
    1,
    'To DS 1, From DS 1',
    'AP to AP over the air: a wireless distribution system (WDS) or mesh '
        'backhaul',
  );

  const DsCase(this.toDsBit, this.fromDsBit, this.label, this.meaning);

  final int toDsBit;
  final int fromDsBit;
  final String label;
  final String meaning;

  bool get fourAddress => this == DsCase.both;

  static DsCase of({required bool toDs, required bool fromDs}) =>
      DsCase.values.firstWhere(
        (DsCase c) =>
            c.toDsBit == (toDs ? 1 : 0) && c.fromDsBit == (fromDs ? 1 : 0),
      );
}

/// What Addresses 1 to 4 hold for [c] (clause 9.3.2.1). Address 1 is always
/// the receiver, Address 2 always the transmitter.
List<List<AddrRole>> addressRoles(DsCase c) => switch (c) {
  DsCase.none => <List<AddrRole>>[
    <AddrRole>[AddrRole.ra, AddrRole.da],
    <AddrRole>[AddrRole.ta, AddrRole.sa],
    <AddrRole>[AddrRole.bssid],
  ],
  DsCase.fromDs => <List<AddrRole>>[
    <AddrRole>[AddrRole.ra, AddrRole.da],
    <AddrRole>[AddrRole.ta, AddrRole.bssid],
    <AddrRole>[AddrRole.sa],
  ],
  DsCase.toDs => <List<AddrRole>>[
    <AddrRole>[AddrRole.ra, AddrRole.bssid],
    <AddrRole>[AddrRole.ta, AddrRole.sa],
    <AddrRole>[AddrRole.da],
  ],
  DsCase.both => <List<AddrRole>>[
    <AddrRole>[AddrRole.ra],
    <AddrRole>[AddrRole.ta],
    <AddrRole>[AddrRole.da],
    <AddrRole>[AddrRole.sa],
  ],
};

/// One filled-in address field.
class AddressField {
  const AddressField({
    required this.number,
    required this.roles,
    required this.device,
  });

  /// 1 to 4.
  final int number;
  final List<AddrRole> roles;
  final FjDevice device;

  Mac get mac => device.mac;

  /// "RA = DA".
  String get roleText => roles.map((AddrRole r) => r.short).join(' = ');
}

/// The people in one frame: who receives it on the air and who sent it on
/// the air, where it started and where it is going, and the network.
class DsParties {
  const DsParties({
    required this.receiver,
    required this.transmitter,
    required this.source,
    required this.destination,
    this.bssid,
  });

  final FjDevice receiver;
  final FjDevice transmitter;
  final FjDevice source;
  final FjDevice destination;

  /// The AP radio for this network; null in the four-address case, where no
  /// field holds a BSSID.
  final FjDevice? bssid;
}

/// Fills the address fields for [c] from [p]. Throws when [p] contradicts
/// [c] (for example To DS 1 From DS 0 with a receiver that is not the BSSID).
List<AddressField> addressFields(DsCase c, DsParties p) {
  FjDevice who(AddrRole r) => switch (r) {
    AddrRole.ra => p.receiver,
    AddrRole.ta => p.transmitter,
    AddrRole.da => p.destination,
    AddrRole.sa => p.source,
    AddrRole.bssid => p.bssid ?? (throw ArgumentError('$c needs a BSSID')),
  };
  final List<List<AddrRole>> roles = addressRoles(c);
  return <AddressField>[
    for (int i = 0; i < roles.length; i++)
      () {
        final FjDevice first = who(roles[i].first);
        for (final AddrRole r in roles[i].skip(1)) {
          if (who(r).mac != first.mac) {
            throw ArgumentError(
              'Address ${i + 1} must be ${roles[i].map((AddrRole x) => x.short).join(' = ')} '
              'in $c, but ${roles[i].first.short} is ${first.name} and '
              '${r.short} is ${who(r).name}',
            );
          }
        }
        return AddressField(number: i + 1, roles: roles[i], device: first);
      }(),
  ];
}

/// One worked scene per DS case, for the explorer.
class DsExample {
  const DsExample({
    required this.dsCase,
    required this.parties,
    required this.story,
  });

  final DsCase dsCase;
  final DsParties parties;

  /// One sentence: who is sending what to whom, and over which hop.
  final String story;

  List<AddressField> get fields => addressFields(dsCase, parties);

  int get macHeader =>
      macHeaderBytes(qos: true, fourAddress: dsCase.fourAddress);
}

/// The worked scene for each case. To DS 1 / From DS 0 and To DS 0 /
/// From DS 1 are the two air hops of the main example; the router's LAN MAC
/// is in Address 3 both ways, because the server is on another subnet.
DsExample dsExample(DsCase c) => switch (c) {
  DsCase.none => const DsExample(
    dsCase: DsCase.none,
    parties: DsParties(
      receiver: FjScene.tablet,
      transmitter: FjScene.laptop,
      source: FjScene.laptop,
      destination: FjScene.tablet,
      bssid: FjScene.ap,
    ),
    story:
        'The laptop sends straight to the tablet, with no AP relaying it. '
        'The sender and the receiver on the air are also the source and the '
        'destination, so three addresses are enough.',
  ),
  DsCase.fromDs => const DsExample(
    dsCase: DsCase.fromDs,
    parties: DsParties(
      receiver: FjScene.laptop,
      transmitter: FjScene.ap,
      source: FjScene.routerLan,
      destination: FjScene.laptop,
      bssid: FjScene.ap,
    ),
    story:
        'The server\'s reply reaches the laptop. The AP transmits it, but the '
        'frame came onto this LAN from the router, so the router\'s LAN MAC '
        'is the source address.',
  ),
  DsCase.toDs => const DsExample(
    dsCase: DsCase.toDs,
    parties: DsParties(
      receiver: FjScene.ap,
      transmitter: FjScene.laptop,
      source: FjScene.laptop,
      destination: FjScene.routerLan,
      bssid: FjScene.ap,
    ),
    story:
        'The laptop sends to the server on another subnet. The AP receives '
        'it, but the frame is going to the router, the laptop\'s default '
        'gateway, so the router\'s LAN MAC is the destination address, not '
        'the server\'s.',
  ),
  DsCase.both => const DsExample(
    dsCase: DsCase.both,
    parties: DsParties(
      receiver: FjScene.rootAp,
      transmitter: FjScene.meshAp,
      source: FjScene.laptop,
      destination: FjScene.routerLan,
    ),
    story:
        'The laptop is on a mesh AP, and the mesh AP relays its frame to the '
        'root AP over the air. Both radios on this hop are relays, neither '
        'is where the frame started or where it is going, so the frame needs '
        'a fourth address.',
  ),
};

// ── Checksums ───────────────────────────────────────────────────────────────

final Uint32List _crcTable = () {
  final Uint32List t = Uint32List(256);
  for (int n = 0; n < 256; n++) {
    int c = n;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

/// CRC-32 (the IEEE 802.3 polynomial, reflected, initial and final XOR
/// 0xFFFFFFFF), the 32-bit CRC 802.11 uses for the FCS.
int crc32(List<int> bytes, [int start = 0, int? end]) {
  int c = 0xFFFFFFFF;
  final int stop = end ?? bytes.length;
  for (int i = start; i < stop; i++) {
    c = _crcTable[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// The Internet checksum (one's-complement sum of 16-bit words) over an
/// IPv4 header whose checksum field is zero.
int internetChecksum(List<int> bytes) {
  int sum = 0;
  for (int i = 0; i < bytes.length; i += 2) {
    final int hi = bytes[i];
    final int lo = i + 1 < bytes.length ? bytes[i + 1] : 0;
    sum += (hi << 8) | lo;
  }
  while (sum >> 16 != 0) {
    sum = (sum & 0xFFFF) + (sum >> 16);
  }
  return (~sum) & 0xFFFF;
}

String hex16(int v) => '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';
String hex32(int v) => '0x${v.toRadixString(16).toUpperCase().padLeft(8, '0')}';

// ── The IP packet ───────────────────────────────────────────────────────────

/// The IPv4 header fields the lesson follows.
class FjIp {
  const FjIp({
    required this.src,
    required this.dst,
    required this.ttl,
    required this.totalLength,
    required this.protocol,
  });

  final String src;
  final String dst;
  final int ttl;
  final int totalLength;
  final int protocol;

  /// The header, 20 bytes, with its checksum filled in. Identification is an
  /// illustrative fixed value; Don't Fragment is set.
  List<int> headerBytes() {
    final List<int> h = <int>[
      0x45, 0x00, (totalLength >> 8) & 0xFF, totalLength & 0xFF, //
      0x1c, 0x46, 0x40, 0x00, //
      ttl & 0xFF, protocol, 0x00, 0x00, //
      ...ipv4Bytes(src), ...ipv4Bytes(dst),
    ];
    final int sum = internetChecksum(h);
    h[10] = (sum >> 8) & 0xFF;
    h[11] = sum & 0xFF;
    return h;
  }

  /// The header checksum, as the router must recompute it.
  int get checksum {
    final List<int> h = headerBytes();
    return (h[10] << 8) | h[11];
  }

  FjIp decremented() => FjIp(
    src: src,
    dst: dst,
    ttl: ttl - 1,
    totalLength: totalLength,
    protocol: protocol,
  );
}

/// The transport header's two ports.
class FjPorts {
  const FjPorts(this.src, this.dst);
  final int src;
  final int dst;
}

/// The illustrative payload: printable text, repeated.
List<int> fjPayload(int n) {
  const String text = 'Hello from the laptop. ';
  return <int>[for (int i = 0; i < n; i++) text.codeUnitAt(i % text.length)];
}

List<int> _transportBytes(FjTransport t, FjPorts p, int payloadLen) {
  switch (t) {
    case FjTransport.tcp:
      // Sequence and acknowledgment numbers illustrative; checksum left 0
      // (not part of the lesson, and never shown).
      return <int>[
        (p.src >> 8) & 0xFF, p.src & 0xFF, (p.dst >> 8) & 0xFF, p.dst & 0xFF,
        0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x20, 0x00, //
        0x50, 0x18, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00,
      ];
    case FjTransport.udp:
      final int len = kUdpHeaderBytes + payloadLen;
      return <int>[
        (p.src >> 8) & 0xFF,
        p.src & 0xFF,
        (p.dst >> 8) & 0xFF,
        p.dst & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
        0x00,
        0x00,
      ];
  }
}

/// LLC/SNAP for an IPv4 packet: AA AA 03, OUI 00-00-00, EtherType 0x0800.
const List<int> kLlcSnapIpv4 = <int>[
  0xaa,
  0xaa,
  0x03,
  0x00,
  0x00,
  0x00,
  0x08,
  0x00,
];

// ── The 802.11 frame on the air ─────────────────────────────────────────────

/// A named byte range inside a frame, for "which field did that bit land in".
class FjField {
  const FjField(this.name, this.start, this.length);
  final String name;
  final int start;
  final int length;
  int get end => start + length;
}

/// One 802.11 QoS Data MPDU, built byte for byte so the FCS is a real CRC-32.
class AirFrame {
  AirFrame._(this.bytes, this.fields, this.sizes, this.dsCase, this.retry);

  /// Builds the frame for [c] from [p] carrying [ip] and [ports] over
  /// [transport], with [payload] bytes of data.
  factory AirFrame.build({
    required DsCase c,
    required DsParties p,
    required FjIp ip,
    required FjPorts ports,
    required FjTransport transport,
    required int payload,
    bool qos = true,
    bool retry = false,
  }) {
    final List<AddressField> addr = addressFields(c, p);
    final List<FjField> fields = <FjField>[];
    final List<int> b = <int>[];
    void add(String name, List<int> bytes) {
      fields.add(FjField(name, b.length, bytes.length));
      b.addAll(bytes);
    }

    // Frame Control: protocol 0, type 2 (Data), subtype 8 (QoS Data) or 0.
    final int fc0 = qos ? 0x88 : 0x08;
    final int fc1 = (c.toDsBit) | (c.fromDsBit << 1) | (retry ? 0x08 : 0x00);
    add('Frame Control (To DS, From DS, Retry)', <int>[fc0, fc1]);
    // Duration: illustrative.
    add('Duration', <int>[0x2c, 0x00]);
    add('Address 1 (${addr[0].roleText})', addr[0].mac.bytes);
    add('Address 2 (${addr[1].roleText})', addr[1].mac.bytes);
    add('Address 3 (${addr[2].roleText})', addr[2].mac.bytes);
    // Sequence Control: sequence number 100, fragment 0 (illustrative).
    add('Sequence Control', <int>[0x40, 0x06]);
    if (c.fourAddress) {
      add('Address 4 (${addr[3].roleText})', addr[3].mac.bytes);
    }
    if (qos) add('QoS Control', <int>[0x00, 0x00]);
    final int headerLen = b.length;
    add('LLC/SNAP', kLlcSnapIpv4);
    add('IPv4 header', ip.headerBytes());
    add(
      '${transport.label} header',
      _transportBytes(transport, ports, payload),
    );
    add('Data', fjPayload(payload));
    final int fcs = crc32(b);
    // The FCS goes out least significant byte first.
    add('FCS', <int>[
      fcs & 0xFF,
      (fcs >> 8) & 0xFF,
      (fcs >> 16) & 0xFF,
      (fcs >> 24) & 0xFF,
    ]);
    final FjSizes sizes = FjSizes(
      payload: payload,
      transport: transport,
      qos: qos,
      fourAddress: c.fourAddress,
    );
    assert(headerLen == sizes.macHeader);
    assert(b.length == sizes.mpdu);
    return AirFrame._(Uint8List.fromList(b), fields, sizes, c, retry);
  }

  final Uint8List bytes;
  final List<FjField> fields;
  final FjSizes sizes;
  final DsCase dsCase;
  final bool retry;

  int get length => bytes.length;
  int get bitCount => bytes.length * 8;

  /// The FCS the sender put in the frame.
  int get fcsSent => fcsField(bytes);

  /// Reads the FCS field from the last four bytes of [b].
  static int fcsField(List<int> b) {
    final int n = b.length;
    return b[n - 4] | (b[n - 3] << 8) | (b[n - 2] << 16) | (b[n - 1] << 24);
  }

  /// The field bit [bit] (0 = the first bit of the first byte) sits in.
  FjField fieldAtBit(int bit) {
    final int byte = bit ~/ 8;
    return fields.firstWhere((FjField f) => byte >= f.start && byte < f.end);
  }

  /// A copy of the bytes with bit [bit] flipped (0 = the most significant
  /// bit of byte 0, for display; the physical bit order on the air is not
  /// modeled).
  Uint8List withBitFlipped(int bit) {
    final Uint8List copy = Uint8List.fromList(bytes);
    copy[bit ~/ 8] ^= 0x80 >> (bit % 8);
    return copy;
  }
}

/// The receiver's FCS check on [received]: recompute the CRC-32 over
/// everything before the FCS and compare it with the FCS that arrived.
class FcsCheck {
  FcsCheck(List<int> received)
    : computed = crc32(received, 0, received.length - kFcsBytes),
      arrived = AirFrame.fcsField(received);

  final int computed;
  final int arrived;

  bool get pass => computed == arrived;
}

// ── Down the Stack: the journey ─────────────────────────────────────────────

/// Which way the data goes.
enum FjDirection {
  toServer('Laptop to server'),
  reply('Server replies to laptop');

  const FjDirection(this.label);
  final String label;
}

/// Where the server is.
enum FjServerLocation {
  otherSubnet('Another subnet, through the router'),
  sameSubnet('The laptop\'s own subnet, no router');

  const FjServerLocation(this.label);
  final String label;
}

/// The layers of the drawing, top to bottom. Names follow the OSI model's
/// layers 7, 4, 3, 2 and 1; 5 and 6 are left out.
enum FjLayer {
  application('Application', 7),
  transport('Transport', 4),
  network('Network', 3),
  dataLink('Data link', 2),
  physical('Physical', 1);

  const FjLayer(this.label, this.osi);
  final String label;
  final int osi;
}

/// A node in the drawing.
enum FjNode {
  laptop('Laptop', FjLayer.application),
  ap('AP', FjLayer.dataLink),
  router('Router', FjLayer.network),
  server('Server', FjLayer.application);

  const FjNode(this.label, this.top);
  final String label;

  /// The highest layer this node climbs to.
  final FjLayer top;
}

/// A medium between two nodes.
enum FjMedium {
  air('Air (Wi-Fi, RF)'),
  wire('Wire (Ethernet)');

  const FjMedium(this.label);
  final String label;
}

/// The kinds of piece a PDU is built from.
enum FjPart {
  data('Data'),
  transport('Transport header'),
  ip('IPv4 header'),
  llcSnap('LLC/SNAP'),
  wifiHeader('802.11 header'),
  ethHeader('Ethernet header'),
  fcs('FCS'),
  bits('Bits');

  const FjPart(this.label);
  final String label;
}

/// One piece of the PDU, outermost first when listed.
class FjPiece {
  const FjPiece(this.part, this.bytes, this.label);
  final FjPart part;
  final int bytes;

  /// Shown on the chip ("TCP 20 B").
  final String label;
}

/// The layer-2 header in force at a step.
sealed class FjLink {
  const FjLink();
}

class FjWifiLink extends FjLink {
  const FjWifiLink(this.dsCase, this.fields);
  final DsCase dsCase;
  final List<AddressField> fields;
}

class FjEthLink extends FjLink {
  const FjEthLink({required this.src, required this.dst});
  final FjDevice src;
  final FjDevice dst;
}

/// What happens at a step.
enum FjAction { add, remove, change, cross, none }

/// One step of the journey.
class FjStep {
  const FjStep({
    required this.index,
    required this.title,
    required this.detail,
    required this.action,
    required this.pieces,
    required this.ip,
    required this.ports,
    this.node,
    this.layer,
    this.medium,
    this.from,
    this.to,
    this.link,
    this.changed = const <FjPart>{},
  });

  final int index;
  final String title;
  final String detail;
  final FjAction action;

  /// At a device: which, and at which layer. Null on a medium.
  final FjNode? node;
  final FjLayer? layer;

  /// On a medium: which, and between which nodes.
  final FjMedium? medium;
  final FjNode? from;
  final FjNode? to;

  /// The PDU after this step, outermost piece first.
  final List<FjPiece> pieces;

  /// The layer-2 header on the PDU (null above layer 2).
  final FjLink? link;

  /// Present from the network layer down (always, in this lesson: the IP
  /// header is only absent at the endpoints' top layers, where it is shown
  /// for reference).
  final FjIp ip;
  final FjPorts ports;

  /// The pieces this step added or changed (highlighted).
  final Set<FjPart> changed;

  bool get onMedium => medium != null;

  int get pduBytes => pieces.fold<int>(0, (int s, FjPiece p) => s + p.bytes);

  /// What this PDU is called at this point.
  String get pduName {
    if (pieces.any((FjPiece p) => p.part == FjPart.bits)) return 'Bits';
    if (pieces.any(
      (FjPiece p) => p.part == FjPart.wifiHeader || p.part == FjPart.ethHeader,
    )) {
      return 'Frame';
    }
    if (pieces.any((FjPiece p) => p.part == FjPart.ip)) return 'Packet';
    if (pieces.any((FjPiece p) => p.part == FjPart.transport)) {
      return 'Segment';
    }
    return 'Data';
  }
}

/// The inputs for Down the Stack.
class FjConfig {
  const FjConfig({
    this.direction = FjDirection.toServer,
    this.server = FjServerLocation.otherSubnet,
    this.transport = FjTransport.tcp,
    this.payload = kFjDefaultPayload,
    this.qos = true,
  });

  final FjDirection direction;
  final FjServerLocation server;
  final FjTransport transport;
  final int payload;

  /// True: QoS Data, the 26-byte header nearly every modern data frame
  /// uses. False: the textbook 24-byte Data header.
  final bool qos;

  FjConfig copyWith({
    FjDirection? direction,
    FjServerLocation? server,
    FjTransport? transport,
    int? payload,
    bool? qos,
  }) => FjConfig(
    direction: direction ?? this.direction,
    server: server ?? this.server,
    transport: transport ?? this.transport,
    payload: payload ?? this.payload,
    qos: qos ?? this.qos,
  );

  FjSizes get sizes => FjSizes(
    payload: payload,
    transport: transport,
    qos: qos,
    fourAddress: false,
  );

  FjDevice get serverDevice => server == FjServerLocation.otherSubnet
      ? FjScene.server
      : FjScene.serverSameLan;

  bool get throughRouter => server == FjServerLocation.otherSubnet;

  @override
  bool operator ==(Object other) =>
      other is FjConfig &&
      other.direction == direction &&
      other.server == server &&
      other.transport == transport &&
      other.payload == payload &&
      other.qos == qos;

  @override
  int get hashCode => Object.hash(direction, server, transport, payload, qos);
}

/// The air frame of the laptop's hop for [cfg]: To DS 1 going to the server,
/// From DS 1 on the reply. A Frame's Journey follows this same frame.
AirFrame airFrameFor(FjConfig cfg, {bool retry = false}) {
  final _Hops h = _Hops(cfg);
  return AirFrame.build(
    c: h.airCase,
    p: h.airParties,
    ip: h.airIp,
    ports: h.ports,
    transport: cfg.transport,
    payload: cfg.payload,
    qos: cfg.qos,
    retry: retry,
  );
}

/// Who is on each hop, for one configuration.
class _Hops {
  _Hops(this.cfg);
  final FjConfig cfg;

  bool get up => cfg.direction == FjDirection.toServer;
  FjDevice get server => cfg.serverDevice;

  /// The laptop's gateway or the server, whichever the laptop sends to at
  /// layer 2 (and whichever sends to the laptop on the reply).
  FjDevice get laptopPeer {
    final Mac next = layer2NextHop(
      srcIp: FjScene.laptop.ip!,
      prefix: FjScene.lanPrefix,
      dstIp: server.ip!,
      dstMac: server.mac,
      gatewayMac: FjScene.routerLan.mac,
    );
    return next == server.mac ? server : FjScene.routerLan;
  }

  FjPorts get ports => up
      ? const FjPorts(FjScene.laptopPort, FjScene.serverPort)
      : const FjPorts(FjScene.serverPort, FjScene.laptopPort);

  FjIp get startIp => FjIp(
    src: up ? FjScene.laptop.ip! : server.ip!,
    dst: up ? server.ip! : FjScene.laptop.ip!,
    ttl: FjScene.startTtl,
    totalLength: cfg.sizes.packet,
    protocol: cfg.transport.ipProtocol,
  );

  /// The IP header as it crosses the air: after the router on the reply.
  FjIp get airIp =>
      (!up && cfg.throughRouter) ? startIp.decremented() : startIp;

  DsCase get airCase => up ? DsCase.toDs : DsCase.fromDs;

  DsParties get airParties => up
      ? DsParties(
          receiver: FjScene.ap,
          transmitter: FjScene.laptop,
          source: FjScene.laptop,
          destination: laptopPeer,
          bssid: FjScene.ap,
        )
      : DsParties(
          receiver: FjScene.laptop,
          transmitter: FjScene.ap,
          source: laptopPeer,
          destination: FjScene.laptop,
          bssid: FjScene.ap,
        );
}

/// Builds the whole journey for [cfg], one step per layer crossed.
List<FjStep> buildJourney(FjConfig cfg) {
  final _Hops h = _Hops(cfg);
  final FjSizes s = cfg.sizes;
  final bool up = h.up;
  final FjDevice server = h.server;
  final List<FjStep> out = <FjStep>[];
  final String t = cfg.transport.label;

  FjIp ip = h.startIp;
  final FjPorts ports = h.ports;

  // Piece builders.
  FjPiece data() => FjPiece(FjPart.data, s.payload, 'Data ${s.payload} B');
  FjPiece tHdr() =>
      FjPiece(FjPart.transport, s.transportHeader, '$t ${s.transportHeader} B');
  FjPiece ipHdr() => FjPiece(FjPart.ip, s.ipHeader, 'IPv4 ${s.ipHeader} B');
  FjPiece llc() =>
      FjPiece(FjPart.llcSnap, s.llcSnap, 'LLC/SNAP ${s.llcSnap} B');
  FjPiece wifi() =>
      FjPiece(FjPart.wifiHeader, s.macHeader, '802.11 ${s.macHeader} B');
  FjPiece fcs() => FjPiece(FjPart.fcs, s.fcs, 'FCS ${s.fcs} B');
  FjPiece eth() => FjPiece(
    FjPart.ethHeader,
    kEthernetHeaderBytes,
    'Ethernet $kEthernetHeaderBytes B',
  );
  FjPiece ethFcs() =>
      FjPiece(FjPart.fcs, kEthernetFcsBytes, 'FCS $kEthernetFcsBytes B');
  FjPiece bits(int bytes) => FjPiece(FjPart.bits, bytes, '${bytes * 8} bits');

  List<FjPiece> segment() => <FjPiece>[tHdr(), data()];
  List<FjPiece> packet() => <FjPiece>[ipHdr(), ...segment()];
  List<FjPiece> wifiFrame() => <FjPiece>[wifi(), llc(), ...packet(), fcs()];
  List<FjPiece> ethFrame() => <FjPiece>[eth(), ...packet(), ethFcs()];

  void add({
    required String title,
    required String detail,
    required FjAction action,
    required List<FjPiece> pieces,
    FjNode? node,
    FjLayer? layer,
    FjMedium? medium,
    FjNode? from,
    FjNode? to,
    FjLink? link,
    Set<FjPart> changed = const <FjPart>{},
  }) {
    out.add(
      FjStep(
        index: out.length,
        title: title,
        detail: detail,
        action: action,
        pieces: pieces,
        node: node,
        layer: layer,
        medium: medium,
        from: from,
        to: to,
        link: link,
        ip: ip,
        ports: ports,
        changed: changed,
      ),
    );
  }

  // The links on each hop.
  final FjWifiLink airLink = FjWifiLink(
    h.airCase,
    addressFields(h.airCase, h.airParties),
  );
  // Ethernet between the AP and the router (or the same-subnet server). On
  // the way up the AP forwards with the laptop's MAC as the source: it is a
  // bridge and never appears as an Ethernet address.
  final FjEthLink lanLink = up
      ? FjEthLink(src: FjScene.laptop, dst: h.laptopPeer)
      : FjEthLink(src: h.laptopPeer, dst: FjScene.laptop);
  // Ethernet between the router and the server.
  final FjEthLink farLink = up
      ? FjEthLink(src: FjScene.routerOther, dst: server)
      : FjEthLink(src: server, dst: FjScene.routerOther);

  // ── The sender goes down its stack ──
  final FjNode first = up ? FjNode.laptop : FjNode.server;
  final String firstName = up ? 'laptop' : 'server';
  add(
    title: '${first.label}: application data',
    detail:
        'The ${up ? 'browser on the laptop' : 'web service on the server'} '
        'hands ${s.payload} bytes of data to the stack.',
    action: FjAction.none,
    pieces: <FjPiece>[data()],
    node: first,
    layer: FjLayer.application,
    changed: <FjPart>{FjPart.data},
  );
  add(
    title: '${first.label}: add the ports ($t header)',
    detail:
        'The transport layer adds a ${s.transportHeader}-byte $t '
        '(${cfg.transport.long}) header with '
        'the source port ${ports.src} and the destination port ${ports.dst}. '
        'Ports say which program on each end the data belongs to.',
    action: FjAction.add,
    pieces: segment(),
    node: first,
    layer: FjLayer.transport,
    changed: <FjPart>{FjPart.transport},
  );
  add(
    title: '${first.label}: add the IP addresses (IPv4 header)',
    detail:
        'The network layer adds a ${s.ipHeader}-byte IPv4 (Internet Protocol '
        'version 4) header: source '
        '${ip.src}, destination ${ip.dst}, TTL (time to live) ${ip.ttl}. '
        'The packet is now ${s.packet} bytes.',
    action: FjAction.add,
    pieces: packet(),
    node: first,
    layer: FjLayer.network,
    changed: <FjPart>{FjPart.ip},
  );
  if (up) {
    final bool viaRouter = cfg.throughRouter;
    add(
      title: 'Laptop: add the MAC addresses (802.11 header)',
      detail: viaRouter
          ? 'The server ${server.ip} is not on the laptop\'s subnet '
                '(192.0.2.0/24), so the laptop sends the frame to its default '
                'gateway, the router, using the router\'s LAN MAC (media '
                'access control) address, which ARP (Address Resolution '
                'Protocol) found. The data link layer adds ${s.llcSnap} bytes '
                'of LLC/SNAP (logical link control and subnetwork access '
                'protocol), a ${s.macHeader}-byte 802.11 '
                '${cfg.qos ? 'QoS (quality of service) Data' : 'Data'} header '
                'with To DS 1, From DS 0 (DS: the distribution system), and a '
                '${s.fcs}-byte FCS (frame check sequence). The frame is '
                '${s.mpdu} bytes.'
          : 'The server ${server.ip} is on the laptop\'s own subnet, so the '
                'laptop sends straight to the server\'s MAC (media access '
                'control) address, which ARP (Address Resolution Protocol) '
                'found. The data link layer adds ${s.llcSnap} bytes of LLC/SNAP '
                '(logical link control and subnetwork access protocol), a '
                '${s.macHeader}-byte 802.11 '
                '${cfg.qos ? 'QoS (quality of service) Data' : 'Data'} header '
                'with To DS 1, From DS 0 (DS: the distribution system), and a '
                '${s.fcs}-byte FCS (frame check sequence). The frame is '
                '${s.mpdu} bytes.',
      action: FjAction.add,
      pieces: wifiFrame(),
      node: FjNode.laptop,
      layer: FjLayer.dataLink,
      link: airLink,
      changed: <FjPart>{FjPart.wifiHeader, FjPart.llcSnap, FjPart.fcs},
    );
    add(
      title: 'Laptop: turn the frame into bits, then radio waves',
      detail:
          'The physical layer sends the ${s.mpdu} bytes as ${s.mpduBits} bits, '
          'carried by RF (radio frequency) waves. The radio also sends a preamble in front of '
          'the frame (see PHY Preamble); A Frame\'s Journey follows this hop '
          'bit by bit.',
      action: FjAction.change,
      pieces: <FjPiece>[bits(s.mpdu)],
      node: FjNode.laptop,
      layer: FjLayer.physical,
      link: airLink,
      changed: <FjPart>{FjPart.bits},
    );
    add(
      title: 'Across the air to the AP',
      detail:
          'The same bits cross the air gap as RF (radio frequency). Nothing '
          'in the frame changes in flight.',
      action: FjAction.cross,
      pieces: <FjPiece>[bits(s.mpdu)],
      medium: FjMedium.air,
      from: FjNode.laptop,
      to: FjNode.ap,
      link: airLink,
    );
    add(
      title: 'AP: radio waves back into bits',
      detail:
          'The AP\'s radio decodes the radio waves back into ${s.mpduBits} '
          'bits.',
      action: FjAction.change,
      pieces: wifiFrame(),
      node: FjNode.ap,
      layer: FjLayer.physical,
      link: airLink,
      changed: <FjPart>{FjPart.bits},
    );
    add(
      title: 'AP: check the FCS, remove the 802.11 header',
      detail:
          'Address 1 is the AP\'s BSSID (basic service set identifier), so '
          'the frame is for this radio. The '
          'FCS checks out and the AP sends an ACK (acknowledgment). It removes '
          'the 802.11 header, the LLC/SNAP and the FCS, keeping the laptop\'s '
          'MAC and Address 3 to build the Ethernet frame. It never reads the '
          'IP header: an AP is a bridge.',
      action: FjAction.remove,
      pieces: packet(),
      node: FjNode.ap,
      layer: FjLayer.dataLink,
      changed: <FjPart>{FjPart.wifiHeader, FjPart.llcSnap, FjPart.fcs},
    );
    add(
      title: 'AP: add an Ethernet header',
      detail:
          'The AP turns the LLC/SNAP back into an EtherType and adds a '
          '$kEthernetHeaderBytes-byte Ethernet header and a '
          '$kEthernetFcsBytes-byte FCS: source ${lanLink.src.mac} (the '
          'laptop, not the AP), destination ${lanLink.dst.mac} '
          '(${lanLink.dst.phrase}). The frame is '
          '${s.ethernetFrame} bytes.',
      action: FjAction.add,
      pieces: ethFrame(),
      node: FjNode.ap,
      layer: FjLayer.dataLink,
      link: lanLink,
      changed: <FjPart>{FjPart.ethHeader, FjPart.fcs},
    );
    add(
      title: 'AP: bits onto the wire',
      detail: 'The AP sends ${s.ethernetBits} bits onto the Ethernet cable.',
      action: FjAction.change,
      pieces: <FjPiece>[bits(s.ethernetFrame)],
      node: FjNode.ap,
      layer: FjLayer.physical,
      link: lanLink,
      changed: <FjPart>{FjPart.bits},
    );
    final FjNode lanPeer = viaRouter ? FjNode.router : FjNode.server;
    add(
      title: 'Along the wire to the ${lanPeer.label.toLowerCase()}',
      detail: 'The same bits travel the Ethernet cable.',
      action: FjAction.cross,
      pieces: <FjPiece>[bits(s.ethernetFrame)],
      medium: FjMedium.wire,
      from: FjNode.ap,
      to: lanPeer,
      link: lanLink,
    );
    if (viaRouter) {
      _routerSteps(
        add: add,
        cfg: cfg,
        s: s,
        inLink: lanLink,
        outLink: farLink,
        ipIn: () => ip,
        setIp: (FjIp v) => ip = v,
        ethFrame: ethFrame,
        packet: packet,
        bits: bits,
        nextNode: FjNode.server,
      );
    }
    _climb(
      add: add,
      node: FjNode.server,
      s: s,
      t: t,
      ip: () => ip,
      ports: ports,
      link: viaRouter ? farLink : lanLink,
      ethFrame: ethFrame,
      packet: packet,
      segment: segment,
      data: data,
      programName: 'the web service',
    );
    return out;
  }

  // ── The reply: server down, then router, AP, laptop ──
  final bool viaRouter = cfg.throughRouter;
  final FjEthLink serverLink = viaRouter ? farLink : lanLink;
  final FjDevice serverNext = viaRouter ? FjScene.routerOther : FjScene.laptop;
  add(
    title: 'Server: add the MAC addresses (Ethernet header)',
    detail: viaRouter
        ? 'The laptop ${FjScene.laptop.ip} is on another subnet, so the '
              'server sends to its own gateway, the router\'s server-side '
              'interface, MAC (media access control) address '
              '${FjScene.routerOther.mac}. Ethernet adds a '
              '$kEthernetHeaderBytes-byte header and a $kEthernetFcsBytes-byte '
              'FCS (frame check sequence): ${s.ethernetFrame} bytes.'
        : 'The laptop is on the same subnet, so the server sends straight to '
              'the laptop\'s MAC (media access control) address '
              '${serverNext.mac}; the AP will bridge it. '
              'Ethernet adds a $kEthernetHeaderBytes-byte header and a '
              '$kEthernetFcsBytes-byte FCS (frame check sequence): '
              '${s.ethernetFrame} bytes.',
    action: FjAction.add,
    pieces: ethFrame(),
    node: FjNode.server,
    layer: FjLayer.dataLink,
    link: serverLink,
    changed: <FjPart>{FjPart.ethHeader, FjPart.fcs},
  );
  add(
    title: 'Server: bits onto the wire',
    detail: 'The server sends ${s.ethernetBits} bits onto the cable.',
    action: FjAction.change,
    pieces: <FjPiece>[bits(s.ethernetFrame)],
    node: FjNode.server,
    layer: FjLayer.physical,
    link: serverLink,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: viaRouter
        ? 'Along the wire to the router'
        : 'Along the wire to the AP',
    detail: 'The same bits travel the Ethernet cable.',
    action: FjAction.cross,
    pieces: <FjPiece>[bits(s.ethernetFrame)],
    medium: FjMedium.wire,
    from: FjNode.server,
    to: viaRouter ? FjNode.router : FjNode.ap,
    link: serverLink,
  );
  if (viaRouter) {
    _routerSteps(
      add: add,
      cfg: cfg,
      s: s,
      inLink: farLink,
      outLink: lanLink,
      ipIn: () => ip,
      setIp: (FjIp v) => ip = v,
      ethFrame: ethFrame,
      packet: packet,
      bits: bits,
      nextNode: FjNode.ap,
    );
  }
  add(
    title: 'AP: bits off the wire',
    detail: 'The AP reads ${s.ethernetBits} bits off the cable.',
    action: FjAction.change,
    pieces: ethFrame(),
    node: FjNode.ap,
    layer: FjLayer.physical,
    link: lanLink,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: 'AP: remove the Ethernet header',
    detail:
        'The destination ${FjScene.laptop.mac} is a client of this AP. The '
        'AP removes the Ethernet header and FCS, keeping the source MAC '
        '${lanLink.src.mac} (${lanLink.src.phrase}) for Address '
        '3. It never reads the IP header.',
    action: FjAction.remove,
    pieces: packet(),
    node: FjNode.ap,
    layer: FjLayer.dataLink,
    changed: <FjPart>{FjPart.ethHeader, FjPart.fcs},
  );
  add(
    title: 'AP: add the 802.11 header',
    detail:
        'The AP adds LLC/SNAP (logical link control and subnetwork access '
        'protocol), a ${s.macHeader}-byte 802.11 header with To DS 0, From '
        'DS 1 (DS: the distribution system), and an FCS: Address 1 is the '
        'laptop (receiver and destination), Address 2 the AP\'s BSSID (basic '
        'service set identifier, here the transmitter), Address 3 '
        '${lanLink.src.phrase} (source). ${s.mpdu} bytes.',
    action: FjAction.add,
    pieces: wifiFrame(),
    node: FjNode.ap,
    layer: FjLayer.dataLink,
    link: airLink,
    changed: <FjPart>{FjPart.wifiHeader, FjPart.llcSnap, FjPart.fcs},
  );
  add(
    title: 'AP: turn the frame into bits, then radio waves',
    detail:
        'The AP\'s radio sends ${s.mpduBits} bits as RF (radio frequency) '
        'waves.',
    action: FjAction.change,
    pieces: <FjPiece>[bits(s.mpdu)],
    node: FjNode.ap,
    layer: FjLayer.physical,
    link: airLink,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: 'Across the air to the laptop',
    detail:
        'The same bits cross the air gap as radio waves. Nothing in the '
        'frame changes in flight.',
    action: FjAction.cross,
    pieces: <FjPiece>[bits(s.mpdu)],
    medium: FjMedium.air,
    from: FjNode.ap,
    to: FjNode.laptop,
    link: airLink,
  );
  add(
    title: 'Laptop: radio waves back into bits',
    detail:
        'The laptop\'s radio decodes the radio waves back into '
        '${s.mpduBits} bits.',
    action: FjAction.change,
    pieces: wifiFrame(),
    node: FjNode.laptop,
    layer: FjLayer.physical,
    link: airLink,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: 'Laptop: check the FCS, remove the 802.11 header',
    detail:
        'Address 1 is the laptop\'s own MAC. The FCS checks out, the laptop '
        'sends an ACK, and removes the 802.11 header, LLC/SNAP and FCS.',
    action: FjAction.remove,
    pieces: packet(),
    node: FjNode.laptop,
    layer: FjLayer.dataLink,
    changed: <FjPart>{FjPart.wifiHeader, FjPart.llcSnap, FjPart.fcs},
  );
  add(
    title: 'Laptop: remove the IPv4 header',
    detail:
        'The destination IP ${ip.dst} is the laptop\'s own. Source '
        '${ip.src} is still the server: the IP addresses never changed. TTL '
        'arrived as ${ip.ttl}.',
    action: FjAction.remove,
    pieces: segment(),
    node: FjNode.laptop,
    layer: FjLayer.network,
    changed: <FjPart>{FjPart.ip},
  );
  add(
    title: 'Laptop: remove the $t header',
    detail:
        'Destination port ${ports.dst} tells the laptop which program gets '
        'the data: the browser that asked.',
    action: FjAction.remove,
    pieces: <FjPiece>[data()],
    node: FjNode.laptop,
    layer: FjLayer.transport,
    changed: <FjPart>{FjPart.transport},
  );
  add(
    title: 'Laptop: the data arrives',
    detail:
        'The browser gets the same ${s.payload} bytes the server sent. The '
        '$firstName\'s data went down one stack, across the wire and the air, '
        'and up the other side.',
    action: FjAction.none,
    pieces: <FjPiece>[data()],
    node: FjNode.laptop,
    layer: FjLayer.application,
    changed: <FjPart>{FjPart.data},
  );
  return out;
}

typedef _Add =
    void Function({
      required String title,
      required String detail,
      required FjAction action,
      required List<FjPiece> pieces,
      FjNode? node,
      FjLayer? layer,
      FjMedium? medium,
      FjNode? from,
      FjNode? to,
      FjLink? link,
      Set<FjPart> changed,
    });

void _routerSteps({
  required _Add add,
  required FjConfig cfg,
  required FjSizes s,
  required FjEthLink inLink,
  required FjEthLink outLink,
  required FjIp Function() ipIn,
  required void Function(FjIp) setIp,
  required List<FjPiece> Function() ethFrame,
  required List<FjPiece> Function() packet,
  required FjPiece Function(int) bits,
  required FjNode nextNode,
}) {
  final String inSide = inLink.dst.phrase;
  add(
    title: 'Router: bits off the wire',
    detail: 'The router reads ${s.ethernetBits} bits off the cable.',
    action: FjAction.change,
    pieces: ethFrame(),
    node: FjNode.router,
    layer: FjLayer.physical,
    link: inLink,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: 'Router: remove the Ethernet header',
    detail:
        'The destination MAC ${inLink.dst.mac} is $inSide, so the frame is '
        'for the router. It checks the FCS and removes the Ethernet header.',
    action: FjAction.remove,
    pieces: packet(),
    node: FjNode.router,
    layer: FjLayer.dataLink,
    changed: <FjPart>{FjPart.ethHeader, FjPart.fcs},
  );
  final FjIp before = ipIn();
  final FjIp after = before.decremented();
  setIp(after);
  add(
    title: 'Router: read the destination IP, lower the TTL',
    detail:
        'The destination ${before.dst} is reached through the router\'s other '
        'interface. The router lowers the TTL from ${before.ttl} to '
        '${after.ttl} and recomputes the header checksum '
        '(${hex16(before.checksum)} to ${hex16(after.checksum)}). The source '
        'and destination IP addresses do not change (no NAT, network address '
        'translation).',
    action: FjAction.change,
    pieces: packet(),
    node: FjNode.router,
    layer: FjLayer.network,
    changed: <FjPart>{FjPart.ip},
  );
  add(
    title: 'Router: add a new Ethernet header',
    detail:
        'A brand-new layer 2 header for the next hop: source ${outLink.src.mac} '
        '(${outLink.src.phrase}), destination ${outLink.dst.mac} '
        '(${outLink.dst.phrase}). Both MAC addresses changed; the '
        'IP addresses did not.',
    action: FjAction.add,
    pieces: ethFrame(),
    node: FjNode.router,
    layer: FjLayer.dataLink,
    link: outLink,
    changed: <FjPart>{FjPart.ethHeader, FjPart.fcs},
  );
  add(
    title: 'Router: bits onto the wire',
    detail: 'The router sends ${s.ethernetBits} bits onto the next cable.',
    action: FjAction.change,
    pieces: <FjPiece>[bits(s.ethernetFrame)],
    node: FjNode.router,
    layer: FjLayer.physical,
    link: outLink,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: nextNode == FjNode.ap
        ? 'Along the wire to the AP'
        : 'Along the wire to the ${nextNode.label.toLowerCase()}',
    detail: 'The same bits travel the Ethernet cable.',
    action: FjAction.cross,
    pieces: <FjPiece>[bits(s.ethernetFrame)],
    medium: FjMedium.wire,
    from: FjNode.router,
    to: nextNode,
    link: outLink,
  );
}

void _climb({
  required _Add add,
  required FjNode node,
  required FjSizes s,
  required String t,
  required FjIp Function() ip,
  required FjPorts ports,
  required FjEthLink link,
  required List<FjPiece> Function() ethFrame,
  required List<FjPiece> Function() packet,
  required List<FjPiece> Function() segment,
  required FjPiece Function() data,
  required String programName,
}) {
  add(
    title: '${node.label}: bits off the wire',
    detail:
        'The ${node.label.toLowerCase()} reads ${s.ethernetBits} bits off '
        'the cable.',
    action: FjAction.change,
    pieces: ethFrame(),
    node: node,
    layer: FjLayer.physical,
    link: link,
    changed: <FjPart>{FjPart.bits},
  );
  add(
    title: '${node.label}: remove the Ethernet header',
    detail:
        'The destination MAC ${link.dst.mac} is the ${node.label.toLowerCase()}\'s '
        'own. It checks the FCS and removes the Ethernet header.',
    action: FjAction.remove,
    pieces: packet(),
    node: node,
    layer: FjLayer.dataLink,
    changed: <FjPart>{FjPart.ethHeader, FjPart.fcs},
  );
  add(
    title: '${node.label}: remove the IPv4 header',
    detail:
        'The destination IP ${ip().dst} is the ${node.label.toLowerCase()}\'s '
        'own. Source ${ip().src} is still the laptop: the IP addresses never '
        'changed. TTL arrived as ${ip().ttl}.',
    action: FjAction.remove,
    pieces: segment(),
    node: node,
    layer: FjLayer.network,
    changed: <FjPart>{FjPart.ip},
  );
  add(
    title: '${node.label}: remove the $t header',
    detail:
        'Destination port ${ports.dst} tells the ${node.label.toLowerCase()} '
        'which program gets the data: $programName.',
    action: FjAction.remove,
    pieces: <FjPiece>[data()],
    node: node,
    layer: FjLayer.transport,
    changed: <FjPart>{FjPart.transport},
  );
  add(
    title: '${node.label}: the data arrives',
    detail:
        'The ${node.label.toLowerCase()} gets the same ${s.payload} bytes the '
        'laptop sent: down one stack, across the air and the wire, and up the '
        'other side.',
    action: FjAction.none,
    pieces: <FjPiece>[data()],
    node: node,
    layer: FjLayer.application,
    changed: <FjPart>{FjPart.data},
  );
}

/// The nodes the journey passes, in drawing order (left to right).
List<FjNode> journeyNodes(FjConfig cfg) => cfg.throughRouter
    ? const <FjNode>[FjNode.laptop, FjNode.ap, FjNode.router, FjNode.server]
    : const <FjNode>[FjNode.laptop, FjNode.ap, FjNode.server];

// ── A Frame's Journey: the air hop, bit by bit ──────────────────────────────

/// The three bands.
enum FjBand {
  ghz24('2.4 GHz', 2437, 6),
  ghz5('5 GHz', 5180, 36),
  ghz6('6 GHz', 6135, 37);

  const FjBand(this.label, this.freqMHz, this.channel);

  final String label;

  /// Center frequency of the 20 MHz channel used (radiotap Channel field).
  final int freqMHz;
  final int channel;
}

/// The gap before the ACK.
class SifsTiming {
  const SifsTiming(this.sifsUs, this.signalExtensionUs);

  /// SIFS (short interframe space) for the band.
  final int sifsUs;

  /// Signal extension after an ERP-OFDM or HT PPDU at 2.4 GHz; 0 otherwise.
  final int signalExtensionUs;

  /// What the gap looks like on the air.
  int get gapUs => sifsUs + signalExtensionUs;
}

/// SIFS by band: 16 us at 5 and 6 GHz; 10 us plus a 6 us signal extension
/// at 2.4 GHz (OFDM frames).
SifsTiming sifsFor(FjBand b) => switch (b) {
  FjBand.ghz24 => const SifsTiming(10, 6),
  FjBand.ghz5 => const SifsTiming(16, 0),
  FjBand.ghz6 => const SifsTiming(16, 0),
};

/// Transmit EIRP for the level readout (illustrative).
const double kFjTxEirpDbm = 20;

/// Distance limits (m).
const double kFjMinDistanceM = 1;
const double kFjMaxDistanceM = 30;
const double kFjDefaultDistanceM = 8;

/// MCS written into the radiotap view (illustrative).
const int kFjRadiotapMcs = 7;

/// TSF timer value at the first frame (illustrative, microseconds).
const int kFjTsfStartUs = 4200000000;

/// Signal level at [distanceM] on [band]: EIRP - free-space path loss, with
/// 0 dBi at the receiver.
double fjSignalDbm(double distanceM, FjBand band) =>
    kFjTxEirpDbm - FsplMath.fsplDb(distanceM, band.freqMHz.toDouble());

/// How long RF takes to cross [distanceM], in nanoseconds.
double fjFlightNs(double distanceM) => distanceM / FsplMath.speedOfLight * 1e9;

/// The radiotap fields a capturing receiver adds (none of them sent).
class RadiotapView {
  const RadiotapView({
    required this.tsftUs,
    required this.signalDbm,
    required this.freqMHz,
    required this.channel,
    required this.mcs,
  });

  /// Bit 0, TSFT: the receiver's TSF timer when the first bit arrived.
  final int tsftUs;

  /// Bit 5, antenna signal, signed dBm.
  final int signalDbm;

  /// Bit 3, channel frequency.
  final int freqMHz;
  final int channel;

  /// Bit 19, MCS (illustrative here).
  final int mcs;
}

/// One stage of A Frame's Journey.
enum FjHopStage {
  build('Build the frame', 'Sender'),
  toRf('Bits become radio waves', 'Sender'),
  air('Across the air', 'Air'),
  decode('Radio waves become bits', 'Receiver'),
  radiotap('The receiver adds what it knows', 'Receiver'),
  fcs('Check the frame', 'Receiver'),
  sifs('Wait before answering', 'Receiver'),
  ack('Send the acknowledgment', 'Receiver'),
  noAck('No acknowledgment', 'Receiver'),
  retry('The sender retries', 'Sender'),
  done('Delivered', 'Sender');

  const FjHopStage(this.label, this.where);
  final String label;
  final String where;
}

/// The inputs for A Frame's Journey.
class FhConfig {
  const FhConfig({
    this.band = FjBand.ghz5,
    this.distanceM = kFjDefaultDistanceM,
    this.corrupt = false,
    this.flipBit = 0,
    this.capturing = true,
    this.transport = FjTransport.tcp,
    this.payload = kFjDefaultPayload,
  });

  final FjBand band;
  final double distanceM;

  /// Flip one bit on the first attempt.
  final bool corrupt;

  /// Which bit to flip, 0 to frame bits - 1.
  final int flipBit;

  /// Whether the receiver is capturing (shows the radiotap view).
  final bool capturing;

  final FjTransport transport;
  final int payload;

  FhConfig copyWith({
    FjBand? band,
    double? distanceM,
    bool? corrupt,
    int? flipBit,
    bool? capturing,
    FjTransport? transport,
    int? payload,
  }) => FhConfig(
    band: band ?? this.band,
    distanceM: distanceM ?? this.distanceM,
    corrupt: corrupt ?? this.corrupt,
    flipBit: flipBit ?? this.flipBit,
    capturing: capturing ?? this.capturing,
    transport: transport ?? this.transport,
    payload: payload ?? this.payload,
  );

  /// The same frame Down the Stack sends on its air hop.
  FjConfig get stack => FjConfig(transport: transport, payload: payload);

  @override
  bool operator ==(Object other) =>
      other is FhConfig &&
      other.band == band &&
      other.distanceM == distanceM &&
      other.corrupt == corrupt &&
      other.flipBit == flipBit &&
      other.capturing == capturing &&
      other.transport == transport &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(
    band,
    distanceM,
    corrupt,
    flipBit,
    capturing,
    transport,
    payload,
  );
}

/// One step of A Frame's Journey.
class FhStep {
  const FhStep({
    required this.index,
    required this.attempt,
    required this.stage,
    required this.title,
    required this.detail,
    required this.frame,
    required this.received,
    this.check,
    this.radiotap,
  });

  final int index;

  /// 1 for the first transmission, 2 for the retry.
  final int attempt;
  final FjHopStage stage;
  final String title;
  final String detail;

  /// The frame as sent on this attempt.
  final AirFrame frame;

  /// The bytes as they arrived (null before they arrive).
  final Uint8List? received;

  /// The FCS check (from the check step on).
  final FcsCheck? check;

  /// The radiotap view (from the radiotap step on, when capturing).
  final RadiotapView? radiotap;

  bool get corruptedAttempt =>
      received != null && !_same(received!, frame.bytes);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The whole hop for [cfg]. A clean frame: build, RF, air, decode, radiotap
/// (when capturing), FCS pass, SIFS, ACK, delivered. A corrupted frame:
/// the first attempt fails its FCS, no ACK comes back, and the second
/// attempt (Retry bit set) goes through clean.
List<FhStep> buildHop(FhConfig cfg) {
  final List<FhStep> out = <FhStep>[];
  final SifsTiming sifs = sifsFor(cfg.band);
  final double level = fjSignalDbm(cfg.distanceM, cfg.band);
  final double flight = fjFlightNs(cfg.distanceM);

  void attempt(int n, {required bool corrupt}) {
    final AirFrame f = airFrameFor(cfg.stack, retry: n > 1);
    final int bit = cfg.flipBit.clamp(0, f.bitCount - 1);
    final Uint8List rx = corrupt
        ? f.withBitFlipped(bit)
        : Uint8List.fromList(f.bytes);
    final FcsCheck check = FcsCheck(rx);
    final RadiotapView rt = RadiotapView(
      // Illustrative TSF start; the retry arrives later (a nominal 1 ms later,
      // illustrative, for the wait and the new contention).
      tsftUs: kFjTsfStartUs + (n - 1) * 1000,
      signalDbm: level.round(),
      freqMHz: cfg.band.freqMHz,
      channel: cfg.band.channel,
      mcs: kFjRadiotapMcs,
    );
    void add(
      FjHopStage stage,
      String title,
      String detail, {
      bool arrived = false,
      bool checked = false,
      bool tapped = false,
    }) {
      out.add(
        FhStep(
          index: out.length,
          attempt: n,
          stage: stage,
          title: title,
          detail: detail,
          frame: f,
          received: arrived ? rx : null,
          check: checked ? check : null,
          radiotap: tapped && cfg.capturing ? rt : null,
        ),
      );
    }

    final String prefix = n > 1 ? 'Retry: ' : '';
    const String us = 'µs';
    add(
      FjHopStage.build,
      n > 1
          ? 'Retry: the sender builds the frame again'
          : 'The sender builds the frame',
      n > 1
          ? 'The sender builds the same frame again with the Retry bit set in '
                'Frame Control. That one bit changes the CRC, so the new FCS '
                'is ${hex32(f.fcsSent)}.'
          : 'The transmitting NIC (network interface card) has a '
                '${f.length}-byte frame: a ${f.sizes.macHeader}-byte 802.11 '
                'header, ${f.sizes.msdu} bytes of body and a 4-byte FCS (frame '
                'check sequence). The FCS is a CRC-32 (32-bit cyclic '
                'redundancy check) over the header and body: '
                '${hex32(f.fcsSent)}.',
    );
    add(
      FjHopStage.toRf,
      '${prefix}Bits become radio waves',
      'The ${f.bitCount} bits modulate an RF (radio frequency) carrier on '
          '${cfg.band.label} (channel ${cfg.band.channel}, '
          '${cfg.band.freqMHz} MHz). A preamble goes out first so the '
          'receiver can lock on (see PHY Preamble).',
    );
    add(
      FjHopStage.air,
      '${prefix}Across the air',
      corrupt
          ? 'The wave loses strength with distance but keeps its frequency; '
                'it arrives at ${level.toStringAsFixed(1)} dBm after '
                '${flight.toStringAsFixed(1)} ns. On the way, bit $bit (in '
                '${f.fieldAtBit(bit).name}) is received wrong.'
          : 'The wave loses strength with distance but keeps its frequency; '
                'it arrives at ${level.toStringAsFixed(1)} dBm after '
                '${flight.toStringAsFixed(1)} ns.',
    );
    add(
      FjHopStage.decode,
      '${prefix}Radio waves become bits',
      'The receiving NIC demodulates the waves back into ${f.bitCount} bits.',
      arrived: true,
    );
    if (cfg.capturing) {
      add(
        FjHopStage.radiotap,
        '${prefix}The receiver adds what it knows',
        'This receiver is capturing, so its driver puts a radiotap header in '
            'front of the frame: when the first bit arrived (by its own TSF, '
            'timing synchronization function, timer), the signal it '
            'measured, the channel and the rate. None of it was sent over '
            'the air.',
        arrived: true,
        tapped: true,
      );
    }
    add(
      FjHopStage.fcs,
      '${prefix}Check the FCS',
      check.pass
          ? 'The receiver runs the same CRC-32 over the header and body and '
                'gets ${hex32(check.computed)}, the same as the FCS that '
                'arrived. The frame is good.'
          : 'The receiver runs the same CRC-32 and gets '
                '${hex32(check.computed)}, but the FCS that arrived says '
                '${hex32(check.arrived)}. One wrong bit is enough: the frame '
                'is thrown away.',
      arrived: true,
      checked: true,
      tapped: true,
    );
    if (check.pass) {
      add(
        FjHopStage.sifs,
        '${prefix}Wait one SIFS',
        sifs.signalExtensionUs > 0
            ? 'The receiver waits one SIFS (short interframe space): '
                  '${sifs.sifsUs} $us on ${cfg.band.label}, after a '
                  '${sifs.signalExtensionUs} $us signal extension that follows '
                  'an OFDM (orthogonal frequency division multiplexing) frame '
                  'there, so the gap is ${sifs.gapUs} $us. The trip across '
                  'took ${flight.toStringAsFixed(1)} ns.'
            : 'The receiver waits one SIFS (short interframe space): '
                  '${sifs.sifsUs} $us on ${cfg.band.label}. The trip across '
                  'took ${flight.toStringAsFixed(1)} ns.',
        arrived: true,
        checked: true,
        tapped: true,
      );
      add(
        FjHopStage.ack,
        '${prefix}Send the ACK',
        'The receiver sends an ACK (acknowledgment) back to the radio in '
            'Address 2 of the frame, the transmitter '
            '(${addressFields(f.dsCase, _hopParties).elementAt(1).mac}), one '
            'SIFS after the frame ended.',
        arrived: true,
        checked: true,
        tapped: true,
      );
      add(
        FjHopStage.done,
        n > 1 ? 'Delivered on the retry' : 'Delivered',
        n > 1
            ? 'The ACK arrives. The frame got through on the second attempt; '
                  'the first one cost airtime and never counted.'
            : 'The ACK arrives. The sender moves on to its next frame.',
        arrived: true,
        checked: true,
        tapped: true,
      );
    } else {
      add(
        FjHopStage.noAck,
        'No ACK comes back',
        'The receiver says nothing: it sends an ACK (acknowledgment) only for '
            'a frame whose FCS checks out. The sender waits for an ACK that '
            'never comes.',
        arrived: true,
        checked: true,
        tapped: true,
      );
      add(
        FjHopStage.retry,
        'The sender retries',
        'With no ACK, the sender treats the frame as lost, contends for the '
            'air again and sends it again.',
        arrived: true,
        checked: true,
        tapped: true,
      );
    }
  }

  attempt(1, corrupt: cfg.corrupt);
  if (cfg.corrupt) attempt(2, corrupt: false);
  return out;
}

/// The uplink air hop's parties (Laptop to AP, To DS 1).
DsParties get _hopParties => _Hops(const FjConfig()).airParties;

/// The flip-bit slider's upper limit for [cfg].
int fhBitCount(FhConfig cfg) => airFrameFor(cfg.stack).bitCount;
