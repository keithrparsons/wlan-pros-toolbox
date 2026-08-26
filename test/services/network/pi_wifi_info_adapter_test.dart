// PiWifiInfoAdapter — the WLAN Pi's own radio, behind the shared WifiInfoAdapter
// seam.
//
// WHY THIS EXISTS. Keith's 2026-08-26 click-through found Wi-Fi Information
// gated off on the Pi with "browsers do not allow this, download the WLAN Pros
// Toolbox for macOS, Windows, Android, or iOS". The first half is true of a
// BROWSER. It is the wrong ADVICE on a WLAN Pi, whose radios answer the question
// completely — and it points the user away from the one machine on the network
// that can. These tests pin the mapping that closed that gap.
//
// The load-bearing assertions here are the HONEST-NULL ones. A field that is
// absent must stay absent with its own reason: the driver reports no noise
// floor, or the radio is joined to nothing. Those are different facts, and
// different again from "this platform cannot" — collapsing them is the defect
// this whole path exists to end (GL-005).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart'
    show LocationAuthStatus, WifiInfoUnavailable, WifiInfoUnavailableReason;

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: <String, String>{'content-type': 'application/json'});

PiWifiInfoAdapter _adapter(Object body, {int status = 200}) {
  final MockClient mock = MockClient((http.Request req) async {
    if (req.url.path == '/toolboxapi/wifi') return _json(body, status: status);
    return _json(<String, dynamic>{'detail': 'unexpected route'}, status: 404);
  });
  return PiWifiInfoAdapter(
    client: PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/')),
  );
}

/// A live association, shaped exactly as the Pi returns it.
Map<String, dynamic> _associated({String band = '5 GHz', int freq = 5320}) =>
    <String, dynamic>{
      'interface': 'wlan1',
      'associated': true,
      'reason': null,
      'ssid': 'MUDI',
      'bssid': '2a:59:b2:0c:e9:52',
      'signal_dbm': -28,
      'signal_avg_dbm': -30,
      'noise_dbm': null,
      'snr_db': null,
      'noise_reason': "this radio's driver does not report a noise floor, "
          'so SNR cannot be derived',
      'tx_rate_mbps': 1200.9,
      'rx_rate_mbps': 6.0,
      'phy_mode': band == '6 GHz' ? '802.11ax (Wi-Fi 6E)' : '802.11ax (Wi-Fi 6)',
      'mcs': 11,
      'nss': 2,
      'freq_mhz': freq,
      'channel': band == '6 GHz' ? 37 : 64,
      'width_mhz': 80,
      'band': band,
      'country': 'US',
      'mac': '9c:ef:d5:f6:34:0b',
      'tx_power_dbm': 3.0,
      'mfp': true,
      'beacon_interval': 100,
      'dtim_period': 1,
      'radios': <dynamic>[
        <String, dynamic>{'name': 'wlan0', 'associated': false},
        <String, dynamic>{'name': 'wlan1', 'associated': true},
      ],
    };

void main() {
  group('PiWifiInfoAdapter maps the Pi association into ConnectedAp', () {
    test('a live 5 GHz link carries every field the Pi can measure', () async {
      final ConnectedAp ap = await _adapter(_associated()).fetch();

      expect(ap.ssid, 'MUDI');
      expect(ap.bssid, '2a:59:b2:0c:e9:52');
      expect(ap.txRateMbps, 1200.9);
      expect(ap.rxRateMbps, 6.0);
      expect(ap.channel, 64);
      expect(ap.channelWidthMhz, 80);
      expect(ap.band, '5 GHz');
      expect(ap.standard, '802.11ax (Wi-Fi 6)');
      expect(ap.countryCode, 'US');
      expect(ap.interfaceName, 'wlan1');
      expect(ap.hardwareAddress, '9c:ef:d5:f6:34:0b');
      expect(ap.poweredOn, isTrue);
      expect(ap.rxRateAvailable, isTrue);
      expect(ap.channelWidthAvailable, isTrue);
    });

    test('the AVERAGED signal wins over the instantaneous one', () async {
      // A single -28 sample is noisier than the driver's own average, and the
      // sparklines read better from the average. Both are real; the average is
      // the more honest single number to show.
      final ConnectedAp ap = await _adapter(_associated()).fetch();
      expect(ap.rssiDbm, -30);
    });

    test('802.11ax on 6 GHz is Wi-Fi 6E, not Wi-Fi 6', () async {
      // Same PHY, different generation name. Calling a 6 GHz link "Wi-Fi 6" in
      // a Wi-Fi professional's tool is the kind of wrong that gets noticed, so
      // the Pi derives the label from the band it measured.
      final ConnectedAp ap =
          await _adapter(_associated(band: '6 GHz', freq: 6135)).fetch();
      expect(ap.standard, '802.11ax (Wi-Fi 6E)');
      expect(ap.band, '6 GHz');
    });

    test('HONEST NULL: noise and SNR stay absent, never fabricated', () async {
      // iw survey dump on the MT7921 driver reports busy/active times but no
      // noise floor. A fabricated floor would make SNR look measured when it
      // was invented.
      final ConnectedAp ap = await _adapter(_associated()).fetch();
      expect(ap.noiseDbm, isNull);
      expect(ap.snrDb, isNull);
      expect(ap.snrDerived, isFalse);
    });

    test('the band is MEASURED, not derived from a channel number', () async {
      final ConnectedAp ap = await _adapter(_associated()).fetch();
      expect(ap.bandDerived, isFalse);
    });

    test('security is reported ABSENT rather than half-answered', () async {
      // The association carries MFP but not the full security suite, and half a
      // security answer is worse than an honest absence.
      final ConnectedAp ap = await _adapter(_associated()).fetch();
      expect(ap.securityAvailable, isFalse);
      expect(ap.securityType, isNull);
    });
  });

  group('PiWifiInfoAdapter distinguishes its kinds of absence', () {
    test(
        'AN UNASSOCIATED RADIO IS AN ANSWER, NOT AN ERROR: it returns a '
        'ConnectedAp with no network rather than throwing', () async {
      // On a two-radio Pi one radio is deliberately free for scanning or
      // capture. Throwing here would render that deliberate state as a failure.
      final PiWifiInfoAdapter a = _adapter(<String, dynamic>{
        'interface': 'wlan0',
        'associated': false,
        'reason': 'this radio is not associated to a network '
            '(it is free for scanning or capture)',
        'mac': '9c:ef:d5:f6:3b:be',
        'country': 'US',
        'radios': <dynamic>[],
      });

      final ConnectedAp ap = await a.fetch();
      expect(ap.ssid, isNull);
      expect(ap.bssid, isNull);
      expect(ap.poweredOn, isTrue, reason: 'the radio is up, just unjoined');
      expect(ap.hardwareAddress, '9c:ef:d5:f6:3b:be');
      // The Pi's own reason survives for a caller that wants to show it.
      expect(a.lastLink?.reason, contains('free for scanning or capture'));
    });

    test('a backend failure IS an error, and is typed as one', () async {
      final PiWifiInfoAdapter a =
          _adapter(<String, dynamic>{'detail': 'boom'}, status: 500);
      await expectLater(
        a.fetch(),
        throwsA(isA<WifiInfoUnavailable>().having(
          (WifiInfoUnavailable e) => e.reason,
          'reason',
          WifiInfoUnavailableReason.channelError,
        )),
      );
    });
  });

  group('PiWifiInfoAdapter has no permission gate, truthfully', () {
    test('nothing on the Pi hides the SSID behind a user grant', () async {
      final PiWifiInfoAdapter a = _adapter(_associated());
      expect(a.gatesNameBehindPermission, isFalse);
      expect(await a.requestNamePermission(), isTrue);
      expect(await a.currentNameAuthorization(), isTrue);
      expect(await a.nameAuthorizationStatus(), LocationAuthStatus.authorized);
      // There is no settings pane to deep-link to, so this reports false rather
      // than pretending it opened something.
      expect(await a.openNamePermissionSettings(), isFalse);
    });

    test('the platform label names the Pi, so absent fields read truthfully',
        () async {
      // The per-field copy becomes "not exposed by the WLAN Pi" — specific and
      // true, rather than the "not available on this platform" that sent users
      // to a different product.
      expect(_adapter(_associated()).platformLabel, 'the WLAN Pi');
    });
  });
}
