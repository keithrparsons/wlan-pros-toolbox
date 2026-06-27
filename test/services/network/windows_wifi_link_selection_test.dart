// Pure connected-link-selection tests for the Windows Native Wifi FFI helpers
// (windows_wifi_ffi.dart). [selectConnectedLink] and [bssidRadioPrefix] are pure
// Dart over a plain [WifiBssCandidate] value object — they touch no win32 symbol
// — so they run on macOS CI even though the FFI body that reads wlanapi.dll
// cannot. Importing the module here never triggers the lazy wlanapi.dll load,
// since these tests make no FFI call.
//
// These lock the BSSID-matching precedence (exact → same AP radio → same SSID)
// that lets the connected-AP RSSI / channel / band resolve on a Wi-Fi 7 MLO /
// Multiple-BSSID AP, where the current-connection BSSID is the AP MLD address
// that never beacons as its own BSS. The fixture mirrors Keith's hardware-
// verified Wi-Fi 7 link: connected BSSID 94:2a:6f:a0:a5:5a is ABSENT from the
// BSS list; its same-radio per-link siblings ...5b (5 GHz ch44) and ...5d
// (6 GHz ch197) are present, and the operating-channel query disambiguates which
// to report.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/windows_wifi_ffi.dart';

/// The connected AP MLD address from the device fixture (never beacons).
const String _connMld = '94:2a:6f:a0:a5:5a';

/// The 5 GHz affiliated link of that radio (channel 44).
const WifiBssCandidate _link5b = WifiBssCandidate(
  bssid: '94:2a:6f:a0:a5:5b',
  ssid: 'KeithNet',
  rssiDbm: -69,
  centerFreqKhz: 5220000, // 5 GHz, ch 44
);

/// The 6 GHz affiliated link of that radio (channel 197) — the strongest.
const WifiBssCandidate _link5d = WifiBssCandidate(
  bssid: '94:2a:6f:a0:a5:5d',
  ssid: 'KeithNet',
  rssiDbm: -47,
  centerFreqKhz: 6935000, // 6 GHz, ch 197
);

/// A non-transmitted MBSSID sibling on the same radio (different SSID, weaker).
const WifiBssCandidate _siblingNonTx = WifiBssCandidate(
  bssid: '9a:2a:6f:a0:a5:5b',
  ssid: 'KeithGuest',
  rssiDbm: -72,
  centerFreqKhz: 5220000,
);

/// An unrelated neighbour AP — different radio prefix and SSID.
const WifiBssCandidate _otherAp = WifiBssCandidate(
  bssid: 'a4:83:e7:11:22:33',
  ssid: 'Neighbour',
  rssiDbm: -55,
  centerFreqKhz: 2437000, // 2.4 GHz, ch 6
);

void main() {
  group('bssidRadioPrefix', () {
    test('yields the first 5 octets of a colon-hex BSSID', () {
      expect(bssidRadioPrefix('94:2a:6f:a0:a5:5a'), '94:2a:6f:a0:a5');
      expect(bssidRadioPrefix('a4:83:e7:11:22:33'), 'a4:83:e7:11:22');
    });

    test('is case-insensitive (uppercase and lowercase share one prefix)', () {
      expect(
        bssidRadioPrefix('94:2A:6F:A0:A5:5A'),
        bssidRadioPrefix('94:2a:6f:a0:a5:5a'),
      );
      expect(bssidRadioPrefix('94:2A:6F:A0:A5:5A'), '94:2a:6f:a0:a5');
    });

    test('an unexpectedly short BSSID is returned lowercased, not crashed', () {
      expect(bssidRadioPrefix('94:2A:6F'), '94:2a:6f');
    });
  });

  group('selectConnectedLink — exact BSSID match', () {
    test('exact match wins even when same-radio / same-SSID candidates exist',
        () {
      // The connected BSSID is itself present; it must win over the affiliated
      // links and any operating-channel hint that points elsewhere.
      const WifiBssCandidate exact = WifiBssCandidate(
        bssid: _connMld,
        ssid: 'KeithNet',
        rssiDbm: -60,
        centerFreqKhz: 5180000, // ch 36
      );
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, exact, _link5d, _siblingNonTx],
        connBssid: _connMld,
        connSsid: 'KeithNet',
        operatingChannel: 197, // would point at _link5d if it fell through
      );
      expect(result, same(exact));
    });

    test('exact match is case-insensitive against the connection BSSID', () {
      const WifiBssCandidate exact = WifiBssCandidate(
        bssid: '94:2a:6f:a0:a5:5a',
        ssid: 'KeithNet',
        rssiDbm: -60,
        centerFreqKhz: 5180000,
      );
      final result = selectConnectedLink(
        <WifiBssCandidate>[exact],
        connBssid: '94:2A:6F:A0:A5:5A', // uppercase from the connection attrs
        connSsid: 'KeithNet',
        operatingChannel: null,
      );
      expect(result, same(exact));
    });
  });

  group('selectConnectedLink — MLO same-radio fallback', () {
    test('operatingChannel 197 selects the 6 GHz affiliated link (...5d, -47)',
        () {
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, _link5d, _siblingNonTx, _otherAp],
        connBssid: _connMld, // absent from the list (AP MLD address)
        connSsid: 'KeithNet',
        operatingChannel: 197,
      );
      expect(result, same(_link5d));
      expect(result!.rssiDbm, -47);
      expect(result.centerFreqKhz, 6935000);
    });

    test('operatingChannel 44 selects the 5 GHz affiliated link (...5b, -69)',
        () {
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, _link5d, _siblingNonTx, _otherAp],
        connBssid: _connMld,
        connSsid: 'KeithNet',
        operatingChannel: 44,
      );
      expect(result, same(_link5b));
      expect(result!.rssiDbm, -69);
      expect(result.centerFreqKhz, 5220000);
    });

    test('operatingChannel null falls back to the strongest same-radio link',
        () {
      // No channel hint → least-negative dBm wins: ...5d at -47 over ...5b/-69
      // and the non-transmitted sibling at -72.
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, _link5d, _siblingNonTx, _otherAp],
        connBssid: _connMld,
        connSsid: 'KeithNet',
        operatingChannel: null,
      );
      expect(result, same(_link5d));
      expect(result!.rssiDbm, -47);
    });
  });

  group('selectConnectedLink — same-SSID last resort', () {
    test('no same-radio match falls back to the strongest same-SSID link', () {
      // connBssid is on a radio with NO candidates; selection must drop to the
      // SSID tier and pick the strongest matching-SSID entry (_link5d, -47).
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, _link5d, _otherAp],
        connBssid: '00:11:22:33:44:55', // unrelated radio, absent
        connSsid: 'KeithNet',
        operatingChannel: null,
      );
      expect(result, same(_link5d));
    });

    test('same-SSID tier honours the operating channel when known', () {
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, _link5d, _otherAp],
        connBssid: '00:11:22:33:44:55',
        connSsid: 'KeithNet',
        operatingChannel: 44, // → the 5 GHz same-SSID link
      );
      expect(result, same(_link5b));
    });
  });

  group('selectConnectedLink — no match', () {
    test('nothing matches BSSID radio or SSID → null', () {
      final result = selectConnectedLink(
        <WifiBssCandidate>[_otherAp],
        connBssid: '00:11:22:33:44:55',
        connSsid: 'KeithNet', // no candidate carries this SSID
        operatingChannel: 36,
      );
      expect(result, isNull);
    });

    test('an empty candidate list → null', () {
      final result = selectConnectedLink(
        const <WifiBssCandidate>[],
        connBssid: _connMld,
        connSsid: 'KeithNet',
        operatingChannel: 197,
      );
      expect(result, isNull);
    });

    test('null connBssid and null SSID → null (nothing to match on)', () {
      final result = selectConnectedLink(
        <WifiBssCandidate>[_link5b, _link5d],
        connBssid: null,
        connSsid: null,
        operatingChannel: 197,
      );
      expect(result, isNull);
    });
  });
}
