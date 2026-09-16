// One interface over the two ways this app can join a network, so the screen
// does not have to know which it is talking to.
//
// WHY AN ABSTRACTION RATHER THAN AN `if (Platform.isWindows)` IN THE SCREEN.
// The two backends differ in more than their transport. The Pi drives a REMOTE
// radio and reports twenty-four fields about the resulting link. Windows drives
// THIS machine's radio and can report almost none of that. An `if` in the screen
// would have to decide, at every render, which fields are real -- and the
// failure mode of getting that wrong is an interface that displays a number it
// invented.
//
// SO THE RESULT TYPE CARRIES WHAT BOTH CAN SUPPLY, AND THE PI'S RICH DETAIL IS
// AN OPTIONAL EXTRA. A native join leaves it null, the screen renders nothing
// for it, and there is no place for a fabricated field to live.
import 'pi_backend_client.dart'
    show
        PiBackendClient,
        PiJoinResult,
        PiJoinSecurity,
        PiScanInterface,
        PiScanNet;

/// What a join or disconnect attempt produced, in terms both backends can honour.
class JoinOutcome {
  const JoinOutcome({
    required this.connected,
    required this.ssid,
    this.detail,
    this.failureNote,
  });

  /// Whether the radio ended the attempt associated. **Not whether the request
  /// was accepted.** Windows returns success for a connect request to a network
  /// that does not exist, so this is the polled outcome, never the return code.
  final bool connected;

  /// The SSID that was asked for, echoed so a caller can prove the radio joined
  /// THE network requested rather than merely joining something.
  final String? ssid;

  /// The WLAN Pi's full link record, when a Pi performed the join.
  ///
  /// **NULL ON A NATIVE JOIN, AND THAT IS THE POINT.** The native path has no
  /// equivalent of the Pi's RSSI, noise, MCS, NSS or phy mode, so it supplies
  /// nothing rather than zeroes.
  final PiJoinResult? detail;

  /// A backend's own words on a failure, when it has any worth showing.
  final String? failureNote;
}

/// A way to list radios, scan, join and disconnect.
abstract interface class JoinBackend {
  /// True when this backend drives THIS device's own radio.
  ///
  /// The screen uses it for copy, because "this Pi will join" and "this computer
  /// will join" are different promises and a user acts differently on each.
  bool get joinsThisDevice;

  Future<List<PiScanInterface>> radios();
  Future<List<PiScanNet>> scan({String? interface});
  Future<JoinOutcome> join({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  });
  Future<JoinOutcome> disconnect({String? interface});
}

/// The existing WLAN Pi path, wrapped without changing a single behaviour.
///
/// **NOTHING HERE IS NEW LOGIC.** It forwards to [PiBackendClient] exactly as
/// the screen used to call it, so the Pi path in 1.10.0 behaves as it did in
/// 1.9.0. The only addition is packing the result into [JoinOutcome], with the
/// Pi's own record carried through untouched in `detail`.
class PiJoinBackend implements JoinBackend {
  PiJoinBackend(this._client);
  final PiBackendClient _client;

  @override
  bool get joinsThisDevice => false;

  @override
  Future<List<PiScanInterface>> radios() => _client.scanInterfaces();

  @override
  Future<List<PiScanNet>> scan({String? interface}) =>
      _client.scan(interface: interface ?? 'wlan0');

  @override
  Future<JoinOutcome> join({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  }) async {
    final PiJoinResult r = await _client.wifiConnect(
      ssid: ssid,
      security: security,
      psk: psk,
      interface: interface,
    );
    return JoinOutcome(
      connected: r.link.associated,
      ssid: r.requestedSsid ?? ssid,
      detail: r,
      failureNote: r.link.associated ? null : r.link.reason,
    );
  }

  @override
  Future<JoinOutcome> disconnect({String? interface}) async {
    final PiJoinResult r = await _client.wifiDisconnect(interface: interface);
    return JoinOutcome(
      connected: r.link.associated,
      ssid: r.requestedSsid,
      detail: r,
    );
  }
}
