// The native macOS join path, behind the same interface Windows and the Pi use.
//
// SMALLER THAN THE WINDOWS ONE, AND FOR A GOOD REASON. macOS already answers
// `com.wlanpros.toolbox/ap_scan` from Swift, and ApScanService already handles
// the Location authorization that macOS gates the SSID behind. So the scan half
// is not rebuilt here; only the two new verbs are.
import 'package:flutter/services.dart' show MethodChannel;

import 'ap_scan_service.dart' show ApScanService, ApScanSnapshot, ScannedAp;
import 'join_backend.dart';
import 'join_network_list.dart' show keyMgmtFromSecurityTokens;
import 'pi_backend_client.dart' show PiJoinSecurity, PiScanInterface, PiScanNet;

/// Joins using THIS Mac's own radio, through CoreWLAN in `ApScanChannel.swift`.
class MacNativeJoinBackend implements JoinBackend {
  MacNativeJoinBackend({
    ApScanService? scanner,
    MethodChannel channel = const MethodChannel('com.wlanpros.toolbox/ap_scan'),
  }) : _scanner = scanner ?? ApScanService(),
       _channel = channel;

  final ApScanService _scanner;
  final MethodChannel _channel;

  @override
  bool get joinsThisDevice => true;

  /// A Mac has one Wi-Fi interface and this screen has never offered a choice.
  /// An empty list makes the radio picker hide itself.
  @override
  Future<List<PiScanInterface>> radios() async => const <PiScanInterface>[];

  @override
  Future<List<PiScanNet>> scan({String? interface}) async {
    final ApScanSnapshot snap = await _scanner.scan();
    return <PiScanNet>[
      for (final ScannedAp ap in snap.accessPoints)
        PiScanNet(
          ssid: ap.ssid,
          bssid: ap.bssid,
          signalDbm: ap.rssiDbm,
          freqMhz: ap.frequencyMhz,
          // The SAME translation the Pi and Windows paths use, so SAE beats PSK
          // and EAP beats both in ONE place rather than three that can drift.
          keyMgmt: keyMgmtFromSecurityTokens(ap.security),
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
    if (security == PiJoinSecurity.unsupported) {
      return JoinOutcome(
        connected: false,
        ssid: ssid,
        failureNote:
            'This network needs credentials this tool does not collect.',
      );
    }
    try {
      final Map<Object?, Object?>? r = await _channel
          .invokeMapMethod<Object?, Object?>('join', <String, Object?>{
            'ssid': ssid,
            // OWE and open both send NOTHING. CoreWLAN associates and derives
            // the OWE keys itself.
            'password':
                (security == PiJoinSecurity.open ||
                    security == PiJoinSecurity.owe)
                ? null
                : psk,
          });
      // `connected` is read back from the interface on the Swift side, not
      // inferred from the call returning. See the note in ApScanChannel.join.
      final bool ok = r?['connected'] == true;
      return JoinOutcome(
        connected: ok,
        ssid: ssid,
        failureNote: ok ? null : r?['reason'] as String?,
      );
    } on Object catch (e) {
      return JoinOutcome(
        connected: false,
        ssid: ssid,
        failureNote: e.toString(),
      );
    }
  }

  @override
  Future<JoinOutcome> disconnect({String? interface}) async {
    try {
      await _channel.invokeMethod<Object?>('disconnect');
      return const JoinOutcome(connected: false, ssid: null);
    } on Object catch (e) {
      return JoinOutcome(
        connected: true,
        ssid: null,
        failureNote: e.toString(),
      );
    }
  }
}
