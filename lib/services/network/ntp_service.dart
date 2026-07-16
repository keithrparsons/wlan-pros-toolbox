// NtpService — query an NTP server over SNTP and report the server's time, the
// device clock's offset, and the round-trip delay.
//
// TRANSPORT DECISION: SNTP (RFC 4330 / RFC 5905) over a UDP datagram to port
// 123 via `RawDatagramSocket.bind` + `send` + a single read of the reply. NOT a
// subprocess (`sntp`/`ntpdate` are sandbox-blocked) and NOT an HTTPS time API
// (those report the SERVER's time but cannot measure the symmetric round-trip
// the SNTP four-timestamp formula needs to separate offset from delay).
//
// Why this is sandbox/iOS safe:
//  - It is an OUTBOUND UDP client datagram to a REMOTE server (time.apple.com),
//    not a local-network broadcast or a listening server. The macOS
//    `com.apple.security.network.client` entitlement we already ship for every
//    socket tool covers it; iOS allows outbound UDP to a remote host without a
//    local-network grant. (Wake-on-LAN already sends UDP from this app; this is
//    the unicast cousin of that.)
//  - No raw/privileged socket, no subprocess. Works identically on iOS / macOS
//    / Android / Windows. Web has no `dart:io`, so the screen is gated behind
//    `NetworkSupport.ntpSupported` (= !kIsWeb) like the other socket tools.
//
// THE SNTP MATH (RFC 4330 §5):
//   t1 = client transmit time  (recorded here at send)
//   t2 = server receive time   (reply bytes 32..39)
//   t3 = server transmit time  (reply bytes 40..47)
//   t4 = client receive time   (recorded here at receive)
//   clock offset    = ((t2 - t1) + (t3 - t4)) / 2
//   round-trip delay = (t4 - t1) - (t3 - t2)
// A positive offset means the SERVER is ahead of the device, i.e. the device
// clock is SLOW (behind) by that amount. The screen translates the sign into
// plain language so a reader never has to remember the convention.
//
// NTP timestamps are 64-bit fixed-point seconds since 1900-01-01 00:00:00 UTC
// (32 bits integer seconds, 32 bits fraction). Unix epoch (1970) is 2208988800
// seconds later, so unixSeconds = ntpSeconds - 2208988800.
//
// HONESTY (GL-005): a timeout, a DNS failure, an empty/short reply, or a
// server returning the "kiss-o'-death" stratum 0 all surface as a clear, honest
// error or a labeled caveat — never a fabricated offset or a zeroed delay.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'network_target.dart';

/// Seconds between the NTP epoch (1900-01-01) and the Unix epoch (1970-01-01).
const int _ntpToUnixSeconds = 2208988800;

/// The default time server. Apple's pool is the natural first choice on iOS /
/// macOS — it is the same server the OS itself syncs to, low-latency and
/// reliable. `pool.ntp.org` is the documented public fallback.
const String kDefaultNtpServer = 'time.apple.com';

/// A documented public fallback server the UI offers as a one-tap alternative
/// when the default is blocked or slow.
const String kFallbackNtpServer = 'pool.ntp.org';

/// The parsed, computed result of a single SNTP exchange. Pure data — produced
/// by [NtpService.parseReply] from the 48 reply bytes + the client send/receive
/// instants, so it is fully unit-testable without a live network.
class NtpReading {
  const NtpReading({
    required this.stratum,
    required this.serverUtc,
    required this.deviceTime,
    required this.offsetMs,
    required this.delayMs,
  });

  /// The server's stratum byte (0..16). 0 is the packet-header "kiss-o'-death"
  /// / unspecified marker; 1..15 are valid synchronized strata; 16 means
  /// "unsynchronized". The screen maps this to its human meaning.
  final int stratum;

  /// The server's transmit time (t3), in UTC. This is the authoritative "what
  /// time the server thinks it is" value.
  final DateTime serverUtc;

  /// The device clock's reading at the moment the reply arrived (t4). Kept so
  /// the UI can show the device-vs-server comparison without re-reading the
  /// clock (which would drift the displayed pair).
  final DateTime deviceTime;

  /// Signed clock offset in milliseconds. POSITIVE = the device clock is BEHIND
  /// the server (server is ahead); NEGATIVE = the device clock is AHEAD of the
  /// server. Per RFC 4330: offset = ((t2 - t1) + (t3 - t4)) / 2.
  final int offsetMs;

  /// Round-trip network delay in milliseconds: (t4 - t1) - (t3 - t2). Never
  /// negative in a well-behaved exchange; a small negative from clock jitter is
  /// clamped to 0 by [parseReply] so the UI never shows a nonsensical value.
  final int delayMs;
}

/// Outcome of a query — success carries the [NtpReading] plus the server and
/// resolved IP for display; failure carries an honest message. Three render
/// states for the screen (SOP-007 §5): success / error (and the screen adds its
/// own idle + loading).
class NtpResult {
  const NtpResult._({
    required this.server,
    required this.resolvedIp,
    required this.reading,
    this.errorMessage,
  });

  factory NtpResult.success({
    required String server,
    required String? resolvedIp,
    required NtpReading reading,
  }) =>
      NtpResult._(
        server: server,
        resolvedIp: resolvedIp,
        reading: reading,
      );

  factory NtpResult.failure({
    required String server,
    required String message,
    String? resolvedIp,
  }) =>
      NtpResult._(
        server: server,
        resolvedIp: resolvedIp,
        reading: null,
        errorMessage: message,
      );

  /// The server hostname (or IP) that was queried.
  final String server;

  /// The IP the hostname resolved to, when known. Null when resolution did not
  /// happen or the server was already an IP literal handled by the OS.
  final String? resolvedIp;

  /// The parsed reading, present only on success.
  final NtpReading? reading;

  /// Non-null on failure (timeout / DNS / short reply / bad input).
  final String? errorMessage;

  bool get isError => errorMessage != null;
}

/// The injectable transport seam: perform one SNTP exchange and return the raw
/// reply bytes plus the client send (t1) and receive (t4) instants. Abstracting
/// the socket here keeps [NtpService.query]'s validation and the parse math
/// unit-testable without touching the network.
typedef SntpExchange = Future<SntpExchangeResult> Function(
  String host,
  int port,
  Duration timeout,
);

/// Raw output of one [SntpExchange]: the reply bytes and the two client-side
/// instants the SNTP formula needs. [resolvedIp] is the address the host
/// resolved to, when the transport learned it (null otherwise).
class SntpExchangeResult {
  const SntpExchangeResult({
    required this.reply,
    required this.t1,
    required this.t4,
    this.resolvedIp,
  });

  final List<int> reply;
  final DateTime t1;
  final DateTime t4;
  final String? resolvedIp;
}

/// Queries an NTP server over SNTP. The socket work lives behind the [exchange]
/// seam so the validation and the four-timestamp math are testable with a
/// crafted packet and no real network.
class NtpService {
  NtpService({SntpExchange? exchange})
      : _exchange = exchange ?? _defaultExchange;

  final SntpExchange _exchange;

  /// The SNTP service port.
  static const int ntpPort = 123;

  /// Default exchange timeout. NTP replies are sub-100 ms on a healthy network;
  /// 3 s is generous headroom before we call it unreachable.
  static const Duration defaultTimeout = Duration(seconds: 3);

  /// Query [server] (defaults to [kDefaultNtpServer]) and return the parsed
  /// reading or an honest failure.
  Future<NtpResult> query({
    String server = kDefaultNtpServer,
    Duration timeout = defaultTimeout,
  }) async {
    final String host = server.trim();
    if (host.isEmpty) {
      return NtpResult.failure(
        server: host,
        message: 'Enter an NTP server hostname, e.g. $kDefaultNtpServer.',
      );
    }
    // Reject a malformed server BEFORE the SNTP exchange, so a typo is an
    // honest "not a valid host or IP" message, not a silent timeout.
    final NetworkTargetResult target = NetworkTarget.validateHostOrIp(host);
    if (target is! ValidNetworkTarget) {
      return NtpResult.failure(
        server: host,
        message: (target as InvalidNetworkTarget).message,
      );
    }

    try {
      final SntpExchangeResult ex = await _exchange(host, ntpPort, timeout);

      if (ex.reply.length < 48) {
        return NtpResult.failure(
          server: host,
          resolvedIp: ex.resolvedIp,
          message: 'The server replied with ${ex.reply.length} bytes. An SNTP '
              'reply is 48 bytes. The endpoint may not be an NTP server.',
        );
      }

      final NtpReading reading = parseReply(ex.reply, ex.t1, ex.t4);

      // Stratum 0 in the reply header is the "kiss-o'-death" / unspecified
      // marker (RFC 5905 §7.4) — the timestamps are not a trustworthy sync
      // source. Surface it honestly rather than presenting a confident offset.
      if (reading.stratum == 0) {
        return NtpResult.failure(
          server: host,
          resolvedIp: ex.resolvedIp,
          message: 'The server returned stratum 0 (a "kiss-o\'-death" / '
              'unspecified response). It is not offering a usable time sync. '
              'try $kFallbackNtpServer.',
        );
      }

      return NtpResult.success(
        server: host,
        resolvedIp: ex.resolvedIp,
        reading: reading,
      );
    } on TimeoutException {
      return NtpResult.failure(
        server: host,
        message: 'No reply within ${timeout.inSeconds}s. The server may be '
            'unreachable or UDP/123 may be blocked. Try $kFallbackNtpServer.',
      );
    } on SocketException catch (e) {
      // A DNS failure surfaces here as a SocketException with no address.
      final String detail = _short(e.message);
      return NtpResult.failure(
        server: host,
        message: detail.isEmpty
            ? 'Could not reach the server (check the hostname and your '
                'connection).'
            : 'Could not reach the server: $detail.',
      );
    } on Object catch (e) {
      return NtpResult.failure(
        server: host,
        message: 'Query failed: ${_short(e.toString())}.',
      );
    }
  }

  /// Build the 48-byte SNTP client request. Byte 0 is 0x1B: leap indicator 0,
  /// version number 3, mode 3 (client). Every other byte is zero. Exposed
  /// (static) for unit tests — the header byte is the contract.
  static Uint8List buildRequest() {
    final Uint8List packet = Uint8List(48);
    packet[0] = 0x1B; // LI=0 (00), VN=3 (011), Mode=3 (011) → 0b00011011.
    return packet;
  }

  /// Parse a 48-byte SNTP reply with the recorded client transmit ([t1]) and
  /// receive ([t4]) instants into a computed [NtpReading].
  ///
  /// PURE: no I/O, no clock read — every value is derived from the arguments,
  /// so a test can feed a crafted packet with known timestamps and assert the
  /// exact offset/delay. Throws [ArgumentError] if [reply] is shorter than 48
  /// bytes (callers validate length first).
  ///
  /// Field offsets (RFC 4330 §4, big-endian 32.32 fixed-point):
  ///   byte 1      stratum
  ///   24..31      originate timestamp (t1 echo) — not needed; we hold the real
  ///               t1 locally, which is more precise than the echo.
  ///   32..39      receive  timestamp (t2)
  ///   40..47      transmit timestamp (t3)
  static NtpReading parseReply(List<int> reply, DateTime t1, DateTime t4) {
    if (reply.length < 48) {
      throw ArgumentError.value(
        reply.length,
        'reply.length',
        'SNTP reply must be at least 48 bytes',
      );
    }

    final int stratum = reply[1];

    // Server receive (t2) and transmit (t3) timestamps, as DateTimes in UTC.
    final DateTime t2 = _ntpTimestampToDateTime(reply, 32);
    final DateTime t3 = _ntpTimestampToDateTime(reply, 40);

    // Work in integer microseconds for precision, then report milliseconds.
    final int t1us = t1.toUtc().microsecondsSinceEpoch;
    final int t2us = t2.microsecondsSinceEpoch;
    final int t3us = t3.microsecondsSinceEpoch;
    final int t4us = t4.toUtc().microsecondsSinceEpoch;

    // RFC 4330: offset = ((t2 - t1) + (t3 - t4)) / 2.
    final int offsetUs = ((t2us - t1us) + (t3us - t4us)) ~/ 2;

    // RFC 4330: delay = (t4 - t1) - (t3 - t2). Clamp tiny negatives (clock
    // jitter on a fast LAN) to 0 so the UI never shows a negative delay.
    int delayUs = (t4us - t1us) - (t3us - t2us);
    if (delayUs < 0) delayUs = 0;

    return NtpReading(
      stratum: stratum,
      serverUtc: t3, // t3 is the server's authoritative transmit time.
      deviceTime: t4,
      offsetMs: (offsetUs / 1000).round(),
      delayMs: (delayUs / 1000).round(),
    );
  }

  /// Read a 64-bit NTP timestamp (32.32 fixed-point seconds since 1900) at
  /// [offset] in [bytes] and convert it to a UTC [DateTime]. Big-endian.
  static DateTime _ntpTimestampToDateTime(List<int> bytes, int offset) {
    int seconds = 0;
    for (int i = 0; i < 4; i++) {
      seconds = (seconds << 8) | (bytes[offset + i] & 0xFF);
    }
    int fraction = 0;
    for (int i = 4; i < 8; i++) {
      fraction = (fraction << 8) | (bytes[offset + i] & 0xFF);
    }

    final int unixSeconds = seconds - _ntpToUnixSeconds;
    // Fraction is in units of 1/2^32 second. Convert to microseconds.
    final int fractionUs = ((fraction * 1000000) >> 32);
    final int totalUs = unixSeconds * 1000000 + fractionUs;

    return DateTime.fromMicrosecondsSinceEpoch(totalUs, isUtc: true);
  }

  /// Default transport: open a UDP socket, send the 48-byte request to the
  /// server's first resolved address, and read the first reply (or time out).
  static Future<SntpExchangeResult> _defaultExchange(
    String host,
    int port,
    Duration timeout,
  ) async {
    // Resolve the host so we can both target a concrete address and report the
    // resolved IP to the user. A DNS failure throws SocketException here, which
    // query() maps to an honest "could not reach" message.
    final List<InternetAddress> addresses =
        await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw const SocketException('No address found for the server');
    }
    final InternetAddress target = addresses.first;

    final RawDatagramSocket socket = await RawDatagramSocket.bind(
      target.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );

    final Completer<SntpExchangeResult> completer =
        Completer<SntpExchangeResult>();
    StreamSubscription<RawSocketEvent>? sub;
    Timer? timer;

    void cleanup() {
      timer?.cancel();
      sub?.cancel();
      socket.close();
    }

    final DateTime t1 = DateTime.now().toUtc();

    sub = socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final Datagram? dg = socket.receive();
        if (dg == null) return;
        final DateTime t4 = DateTime.now().toUtc();
        if (!completer.isCompleted) {
          completer.complete(
            SntpExchangeResult(
              reply: dg.data,
              t1: t1,
              t4: t4,
              resolvedIp: target.address,
            ),
          );
          cleanup();
        }
      }
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('NTP request timed out', timeout),
        );
        cleanup();
      }
    });

    socket.send(buildRequest(), target, port);

    return completer.future;
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}
