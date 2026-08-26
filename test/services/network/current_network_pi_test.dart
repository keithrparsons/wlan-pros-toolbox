// CurrentNetwork.pi — the Pi-backed prefill reader.
//
// WHY THIS EXISTS: on the Pi-hosted web build the default reader calls
// network_info_plus, which has no Wi-Fi API in a browser. It returns nothing,
// so Ping Sweep and Port Scan opened with an EMPTY subnet field and asked the
// user to type back the very network the tool was running on (Keith, 2026-08-26:
// "portscan and ping sweep worked, but did not start pre-populated with the
// correct IP address"). The Pi knows its own addressing, so it answers instead.
//
// The honest-NONE contract is the load-bearing part: when nothing qualifies, the
// reader returns all-null and no subnet is invented.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: <String, String>{'content-type': 'application/json'});

/// `/toolboxapi/interfaces` is shaped like `ip -j addr`, keyed by interface.
List<dynamic> _iface(String local, int prefix, {String family = 'inet'}) =>
    <dynamic>[
      <String, dynamic>{
        'addr_info': <dynamic>[
          <String, dynamic>{
            'local': local,
            'prefixlen': prefix,
            'family': family,
          },
        ],
      },
    ];

CurrentNetwork _net(Object interfacesBody, {int status = 200}) {
  final MockClient mock = MockClient((http.Request req) async {
    if (req.url.path == '/toolboxapi/interfaces') {
      return _json(interfacesBody, status: status);
    }
    return _json(<String, dynamic>{'error': 'unexpected route'}, status: 404);
  });
  return CurrentNetwork.pi(
    client: PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/')),
  );
}

void main() {
  group('CurrentNetwork.pi derives the subnet from the Pi', () {
    test('a single wired interface yields its true CIDR at its true prefix',
        () async {
      final NetworkSuggestion s = await _net(<String, dynamic>{
        'lo': _iface('127.0.0.1', 8),
        'eth0': _iface('192.168.8.185', 24),
      }).suggest();

      expect(s.cidr, '192.168.8.0/24');
      expect(s.deviceIp, '192.168.8.185');
      // The prefix came from the Pi, so this is a REAL mask, not an assumed /24.
      expect(s.maskWasReal, isTrue);
    });

    test('loopback is never chosen even when it is listed first', () async {
      final NetworkSuggestion s = await _net(<String, dynamic>{
        'lo': _iface('127.0.0.1', 8),
        'eth0': _iface('10.20.30.40', 16),
      }).suggest();

      expect(s.deviceIp, '10.20.30.40');
      expect(s.cidr, '10.20.0.0/16');
    });

    test('IPv6 addresses are skipped — the tools sweep IPv4', () async {
      final NetworkSuggestion s = await _net(<String, dynamic>{
        'eth0': <dynamic>[
          <String, dynamic>{
            'addr_info': <dynamic>[
              <String, dynamic>{
                'local': 'fe80::1',
                'prefixlen': 64,
                'family': 'inet6',
              },
              <String, dynamic>{
                'local': '172.16.5.9',
                'prefixlen': 24,
                'family': 'inet',
              },
            ],
          },
        ],
      }).suggest();

      expect(s.cidr, '172.16.5.0/24');
    });

    test(
        'HONEST NONE: a backend error yields no suggestion rather than a '
        'fabricated subnet', () async {
      final NetworkSuggestion s =
          await _net(<String, dynamic>{'error': 'boom'}, status: 500).suggest();

      expect(s.cidr, isNull);
      expect(s.deviceIp, isNull);
    });

    test('HONEST NONE: an interface list with no usable IPv4 invents nothing',
        () async {
      final NetworkSuggestion s = await _net(<String, dynamic>{
        'lo': _iface('127.0.0.1', 8),
        'usb0': <dynamic>[
          <String, dynamic>{'addr_info': <dynamic>[]},
        ],
      }).suggest();

      expect(s.cidr, isNull);
    });

    test(
        'THE CHOICE RULE: the interface matching the host the page came from '
        'wins over an earlier-listed one', () async {
      // The Pi is multi-homed on purpose (eth0 for access, wlan1 as the client
      // radio). The user reached it on wlan1's address here, so the sweep must
      // default to wlan1's subnet, not to whichever interface happened to parse
      // first.
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path == '/toolboxapi/interfaces') {
          return _json(<String, dynamic>{
            'eth0': _iface('10.0.0.5', 24),
            'wlan1': _iface('192.168.8.197', 24),
          });
        }
        return _json(<String, dynamic>{'error': 'no'}, status: 404);
      });
      final CurrentNetwork net = CurrentNetwork.pi(
        client: PiBackendClient(
          httpClient: mock,
          base: Uri.parse('http://192.168.8.197:8080/'),
        ),
      );

      final NetworkSuggestion s = await net.suggest();
      expect(s.deviceIp, '192.168.8.197');
      expect(s.cidr, '192.168.8.0/24');
    });

    test('the gateway is NOT guessed from the subnet', () async {
      final NetworkSuggestion s = await _net(<String, dynamic>{
        'eth0': _iface('192.168.8.185', 24),
      }).suggest();

      // Assuming ".1" would be exactly the fabrication this codebase bars, so
      // the Pi path leaves the gateway unknown until something measures it.
      expect(s.gatewayIp, isNull);
    });
  });
}
