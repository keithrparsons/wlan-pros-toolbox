// WakeOnLanService — build and send a Wake-on-LAN "magic packet".
//
// WHAT A MAGIC PACKET IS: 6 bytes of 0xFF followed by the target's 6-byte MAC
// repeated 16 times = 102 bytes total. It is sent as a UDP datagram to the
// broadcast address (default 255.255.255.255) on port 9 (or 7), so every NIC
// on the segment sees it; a NIC in WoL mode wakes when it matches its own MAC.
//
// TRANSPORT: a UDP broadcast datagram via `RawDatagramSocket.bind` +
// `broadcastEnabled = true` + `send`. No subprocess, no raw/privileged socket
// — works on every native platform. The macOS `network.client` entitlement and
// the iOS `NSLocalNetworkUsageDescription` (already shipped for the active
// network tools) cover an outbound UDP broadcast to the local segment.
//
// FIRE-AND-FORGET: WoL has NO acknowledgement. A switch may also not forward a
// 255.255.255.255 broadcast across subnets, and the target may ignore the
// packet if WoL is disabled in its BIOS/OS. So the success result asserts only
// that the packet was SENT — it never claims the device woke. The UI copy must
// honor this (see WakeOnLanScreen).
//
// Web safety: imports `dart:io` (RawDatagramSocket). Gated behind
// `NetworkSupport.wakeOnLanSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

/// Outcome of a send attempt. Success means the datagram left the socket; it
/// makes no claim about the target waking (WoL is unacknowledged).
class WakeOnLanResult {
  const WakeOnLanResult._({
    required this.normalizedMac,
    required this.broadcast,
    required this.port,
    required this.bytesSent,
    this.errorMessage,
  });

  factory WakeOnLanResult.sent({
    required String normalizedMac,
    required String broadcast,
    required int port,
    required int bytesSent,
  }) =>
      WakeOnLanResult._(
        normalizedMac: normalizedMac,
        broadcast: broadcast,
        port: port,
        bytesSent: bytesSent,
      );

  factory WakeOnLanResult.failure({
    required String message,
    String normalizedMac = '',
    String broadcast = '',
    int port = 0,
  }) =>
      WakeOnLanResult._(
        normalizedMac: normalizedMac,
        broadcast: broadcast,
        port: port,
        bytesSent: 0,
        errorMessage: message,
      );

  /// The target MAC in canonical aa:bb:cc:dd:ee:ff form.
  final String normalizedMac;
  final String broadcast;
  final int port;

  /// Number of bytes the socket reported as sent (102 for a full magic packet).
  final int bytesSent;

  final String? errorMessage;

  bool get isError => errorMessage != null;
}

/// Builds the magic packet, validates inputs, and sends the UDP broadcast. The
/// [sender] seam abstracts the actual datagram send so the packet construction
/// and MAC/broadcast validation are unit-testable without touching the network.
class WakeOnLanService {
  WakeOnLanService({WolSender? sender}) : _send = sender ?? _defaultSend;

  final WolSender _send;

  /// Default WoL port. Port 9 (discard) is the de-facto standard; port 7
  /// (echo) is the documented alternative the UI also offers.
  static const int defaultPort = 9;

  /// Default broadcast target — the limited (all-ones) broadcast address.
  static const String defaultBroadcast = '255.255.255.255';

  static Future<int> _defaultSend(
    List<int> packet,
    InternetAddress destination,
    int port,
  ) async {
    // Bind any local IPv4 interface/ephemeral port, enable broadcast, send.
    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    try {
      socket.broadcastEnabled = true;
      return socket.send(packet, destination, port);
    } finally {
      socket.close();
    }
  }

  /// Send a magic packet to wake the host identified by [rawMac].
  ///
  /// - [rawBroadcast] defaults to 255.255.255.255; pass a subnet-directed
  ///   broadcast (e.g. 192.168.1.255) to cross a router that drops the
  ///   all-ones broadcast.
  /// - [port] defaults to 9; 7 is also accepted.
  ///
  /// Returns [WakeOnLanResult.sent] only — never claims the device woke.
  Future<WakeOnLanResult> wake({
    required String rawMac,
    String? rawBroadcast,
    int port = defaultPort,
  }) async {
    final String? mac = normalizeMac(rawMac);
    if (mac == null) {
      return WakeOnLanResult.failure(
        message: 'Enter a valid MAC address — 6 bytes, e.g. '
            'AA:BB:CC:DD:EE:FF (colons, hyphens, or no separators all work).',
      );
    }

    final String broadcast = (rawBroadcast == null || rawBroadcast.trim().isEmpty)
        ? defaultBroadcast
        : rawBroadcast.trim();

    if (!_isValidIpv4(broadcast)) {
      return WakeOnLanResult.failure(
        normalizedMac: mac,
        message: 'Broadcast address must be a valid IPv4 address, '
            'e.g. 255.255.255.255 or 192.168.1.255.',
      );
    }

    if (port < 1 || port > 65535) {
      return WakeOnLanResult.failure(
        normalizedMac: mac,
        broadcast: broadcast,
        message: 'Port must be between 1 and 65535 (typically 9 or 7).',
      );
    }

    final List<int> packet = buildMagicPacket(mac);

    try {
      final InternetAddress dest = InternetAddress(broadcast);
      final int sent = await _send(packet, dest, port);
      if (sent <= 0) {
        return WakeOnLanResult.failure(
          normalizedMac: mac,
          broadcast: broadcast,
          port: port,
          message: 'The socket reported 0 bytes sent — the broadcast may be '
              'blocked by the OS or interface. Try a subnet-directed '
              'broadcast (e.g. 192.168.1.255).',
        );
      }
      return WakeOnLanResult.sent(
        normalizedMac: mac,
        broadcast: broadcast,
        port: port,
        bytesSent: sent,
      );
    } on SocketException catch (e) {
      return WakeOnLanResult.failure(
        normalizedMac: mac,
        broadcast: broadcast,
        port: port,
        message: 'Could not send the packet: ${_short(e.message)}.',
      );
    } on Object catch (e) {
      return WakeOnLanResult.failure(
        normalizedMac: mac,
        broadcast: broadcast,
        port: port,
        message: 'Send failed: ${_short(e.toString())}.',
      );
    }
  }

  /// Normalize a user-entered MAC to canonical lower-case colon form
  /// (`aa:bb:cc:dd:ee:ff`). Accepts colon-, hyphen-, dot- (Cisco
  /// `aabb.ccdd.eeff`) and no-separator forms. Returns null when the input is
  /// not exactly 6 hex bytes.
  ///
  /// Exposed (static) for unit tests — multi-format parsing is regression-prone.
  static String? normalizeMac(String raw) {
    // Strip every non-hex character, then require exactly 12 hex digits.
    final String hex =
        raw.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 12) return null;
    final List<String> bytes = <String>[];
    for (int i = 0; i < 12; i += 2) {
      bytes.add(hex.substring(i, i + 2));
    }
    return bytes.join(':');
  }

  /// Parse a normalized (or raw) MAC into its 6 bytes. Returns null on invalid
  /// input. Exposed for tests and for [buildMagicPacket].
  static List<int>? macBytes(String mac) {
    final String? norm = normalizeMac(mac);
    if (norm == null) return null;
    return norm
        .split(':')
        .map((String b) => int.parse(b, radix: 16))
        .toList(growable: false);
  }

  /// Build the 102-byte magic packet for [mac]: 6×0xFF + 16× the MAC bytes.
  /// [mac] may be in any accepted format. Throws [ArgumentError] on an invalid
  /// MAC (callers validate first via [normalizeMac]).
  ///
  /// Exposed (static) for unit tests — byte layout is the heart of WoL.
  static List<int> buildMagicPacket(String mac) {
    final List<int>? bytes = macBytes(mac);
    if (bytes == null) {
      throw ArgumentError.value(mac, 'mac', 'Not a valid 6-byte MAC address');
    }
    final List<int> packet = <int>[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
    for (int i = 0; i < 16; i++) {
      packet.addAll(bytes);
    }
    return packet; // 6 + 16*6 = 102 bytes.
  }

  /// A space-free, two-hex-digit-per-byte string of the packet, for the UI to
  /// show what was sent (mono / selectable). e.g. "ffffffffffffaabbcc…".
  static String packetHex(List<int> packet) {
    final StringBuffer sb = StringBuffer();
    for (final int b in packet) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool _isValidIpv4(String s) {
    final List<String> parts = s.split('.');
    if (parts.length != 4) return false;
    for (final String p in parts) {
      if (p.isEmpty || p.length > 3) return false;
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}

/// The injectable send seam: dispatch one datagram, return bytes sent.
typedef WolSender = Future<int> Function(
  List<int> packet,
  InternetAddress destination,
  int port,
);
