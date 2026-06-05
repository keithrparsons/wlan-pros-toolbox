// Unit tests for the typed models shaped from the public wlanpi-core schemas.
// These confirm the source-accurate parse for auth/system/network_info, and the
// defensive coercion that keeps a slightly-different OS build from crashing the
// parse. The profiler capability parse keys are PLACEHOLDER (confirmed Monday) —
// the test asserts the defensive behavior, not specific real device keys.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/wlanpi/wlanpi_models.dart';

void main() {
  group('WlanPiToken (schemas/auth/auth.py)', () {
    test('parses access_token + token_type', () {
      final WlanPiToken t = WlanPiToken.fromJson(<String, dynamic>{
        'access_token': 'abc.def.ghi',
        'token_type': 'bearer',
      });
      expect(t.accessToken, 'abc.def.ghi');
      expect(t.isBearer, isTrue);
    });

    test('isBearer is case-insensitive', () {
      final WlanPiToken t = WlanPiToken.fromJson(<String, dynamic>{
        'access_token': 'x',
        'token_type': 'Bearer',
      });
      expect(t.isBearer, isTrue);
    });
  });

  group('WlanPiTokenRequest', () {
    test('serializes device_id', () {
      expect(
        const WlanPiTokenRequest(deviceId: 'client-1').toJson(),
        <String, dynamic>{'device_id': 'client-1'},
      );
    });
  });

  group('WlanPiDeviceInfo (schemas/system/system.py)', () {
    test('parses all five fields', () {
      final WlanPiDeviceInfo d = WlanPiDeviceInfo.fromJson(<String, dynamic>{
        'model': 'WLAN Pi M4+',
        'name': 'wlanpi-cda',
        'hostname': 'wlanpi-cda.local',
        'software_version': 'WLAN Pi OS 3.2.2',
        'mode': 'classic',
      });
      expect(d.model, 'WLAN Pi M4+');
      expect(d.hostname, 'wlanpi-cda.local');
      expect(d.softwareVersion, 'WLAN Pi OS 3.2.2');
      expect(d.mode, 'classic');
    });

    test('missing fields coerce to empty string, never throw', () {
      final WlanPiDeviceInfo d =
          WlanPiDeviceInfo.fromJson(<String, dynamic>{'model': 'X'});
      expect(d.model, 'X');
      expect(d.hostname, '');
    });
  });

  group('WlanPiDeviceStats (schemas/system/system.py)', () {
    test('parses all six fields', () {
      final WlanPiDeviceStats s = WlanPiDeviceStats.fromJson(<String, dynamic>{
        'ip': '192.168.1.42',
        'cpu': '7%',
        'ram': '512 MB',
        'disk': '6 GB',
        'cpu_temp': '47C',
        'uptime': '3d',
      });
      expect(s.ip, '192.168.1.42');
      expect(s.cpuTemp, '47C');
      expect(s.uptime, '3d');
    });
  });

  group('WlanPiNetworkInfo (schemas/network_info/network_info.py)', () {
    test('holds the seven opaque dict fields', () {
      final WlanPiNetworkInfo n = WlanPiNetworkInfo.fromJson(<String, dynamic>{
        'interfaces': <String, dynamic>{'wlan0': <String, dynamic>{}},
        'wlan_interfaces': <String, dynamic>{},
        'eth0_ipconfig_info': <String, dynamic>{},
        'vlan_info': <String, dynamic>{},
        'lldp_neighbour_info': <String, dynamic>{},
        'cdp_neighbour_info': <String, dynamic>{},
        'public_ip': <String, dynamic>{'ip': '1.2.3.4'},
      });
      expect(n.interfaces.containsKey('wlan0'), isTrue);
      expect(n.publicIp['ip'], '1.2.3.4');
    });

    test('non-map fields coerce to empty map, never throw', () {
      final WlanPiNetworkInfo n =
          WlanPiNetworkInfo.fromJson(<String, dynamic>{'interfaces': 'oops'});
      expect(n.interfaces, isEmpty);
      expect(n.vlanInfo, isEmpty);
    });
  });

  group('ProfilerClientCapabilities (PLACEHOLDER keys — confirmed Monday)', () {
    test('parses the candidate placeholder keys defensively', () {
      final ProfilerClientCapabilities c =
          ProfilerClientCapabilities.fromJson(<String, dynamic>{
        'mac': 'aa:bb:cc:dd:ee:ff',
        'channel_width': 160,
        'spatial_streams': 2,
        'max_mcs': 11,
        'bands': <String>['2.4 GHz', '5 GHz'],
        'dot11k': true,
        'dot11r': false,
        'wpa3': 'true',
      });
      expect(c.clientMac, 'aa:bb:cc:dd:ee:ff');
      expect(c.maxChannelWidthMhz, 160);
      expect(c.maxSpatialStreams, 2);
      expect(c.supports11k, isTrue);
      expect(c.supports11r, isFalse);
      expect(c.wpa3Sae, isTrue); // "true" string coerced
      expect(c.bands, <String>['2.4 GHz', '5 GHz']);
    });

    test('unknown fields land in rawCapabilities, nothing lost', () {
      final ProfilerClientCapabilities c =
          ProfilerClientCapabilities.fromJson(<String, dynamic>{
        'mac': 'x',
        'some_future_field': 42,
      });
      expect(c.rawCapabilities['some_future_field'], 42);
      expect(c.maxChannelWidthMhz, isNull); // absent → null, not zero
    });
  });
}
