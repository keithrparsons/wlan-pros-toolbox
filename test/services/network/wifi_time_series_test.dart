// Wi-Fi Live rolling-window capture — unit tests (TICKET-01).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_time_series.dart';

ConnectedAp _ap({int? rssi, int? noise, int rxRate = 780, int txRate = 866}) {
  return ConnectedAp.fromWifiDetails(
    WiFiDetails(rssi: rssi, noise: noise, rxRate: rxRate, txRate: txRate),
  );
}

void main() {
  test('starts empty', () {
    final WifiTimeSeries s = WifiTimeSeries();
    expect(s.isEmpty, isTrue);
    expect(s.length, 0);
  });

  test('appends samples oldest -> newest', () {
    final WifiTimeSeries s = WifiTimeSeries();
    s.add(_ap(rssi: -50, noise: -95)); // snr derived = 45
    s.add(_ap(rssi: -55, noise: -95)); // snr = 40
    expect(s.length, 2);
    expect(s.rssi, <double?>[-50, -55]);
    expect(s.snr, <double?>[45, 40]);
    expect(s.txRate, <double?>[866, 866]);
    expect(s.rxRate, <double?>[780, 780]);
  });

  test('a missing field is stored as null (a gap), never fabricated 0', () {
    final WifiTimeSeries s = WifiTimeSeries();
    // No noise -> snr cannot be computed -> null, not 0.
    s.add(_ap(rssi: -50));
    expect(s.snr, <double?>[null]);
    expect(s.rssi, <double?>[-50]);
  });

  test('evicts the oldest sample at capacity (ring behavior)', () {
    final WifiTimeSeries s = WifiTimeSeries(capacity: 3);
    s.add(_ap(rssi: -50, noise: -95));
    s.add(_ap(rssi: -51, noise: -95));
    s.add(_ap(rssi: -52, noise: -95));
    s.add(_ap(rssi: -53, noise: -95)); // evicts -50
    expect(s.length, 3);
    expect(s.rssi, <double?>[-51, -52, -53]);
  });

  test('clear empties every window', () {
    final WifiTimeSeries s = WifiTimeSeries();
    s.add(_ap(rssi: -50, noise: -95));
    s.clear();
    expect(s.isEmpty, isTrue);
    expect(s.rssi, isEmpty);
    expect(s.snr, isEmpty);
    expect(s.txRate, isEmpty);
    expect(s.rxRate, isEmpty);
  });
}
