// PiBackendClient.scanInterfaces() — fixture coverage for the scan-radio picker.
//
// The fixture is the exact wire shape the Pi's `/toolboxapi/scan-interfaces`
// endpoint returns (Mack's backend): a managed, scan-capable radio list, wlan0
// first, each entry carrying its kernel name and driver. A MockClient stands in
// for the browser fetch so no Pi is needed. Load-bearing checks: the endpoint
// path, order preservation (wlan0 first), name+driver mapping, honest-null on a
// missing/blank driver, and a malformed entry (no name) dropped rather than
// guessed (GL-005).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: <String, String>{'content-type': 'application/json'});

PiBackendClient _client(MockClient mock) =>
    PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/'));

void main() {
  group('scanInterfaces()', () {
    test('maps the two-radio shape, wlan0 first, name + driver', () async {
      late Uri seen;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        seen = req.url;
        return _json(<String, dynamic>{
          'interfaces': <dynamic>[
            <String, dynamic>{'name': 'wlan0', 'driver': 'mt7921u'},
            <String, dynamic>{'name': 'wlan1', 'driver': 'iwlwifi'},
          ],
        });
      }));

      final List<PiScanInterface> ifaces = await client.scanInterfaces();

      expect(seen.path, '/toolboxapi/scan-interfaces');
      expect(ifaces, hasLength(2));
      // Order preserved — wlan0 first, so it defaults the picker.
      expect(ifaces.first.name, 'wlan0');
      expect(ifaces.first.driver, 'mt7921u');
      expect(ifaces.first.label, 'wlan0 (mt7921u)');
      expect(ifaces[1].name, 'wlan1');
      expect(ifaces[1].label, 'wlan1 (iwlwifi)');
    });

    test('a missing/blank driver is honest-null; label is the bare name',
        () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'interfaces': <dynamic>[
            <String, dynamic>{'name': 'wlan0'}, // no driver key
            <String, dynamic>{'name': 'wlan1', 'driver': ''}, // blank driver
          ],
        });
      }));

      final List<PiScanInterface> ifaces = await client.scanInterfaces();
      expect(ifaces, hasLength(2));
      expect(ifaces.first.driver, isNull); // never guessed
      expect(ifaces.first.label, 'wlan0');
      expect(ifaces[1].driver, isNull);
      expect(ifaces[1].label, 'wlan1');
    });

    test('a malformed entry (no name) is dropped, never guessed', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'interfaces': <dynamic>[
            <String, dynamic>{'driver': 'mt7921u'}, // no name → dropped
            <String, dynamic>{'name': '', 'driver': 'x'}, // empty name → dropped
            <String, dynamic>{'name': 'wlan0', 'driver': 'mt7921u'},
          ],
        });
      }));

      final List<PiScanInterface> ifaces = await client.scanInterfaces();
      expect(ifaces, hasLength(1));
      expect(ifaces.first.name, 'wlan0');
    });

    test('a non-200 surfaces as a PiBackendException', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{'error': 'no scan radios'}, status: 500);
      }));
      expect(
        client.scanInterfaces,
        throwsA(isA<PiBackendException>()),
      );
    });
  });
}
