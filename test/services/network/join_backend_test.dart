// The backend abstraction exists so the screen does not have to know which
// radio it is driving. These tests pin the two things that would hurt if they
// drifted: the Pi path must behave exactly as it did before it was wrapped, and
// a backend that cannot supply the Pi's link detail must supply NOTHING rather
// than zeroes.
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/join_backend.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

/// Minimal Pi double. Returns whatever the test hands it.
class _Pi implements PiBackendClient {
  _Pi({this.connectResult, this.throwOnConnect});
  final PiJoinResult? connectResult;
  final Object? throwOnConnect;

  String? lastSsid;
  PiJoinSecurity? lastSecurity;
  String? lastPsk;
  String? lastInterface;
  String? lastScanInterface;

  @override
  Future<List<PiScanInterface>> scanInterfaces() async =>
      const <PiScanInterface>[
        PiScanInterface(name: 'wlan0', driver: 'mt7921u'),
      ];

  @override
  Future<List<PiScanNet>> scan({String interface = 'wlan0'}) async {
    lastScanInterface = interface;
    return const <PiScanNet>[
      PiScanNet(
        ssid: 'Lab',
        bssid: 'aa:bb:cc:dd:ee:ff',
        signalDbm: -40,
        freqMhz: 5180,
        keyMgmt: 'wpa-psk',
      ),
    ];
  }

  @override
  Future<PiJoinResult> wifiConnect({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  }) async {
    lastSsid = ssid;
    lastSecurity = security;
    lastPsk = psk;
    lastInterface = interface;
    if (throwOnConnect != null) throw throwOnConnect!;
    return connectResult!;
  }

  @override
  Future<PiJoinResult> wifiDisconnect({String? interface}) async {
    lastInterface = interface;
    return connectResult!;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PiJoinResult _result({required bool associated, String? reason, String? ssid}) {
  return PiJoinResult(
    link: PiWifiLink.fromJson(<String, dynamic>{
      'interface': 'wlan0',
      'associated': associated,
      if (reason != null) 'reason': reason,
      if (ssid != null) 'ssid': ssid,
    }),
    requestedSsid: ssid,
    secureTransport: false,
  );
}

void main() {
  group('PiJoinBackend forwards without changing behaviour', () {
    test('the scan interface the caller asked for is the one used', () async {
      final _Pi pi = _Pi();
      await PiJoinBackend(pi).scan(interface: 'wlan1');
      expect(pi.lastScanInterface, 'wlan1');
    });

    test(
      'a null interface still lands on wlan0, as the screen always did',
      () async {
        final _Pi pi = _Pi();
        await PiJoinBackend(pi).scan();
        expect(pi.lastScanInterface, 'wlan0');
      },
    );

    test('every join argument reaches the client untouched', () async {
      final _Pi pi = _Pi(connectResult: _result(associated: true, ssid: 'Lab'));
      await PiJoinBackend(pi).join(
        ssid: 'Lab',
        security: PiJoinSecurity.wpa2Psk,
        psk: 'correcthorse',
        interface: 'wlan1',
      );
      expect(pi.lastSsid, 'Lab');
      expect(pi.lastSecurity, PiJoinSecurity.wpa2Psk);
      expect(pi.lastPsk, 'correcthorse');
      expect(pi.lastInterface, 'wlan1');
    });

    test('the Pi keeps its rich record, so the screen loses nothing', () async {
      final _Pi pi = _Pi(connectResult: _result(associated: true, ssid: 'Lab'));
      final JoinOutcome o = await PiJoinBackend(
        pi,
      ).join(ssid: 'Lab', security: PiJoinSecurity.open);
      expect(o.connected, isTrue);
      expect(
        o.detail,
        isNotNull,
        reason: 'the Pi path must still carry its full link record',
      );
      expect(o.ssid, 'Lab');
    });

    test('a failed Pi join carries the PI OWN words, not ours', () async {
      final _Pi pi = _Pi(
        connectResult: _result(
          associated: false,
          reason: 'authentication failed',
          ssid: 'Lab',
        ),
      );
      final JoinOutcome o = await PiJoinBackend(
        pi,
      ).join(ssid: 'Lab', security: PiJoinSecurity.wpa2Psk, psk: 'x');
      expect(o.connected, isFalse);
      expect(o.failureNote, 'authentication failed');
    });

    test('a successful join carries NO failure note', () async {
      final _Pi pi = _Pi(connectResult: _result(associated: true, ssid: 'Lab'));
      final JoinOutcome o = await PiJoinBackend(
        pi,
      ).join(ssid: 'Lab', security: PiJoinSecurity.open);
      expect(o.failureNote, isNull);
    });

    test('the Pi does NOT claim to join this device', () {
      expect(PiJoinBackend(_Pi()).joinsThisDevice, isFalse);
    });
  });

  group('JoinOutcome refuses to invent what a backend cannot know', () {
    test('detail defaults to null rather than an empty record', () {
      const JoinOutcome o = JoinOutcome(connected: true, ssid: 'Lab');
      expect(
        o.detail,
        isNull,
        reason:
            'a native join has no RSSI, noise, MCS or NSS to report, and '
            'must supply nothing rather than zeroes',
      );
      expect(o.failureNote, isNull);
    });

    test('connected is the POLLED outcome, and false is representable '
        'alongside a named SSID', () {
      const JoinOutcome o = JoinOutcome(
        connected: false,
        ssid: 'Lab',
        failureNote: 'never associated',
      );
      expect(o.connected, isFalse);
      expect(o.ssid, 'Lab');
      expect(o.failureNote, 'never associated');
    });
  });
}
