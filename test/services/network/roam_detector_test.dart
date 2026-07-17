// RoamDetector — pure unit tests (Feature 2, Felix 2026-06-13). No I/O, no
// timers: feed ConnectedAp samples, assert the recorded roam events.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/roam_detector.dart';

ConnectedAp ap({
  String? ssid = 'HomeNet',
  String? bssid,
  int? rssi,
  int? snr,
  int? channel,
  String? band,
  bool bandDerived = false,
}) =>
    ConnectedAp(
      ssid: ssid,
      bssid: bssid,
      rssiDbm: rssi,
      snrDb: snr,
      channel: channel,
      band: band,
      bandDerived: bandDerived,
    );

void main() {
  group('RoamDetector', () {
    test('first known BSSID seeds the anchor and records no roam', () {
      final RoamDetector d = RoamDetector();
      expect(d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa')), isNull);
      expect(d.isEmpty, isTrue);
      expect(d.count, 0);
    });

    test('unchanged BSSID records no roam', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa'));
      expect(d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa')), isNull);
      expect(d.count, 0);
    });

    test('BSSID change on the same SSID records a roam', () {
      final RoamDetector d = RoamDetector(now: () => DateTime(2026, 6, 13, 14, 0));
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa', rssi: -55, snr: 35));
      final RoamEvent? e =
          d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb', rssi: -60, snr: 30));
      expect(e, isNotNull);
      expect(e!.fromBssid, 'aa:aa:aa:aa:aa:aa');
      expect(e.toBssid, 'bb:bb:bb:bb:bb:bb');
      expect(e.ssid, 'HomeNet');
      expect(e.rssiDbm, -60);
      expect(e.snrDb, 30);
      expect(e.at, DateTime(2026, 6, 13, 14, 0));
      expect(d.count, 1);
      expect(d.latest, e);
    });

    test('records a roam even when RSSI/SNR are identical', () {
      // A roam can land at the same signal — the detector must not depend on an
      // RF delta (that is the sparkline-guard trap this fix closes).
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa', rssi: -55, snr: 35));
      final RoamEvent? e =
          d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb', rssi: -55, snr: 35));
      expect(e, isNotNull);
      expect(d.count, 1);
    });

    test('SSID change is a network switch, NOT a roam', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(ssid: 'HomeNet', bssid: 'aa:aa:aa:aa:aa:aa'));
      final RoamEvent? e =
          d.observe(ap(ssid: 'OtherNet', bssid: 'bb:bb:bb:bb:bb:bb'));
      expect(e, isNull);
      expect(d.count, 0);
      // The anchor re-seeds to the new network: a subsequent same-SSID BSSID
      // change on OtherNet IS a roam.
      final RoamEvent? e2 =
          d.observe(ap(ssid: 'OtherNet', bssid: 'cc:cc:cc:cc:cc:cc'));
      expect(e2, isNotNull);
      expect(e2!.fromBssid, 'bb:bb:bb:bb:bb:bb');
      expect(e2.toBssid, 'cc:cc:cc:cc:cc:cc');
      expect(d.count, 1);
    });

    test('null/blank BSSID breaks the chain without fabricating a roam', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa'));
      // A momentarily unreadable sample: no event, anchor preserved.
      expect(d.observe(ap(bssid: null)), isNull);
      expect(d.observe(ap(bssid: '   ')), isNull);
      expect(d.count, 0);
      // The anchor was preserved: the SAME BSSID returning is not a roam...
      expect(d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa')), isNull);
      expect(d.count, 0);
      // ...but a genuine change still registers.
      expect(d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb')), isNotNull);
      expect(d.count, 1);
    });

    test('records multiple roams in order, newest last', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa'));
      d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb'));
      d.observe(ap(bssid: 'cc:cc:cc:cc:cc:cc'));
      expect(d.count, 2);
      expect(d.events.first.toBssid, 'bb:bb:bb:bb:bb:bb');
      expect(d.events.last.toBssid, 'cc:cc:cc:cc:cc:cc');
    });

    test('reset clears events and the anchor', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa'));
      d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb'));
      expect(d.count, 1);
      d.reset();
      expect(d.isEmpty, isTrue);
      // After reset the next BSSID is a fresh anchor (no roam against the old one).
      expect(d.observe(ap(bssid: 'cc:cc:cc:cc:cc:cc')), isNull);
      expect(d.count, 0);
    });

    test('unknown SSID on both sides treats a BSSID change as a roam', () {
      // macOS/iOS supply the SSID in practice; when it is absent the BSSID
      // change is the stronger signal, so we record rather than drop a real roam.
      final RoamDetector d = RoamDetector();
      d.observe(ap(ssid: null, bssid: 'aa:aa:aa:aa:aa:aa'));
      final RoamEvent? e = d.observe(ap(ssid: null, bssid: 'bb:bb:bb:bb:bb:bb'));
      expect(e, isNotNull);
      expect(e!.ssid, isNull);
      expect(d.count, 1);
    });

    test(
        'roam carries the from/to CHANNEL and BAND from consecutive samples '
        '(band+channel were being dropped)', () {
      // The prior AP anchors from* (channel 44 / 5 GHz); the current sample
      // supplies to* (channel 37 / 6 GHz). Channel is exact on every platform;
      // band on iOS is derived from the channel and must carry its marker.
      final RoamDetector d = RoamDetector();
      d.observe(ap(
        bssid: 'aa:aa:aa:aa:aa:aa',
        channel: 44,
        band: '5 GHz',
        bandDerived: true,
      ));
      final RoamEvent? e = d.observe(ap(
        bssid: 'bb:bb:bb:bb:bb:bb',
        channel: 37,
        band: '6 GHz',
        bandDerived: true,
      ));
      expect(e, isNotNull);
      expect(e!.fromChannel, 44);
      expect(e.toChannel, 37);
      expect(e.fromBand, '5 GHz');
      expect(e.toBand, '6 GHz');
      expect(e.fromBandDerived, isTrue);
      expect(e.toBandDerived, isTrue);
    });

    test('a directly-reported band (macOS/Android) is not marked derived', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa', channel: 44, band: '5 GHz'));
      final RoamEvent? e =
          d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb', channel: 100, band: '5 GHz'));
      expect(e, isNotNull);
      expect(e!.fromBandDerived, isFalse);
      expect(e.toBandDerived, isFalse);
    });

    test('a channel that resolves late on the same AP anchors the from channel',
        () {
      // First sample carries the BSSID but no channel yet; a later same-AP
      // sample resolves it. The roam's from-channel must be the resolved value,
      // not null.
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa', channel: null, band: null));
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa', channel: 44, band: '5 GHz'));
      final RoamEvent? e =
          d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb', channel: 149, band: '5 GHz'));
      expect(e, isNotNull);
      expect(e!.fromChannel, 44);
      expect(e.fromBand, '5 GHz');
      expect(e.toChannel, 149);
    });

    test('honest-null when a sample omitted the channel/band', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa'));
      final RoamEvent? e = d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb'));
      expect(e, isNotNull);
      expect(e!.fromChannel, isNull);
      expect(e.toChannel, isNull);
      expect(e.fromBand, isNull);
      expect(e.toBand, isNull);
    });

    test('events view is unmodifiable', () {
      final RoamDetector d = RoamDetector();
      d.observe(ap(bssid: 'aa:aa:aa:aa:aa:aa'));
      d.observe(ap(bssid: 'bb:bb:bb:bb:bb:bb'));
      expect(
        () => d.events.add(d.events.first),
        throwsUnsupportedError,
      );
    });
  });
}
