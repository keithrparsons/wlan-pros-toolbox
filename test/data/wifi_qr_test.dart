// Tests for the Wi-Fi "scan to join" QR payload builder (lib/data/wifi_qr.dart).
//
// The escaping rule is the part that silently breaks scanning when wrong, so it
// is asserted directly: the five delimiter characters  \ ; , : "  must be
// backslash-escaped inside SSID/password values, and all-hex / space-padded
// values must be double-quoted so a scanner reads them verbatim. Pure string
// math — no widget pump, no platform.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/wifi_qr.dart';

void main() {
  group('wifiAuthToken — auth mapping', () {
    test('WPA family → WPA', () {
      expect(wifiAuthToken(WifiAuthType.wpa), 'WPA');
    });
    test('WEP → WEP', () {
      expect(wifiAuthToken(WifiAuthType.wep), 'WEP');
    });
    test('None → nopass', () {
      expect(wifiAuthToken(WifiAuthType.none), 'nopass');
    });
  });

  group('escapeWifiValue — special-character escaping', () {
    test('plain value is unchanged', () {
      expect(escapeWifiValue('WLAN-Pros-Guest'), 'WLAN-Pros-Guest');
    });

    test('each delimiter is backslash-escaped', () {
      expect(escapeWifiValue('a;b'), r'a\;b');
      expect(escapeWifiValue('a,b'), r'a\,b');
      expect(escapeWifiValue('a:b'), r'a\:b');
      expect(escapeWifiValue('a"b'), r'a\"b');
      expect(escapeWifiValue(r'a\b'), r'a\\b');
    });

    test('a value with several specials escapes them all', () {
      // Worked example: SSID  Cafe; "Free":,\  →  Cafe\; \"Free\"\:\,\\
      expect(
        escapeWifiValue(r'Cafe; "Free":,\'),
        r'Cafe\; \"Free\"\:\,\\',
      );
    });

    test('backslash is escaped before the char it precedes (no double-count)',
        () {
      // A backslash already in the value becomes \\, and a following ; is its
      // own \; — they do not merge.
      expect(escapeWifiValue(r'\;'), r'\\\;');
    });

    test('all-hex value is double-quoted so it is read verbatim', () {
      expect(escapeWifiValue('deadbeef'), '"deadbeef"');
      expect(escapeWifiValue('0A1B2C'), '"0A1B2C"');
    });

    test('mixed alphanumeric (not all hex) is NOT quoted', () {
      // Contains g/h/z — not hex digits — so no quote wrap.
      expect(escapeWifiValue('cafe123z'), 'cafe123z');
    });

    test('leading or trailing space forces a quote wrap', () {
      expect(escapeWifiValue(' lobby'), '" lobby"');
      expect(escapeWifiValue('lobby '), '"lobby "');
    });

    test('empty value is neither escaped nor quoted', () {
      expect(escapeWifiValue(''), '');
    });
  });

  group('buildWifiQrPayload — full WIFI: string', () {
    test('WPA network with password and visible SSID', () {
      expect(
        buildWifiQrPayload(
          ssid: 'WLAN-Pros-Guest',
          auth: WifiAuthType.wpa,
          password: 'letmein123',
          hidden: false,
        ),
        'WIFI:T:WPA;S:WLAN-Pros-Guest;P:letmein123;H:false;;',
      );
    });

    test('WEP network maps auth to WEP', () {
      expect(
        buildWifiQrPayload(
          ssid: 'OldNet',
          auth: WifiAuthType.wep,
          password: 'abcde',
          hidden: false,
        ),
        // "abcde" is all-hex → quoted verbatim.
        'WIFI:T:WEP;S:OldNet;P:"abcde";H:false;;',
      );
    });

    test('open network: nopass and NO P: field at all', () {
      final String s = buildWifiQrPayload(
        ssid: 'PublicWiFi',
        auth: WifiAuthType.none,
        password: 'ignored',
        hidden: false,
      );
      expect(s, 'WIFI:T:nopass;S:PublicWiFi;H:false;;');
      expect(s.contains('P:'), isFalse);
    });

    test('hidden network emits H:true', () {
      expect(
        buildWifiQrPayload(
          ssid: 'StealthNet',
          auth: WifiAuthType.wpa,
          password: 'secretpass',
          hidden: true,
        ),
        'WIFI:T:WPA;S:StealthNet;P:secretpass;H:true;;',
      );
    });

    test('special characters in SSID and password are escaped in the payload',
        () {
      expect(
        buildWifiQrPayload(
          ssid: 'Cafe; Free',
          auth: WifiAuthType.wpa,
          password: r'p@ss;word\1',
          hidden: false,
        ),
        r'WIFI:T:WPA;S:Cafe\; Free;P:p@ss\;word\\1;H:false;;',
      );
    });

    test('payload always ends with the ;; record terminator', () {
      final String s = buildWifiQrPayload(
        ssid: 'Net',
        auth: WifiAuthType.wpa,
        password: 'password1',
      );
      expect(s.endsWith(';;'), isTrue);
    });
  });
}
