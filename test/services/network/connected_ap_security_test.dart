// ConnectedAp security + AP-vendor enrichment — Batch 7 unit tests.
//
// Covers the new securityType / securityAvailable fields, the macOS fine-grained
// security mapping via fromWifiInfo, the iOS coarse path (security null until
// enriched), the withSecurity enrichment used on the iOS path, and the
// AP-vendor (OUI-from-BSSID) lookup contract the Wi-Fi Information tool relies on.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security.dart';

WifiInfo _macInfo({String? securityToken}) => WifiInfo(
      interfaceName: 'en0',
      ssid: 'KeithNet',
      bssid: 'a4:83:e7:00:11:22',
      rssiDbm: -50,
      noiseDbm: -95,
      snrDb: 45,
      txRateMbps: 866,
      phyMode: '802.11ax',
      channel: 36,
      channelWidthMhz: 80,
      band: '5 GHz',
      countryCode: 'US',
      hardwareAddress: 'a4:83:e7:aa:bb:cc',
      securityToken: securityToken,
      poweredOn: true,
      locationAuthorized: true,
    );

void main() {
  group('ConnectedAp security — macOS (fine truth)', () {
    test('maps the CoreWLAN security token to the fine label', () {
      final ConnectedAp ap =
          ConnectedAp.fromWifiInfo(_macInfo(securityToken: 'wpa3Transition'));
      expect(ap.securityAvailable, isTrue);
      expect(ap.securityType, WifiSecurity.wpa3Transition);
      expect(ap.securityType!.label, 'WPA2/WPA3 Transition');
    });

    test('a null security token is available-but-absent, never fabricated', () {
      final ConnectedAp ap = ConnectedAp.fromWifiInfo(_macInfo());
      // macOS can expose security, so the flag stays true even when this read
      // carried no token — the UI shows "Not in this reading", not "not on this
      // platform".
      expect(ap.securityAvailable, isTrue);
      expect(ap.securityType, isNull);
    });
  });

  group('ConnectedAp security — iOS (coarse, enriched separately)', () {
    final ConnectedAp ios = ConnectedAp.fromWifiDetails(
      WiFiDetails.fromMap(const <String, dynamic>{
        'SSID': 'KeithNet',
        'BSSID': 'a4:83:e7:00:11:22',
        'Channel': 36,
        'RSSI': -50,
      }),
    );

    test('the Shortcut path declares security available but unset', () {
      expect(ios.securityAvailable, isTrue);
      expect(ios.securityType, isNull);
    });

    test('withSecurity folds the native coarse token onto the model', () {
      final ConnectedAp enriched =
          ios.withSecurity(WifiSecurity.personalCoarse);
      expect(enriched.securityType, WifiSecurity.personalCoarse);
      // Every other field is preserved.
      expect(enriched.ssid, 'KeithNet');
      expect(enriched.bssid, 'a4:83:e7:00:11:22');
      expect(enriched.rssiDbm, -50);
      expect(enriched.securityAvailable, isTrue);
    });

    test('withSecurity(null) leaves the existing value untouched', () {
      final ConnectedAp withPersonal =
          ios.withSecurity(WifiSecurity.personalCoarse);
      expect(withPersonal.withSecurity(null).securityType,
          WifiSecurity.personalCoarse);
    });
  });

  group('AP-vendor (OUI-from-BSSID) lookup contract', () {
    // A tiny in-memory OUI table standing in for the bundled asset.
    final MacOuiService oui = MacOuiService.fromTable(<String, String>{
      'A483E7': 'Apple, Inc.',
      'B827EB': 'Raspberry Pi Foundation',
    });

    test('resolves the AP manufacturer from a globally-administered BSSID', () {
      expect(oui.vendorLabelFor('a4:83:e7:00:11:22'), 'Apple, Inc.');
      expect(oui.vendorLabelFor('b8:27:eb:aa:bb:cc'),
          'Raspberry Pi Foundation');
    });

    test('a locally-administered (randomized) BSSID has no IEEE vendor', () {
      // The U/L bit (0x02) of the first octet is set → no registered vendor.
      expect(oui.vendorLabelFor('a6:83:e7:00:11:22'), isNull);
    });

    test('an unlisted global BSSID falls back to the raw OUI, never invented', () {
      // 00:11:22 is not in the table → the colon-formatted OUI, not a guess.
      expect(oui.vendorLabelFor('00:11:22:33:44:55'), '00:11:22');
    });

    test('an invalid BSSID yields null (no row), never a thrown error', () {
      expect(oui.vendorLabelFor('not-a-mac'), isNull);
    });
  });

  group('ConnectedAp.mergedWith (copy-vs-live RF unification)', () {
    test('fills RF gaps from the live reading without overwriting own values', () {
      // The one-shot read: native security/BSSID enrichment only, NO RF.
      const ConnectedAp oneShot = ConnectedAp(
        ssid: 'KeithNet',
        bssid: 'a4:83:e7:00:11:22',
        securityType: WifiSecurity.wpa2Personal,
        securityAvailable: true,
      );
      // The live sampler reading: rich RF, but a coarser/absent security.
      const ConnectedAp live = ConnectedAp(
        ssid: 'KeithNet',
        rssiDbm: -58,
        noiseDbm: -90,
        channel: 36,
        rxRateMbps: 780,
        txRateMbps: 866,
        standard: '802.11ax (Wi-Fi 6)',
        band: '5 GHz',
        bandDerived: true,
      );

      final ConnectedAp merged = oneShot.mergedWith(live);

      // RF the one-shot lacked is now present (so the copy can serialize it).
      expect(merged.rssiDbm, -58);
      expect(merged.channel, 36);
      expect(merged.rxRateMbps, 780);
      expect(merged.txRateMbps, 866);
      expect(merged.standard, '802.11ax (Wi-Fi 6)');
      // SNR synthesized from merged rssi/noise (-58 − -90 = 32), flagged derived.
      expect(merged.snrDb, 32);
      expect(merged.snrDerived, isTrue);
      // The one-shot's native security/BSSID are NOT lost.
      expect(merged.securityType, WifiSecurity.wpa2Personal);
      expect(merged.bssid, 'a4:83:e7:00:11:22');
    });

    test('own non-null values win over the live reading', () {
      const ConnectedAp oneShot = ConnectedAp(
        rssiDbm: -50,
        channel: 6,
        securityType: WifiSecurity.wpa3Personal,
      );
      const ConnectedAp live = ConnectedAp(
        rssiDbm: -70,
        channel: 36,
        securityType: WifiSecurity.open,
      );
      final ConnectedAp merged = oneShot.mergedWith(live);
      expect(merged.rssiDbm, -50);
      expect(merged.channel, 6);
      expect(merged.securityType, WifiSecurity.wpa3Personal);
    });

    test('returns this unchanged when the live reading is null', () {
      const ConnectedAp oneShot = ConnectedAp(rssiDbm: -50, channel: 6);
      expect(identical(oneShot.mergedWith(null), oneShot), isTrue);
    });

    test('OR-s the platform-availability flags from both sides', () {
      const ConnectedAp oneShot = ConnectedAp(rxRateAvailable: false);
      const ConnectedAp live = ConnectedAp(rxRateAvailable: true);
      expect(oneShot.mergedWith(live).rxRateAvailable, isTrue);
    });
  });

  // CoreWLAN reports Enhanced Open (OWE) as open (25 OCT 2026, Keith Guest),
  // so a macOS Open is "may be OWE" until the BSS's own beacon settles it.
  group('ConnectedAp macOS Open vs OWE', () {
    const String caveat = 'macOS also reports Enhanced Open (OWE) as open';
    const String confirmed =
        "The access point's beacon confirms this network is open";

    test('a macOS Open may be OWE and says so', () {
      final ConnectedAp ap =
          ConnectedAp.fromWifiInfo(_macInfo(securityToken: 'open'));
      expect(ap.openMayBeOwe, isTrue);
      expect(ap.securityNote, caveat);
    });

    test('a beacon-confirmed macOS Open is not OWE and says so', () {
      final ConnectedAp ap = ConnectedAp.fromWifiInfo(
        _macInfo(securityToken: 'open'),
      ).withBeaconConfirmsOpen();
      expect(ap.openMayBeOwe, isFalse);
      expect(ap.securityNote, confirmed);
    });

    test('a macOS Open upgraded to OWE carries no note', () {
      final ConnectedAp ap = ConnectedAp.fromWifiInfo(
        _macInfo(securityToken: 'open'),
      ).withSecurity(WifiSecurity.owe);
      expect(ap.openMayBeOwe, isFalse);
      expect(ap.securityNote, isNull);
    });

    test('a non-open macOS answer carries no note', () {
      final ConnectedAp ap =
          ConnectedAp.fromWifiInfo(_macInfo(securityToken: 'wpa2Personal'));
      expect(ap.openMayBeOwe, isFalse);
      expect(ap.securityNote, isNull);
    });

    test('an Open from another platform carries no macOS note', () {
      const ConnectedAp ap = ConnectedAp(
        securityType: WifiSecurity.open,
        securityAvailable: true,
      );
      expect(ap.openMayBeOwe, isFalse);
      expect(ap.securityNote, isNull);
    });

    test('the flag survives the name enrichment and a gap-fill merge', () {
      final ConnectedAp ap = ConnectedAp.fromWifiInfo(
        _macInfo(securityToken: 'open'),
      ).withApName('Workroom');
      expect(ap.openMayBeOwe, isTrue);
      expect(const ConnectedAp().mergedWith(ap).openMayBeOwe, isTrue);
      expect(ap.mergedWith(const ConnectedAp()).openMayBeOwe, isTrue);
    });
  });
}
