// Can this machine actually pin a connection to a chosen interface? Ask it.
//
// WHY A PROBE AND NOT A TABLE. `transport_chooser.dart` first claimed, on
// reasoning alone, that a desktop cannot pin an INTERNET connection to a
// non-default interface: the route is chosen by destination, so a packet leaving
// the wrong interface would be dropped. Measured on the M5 on 2026-08-31 with
// Wi-Fi on `en0` and a wired link on `en5`, a github.com connection bound to
// `en0` used source 192.168.8.134 and CONNECTED, while the default route was
// `en5` at .233. Both interfaces sat on one subnet behind one gateway, so either
// source was legitimate.
//
// Across two different gateways it very likely would NOT connect, and that case
// is untested. Neither answer is right for "macOS". The answer belongs to the
// machine, so this asks the machine.
//
// COST: one TCP connection, torn down immediately. Nothing is sent.

import 'dart:io';

/// Opens a connection, or reports why it could not.
typedef BindConnector =
    Future<bool> Function(
      InternetAddress source,
      String host,
      int port,
      Duration timeout,
    );

Future<bool> _connect(
  InternetAddress source,
  String host,
  int port,
  Duration timeout,
) async {
  Socket? s;
  try {
    s = await Socket.connect(
      host,
      port,
      sourceAddress: source,
      timeout: timeout,
    );
    return true;
  } on Object {
    // Two failures land here and they are NOT the same thing, which is why the
    // caller is told only "this did not work" rather than a reason it would
    // have to invent:
    //   * errno 49, "can't assign requested address": the machine does not hold
    //     that source address. A configuration answer.
    //   * a timeout or reset: the bind took, and the path did not carry it.
    // Distinguishing them properly needs the errno, and OS error codes are not
    // portable enough to branch on. The UI says what was observed.
    return false;
  } finally {
    s?.destroy();
  }
}

/// Tests whether traffic can be pinned to each of [sourceAddresses].
///
/// [host] and [port] should be a destination in the SCOPE being tested: a host
/// on the local subnet for [TransportScope.localSubnet], and something off-link
/// for the internet scope. Probing the wrong scope answers a different question
/// than the one the UI is about to ask.
class LinkBindProbe {
  LinkBindProbe({BindConnector? connector}) : _connect_ = connector ?? _connect;

  final BindConnector _connect_;

  /// Returns interface name -> whether a connection bound to its address got
  /// through. An interface absent from the map was not tested, which the UI
  /// must render differently from one that was tested and failed.
  Future<Map<String, bool>> probe({
    required Map<String, InternetAddress> sourceAddresses,
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Map<String, bool> out = <String, bool>{};
    // Sequential, not parallel. Parallel binds on a multi-homed box can race
    // through the same NAT state on the gateway and produce a false negative
    // for whichever loses. Three interfaces at five seconds worst case is
    // fifteen seconds, and this runs once per screen, not per test.
    for (final MapEntry<String, InternetAddress> e in sourceAddresses.entries) {
      out[e.key] = await _connect_(e.value, host, port, timeout);
    }
    return out;
  }
}
