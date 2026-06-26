// Unit tests for [WifiConnectionService] — the honest "is this device on Wi-Fi?"
// probe (2026-06-25).
//
// Exercises all THREE honest verdicts (onWifi / notOnWifi / unknown) without a
// live network, by injecting a fake [NetworkInfo] and a platform override. The
// GL-005 invariant under test: a null / ambiguous Wi-Fi IP never resolves to a
// false `notOnWifi` — only a positive signal does.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';

/// In-memory fake of [NetworkInfo]: returns a canned Wi-Fi IP (or throws to
/// simulate a denied/unsupported read).
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.wifiIp, this.throws = false});

  final String? wifiIp;
  final bool throws;

  @override
  Future<String?> getWifiIP() async {
    if (throws) throw Exception('getWifiIP denied');
    return wifiIp;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WifiConnectionService _service({
  String? wifiIp,
  bool throws = false,
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  return WifiConnectionService(
    networkInfo: _FakeNetworkInfo(wifiIp: wifiIp, throws: throws),
    platformOverride: platform,
  );
}

void main() {
  group('WifiConnectionService.status — onWifi', () {
    test('a non-empty Wi-Fi IP -> onWifi (iOS)', () async {
      final s = _service(wifiIp: '192.168.1.42');
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('a non-empty Wi-Fi IP -> onWifi (macOS)', () async {
      final s = _service(wifiIp: '10.0.0.5', platform: TargetPlatform.macOS);
      expect(await s.status(), WifiConnectionStatus.onWifi);
    });

    test('a resolved native SSID -> onWifi even with no Wi-Fi IP', () async {
      // A native NEHotspotNetwork SSID can only come from an active Wi-Fi join,
      // so it is a definitive positive even when getWifiIP returns null.
      final s = _service(wifiIp: null);
      expect(
        await s.status(nativeSsid: 'KeithNet'),
        WifiConnectionStatus.onWifi,
      );
    });

    test('a blank native SSID is ignored (falls through to the IP probe)',
        () async {
      // A whitespace-only SSID is not a real join; it must not assert onWifi.
      final s = _service(wifiIp: null, platform: TargetPlatform.iOS);
      expect(await s.status(nativeSsid: '   '), WifiConnectionStatus.notOnWifi);
    });
  });

  group('WifiConnectionService.status — notOnWifi (positive signal only)', () {
    test('null Wi-Fi IP on iOS -> notOnWifi (the cellular-only case)', () async {
      // On iOS a null Wi-Fi IP reliably means there is no Wi-Fi link.
      final s = _service(wifiIp: null);
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('empty Wi-Fi IP on iOS -> notOnWifi', () async {
      final s = _service(wifiIp: '');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });

    test('all-zeros placeholder IP on iOS -> notOnWifi', () async {
      // Some platforms return 0.0.0.0 for "no address"; treat as no Wi-Fi IP.
      final s = _service(wifiIp: '0.0.0.0');
      expect(await s.status(), WifiConnectionStatus.notOnWifi);
    });
  });

  group('WifiConnectionService.status — unknown (never a false notOnWifi)', () {
    test('null Wi-Fi IP on macOS -> unknown (wired desktop is ambiguous)',
        () async {
      // A wired-only Mac legitimately has no Wi-Fi IP — must NOT be told to
      // "connect to Wi-Fi" (GL-005).
      final s = _service(wifiIp: null, platform: TargetPlatform.macOS);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('null Wi-Fi IP on Android -> unknown', () async {
      final s = _service(wifiIp: null, platform: TargetPlatform.android);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });

    test('a thrown read resolves to unknown, not notOnWifi (even on iOS)',
        () async {
      // A denied/unsupported read is ambiguous — never a false negative.
      final s = _service(throws: true, platform: TargetPlatform.iOS);
      expect(await s.status(), WifiConnectionStatus.unknown);
    });
  });
}
