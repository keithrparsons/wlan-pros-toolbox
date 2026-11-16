// PortCheckService probes every target in [kPortCheckTargets] at once and
// returns one [TargetOutcome] each, for [judgePortCheck] to read.
//
// TCP semantics (design section 0.1): a completed handshake gets out. A RST on a
// far-end target means something in the middle rejected us, so it counts as
// "did not get out". That is the OPPOSITE of PingService, which treats a RST as
// "the host is alive"; do not reuse its success flag. [classifyTcpFailure] owns
// the errno reading (no other file may touch `osError`).
//
// Sends nothing after the handshake: connect, then close.

import 'dart:async';
import 'dart:io';

import 'port_check_udp.dart';
import 'port_check_verdict.dart';
import 'tcp_probe_classifier.dart';

/// Hotels need slack; Ping's 2 s is too tight here (design section 0.7).
const Duration kPortCheckTcpTimeout = Duration(seconds: 3);

typedef TcpConnector =
    Future<TargetOutcome> Function(String host, int port, Duration timeout);

/// A lookup failure never reaches the far end, so it says nothing about the
/// port. Everything else, a RST included, is "did not get out".
TargetOutcome tcpOutcomeFor(TcpFailureReason reason) =>
    reason == TcpFailureReason.lookupFailure
    ? TargetOutcome.noVerdict
    : TargetOutcome.didNotGetOut;

Future<TargetOutcome> connectTcp(
  String host,
  int port,
  Duration timeout,
) async {
  try {
    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return TargetOutcome.gotOut;
  } catch (e) {
    return tcpOutcomeFor(classifyTcpFailure(e).reason);
  }
}

typedef UdpProber = Future<TargetOutcome> Function(PortCheckTarget target);

class PortCheckService {
  PortCheckService({TcpConnector? tcp, UdpProber? udp})
    : _tcp = tcp ?? connectTcp,
      _udp = udp ?? probeUdpTarget;

  final TcpConnector _tcp;
  final UdpProber _udp;

  /// All targets at once: the slowest one, not the sum, sets the time.
  Future<Map<PortCheckTarget, TargetOutcome>> run() async {
    final List<TargetOutcome> outcomes = await Future.wait(
      kPortCheckTargets.map(
        (PortCheckTarget t) => t.transport == PortCheckTransport.tcp
            ? _tcp(t.host, t.port, kPortCheckTcpTimeout)
            : _udp(t),
      ),
    );
    return <PortCheckTarget, TargetOutcome>{
      for (int i = 0; i < outcomes.length; i++)
        kPortCheckTargets[i]: outcomes[i],
    };
  }
}
