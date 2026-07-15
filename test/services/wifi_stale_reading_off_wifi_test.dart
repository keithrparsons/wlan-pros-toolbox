// REGRESSION SUITE — the stale-Wi-Fi-reading-on-cellular honesty bug.
//
// Keith, on a real iPhone (iOS, v1.7.2), on CELLULAR ONLY with no Wi-Fi at all:
//
//   * Wi-Fi Information showed a "Live" badge, an RSSI chart still saying
//     "Waiting for the first reading…", and Tx 29 Mbps / Rx 13 Mbps rendered as
//     current / min / avg / max.
//   * Test My Connection showed a "Wi-Fi signal" card with a green LIVE badge and
//     "Wi-Fi data rate 29 Mbps", and the verdict "Your internet can carry more
//     than your Wi-Fi link is passing. Boost the Wi-Fi signal to raise the
//     ceiling."
//
// The app told a user with NO Wi-Fi to go boost his Wi-Fi signal, on the strength
// of a rate read the last time the phone was actually on Wi-Fi.
//
// THREE independent suppression points let a stale reading outrank a POSITIVE
// not-on-Wi-Fi probe. Each is covered here:
//
//   1. WifiMonitorController.load()  — `_notOnWifi && !_hasEverReceived` gated the
//      honest phase behind "has this user ever captured a reading". Covered in
//      test/services/wifi_monitor_controller_test.dart.
//   2. WifiSignalSampler.notOnWifi   — a SECOND `&& !hasEverReceived` gate, reading
//      the controller's RAW probe flag. NOT downstream of (1): fixing the
//      controller alone would have left Test My Connection lying. Covered below.
//   3. The verdict engine            — fed the stale rate, it computed a usable-Wi-Fi
//      ceiling and emitted "boost the Wi-Fi signal". Covered below.
//
// GL-005: two kinds of null. "We could not read this" is one; "this does not
// exist" is the other. Off Wi-Fi is the SECOND, and the copy must say so.
//
// ANTI-OVER-SUPPRESSION: every fix here keys off a POSITIVE not-on-Wi-Fi probe
// only. An ambiguous read (wired desktop, Location-gated, failed read) resolves
// to `unknown` and changes nothing. Tests below pin that down too.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

/// Canned Wi-Fi addresses → the honest probe verdict. On iOS, `notOnWifi` needs
/// BOTH families empty: `getWifiIP()` is IPv4-only, so an IPv6-only SSID reads
/// null there while fully associated (cold-eyes F3). Defaults model a
/// cellular-only phone: no IPv4, no IPv6.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.wifiIp, this.wifiIpv6});

  String? wifiIp;
  String? wifiIpv6;

  @override
  Future<String?> getWifiIP() async => wifiIp;

  @override
  Future<String?> getWifiIPv6() async => wifiIpv6;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WifiConnectionService _conn({
  String? wifiIp,
  String? wifiIpv6,
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  return WifiConnectionService(
    networkInfo: _FakeNetworkInfo(wifiIp: wifiIp, wifiIpv6: wifiIpv6),
    platformOverride: platform,
  );
}

/// In-memory [WiFiDetailsBridge] holding a STALE stored payload — exactly what
/// the iOS App Group holds after the phone leaves Wi-Fi.
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge();

  final StreamController<WiFiDetails> _updates =
      StreamController<WiFiDetails>.broadcast();

  bool everReceived = false;
  bool monitoringFlag = false;
  WiFiDetails? latest;

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;
  @override
  Future<WiFiDetails?> readLatest() async => latest;
  @override
  Future<bool> isMonitoringActive() async => monitoringFlag;
  @override
  Future<void> setMonitoringActive(bool active) async => monitoringFlag = active;
  @override
  Future<void> resetMonitoringColdStart() async => monitoringFlag = false;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => _updates.stream;

  Future<void> close() => _updates.close();
}

/// THE stale payload from Keith's device: Tx 29 / Rx 13 Mbps, captured the last
/// time the phone was on Wi-Fi and still sitting in the App Group.
const WiFiDetails _stale = WiFiDetails(
  ssid: 'KeithHome',
  bssid: '94:2a:6f:a0:a5:5d',
  rssi: -61,
  noise: -95,
  channel: 44,
  standard: '802.11ax - Wi-Fi 6',
  rxRate: 13,
  txRate: 29,
);

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // SUPPRESSION POINT 2 — WifiSignalSampler.notOnWifi
  //
  // This getter is what the Test My Connection "Wi-Fi signal" card gates on. It
  // read `(_controller?.notOnWifi ?? false) && !hasEverReceived` — a SECOND copy
  // of the controller's gate, reading the controller's RAW probe flag. So it was
  // NOT fixed by fixing the controller: on a phone that had ever captured a
  // reading, `notOnWifi` returned false, the honest NotOnWifiCard never rendered,
  // and the card kept painting a LIVE badge over a stale 29 Mbps.
  // ═══════════════════════════════════════════════════════════════════════════
  group('WifiSignalSampler — the second not-on-Wi-Fi gate', () {
    test(
        'REGRESSION: a user who HAS captured a reading before, now on cellular, '
        'still gets the honest not-on-Wi-Fi state', () async {
      final bridge = _FakeBridge()
        ..everReceived = true // the bug's trigger: any real user
        ..latest = _stale;
      final sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: _conn(wifiIp: null), // cellular-only iPhone
      );

      await sampler.load();

      expect(sampler.hasEverReceived, isTrue,
          reason: 'the precondition that used to suppress the honest state');
      expect(sampler.notOnWifi, isTrue,
          reason: 'THE BUG: the honest not-on-Wi-Fi state must NOT be gated on '
              '"has this user ever captured a Wi-Fi reading". It never fired for '
              'anyone real.');

      sampler.dispose();
      await bridge.close();
    });

    test(
        'REGRESSION: the sampler surfaces NO stale Wi-Fi rate while off Wi-Fi '
        '(no "Wi-Fi data rate 29 Mbps" with no Wi-Fi)', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _stale;
      final sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: _conn(wifiIp: null),
      );

      await sampler.load();

      expect(sampler.latest, isNull,
          reason: 'the "Wi-Fi signal" card binds to sampler.latest. There is no '
              'Wi-Fi link, so there is no Tx/Rx rate to show.');
      expect(sampler.series.txRate.isEmpty, isTrue,
          reason: 'and nothing stale gets charted as a live sample');
      expect(sampler.isStreaming, isFalse,
          reason: 'no LIVE badge over a link that does not exist');

      sampler.dispose();
      await bridge.close();
    });

    test(
        'BUT an IPv6-only Wi-Fi network keeps its reading (the suppression must '
        'not over-reach — cold-eyes F3)', () async {
      // The mirror image of the test above, and the reason that one is not enough.
      // `getWifiIP()` is IPv4-only, so this phone — fully associated to a NAT64 /
      // IPv6-only SSID, the kind conference and carrier networks run — also reads
      // a null Wi-Fi IPv4. Suppressing on that null alone blanks a LIVE link.
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _stale;
      final sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService:
            _conn(wifiIp: null, wifiIpv6: '2606:4700:4700::1111'),
      );

      await sampler.load();

      expect(sampler.notOnWifi, isFalse,
          reason: 'an IPv6-only Wi-Fi network is Wi-Fi');
      expect(sampler.latest, isNotNull,
          reason: 'the reading of a CONNECTED device must not be blanked');

      sampler.dispose();
      await bridge.close();
    });

    test(
        'ANTI-OVER-SUPPRESSION: on Wi-Fi with a stored reading, the sampler is '
        'unchanged (data still flows)', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _stale;
      final sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: _conn(wifiIp: '192.168.1.50'), // genuinely on Wi-Fi
      );

      await sampler.load();

      expect(sampler.notOnWifi, isFalse);
      expect(sampler.latest, isNotNull,
          reason: 'a real Wi-Fi link keeps its last known reading — the fix must '
              'not suppress more than is true');
      expect(sampler.latest!.txRateMbps, 29);

      sampler.dispose();
      await bridge.close();
    });

    test(
        'ANTI-OVER-SUPPRESSION: a resolved native SSID beats a null Wi-Fi IP — '
        'never a false "not on Wi-Fi"', () async {
      final bridge = _FakeBridge()
        ..everReceived = true
        ..latest = _stale;
      final sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: _conn(wifiIp: null),
      );

      // A known SSID can only come from an active association.
      await sampler.load(nativeSsid: 'KeithHome');

      expect(sampler.notOnWifi, isFalse);
      expect(sampler.latest, isNotNull);

      sampler.dispose();
      await bridge.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SUPPRESSION POINT 3 — the verdict engine
  //
  // Fed the stale 29/13 Mbps, the engine computed usableWifi = 0.55 × avg(29,13)
  // = 11.55 Mbps, compared it to a live cellular download, got a headroom ratio
  // far above 0.70, and returned `wifiLimiter` — which the screen renders as
  // "Boost the Wi-Fi signal to raise the ceiling."
  //
  // The fix is upstream (the screen no longer hands the engine a stale AP when
  // the probe says off-Wi-Fi), so these tests pin BOTH halves: the engine must
  // not invent a Wi-Fi ceiling from nothing, AND when told the device is off
  // Wi-Fi it must say so instead of "the Wi-Fi link could not be read".
  // ═══════════════════════════════════════════════════════════════════════════
  group('WifiVsInternetEngine — no Wi-Fi link, no Wi-Fi verdict', () {
    test(
        'REGRESSION: the exact device shape — stale 29/13 Mbps + cellular '
        'download — produced "boost the Wi-Fi signal"', () {
      // This is what the engine DID compute pre-fix, and it is arithmetically
      // correct given its inputs. Documented here so the fix is understood as
      // "stop feeding it a rate that does not exist", not "change the math".
      final r = WifiVsInternetEngine.evaluate(
        txRateMbps: 29,
        rxRateMbps: 13,
        internetDownMbps: 40,
        internetHealth: InternetHealth.marginal,
      );

      expect(r.verdict, WifiVsInternetVerdict.wifiLimiter,
          reason: 'the engine is not the liar — its INPUT was');
      expect(r.usableWifiMbps, closeTo(11.55, 0.01));
      expect(r.explanation, contains('The air link is the limiter'));
    });

    test(
        'REGRESSION: off Wi-Fi, the engine gets NO rate and must never name the '
        'Wi-Fi link the limiter', () {
      // Post-fix the screen passes a null AP when the probe says not-on-Wi-Fi, so
      // the engine sees no rate at all. It must not blame a link it cannot see.
      final r = WifiVsInternetEngine.evaluate(
        internetDownMbps: 40,
        internetHealth: InternetHealth.marginal,
        notOnWifi: true,
      );

      expect(r.verdict, isNot(WifiVsInternetVerdict.wifiLimiter));
      expect(r.verdict, isNot(WifiVsInternetVerdict.bothContributing));
      expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
      expect(r.usableWifiMbps, isNull,
          reason: 'no link, no usable-capacity figure — never a fabricated one');
      expect(r.linkRateMbps, isNull);
      expect(r.internetMbps, 40, reason: 'the internet WAS measured; keep it');
    });

    test(
        'TWO KINDS OF NULL: off Wi-Fi says "there is no Wi-Fi link", not "we '
        'could not read it"', () {
      final r = WifiVsInternetEngine.evaluate(
        internetDownMbps: 40,
        internetHealth: InternetHealth.marginal,
        notOnWifi: true,
      );

      expect(r.notOnWifi, isTrue);
      expect(r.headline, 'Not connected to Wi-Fi');
      expect(r.explanation, contains('not on Wi-Fi'));
      expect(r.explanation, isNot(contains('could not be read')),
          reason: '"could not be read" implies a retry might succeed');
      expect(r.explanation.toLowerCase(), isNot(contains('shortcut')),
          reason: 'no Shortcut can read a Wi-Fi link that does not exist — never '
              'send a cellular-only user to install one');
    });

    test(
        'ANTI-OVER-SUPPRESSION: an UNKNOWN probe keeps the original '
        '"could not read" copy (wired / Location-gated / no Shortcut)', () {
      // notOnWifi defaults to false, so every existing caller is untouched.
      final r = WifiVsInternetEngine.evaluate(
        internetDownMbps: 40,
        internetHealth: InternetHealth.marginal,
      );

      expect(r.notOnWifi, isFalse);
      expect(r.verdict, WifiVsInternetVerdict.wifiUnknown);
      expect(r.headline, 'Wi-Fi link not measured');
      expect(r.explanation, contains('could not be read'));
      expect(r.explanation, contains('companion Shortcut'),
          reason: 'a user who CAN get a Wi-Fi read still gets the setup path');
    });

    test(
        'ANTI-OVER-SUPPRESSION: a real Wi-Fi link still produces a real verdict',
        () {
      final r = WifiVsInternetEngine.evaluate(
        txRateMbps: 866,
        rxRateMbps: 866,
        internetDownMbps: 90,
        internetHealth: InternetHealth.marginal,
      );

      expect(r.notOnWifi, isFalse);
      expect(r.verdict, WifiVsInternetVerdict.upstream);
      expect(r.usableWifiMbps, closeTo(476.3, 0.1));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // The two-kinds-of-null distinction must survive the ConnectedAp boundary too:
  // a ConnectedAp built from the stale payload carries the 29/13 rates, and the
  // ONLY thing standing between it and the verdict engine is the screen's
  // not-on-Wi-Fi check. Pin the shape so a future refactor cannot quietly restore
  // the old path.
  // ═══════════════════════════════════════════════════════════════════════════
  group('the stale payload is real data — the bug was showing it as current', () {
    test('ConnectedAp.fromWifiDetails(stale) genuinely carries 29/13 Mbps', () {
      final ap = ConnectedAp.fromWifiDetails(_stale);

      expect(ap.txRateMbps, 29);
      expect(ap.rxRateMbps, 13);
      // Which is exactly why it must never reach the engine off Wi-Fi: the data
      // is real, it is just not TRUE ANY MORE. Staleness is invisible to every
      // layer below the connection probe.
    });
  });
}
