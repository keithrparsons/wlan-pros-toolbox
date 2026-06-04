// InterfaceInfoService unit tests — the Batch-1 enrichment: SSID/BSSID/interface
// /MAC are re-sourced from the native ConnectedAp subsystem, and the honest
// macOS "needs Location" gate is reported when the name is absent AND Location
// is unauthorized.
//
// The connected-AP read is injected (ConnectedApRead seam) so no platform/native
// channel is touched. The interface lister is stubbed empty; NetworkInfo is the
// real instance (its calls return null off-platform, which the service swallows)
// — these tests assert the IDENTITY merge, not the addressing fields.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/interface_info_service.dart';

void main() {
  InterfaceInfoService serviceWith({
    ConnectedAp? ap,
    bool authorized = true,
  }) {
    return InterfaceInfoService(
      interfaceLister: () async => const [],
      connectedApReader: () async => (ap: ap, authorized: authorized),
    );
  }

  group('Wi-Fi identity is sourced from ConnectedAp', () {
    test('SSID/BSSID/interface/MAC come from the connected-AP read', () async {
      const ap = ConnectedAp(
        ssid: 'KeithNet',
        bssid: 'a4:83:e7:00:11:22',
        interfaceName: 'en0',
        hardwareAddress: 'a4:83:e7:aa:bb:cc',
      );
      final snap = await serviceWith(ap: ap).read();
      expect(snap.wifi.ssid, 'KeithNet');
      expect(snap.wifi.bssid, 'a4:83:e7:00:11:22');
      expect(snap.wifi.interfaceName, 'en0');
      expect(snap.wifi.hardwareAddress, 'a4:83:e7:aa:bb:cc');
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('blank ConnectedAp fields normalize to null', () async {
      const ap = ConnectedAp(ssid: '  ', bssid: '', interfaceName: '');
      final snap = await serviceWith(ap: ap).read();
      expect(snap.wifi.ssid, isNull);
      expect(snap.wifi.bssid, isNull);
      expect(snap.wifi.interfaceName, isNull);
    });
  });

  group('macOS Location gate', () {
    test('name absent + Location unauthorized → locationNeeded true', () async {
      // macOS returns an AP with RF data but null SSID/BSSID when Location is off.
      const ap = ConnectedAp(rssiDbm: -50, hardwareAddress: 'a4:83:e7:aa:bb:cc');
      final snap =
          await serviceWith(ap: ap, authorized: false).read();
      expect(snap.wifi.ssid, isNull);
      expect(snap.wifi.locationNeeded, isTrue);
      // The MAC is still read independent of the name gate.
      expect(snap.wifi.hardwareAddress, 'a4:83:e7:aa:bb:cc');
    });

    test('name absent but authorized → not a Location problem', () async {
      const ap = ConnectedAp(rssiDbm: -50);
      final snap = await serviceWith(ap: ap, authorized: true).read();
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('name present → locationNeeded false regardless', () async {
      const ap = ConnectedAp(ssid: 'KeithNet');
      final snap = await serviceWith(ap: ap, authorized: false).read();
      expect(snap.wifi.locationNeeded, isFalse);
    });

    test('no AP reading at all + unauthorized → locationNeeded true', () async {
      final snap = await serviceWith(ap: null, authorized: false).read();
      expect(snap.wifi.ssid, isNull);
      expect(snap.wifi.locationNeeded, isTrue);
    });
  });

  test('a thrown connected-AP read degrades to empty Wi-Fi identity', () async {
    final svc = InterfaceInfoService(
      interfaceLister: () async => const [],
      connectedApReader: () async => throw StateError('read failed'),
    );
    final snap = await svc.read();
    expect(snap.wifi.ssid, isNull);
    expect(snap.wifi.bssid, isNull);
    // A failed read is not a Location problem (authorized defaults true on error).
    expect(snap.wifi.locationNeeded, isFalse);
  });
}
