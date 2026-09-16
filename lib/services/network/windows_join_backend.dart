// The native Windows join path, behind the same interface the WLAN Pi uses.
//
// WHAT IT CAN AND CANNOT REPORT, WHICH IS THE WHOLE REASON THIS FILE IS SHORT.
// Windows can tell us whether the machine ended up associated. It cannot tell
// us the Pi's twenty-four link fields, so [JoinOutcome.detail] stays null and
// the screen renders nothing for it. Nothing is estimated, and nothing is zero.
import 'join_backend.dart';
import 'join_network_list.dart' show keyMgmtFromSecurityTokens;
import 'pi_backend_client.dart' show PiJoinSecurity, PiScanInterface, PiScanNet;
import 'windows_join_profile.dart' show JoinProfileUnsupported;
import 'windows_wifi_ffi.dart' show enumerateNearbyBssFromNativeWifi;
import 'windows_wifi_join_ffi.dart';

/// Joins using THIS Windows machine's own radio.
class WindowsNativeJoinBackend implements JoinBackend {
  const WindowsNativeJoinBackend();

  @override
  bool get joinsThisDevice => true;

  /// Windows exposes its wireless interfaces, but this screen has never offered
  /// a choice of more than one and the Native Wifi path already acts on the
  /// first. Returning an empty list makes the radio picker hide itself rather
  /// than present a control with one entry that changes nothing.
  @override
  Future<List<PiScanInterface>> radios() async => const <PiScanInterface>[];

  @override
  Future<List<PiScanNet>> scan({String? interface}) async {
    final List<Map<String, Object?>> rows = enumerateNearbyBssFromNativeWifi();
    return <PiScanNet>[
      for (final Map<String, Object?> r in rows)
        PiScanNet(
          ssid: r['ssid'] as String?,
          bssid: r['bssid'] as String? ?? '',
          signalDbm: (r['rssiDbm'] as num?)?.toInt() ?? 0,
          freqMhz: (r['frequencyMhz'] as num?)?.toInt() ?? 0,
          // Through the SAME translation the Pi path's precedence lives in, so
          // SAE still beats PSK and EAP still beats both. Re-deriving it here
          // would be a second place for that order to drift.
          keyMgmt: keyMgmtFromSecurityTokens(
            (r['security'] as List<Object?>? ?? const <Object?>[])
                .map((Object? e) => e.toString())
                .toList(),
          ),
        ),
    ];
  }

  @override
  Future<JoinOutcome> join({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  }) async {
    try {
      await joinWifiNetworkWindows(
        ssid: ssid,
        security: security,
        passphrase: psk,
      );
      return JoinOutcome(connected: true, ssid: ssid);
    } on WindowsJoinException catch (e) {
      // The terminal state separates a wrong passphrase from a network that was
      // never found, so the note says which rather than a single vague line.
      return JoinOutcome(connected: false, ssid: ssid, failureNote: e.message);
    } on JoinProfileUnsupported catch (e) {
      return JoinOutcome(connected: false, ssid: ssid, failureNote: e.message);
    }
  }

  @override
  Future<JoinOutcome> disconnect({String? interface}) async {
    try {
      await disconnectWifiWindows();
      return const JoinOutcome(connected: false, ssid: null);
    } on WindowsJoinException catch (e) {
      return JoinOutcome(connected: true, ssid: null, failureNote: e.message);
    }
  }
}
