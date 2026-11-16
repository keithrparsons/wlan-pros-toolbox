// The four UDP probes behind "What This Network Lets Out", and the socket
// code that sends one. Measured on 16 NOV from an unblocked network, each got
// a valid reply from every public target in kPortCheckTargets (design 0.6).
//
// A reply only counts when it comes from the address AND port we asked and the
// probe recognizes it (a DNS answer must carry our id, a STUN reply our
// transaction id). That blocks stray packets, not a gateway that forges every
// field: "DNS got out" means a plausible answer, not proof the real resolver
// replied (design 0.5, item 3).
//
// UDP here has two outcomes only, reply or silence. Nothing reads an ICMP
// "port unreachable", so one silent target is never "blocked" by itself; the
// verdict needs the second target too (port_check_verdict.dart).

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'ntp_service.dart';
import 'port_check_verdict.dart';

class UdpProbeSpec {
  const UdpProbeSpec(this.payload, this.accepts);

  final Uint8List payload;
  final bool Function(Uint8List reply) accepts;
}

final Random _random = Random.secure();

Uint8List _randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

UdpProbeSpec udpProbeFor(UdpProbeKind kind) => switch (kind) {
  UdpProbeKind.dns => _dns(),
  UdpProbeKind.ntp => _ntp(),
  UdpProbeKind.stun => _stun(),
  UdpProbeKind.quic => _quic(),
};

/// RFC 1035 4.1: header (id, flags, 1 question) then google.com A IN.
UdpProbeSpec _dns() {
  final Uint8List id = _randomBytes(2);
  final Uint8List query = Uint8List.fromList(<int>[
    ...id,
    0x01, 0x00, // recursion desired
    0, 1, 0, 0, 0, 0, 0, 0, // one question, nothing else
    6, ...'google'.codeUnits, 3, ...'com'.codeUnits, 0,
    0, 1, 0, 1, // type A, class IN
  ]);
  return UdpProbeSpec(
    query,
    (Uint8List r) =>
        r.length >= 12 && r[0] == id[0] && r[1] == id[1] && (r[2] & 0x80) != 0,
  );
}

/// RFC 4330: a mode 4 (server) reply is 48 bytes or more.
UdpProbeSpec _ntp() => UdpProbeSpec(
  NtpService.buildRequest(),
  (Uint8List r) => r.length >= 48 && (r[0] & 0x07) == 4,
);

/// RFC 5389 6 and 7.3: binding request, magic cookie, 96-bit transaction id.
UdpProbeSpec _stun() {
  final Uint8List txid = _randomBytes(12);
  final Uint8List request = Uint8List.fromList(<int>[
    0,
    1,
    0,
    0,
    0x21,
    0x12,
    0xA4,
    0x42,
    ...txid,
  ]);
  return UdpProbeSpec(request, (Uint8List r) {
    if (r.length < 20) return false;
    for (int i = 4; i < 20; i++) {
      if (r[i] != request[i]) return false;
    }
    return true;
  });
}

/// RFC 9000 17.2: a 1200-byte long-header packet with a reserved version
/// (0x?a?a?a?a, RFC 9000 15) makes any QUIC server answer with Version
/// Negotiation (RFC 8999 6): long-header bit set, version 0.
UdpProbeSpec _quic() {
  final Uint8List packet = Uint8List(1200);
  packet[0] = 0xC0;
  packet.setAll(1, <int>[0x1a, 0x2a, 0x3a, 0x4a]);
  packet[5] = 8; // destination connection id length
  packet.setAll(6, _randomBytes(8));
  return UdpProbeSpec(
    packet,
    (Uint8List r) =>
        r.length >= 7 &&
        (r[0] & 0x80) != 0 &&
        r[1] == 0 &&
        r[2] == 0 &&
        r[3] == 0 &&
        r[4] == 0,
  );
}

/// Send the probe, again after [resendAfter] in case Wi-Fi dropped the first,
/// and wait up to [window] for an accepted reply from [address]:[port].
Future<TargetOutcome> probeUdpAddress(
  InternetAddress address,
  int port,
  UdpProbeSpec spec, {
  Duration resendAfter = const Duration(seconds: 1),
  Duration window = const Duration(milliseconds: 2500),
}) async {
  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
  } on SocketException {
    return TargetOutcome.unavailable;
  }

  final Completer<TargetOutcome> done = Completer<TargetOutcome>();
  void finish(TargetOutcome o) {
    if (!done.isCompleted) done.complete(o);
  }

  final StreamSubscription<RawSocketEvent> sub = socket.listen((
    RawSocketEvent e,
  ) {
    if (e != RawSocketEvent.read) return;
    final Datagram? d = socket.receive();
    if (d != null &&
        d.address == address &&
        d.port == port &&
        spec.accepts(d.data)) {
      finish(TargetOutcome.gotOut);
    }
  });
  final Timer resend = Timer(resendAfter, () {
    if (!done.isCompleted) socket.send(spec.payload, address, port);
  });
  final Timer giveUp = Timer(window, () => finish(TargetOutcome.didNotGetOut));

  socket.send(spec.payload, address, port);
  final TargetOutcome outcome = await done.future;
  resend.cancel();
  giveUp.cancel();
  await sub.cancel();
  socket.close();
  return outcome;
}

/// Resolve [target] (IPv4 first, as the socket is IPv4) and probe it. A name
/// that will not resolve is a DNS problem, not a UDP one.
Future<TargetOutcome> probeUdpTarget(PortCheckTarget target) async {
  try {
    final List<InternetAddress> found = await InternetAddress.lookup(
      target.host,
      type: InternetAddressType.IPv4,
    );
    if (found.isEmpty) return TargetOutcome.noVerdict;
    return probeUdpAddress(found.first, target.port, udpProbeFor(target.udp!));
  } on SocketException {
    return TargetOutcome.noVerdict;
  }
}
