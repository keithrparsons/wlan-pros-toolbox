// PacketSenderService — send a custom payload to host:port over TCP or UDP and
// return the reply (raw bytes + hex + decoded text).
//
// HARD SCOPE LINE (TICKET-005 + GL-008): TCP via `Socket`, UDP via
// `RawDatagramSocket`. NO raw sockets, NO custom ICMP/IP framing — that is the
// same iOS App Sandbox wall that blocked our ICMP traceroute. Both transports
// here use the ordinary network-client capability we already declare for the
// port scanner, so the tool ships clean on every native platform.
//
// TCP: connect (with timeout) → send the payload → read until the peer closes
// the connection OR the read goes idle for [timeout]. Most banner/HTTP services
// answer and either close or fall silent, so an idle-read deadline is what makes
// the "done receiving" decision; a hard total cap prevents a chatty stream from
// running forever.
//
// UDP: bind an ephemeral socket → send one datagram → wait up to [timeout] for a
// reply. UDP has NO delivery guarantee, so "no reply" is a first-class,
// non-error outcome (the service returns a result flagged [timedOut], not an
// exception) — the UI states that honestly.
//
// Web safety: imports `dart:io`. Gated behind
// `NetworkSupport.packetSenderSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Transport for a send attempt.
enum PacketTransport { tcp, udp }

/// Typed failure categories, mirroring the open/closed/filtered taxonomy style
/// of the other socket tools so the UI maps each to a precise message.
enum PacketErrorKind {
  /// Host name did not resolve.
  dnsFailure,

  /// TCP connection actively refused (nothing listening) / reset.
  refused,

  /// Host/network unreachable (no route).
  unreachable,

  /// Connect or read deadline elapsed with no usable response.
  timeout,

  /// Input rejected before any I/O (bad port, empty host, bad hex payload).
  invalidInput,

  /// Anything else (socket bind failure, OS error).
  other,
}

/// The outcome of one send attempt. Always returned, never thrown.
class PacketResult {
  const PacketResult._({
    required this.transport,
    required this.host,
    required this.port,
    required this.bytesSent,
    required this.received,
    required this.elapsed,
    required this.timedOut,
    this.errorKind,
    this.errorMessage,
  });

  /// A successful (or UDP no-reply) outcome.
  factory PacketResult.ok({
    required PacketTransport transport,
    required String host,
    required int port,
    required int bytesSent,
    required List<int> received,
    required Duration elapsed,
    required bool timedOut,
  }) =>
      PacketResult._(
        transport: transport,
        host: host,
        port: port,
        bytesSent: bytesSent,
        received: List<int>.unmodifiable(received),
        elapsed: elapsed,
        timedOut: timedOut,
      );

  /// A failed outcome with a typed [kind] and a user-facing [message].
  factory PacketResult.failure({
    required PacketTransport transport,
    required String host,
    required int port,
    required PacketErrorKind kind,
    required String message,
    int bytesSent = 0,
    Duration elapsed = Duration.zero,
  }) =>
      PacketResult._(
        transport: transport,
        host: host,
        port: port,
        bytesSent: bytesSent,
        received: const <int>[],
        elapsed: elapsed,
        timedOut: kind == PacketErrorKind.timeout,
        errorKind: kind,
        errorMessage: message,
      );

  final PacketTransport transport;
  final String host;
  final int port;

  /// Bytes the payload occupied on the wire.
  final int bytesSent;

  /// Bytes received from the peer (possibly empty).
  final List<int> received;

  final Duration elapsed;

  /// True when the read/connect deadline elapsed. For UDP this is the honest
  /// "no reply arrived" signal and is NOT treated as an error.
  final bool timedOut;

  final PacketErrorKind? errorKind;
  final String? errorMessage;

  bool get isError => errorKind != null;

  /// True for a UDP send that completed but got no datagram back.
  bool get isNoReply =>
      !isError && transport == PacketTransport.udp && received.isEmpty;
}

/// Sends payloads over TCP/UDP. The [tcpConnector] and [udpBinder] seams keep
/// the transport logic testable against in-process echo servers without a live
/// network.
class PacketSenderService {
  PacketSenderService({
    Future<Socket> Function(String host, int port, {required Duration timeout})?
        tcpConnector,
    Future<RawDatagramSocket> Function()? udpBinder,
  })  : _tcpConnect = tcpConnector ?? _defaultTcpConnect,
        _udpBind = udpBinder ?? _defaultUdpBind;

  final Future<Socket> Function(String host, int port,
      {required Duration timeout}) _tcpConnect;
  final Future<RawDatagramSocket> Function() _udpBind;

  static const Duration defaultTimeout = Duration(seconds: 4);

  static Future<Socket> _defaultTcpConnect(
    String host,
    int port, {
    required Duration timeout,
  }) =>
      Socket.connect(host, port, timeout: timeout);

  static Future<RawDatagramSocket> _defaultUdpBind() =>
      RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  /// Parse a payload string into bytes. Supports plain text AND hex-escape
  /// entry: `\xNN` for a literal byte, plus the usual `\r \n \t \0 \\`. Unknown
  /// escapes are kept literally. Returns null only when a `\x` is not followed
  /// by two hex digits (a clear authoring mistake worth surfacing).
  static List<int>? parsePayload(String input) {
    final List<int> out = <int>[];
    int i = 0;
    final List<int> units = input.codeUnits;
    while (i < units.length) {
      final int c = units[i];
      if (c == 0x5C && i + 1 < units.length) {
        // backslash
        final int next = units[i + 1];
        switch (next) {
          case 0x78: // 'x' → \xNN
          case 0x58: // 'X'
            if (i + 3 < units.length) {
              final String hex = String.fromCharCodes(units, i + 2, i + 4);
              final int? byte = int.tryParse(hex, radix: 16);
              if (byte == null) return null;
              out.add(byte);
              i += 4;
              continue;
            }
            return null;
          case 0x6E: // n
            out.add(0x0A);
            i += 2;
            continue;
          case 0x72: // r
            out.add(0x0D);
            i += 2;
            continue;
          case 0x74: // t
            out.add(0x09);
            i += 2;
            continue;
          case 0x30: // 0
            out.add(0x00);
            i += 2;
            continue;
          case 0x5C: // backslash
            out.add(0x5C);
            i += 2;
            continue;
          default:
            // Unknown escape — keep the backslash literally.
            out.add(c);
            i += 1;
            continue;
        }
      }
      // Encode any non-ASCII text as UTF-8.
      if (c <= 0x7F) {
        out.add(c);
        i += 1;
      } else {
        out.addAll(utf8.encode(String.fromCharCode(c)));
        i += 1;
      }
    }
    return out;
  }

  /// Hex dump of [bytes] as space-free two-digit-per-byte (e.g. "0d0aff").
  static String toHex(List<int> bytes) {
    final StringBuffer sb = StringBuffer();
    for (final int b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Best-effort UTF-8 / ASCII decode for display. Invalid sequences become the
  /// Unicode replacement char rather than throwing, so a binary reply still
  /// renders.
  static String decodeText(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  static bool _validPort(int p) => p >= 1 && p <= 65535;

  /// Send [payload] to [host]:[port] over [transport], returning the reply.
  Future<PacketResult> send({
    required PacketTransport transport,
    required String host,
    required int port,
    required List<int> payload,
    Duration timeout = defaultTimeout,
  }) {
    final String h = host.trim();
    if (h.isEmpty) {
      return Future<PacketResult>.value(
        PacketResult.failure(
          transport: transport,
          host: h,
          port: port,
          kind: PacketErrorKind.invalidInput,
          message: 'Enter a host or IP address.',
        ),
      );
    }
    if (!_validPort(port)) {
      return Future<PacketResult>.value(
        PacketResult.failure(
          transport: transport,
          host: h,
          port: port,
          kind: PacketErrorKind.invalidInput,
          message: 'Port must be between 1 and 65535.',
        ),
      );
    }
    return transport == PacketTransport.tcp
        ? _sendTcp(h, port, payload, timeout)
        : _sendUdp(h, port, payload, timeout);
  }

  Future<PacketResult> _sendTcp(
    String host,
    int port,
    List<int> payload,
    Duration timeout,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await _tcpConnect(host, port, timeout: timeout);
      final Socket s = socket;
      final List<int> received = <int>[];
      final Completer<void> done = Completer<void>();
      Timer? idle;

      void resetIdle() {
        idle?.cancel();
        idle = Timer(timeout, () {
          if (!done.isCompleted) done.complete();
        });
      }

      final StreamSubscription<List<int>> sub = s.listen(
        (List<int> data) {
          received.addAll(data);
          resetIdle();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      if (payload.isNotEmpty) s.add(payload);
      await s.flush();
      resetIdle();

      // Hard total cap so a chatty stream can't run unbounded.
      final Timer hardCap = Timer(timeout * 3, () {
        if (!done.isCompleted) done.complete();
      });

      await done.future;
      idle?.cancel();
      hardCap.cancel();
      await sub.cancel();
      s.destroy();
      sw.stop();

      return PacketResult.ok(
        transport: PacketTransport.tcp,
        host: host,
        port: port,
        bytesSent: payload.length,
        received: received,
        elapsed: sw.elapsed,
        timedOut: received.isEmpty,
      );
    } on SocketException catch (e) {
      sw.stop();
      socket?.destroy();
      return _classifyTcp(host, port, e, sw.elapsed, timeout);
    } on Object catch (e) {
      sw.stop();
      socket?.destroy();
      return PacketResult.failure(
        transport: PacketTransport.tcp,
        host: host,
        port: port,
        kind: PacketErrorKind.other,
        message: 'Send failed: ${_short(e.toString())}.',
        elapsed: sw.elapsed,
      );
    }
  }

  PacketResult _classifyTcp(
    String host,
    int port,
    SocketException e,
    Duration elapsed,
    Duration timeout,
  ) {
    final OSError? os = e.osError;
    final String msg = e.message.toLowerCase();
    final PacketErrorKind kind;
    final String message;
    if (os == null && elapsed >= timeout - const Duration(milliseconds: 50)) {
      kind = PacketErrorKind.timeout;
      message = 'Timed out connecting to $host:$port — no response before the '
          'deadline (a firewall may be dropping the connection).';
    } else if (msg.contains('refused') || msg.contains('reset')) {
      kind = PacketErrorKind.refused;
      message = 'Connection refused — nothing is listening on $host:$port.';
    } else if (msg.contains('unreachable') || msg.contains('no route')) {
      kind = PacketErrorKind.unreachable;
      message = 'Host unreachable — no route to $host.';
    } else if (msg.contains('failed host lookup') ||
        msg.contains('lookup') ||
        msg.contains('nodename') ||
        msg.contains('not known')) {
      kind = PacketErrorKind.dnsFailure;
      message = 'Could not resolve "$host" — check the host name.';
    } else {
      kind = PacketErrorKind.other;
      message = 'Could not connect: ${_short(e.message)}.';
    }
    return PacketResult.failure(
      transport: PacketTransport.tcp,
      host: host,
      port: port,
      kind: kind,
      message: message,
      elapsed: elapsed,
    );
  }

  Future<PacketResult> _sendUdp(
    String host,
    int port,
    List<int> payload,
    Duration timeout,
  ) async {
    final Stopwatch sw = Stopwatch()..start();
    // Resolve the host first so a DNS failure is a clean typed error rather than
    // a silent no-reply.
    final InternetAddress dest;
    try {
      if (InternetAddress.tryParse(host) != null) {
        dest = InternetAddress(host);
      } else {
        final List<InternetAddress> addrs = await InternetAddress.lookup(host);
        if (addrs.isEmpty) {
          sw.stop();
          return PacketResult.failure(
            transport: PacketTransport.udp,
            host: host,
            port: port,
            kind: PacketErrorKind.dnsFailure,
            message: 'Could not resolve "$host" — check the host name.',
            elapsed: sw.elapsed,
          );
        }
        dest = addrs.first;
      }
    } on SocketException {
      sw.stop();
      return PacketResult.failure(
        transport: PacketTransport.udp,
        host: host,
        port: port,
        kind: PacketErrorKind.dnsFailure,
        message: 'Could not resolve "$host" — check the host name.',
        elapsed: sw.elapsed,
      );
    }

    RawDatagramSocket? socket;
    try {
      socket = await _udpBind();
      final RawDatagramSocket s = socket;
      final List<int> received = <int>[];
      final Completer<void> gotReply = Completer<void>();

      final StreamSubscription<RawSocketEvent> sub = s.listen((RawSocketEvent ev) {
        if (ev == RawSocketEvent.read) {
          final Datagram? dg = s.receive();
          if (dg != null) {
            received.addAll(dg.data);
            if (!gotReply.isCompleted) gotReply.complete();
          }
        }
      });

      final int sent = s.send(payload, dest, port);

      // Wait for a reply or the timeout. UDP no-reply is a valid outcome.
      await gotReply.future.timeout(timeout, onTimeout: () {});
      await sub.cancel();
      s.close();
      sw.stop();

      return PacketResult.ok(
        transport: PacketTransport.udp,
        host: host,
        port: port,
        bytesSent: sent,
        received: received,
        elapsed: sw.elapsed,
        timedOut: received.isEmpty,
      );
    } on SocketException catch (e) {
      sw.stop();
      socket?.close();
      return PacketResult.failure(
        transport: PacketTransport.udp,
        host: host,
        port: port,
        kind: PacketErrorKind.other,
        message: 'Could not send the datagram: ${_short(e.message)}.',
        elapsed: sw.elapsed,
      );
    } on Object catch (e) {
      sw.stop();
      socket?.close();
      return PacketResult.failure(
        transport: PacketTransport.udp,
        host: host,
        port: port,
        kind: PacketErrorKind.other,
        message: 'Send failed: ${_short(e.toString())}.',
        elapsed: sw.elapsed,
      );
    }
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}
