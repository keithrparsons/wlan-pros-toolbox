// iOS WI-FI ASSIST — THE ADDRESS PROBE OVERRODE THE OS's OWN ROUTING ANSWER.
//
// ============================================================================
// THE SPEND PATH KEITH RULED TO CLOSE (2026-07-14).
// ============================================================================
//
// iOS Wi-Fi Assist: when the Wi-Fi signal is weak, iOS keeps the Wi-Fi interface
// UP — `en0` holds a valid IPv4 — but ROUTES TRAFFIC OVER CELLULAR. A throughput
// run started in that state spends the user's mobile data, silently.
//
// `NWPathMonitor` KNOWS. The default path's `usesInterfaceType(.wifi)` is FALSE and
// its Wi-Fi-required path is UNSATISFIED: the OS is telling us, definitively, that
// the active route is not Wi-Fi. `WifiConnectionService` reads that answer (the path
// probe returns `usesWifi:false, wifiSatisfied:false`) — and then THREW IT AWAY for
// the money axis: the path fell through, the address probe read the raw `en0` IPv4,
// and returned `meteredRisk: MeteredRisk.none` — SPEND WITHOUT ASKING.
//
// The FACT axis is not the problem: Wi-Fi Assist genuinely HAS a Wi-Fi association,
// so `status == onWifi` is honest and STAYS. This is purely the SPEND axis: when the
// OS says the bytes are going over cellular, a raw address is not permission to spend
// silently. Ambiguity ASKS.
//
// KEITH'S RULE: the tap stays. Less cost is not no cost. A spurious prompt costs one
// tap; a silent spend costs real money. So the SPEND axis fails to
// `MeteredRisk.unknown` (which ASKS), while the FACT axis keeps `onWifi`.
//
// GUARD: this test drives `WifiConnectionService.read()` — the layer that RUNS the
// decision — with the Wi-Fi-Assist shape (path route NOT Wi-Fi + en0 holds an IPv4)
// and asserts BOTH axes. It is RED against 34cb906 (address probe returns `none`).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';

/// Canned Wi-Fi addresses; models the real plugin, which exposes both families.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.wifiIp, this.wifiIpv6});
  final String? wifiIp;
  final String? wifiIpv6;
  @override
  Future<String?> getWifiIP() async => wifiIp;
  @override
  Future<String?> getWifiIPv6() async => wifiIpv6;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A path probe with a scripted answer.
class _FakePathProbe implements WifiPathProbe {
  const _FakePathProbe(this.facts);
  final WifiPathFacts? facts;
  @override
  Future<WifiPathFacts?> read() async => facts;
}

/// THE WI-FI-ASSIST SHAPE. The path monitor answered, and it says the active route
/// is NOT Wi-Fi (usesWifi false, wifiSatisfied false) — but a Wi-Fi interface IS
/// present and holding a route-less association. This is exactly what iOS reports
/// when Wi-Fi Assist has moved traffic to cellular while leaving en0 up.
const WifiPathFacts _kWifiAssistPath = WifiPathFacts(
  usesWifi: false,
  wifiSatisfied: false,
  wifiInterfacePresent: true,
);

WifiConnectionService _service({
  String? wifiIp,
  String? wifiIpv6,
  required WifiPathProbe pathProbe,
}) =>
    WifiConnectionService(
      networkInfo: _FakeNetworkInfo(wifiIp: wifiIp, wifiIpv6: wifiIpv6),
      platformOverride: TargetPlatform.iOS,
      pathProbe: pathProbe,
    );

void main() {
  group('iOS Wi-Fi Assist — the OS routing answer governs the SPEND axis', () {
    test(
        'en0 holds an IPv4 while the path route is cellular -> ASK, do not spend',
        () async {
      // The exploit: the address probe reads the raw en0 IPv4 and, on 34cb906,
      // returns MeteredRisk.none — silently spending cellular data. The path probe
      // already told us the route is not Wi-Fi. The money axis must honor it.
      final WifiConnectionService s = _service(
        wifiIp: '10.42.0.7',
        wifiIpv6: 'fe80::10b4:5ba5:5d42:a691%en0',
        pathProbe: const _FakePathProbe(_kWifiAssistPath),
      );

      final LinkVerdict v = await s.read();

      expect(
        v.meteredRisk,
        MeteredRisk.unknown,
        reason: 'iOS said the active route is not Wi-Fi; a raw en0 IPv4 is not '
            'permission to spend cellular data silently. Ambiguity ASKS.',
      );
      expect(
        v.meteredRisk.requiresConsent,
        isTrue,
        reason: 'the consent gate reads requiresConsent; it MUST be true so the '
            'throughput run cannot start without a tap',
      );
    });

    test(
        'the FACT axis is UNTOUCHED — Wi-Fi Assist really is a Wi-Fi association',
        () async {
      // Do NOT assert a falsehood on the Wi-Fi FACT axis. There is a genuine Wi-Fi
      // join here; the raw IPv4 proves it. Only the SPEND axis is ambiguous. Keep
      // the two axes cleanly separated (round 5).
      final WifiConnectionService s = _service(
        wifiIp: '10.42.0.7',
        pathProbe: const _FakePathProbe(_kWifiAssistPath),
      );

      final LinkVerdict v = await s.read();

      expect(
        v.status,
        WifiConnectionStatus.onWifi,
        reason: 'the device DOES have a Wi-Fi association (en0 holds a real IPv4); '
            'the money axis asking does not license claiming it is off Wi-Fi',
      );
    });

    test(
        'a NORMAL iOS Wi-Fi run (path route IS Wi-Fi) still spends without asking',
        () async {
      // NEGATIVE CONTROL. The fix must not nag a healthy Wi-Fi user. When the path
      // monitor says the route runs over Wi-Fi, it returns onWifi/none BEFORE the
      // address probe is ever reached, exactly as before.
      final WifiConnectionService s = _service(
        wifiIp: '192.168.1.20',
        pathProbe: const _FakePathProbe(WifiPathFacts(
          usesWifi: true,
          wifiSatisfied: true,
          wifiInterfacePresent: true,
        )),
      );

      final LinkVerdict v = await s.read();

      expect(v.status, WifiConnectionStatus.onWifi);
      expect(v.meteredRisk, MeteredRisk.none,
          reason: 'a proven Wi-Fi route must not raise a spurious cellular prompt');
      expect(v.meteredRisk.requiresConsent, isFalse);
    });

    test(
        'when the path probe did NOT answer, a raw IPv4 still reads none (unchanged)',
        () async {
      // The pre-existing, DOCUMENTED residual: with no path answer at all, the
      // address alone decides, and an en0 IPv4 reads onWifi/none. The fix keys off
      // the path monitor HAVING ANSWERED "not Wi-Fi" — it does not change the
      // no-answer fallback, so a healthy phone whose native probe is unavailable is
      // not newly nagged.
      final WifiConnectionService s = _service(
        wifiIp: '192.168.1.20',
        pathProbe: const _FakePathProbe(null),
      );

      final LinkVerdict v = await s.read();

      expect(v.status, WifiConnectionStatus.onWifi);
      expect(v.meteredRisk, MeteredRisk.none);
    });
  });
}
