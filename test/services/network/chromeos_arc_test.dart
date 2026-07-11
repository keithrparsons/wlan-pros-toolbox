// ChromeOS / ARC-VM honest-null — the regression net.
//
// WHAT BUG THIS GUARDS (2026-07-10, Keith). On a Chromebook the Android build
// runs inside ARCVM, a virtual machine with a NAT'd private network of its own.
// Before this fix the app reported that VM's world as the USER'S world, with
// full confidence and no caveat:
//
//   * "Default gateway: 100.115.92.1"  — that is ChromeOS's patchpanel bridge,
//     not the school's router. An IT admin would have taken it at face value.
//   * "RSSI: -45 dBm"                  — ChromeOS's ONC vocabulary has NO dBm
//     field (signal there is a 0–100 percentage), so any dBm is at best a lossy
//     reconstruction: a number that looks measured and is not.
//   * "802.11a/b/g", "20 MHz"          — ONC has no PHY-generation or
//     channel-width field either, so these were Android defaults printed as
//     fact, on links that were neither.
//
// Keith's standing rule: a tool that is confidently wrong is worse than no tool.
// So every one of those fields is now suppressed on ChromeOS with a stated
// reason, exactly as Windows already does for Noise/SNR.
//
// THESE TESTS FAIL RED ON THE UNFIXED CODE. Each one asserts a null (or an
// honest reason) where the pre-fix code produced a confident value; flipping any
// guard off turns the relevant test red with the exact wrong value in the
// failure message. That is deliberate — the point of the suite is to catch the
// bug coming back, not to describe the fix.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/ap_scan_service.dart';
import 'package:wlan_pros_toolbox/services/network/chromeos_arc.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

/// The exact payload MainActivity emits on a Chromebook AFTER the native
/// suppression: the ONC-defined fields are real, the rest are genuine nulls.
Map<String, Object?> _arcNativePayload() => <String, Object?>{
      'interfaceName': 'wlan0',
      'poweredOn': true,
      'isChromeOs': true,
      // Real — ONC defines these.
      'ssid': 'Lincoln-Staff',
      'bssid': 'a4:83:e7:00:11:22',
      'channel': 44,
      'band': '5 GHz',
      'securityToken': 'wpa2Enterprise',
      // Suppressed at the source — ONC defines none of these.
      'rssiDbm': null,
      'noiseDbm': null,
      'snrDb': null,
      'txRateMbps': null,
      'rxRateMbps': null,
      'phyMode': null,
      'channelWidthMhz': null,
      'countryCode': null,
      'hardwareAddress': null,
      'locationAuthorized': true,
    };

/// The pre-fix payload — what a Chromebook WOULD have handed us with no native
/// guard. Every value here is the confidently-wrong kind. Used to prove the Dart
/// layer does not resurrect them (the `mergedWith` guard).
Map<String, Object?> _arcPayloadWithBogusRf() => <String, Object?>{
      ..._arcNativePayload(),
      'rssiDbm': -45, // reconstructed from a percentage — never measured
      'txRateMbps': 65.0, // no ONC rate field exists
      'rxRateMbps': 65.0,
      'phyMode': '802.11a/b/g', // Android's default, on a Wi-Fi 6 link
      'channelWidthMhz': 20, // Android's default, on an 80 MHz link
    };

void main() {
  tearDown(() => ChromeOsArc.debugSetIsChromeOs(null));

  // =========================================================================
  group('ChromeOsArc — detection', () {
    test('a true probe sets isChromeOs', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ChromeOsArc.debugSetIsChromeOs(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ChromeOsArc.channel, (MethodCall c) async {
        expect(c.method, 'isChromeOs');
        return true;
      });
      expect(await ChromeOsArc.ensureDetected(), isTrue);
      expect(ChromeOsArc.isChromeOs, isTrue);
      expect(ChromeOsArc.detected, isTrue);
    });

    test('a false probe leaves isChromeOs false (a normal phone)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ChromeOsArc.debugSetIsChromeOs(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              ChromeOsArc.channel, (MethodCall c) async => false);
      expect(await ChromeOsArc.ensureDetected(), isFalse);
      expect(ChromeOsArc.isChromeOs, isFalse);
    });

    test(
        'a MISSING channel (iOS/macOS/Windows/web) resolves to false, never '
        'throws — a failed probe must not suppress data on a real device',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ChromeOsArc.debugSetIsChromeOs(null);
      // No handler registered at all → MissingPluginException.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ChromeOsArc.channel, null);
      expect(await ChromeOsArc.ensureDetected(), isFalse);
      expect(ChromeOsArc.isChromeOs, isFalse);
    });

    test(
        'a THROWING probe resolves to false, never true — ambiguity must fail '
        'toward showing real data on a real phone, not toward suppressing it',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ChromeOsArc.debugSetIsChromeOs(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ChromeOsArc.channel, (MethodCall c) async {
        throw PlatformException(code: 'boom');
      });
      expect(await ChromeOsArc.ensureDetected(), isFalse);
    });
  });

  // =========================================================================
  group('WifiInfo.fromMap — the ARC flag crosses the channel', () {
    test('isChromeOs true rides on the ChromeOS payload', () {
      final WifiInfo info = WifiInfo.fromMap(_arcNativePayload());
      expect(info.isChromeOs, isTrue);
    });

    test('isChromeOs defaults to FALSE when absent (the macOS channel)', () {
      final WifiInfo info = WifiInfo.fromMap(<String, Object?>{
        'ssid': 'WLANPros',
        'rssiDbm': -52,
        'poweredOn': true,
        'locationAuthorized': true,
      });
      expect(info.isChromeOs, isFalse,
          reason: 'a channel that never sends the flag must not be treated as '
              'ChromeOS — that would suppress real data on macOS');
    });
  });

  // =========================================================================
  group('ConnectedAp.fromAndroidWifiInfo — ChromeOS honest-null', () {
    test(
        'the five untrustworthy RF fields are NULL — no dBm, no rate, no PHY, '
        'no width (the headline bug)', () {
      final ConnectedAp ap =
          ConnectedAp.fromAndroidWifiInfo(WifiInfo.fromMap(_arcNativePayload()));

      expect(ap.rssiDbm, isNull,
          reason: 'a dBm on ChromeOS could only be a reconstruction of ONC\'s '
              '0-100 percentage — a number that looks measured and is not');
      expect(ap.txRateMbps, isNull, reason: 'ONC has no PHY-rate field');
      expect(ap.rxRateMbps, isNull, reason: 'ONC has no PHY-rate field');
      expect(ap.standard, isNull,
          reason: 'ONC has no PHY-generation field — the pre-fix code printed '
              'Android\'s LEGACY default as "802.11a/b/g" on modern links');
      expect(ap.channelWidthMhz, isNull,
          reason: 'ONC has no channel-width field — the pre-fix code printed '
              'Android\'s 20 MHz default on 80 MHz links');
      // Noise/SNR were already honest on Android; assert they stay that way.
      expect(ap.noiseDbm, isNull);
      expect(ap.snrDb, isNull);
    });

    test('the ONC-defined fields SURVIVE — this is a scalpel, not a hammer', () {
      final ConnectedAp ap =
          ConnectedAp.fromAndroidWifiInfo(WifiInfo.fromMap(_arcNativePayload()));

      expect(ap.ssid, 'Lincoln-Staff');
      expect(ap.bssid, 'a4:83:e7:00:11:22');
      expect(ap.channel, 44);
      expect(ap.band, '5 GHz');
      expect(ap.securityType, isNotNull,
          reason: 'WiFi.Security IS an ONC field — suppressing it would hide a '
              'real fact, which is its own dishonesty');
      expect(ap.isChromeOs, isTrue);
    });

    test(
        'rxRateAvailable is FALSE on ChromeOS — the rate is a PERMANENT ceiling '
        'there, not a per-reading miss, and the copy must say so', () {
      final ConnectedAp ap =
          ConnectedAp.fromAndroidWifiInfo(WifiInfo.fromMap(_arcNativePayload()));
      expect(ap.rxRateAvailable, isFalse);
      expect(ap.channelWidthAvailable, isFalse);
    });

    test('a NON-ChromeOS Android reading is completely untouched', () {
      final ConnectedAp ap = ConnectedAp.fromAndroidWifiInfo(
        WifiInfo.fromMap(<String, Object?>{
          ..._arcPayloadWithBogusRf(),
          'isChromeOs': false, // a real phone
        }),
      );
      expect(ap.rssiDbm, -45, reason: 'a real phone reports a real dBm');
      expect(ap.txRateMbps, 65.0);
      expect(ap.standard, '802.11a/b/g');
      expect(ap.channelWidthMhz, 20);
      expect(ap.rxRateAvailable, isTrue);
      expect(ap.isChromeOs, isFalse);
    });
  });

  // =========================================================================
  // The subtlest way a suppressed value comes back: a gap-filling merge.
  // =========================================================================
  group('ConnectedAp.mergedWith — a suppressed field can never be resurrected',
      () {
    test(
        'merging an ARC reading with a stale non-ARC one does NOT restore the '
        'dBm, rate, standard, or width', () {
      final ConnectedAp arc =
          ConnectedAp.fromAndroidWifiInfo(WifiInfo.fromMap(_arcNativePayload()));
      // A sibling reading that still carries the untrustworthy numbers — e.g. a
      // stale cache entry, or a future code path that forgets the guard.
      const ConnectedAp stale = ConnectedAp(
        rssiDbm: -45,
        noiseDbm: -95,
        snrDb: 50,
        txRateMbps: 65,
        rxRateMbps: 65,
        standard: '802.11a/b/g',
        channelWidthMhz: 20,
        rxRateAvailable: true,
        channelWidthAvailable: true,
      );

      final ConnectedAp merged = arc.mergedWith(stale);

      expect(merged.rssiDbm, isNull,
          reason: 'the merge resurrected a dBm ChromeOS never measured');
      expect(merged.noiseDbm, isNull);
      expect(merged.snrDb, isNull,
          reason: 'SNR must not be synthesized from resurrected inputs');
      expect(merged.txRateMbps, isNull);
      expect(merged.rxRateMbps, isNull);
      expect(merged.standard, isNull);
      expect(merged.channelWidthMhz, isNull);
      expect(merged.rxRateAvailable, isFalse);
      expect(merged.channelWidthAvailable, isFalse);
      expect(merged.isChromeOs, isTrue,
          reason: 'the ARC taint must propagate through the merge');
    });

    test('the merge STILL fills the real, ONC-defined fields', () {
      const ConnectedAp arc = ConnectedAp(isChromeOs: true, channel: 44);
      const ConnectedAp other = ConnectedAp(
        ssid: 'Lincoln-Staff',
        bssid: 'a4:83:e7:00:11:22',
        band: '5 GHz',
      );
      final ConnectedAp merged = arc.mergedWith(other);
      expect(merged.ssid, 'Lincoln-Staff');
      expect(merged.bssid, 'a4:83:e7:00:11:22');
      expect(merged.band, '5 GHz');
      expect(merged.channel, 44);
    });

    test('withSecurity preserves the ARC flag', () {
      final ConnectedAp arc =
          ConnectedAp.fromAndroidWifiInfo(WifiInfo.fromMap(_arcNativePayload()));
      expect(arc.withSecurity(null).isChromeOs, isTrue);
    });

    test('a normal (non-ARC) merge is completely unchanged', () {
      const ConnectedAp a = ConnectedAp(ssid: 'WLANPros');
      const ConnectedAp b = ConnectedAp(
        rssiDbm: -52,
        noiseDbm: -95,
        txRateMbps: 866,
        standard: '802.11ax (Wi-Fi 6)',
        channelWidthMhz: 80,
        rxRateAvailable: true,
        channelWidthAvailable: true,
      );
      final ConnectedAp merged = a.mergedWith(b);
      expect(merged.rssiDbm, -52);
      expect(merged.snrDb, 43, reason: 'rssi - noise, the existing derivation');
      expect(merged.txRateMbps, 866);
      expect(merged.standard, '802.11ax (Wi-Fi 6)');
      expect(merged.channelWidthMhz, 80);
      expect(merged.isChromeOs, isFalse);
    });
  });

  // =========================================================================
  group('NetworkDetailsService — the VM\'s addressing is never shown as yours',
      () {
    test(
        'ALL FIVE addressing fields are suppressed on ChromeOS, each with the '
        'precise reason', () async {
      final NetworkDetailsService svc = NetworkDetailsService(
        isAndroid: true,
        isChromeOs: true,
        // These readers MUST NOT be consulted — but if the guard regresses and
        // they are, they hand back exactly the VM addressing a Chromebook really
        // reports, so the assertions below fail with the true wrong value.
        networkInfo: _arcNetworkInfo(),
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': '100.115.92.1',
          'dnsServers': <String>['100.115.92.1'],
        },
        interfaceLister: () async => <Never>[],
      );

      final NetworkDetails d = await svc.read();

      expect(d.localIp, isNull,
          reason: "leaked the ARC VM's own address as the user's");
      expect(d.subnetMask, isNull, reason: "leaked the VM's /30 mask");
      expect(d.gateway, isNull,
          reason: "leaked ChromeOS's patchpanel bridge as the user's gateway — "
              'the exact bug: an IT admin would troubleshoot 100.115.92.1');
      expect(d.dhcpServer, isNull, reason: "leaked the VM's DHCP server");
      expect(d.dnsServers, isEmpty,
          reason: "leaked ChromeOS's DNS proxy as the user's resolvers");

      expect(d.isChromeOs, isTrue);
      expect(d.addressingReason, ChromeOsArc.addressingReason);
      expect(d.dhcpReason, ChromeOsArc.addressingReason);
      expect(d.dnsReason, ChromeOsArc.addressingReason);
    });

    test('a normal Android device is completely unaffected', () async {
      final NetworkDetailsService svc = NetworkDetailsService(
        isAndroid: true,
        isChromeOs: false,
        networkInfo: _realNetworkInfo(),
        androidAddressingReader: () async => <Object?, Object?>{
          'dhcpServer': '10.20.0.1',
          'dnsServers': <String>['10.20.0.53'],
        },
        interfaceLister: () async => <Never>[],
      );

      final NetworkDetails d = await svc.read();
      expect(d.localIp, '10.20.0.55');
      expect(d.subnetMask, '255.255.255.0');
      expect(d.gateway, '10.20.0.1');
      expect(d.dhcpServer, '10.20.0.1');
      expect(d.dnsServers, <String>['10.20.0.53']);
      expect(d.addressingReason, isNull,
          reason: 'off ChromeOS a missing value is a genuine per-read miss and '
              'must fall to the row\'s plain "Unavailable", not a ceiling');
      expect(d.isChromeOs, isFalse);
    });
  });

  // =========================================================================
  group('ApScanService — the scan is not offered on ChromeOS', () {
    test('platformStatus is chromeOsUnreliable, NOT supported', () {
      final ApScanService svc =
          ApScanService(platformOverride: 'android', isChromeOs: true);
      expect(svc.isSupportedPlatform, isFalse,
          reason: 'the scan\'s headline datum is signal, which ChromeOS cannot '
              'supply truthfully — a list with a fabricated dBm column is worse '
              'than no list');
      expect(svc.platformStatus, ApScanPlatformStatus.chromeOsUnreliable);
    });

    test('a normal Android phone still scans', () {
      final ApScanService svc =
          ApScanService(platformOverride: 'android', isChromeOs: false);
      expect(svc.isSupportedPlatform, isTrue);
      expect(svc.platformStatus, ApScanPlatformStatus.supported);
    });

    test('the ChromeOS verdict never leaks onto another platform', () {
      for (final String p in <String>['ios', 'macos', 'windows', 'linux']) {
        expect(
          ApScanService(platformOverride: p, isChromeOs: false).platformStatus,
          isNot(ApScanPlatformStatus.chromeOsUnreliable),
          reason: '$p must keep its own honest reason',
        );
      }
    });
  });

  // =========================================================================
  group('the copy is honest and specific', () {
    test('every reason names ChromeOS, never Android', () {
      // A Chromebook user told "Android does not expose this" goes looking for
      // an Android fix that does not exist. The ceiling is ChromeOS's; say so.
      for (final String reason in <String>[
        ChromeOsArc.signalReason,
        ChromeOsArc.noiseReason,
        ChromeOsArc.snrReason,
        ChromeOsArc.rateReason,
        ChromeOsArc.channelWidthReason,
        ChromeOsArc.standardReason,
      ]) {
        expect(reason.toLowerCase(), contains('chromeos'),
            reason: 'the reason must name the OS that actually imposes the '
                'ceiling: "$reason"');
      }
    });

    test(
        'no reason string promises a dBm, a percentage, or any number we do '
        'not have', () {
      expect(ChromeOsArc.signalReason.contains('dBm'), isTrue,
          reason: 'it should name dBm as the thing that is missing…');
      expect(ChromeOsArc.signalReason.contains('%'), isFalse,
          reason: '…but must not imply we can show a percentage instead — we '
              'have no ONC access from inside Android, so we do not have one');
    });

    test('the addressing reason names the virtual machine explicitly', () {
      expect(ChromeOsArc.addressingReason.toLowerCase(),
          contains('virtual machine'));
      expect(ChromeOsArc.addressingReason.toLowerCase(),
          contains('not your network'));
    });
  });
}

/// A fake NetworkInfo. `NetworkInfo` has only a factory constructor, so it is
/// `implement`ed with a noSuchMethod catch-all; only the three getters the
/// service reads are overridden. No platform channel. (Same shape as the fake in
/// network_details_service_test.dart.)
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.ip, this.submask, this.gateway});

  final String? ip;
  final String? submask;
  final String? gateway;

  @override
  Future<String?> getWifiIP() async => ip;
  @override
  Future<String?> getWifiSubmask() async => submask;
  @override
  Future<String?> getWifiGatewayIP() async => gateway;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Exactly what a Chromebook's ARC VM really reports. If the ChromeOS guard ever
/// regresses, THESE are the values that leak into the user's report — which is
/// why the suppression test asserts against this fake and not an empty one.
NetworkInfo _arcNetworkInfo() => _FakeNetworkInfo(
      ip: '100.115.92.2',
      submask: '255.255.255.252',
      gateway: '100.115.92.1',
    );

/// An ordinary phone on a real LAN.
NetworkInfo _realNetworkInfo() => _FakeNetworkInfo(
      ip: '10.20.0.55',
      submask: '255.255.255.0',
      gateway: '10.20.0.1',
    );
