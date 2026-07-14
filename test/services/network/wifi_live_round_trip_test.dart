// THE SHORTCUT ROUND-TRIP TEST (2026-07-14, Keith device — the live-feed regression).
//
// WHY THIS FILE EXISTS. Four rounds of review, 4,220 tests and five cold-eyes
// passes all missed a bug Keith's phone found in five minutes: tapping "Start
// live monitoring" while genuinely on Wi-Fi reported *"Could not start the live
// Wi-Fi feed. The companion 'WLAN Pros Live' Shortcut may not be installed."*
// Reinstalling the Shortcut never helped — because the Shortcut was never the
// problem.
//
// EVERY EXISTING TEST STARTED THE STREAM AND THEN PUSHED A PAYLOAD DOWN THE LIVE
// STREAM, IN THE FOREGROUND, WITHIN THE SETTLE WINDOW. That is not what the
// device does. On a real iPhone, Start does this:
//
//   startMonitoring()            the app raises the App Group loop flag and fires
//                                `shortcuts://run-shortcut?name=WLAN Pros Live`
//   -> iOS FOREGROUNDS THE SHORTCUTS APP, so the Toolbox is BACKGROUNDED
//   -> the Shortcut runs and delivers its sample to the APP GROUP, and posts a
//      Darwin notification that a BACKGROUNDED (soon suspended) Flutter engine
//      cannot receive
//   -> the user switches back; the app RESUMES and load() runs
//
// The payload arrives through the APP GROUP, not through the live stream. So the
// suite's happy path exercised a delivery channel the Start path cannot use, and
// the one channel it does use was never tested. That gap is the bug.
//
// These tests drive the REAL lifecycle. They are the regression guard for:
//   1. the round-trip: a payload delivered while backgrounded must keep the
//      session alive (RED before the fix: the settle declared the Shortcut
//      missing and tore the stream down);
//   2. a TRANSIENT not-on-Wi-Fi probe on resume must never kill a live session;
//   3. a CONFIRMED not-on-Wi-Fi (a genuine drop to cellular) must still tear it
//      down — the honest state is not weakened to buy (2);
//   4. a genuinely MISSING Shortcut must still be reported — the fix does not buy
//      (1) by going blind.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_monitor_controller.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';

/// A [WifiPathProbe] whose answer the test drives — the seam that models what
/// iOS's NWPathMonitor reports at each point in the lifecycle.
class _FakePathProbe implements WifiPathProbe {
  _FakePathProbe(this.facts);

  /// The next answer. Mutable so a test can flip it between reads (the whole
  /// point: a probe result taken during an app-switch is not the same as the one
  /// taken a moment later).
  WifiPathFacts? facts;

  /// Every answer handed out, in order — so a test can prove a CONFIRMATION
  /// re-probe actually happened rather than trusting that it did.
  int reads = 0;

  /// When set, the answer for read N (0-based); falls back to [facts].
  List<WifiPathFacts?>? scripted;

  @override
  Future<WifiPathFacts?> read() async {
    final List<WifiPathFacts?>? s = scripted;
    final WifiPathFacts? answer =
        (s != null && reads < s.length) ? s[reads] : facts;
    reads++;
    return answer;
  }
}

/// On Wi-Fi: the default route runs over Wi-Fi. The shape a healthy iPhone
/// reports while associated.
const WifiPathFacts _onWifi = WifiPathFacts(
  usesWifi: true,
  wifiSatisfied: true,
  wifiInterfacePresent: true,
);

/// Not on Wi-Fi: no Wi-Fi interface on either path at all. The ONLY shape the
/// decision table is permitted to read as a positive `notOnWifi` — the radio-off
/// / cellular-only device.
const WifiPathFacts _offWifi = WifiPathFacts(
  usesWifi: false,
  wifiSatisfied: false,
  wifiInterfacePresent: false,
);

/// The ADDRESS probe, which is now the ONLY route to a negative verdict anywhere
/// in the service (F-4, 2026-07-14: the native path no longer asserts "no Wi-Fi"
/// from a signal no iPhone has ever run). An off-Wi-Fi fixture must therefore be
/// expressed HERE — a native "no Wi-Fi interface" is only an ambiguity now, and
/// falls through to this.
class _AddrNet implements NetworkInfo {
  _AddrNet({this.onWifi = true, this.scripted});

  /// Mirrors the path probe: when the fixture says off Wi-Fi, the interface
  /// carries no address of either family (the radio-off / cellular-only shape).
  bool onWifi;

  /// Per-read answers, so a fixture can model a TRANSIENT — a read taken across
  /// the Shortcuts app-switch that disagrees with the one taken a moment later.
  final List<bool>? scripted;

  int reads = 0;

  bool get _next {
    final List<bool>? s = scripted;
    final bool v = (s != null && reads < s.length) ? s[reads] : onWifi;
    reads++;
    return v;
  }

  @override
  Future<String?> getWifiIP() async => _next ? '192.168.1.20' : null;

  @override
  Future<String?> getWifiIPv6() async => null;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WifiConnectionService _conn(_FakePathProbe probe, {_AddrNet? net}) =>
    WifiConnectionService(
      networkInfo: net ?? _AddrNet(),
      platformOverride: TargetPlatform.iOS,
      pathProbe: probe,
    );

/// In-memory fake of the native bridge, modelling the APP GROUP as the durable
/// store it actually is: [latest] + [receivedAt] are what the out-of-process
/// Shortcut writes, and they are readable whether or not the app was foregrounded
/// when the write happened. [push] is the live Darwin stream, which is ONLY
/// deliverable while the app is in the foreground.
class _FakeBridge extends WiFiDetailsBridge {
  final StreamController<WiFiDetails> _events =
      StreamController<WiFiDetails>.broadcast();

  bool everReceived = false;
  bool monitoringFlag = false;
  WiFiDetails? latest;
  DateTime? receivedAt;
  bool runShortcutResult = true;

  int runShortcutCalls = 0;
  int setMonitoringActiveCalls = 0;

  /// THE APP GROUP WRITE the out-of-process Shortcut performs. This is what a
  /// real delivery looks like when the Toolbox is backgrounded in the Shortcuts
  /// app: the payload and its timestamp land in shared storage, and NOTHING is
  /// delivered to the (suspended) Dart isolate.
  void deliverWhileBackgrounded(WiFiDetails d, {DateTime? at}) {
    latest = d;
    receivedAt = at ?? DateTime.now();
    everReceived = true;
  }

  /// A foreground delivery: the App Group write AND the Darwin push.
  void deliverWhileForegrounded(WiFiDetails d, {DateTime? at}) {
    deliverWhileBackgrounded(d, at: at);
    _events.add(d);
  }

  @override
  Future<bool> hasEverReceivedPayload() async => everReceived;
  @override
  Future<WiFiDetails?> readLatest() async => latest;
  @override
  Future<DateTime?> payloadReceivedAt() async => receivedAt;
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;
  @override
  Future<bool> isMonitoringActive() async => monitoringFlag;

  @override
  Future<void> setMonitoringActive(bool active) async {
    setMonitoringActiveCalls++;
    monitoringFlag = active;
  }

  @override
  Future<void> resetMonitoringColdStart() async => monitoringFlag = false;

  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    return runShortcutResult;
  }

  @override
  Future<bool> runShortcutOneShot(String name) async {
    runShortcutCalls++;
    return runShortcutResult;
  }

  @override
  Stream<WiFiDetails> get updates => _events.stream;

  Future<void> close() => _events.close();
}

WiFiDetails _details({int rssi = -45}) => WiFiDetails(
      ssid: 'KeithHome',
      bssid: '94:2a:6f:a0:a5:5d',
      rssi: rssi,
      noise: -95,
      channel: 44,
      standard: '802.11be - Wi-Fi 7',
      rxRate: 864,
      txRate: 1297,
    );

/// Short, so the tests run fast; the production values are 4s / 1200ms.
const Duration _settle = Duration(milliseconds: 60);
const Duration _confirm = Duration(milliseconds: 20);

/// Long enough for the settle timer AND any confirmation re-probe to have run.
Future<void> _pastSettle() =>
    Future<void>.delayed(_settle + _confirm + const Duration(milliseconds: 60));

void main() {
  group('THE SHORTCUT ROUND-TRIP — start, background, resume', () {
    test(
      'a payload delivered WHILE BACKGROUNDED keeps the live session alive '
      '(the regression Keith hit: it was declared a missing Shortcut)',
      () async {
        final probe = _FakePathProbe(_onWifi);
        final bridge = _FakeBridge()
          ..everReceived = true
          ..latest = _details(rssi: -60) // the STALE stored reading
          ..receivedAt = DateTime.now().subtract(const Duration(days: 30));
        final c = WifiMonitorController(
          bridge: bridge,
          connectionService: _conn(probe),
          missingShortcutSettle: _settle,
          notOnWifiConfirmSettle: _confirm,
        );

        // 1. The user taps Start. The trigger opens Shortcuts; the app backgrounds.
        final bool opened = await c.startMonitoring(
          triggerShortcutName: 'WLAN Pros Live',
        );
        expect(opened, isTrue);
        expect(c.isStreaming, isTrue);
        expect(bridge.monitoringFlag, isTrue,
            reason: 'Start must raise the App Group loop flag');
        final DateTime startedAt = DateTime.now();

        // 2. The Shortcut runs while we are BACKGROUNDED in the Shortcuts app. It
        //    writes to the App Group. It CANNOT push to the suspended engine.
        bridge.deliverWhileBackgrounded(
          _details(rssi: -41),
          at: startedAt.add(const Duration(milliseconds: 10)),
        );

        // 3. The settle window elapses while we are still backgrounded.
        await _pastSettle();

        // 4. The user switches back. The app resumes and load() runs.
        await c.load();

        // THE ASSERTIONS. The Shortcut demonstrably RAN — it delivered a payload
        // stamped after the Start. The session must survive.
        expect(
          c.shortcutMissing,
          isFalse,
          reason: 'A Shortcut that delivered a payload AFTER this Start is not '
              'missing. Declaring it missing is what sent Keith to reinstall a '
              'Shortcut that was never the problem.',
        );
        expect(
          c.isStreaming,
          isTrue,
          reason: 'The live session must survive the app-switch it is REQUIRED '
              'to make. Tearing it down kills the feed the user just started.',
        );
        expect(
          bridge.monitoringFlag,
          isTrue,
          reason: 'The App Group loop flag must stay raised — clearing it halts '
              'the recursive Shortcut on its next ShouldContinueMonitoring check, '
              'so the app kills the very producer it is waiting on.',
        );
        // And the backgrounded delivery must actually land as a real sample.
        expect(c.details?.rssi, -41);
        expect(c.deliveryCount, greaterThan(0));

        c.dispose();
        await bridge.close();
      },
    );

    test(
      'a genuinely MISSING Shortcut is still reported — no payload lands after '
      'Start, so the settle still fires (the fix is not blind)',
      () async {
        final probe = _FakePathProbe(_onWifi);
        final bridge = _FakeBridge()
          ..everReceived = true
          // A STALE stored reading is present, and must NOT be mistaken for proof
          // that this Start ran. This is the exact objection the old code answered
          // by refusing to look at the App Group at all.
          ..latest = _details(rssi: -60)
          ..receivedAt = DateTime.now().subtract(const Duration(days: 30));
        final c = WifiMonitorController(
          bridge: bridge,
          connectionService: _conn(probe),
          missingShortcutSettle: _settle,
          notOnWifiConfirmSettle: _confirm,
        );

        await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
        // The Shortcut is DELETED: it opens the Shortcuts app (iOS reports the
        // open as a success) and delivers NOTHING. No App Group write.
        await _pastSettle();

        expect(
          c.shortcutMissing,
          isTrue,
          reason: 'Nothing landed after this Start. The stale stored reading is '
              'older than the Start and must not mask the miss.',
        );
        expect(c.isStreaming, isFalse);
        expect(bridge.monitoringFlag, isFalse,
            reason: 'No producer exists: the phantom loop flag must be cleared.');

        c.dispose();
        await bridge.close();
      },
    );
  });

  group('not-on-Wi-Fi must be a SETTLED state, never a transient', () {
    test(
      'a TRANSIENT not-on-Wi-Fi probe on resume does NOT tear down a live session',
      () async {
        // The native path reports "no Wi-Fi interface" — which, since F-4, is only
        // an AMBIGUITY and falls through to the address probe. So the TRANSIENT is
        // modelled where the verdict is actually decided: the address read taken
        // across the Shortcuts app-switch (#0) comes back empty, and the
        // confirmation re-probe (#1) finds the link that was there all along.
        final probe = _FakePathProbe(_offWifi);
        final _AddrNet net = _AddrNet(scripted: <bool>[false, true]);
        final bridge = _FakeBridge()
          ..everReceived = true
          ..latest = _details()
          ..receivedAt = DateTime.now();
        final c = WifiMonitorController(
          bridge: bridge,
          connectionService: _conn(probe, net: net),
          missingShortcutSettle: _settle,
          notOnWifiConfirmSettle: _confirm,
        );

        await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
        bridge.deliverWhileBackgrounded(
          _details(rssi: -41),
          at: DateTime.now(),
        );
        await _pastSettle();

        // Resume: read #2 (the scripted _offWifi) is the transient.
        await c.load();

        expect(
          c.notOnWifi,
          isFalse,
          reason: 'One probe result taken across an app-switch is not a settled '
              'verdict. It must be confirmed before it is allowed to blank a link.',
        );
        expect(
          c.isStreaming,
          isTrue,
          reason: 'A transient probe must never tear down a live session.',
        );
        expect(bridge.monitoringFlag, isTrue);
        expect(net.reads, greaterThanOrEqualTo(2),
            reason: 'The not-on-Wi-Fi verdict must be CONFIRMED by a re-probe.');

        c.dispose();
        await bridge.close();
      },
    );

    test(
      'a CONFIRMED not-on-Wi-Fi (a real drop to cellular mid-stream) STILL tears '
      'the session down — the honest state is not weakened',
      () async {
        // Off Wi-Fi on every read, in BOTH probes: the device genuinely dropped to
        // cellular. Since F-4 the negative can only come from the address probe.
        final probe = _FakePathProbe(_offWifi);
        final _AddrNet net = _AddrNet(onWifi: false);
        final bridge = _FakeBridge()
          ..everReceived = true
          ..latest = _details()
          ..receivedAt = DateTime.now();
        final c = WifiMonitorController(
          bridge: bridge,
          connectionService: _conn(probe, net: net),
          missingShortcutSettle: _settle,
          notOnWifiConfirmSettle: _confirm,
        );

        await c.startMonitoring(triggerShortcutName: 'WLAN Pros Live');
        await c.load();

        expect(c.notOnWifi, isTrue,
            reason: 'A confirmed, positive not-on-Wi-Fi probe is the honest state.');
        expect(c.phase, WifiMonitorPhase.notOnWifi);
        expect(c.isStreaming, isFalse,
            reason: 'No Wi-Fi link means no producer: the stream must be torn down.');
        expect(bridge.monitoringFlag, isFalse,
            reason: 'A looping Shortcut has nothing to read off Wi-Fi.');
        expect(c.details, isNull,
            reason: 'THE ORIGINAL BUG: a stale reading must never render as live.');

        c.dispose();
        await bridge.close();
      },
    );

    test(
      'a cellular-only device that never started a stream still gets the honest '
      'not-connected state IMMEDIATELY (no confirmation delay on the idle path)',
      () async {
        final probe = _FakePathProbe(_offWifi);
        final _AddrNet net = _AddrNet(onWifi: false);
        final bridge = _FakeBridge()
          ..everReceived = true
          ..latest = _details()
          ..receivedAt = DateTime.now();
        final c = WifiMonitorController(
          bridge: bridge,
          connectionService: _conn(probe, net: net),
          missingShortcutSettle: _settle,
          notOnWifiConfirmSettle: _confirm,
        );

        await c.load();

        expect(c.notOnWifi, isTrue);
        expect(c.phase, WifiMonitorPhase.notOnWifi);
        expect(c.details, isNull);
        // The confirmation re-probe is a STREAMING-only cost. An idle screen must
        // not pay it (it is on the open path of every live tool).
        expect(probe.reads, 1,
            reason: 'No live session is at risk, so no confirmation is needed.');

        c.dispose();
        await bridge.close();
      },
    );
  });
}
