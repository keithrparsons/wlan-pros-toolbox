// Phase B PiBackend gate coverage — the served-tool set and canServe mapping.
//
// The screen-level `_piBacked` branch itself is only reachable under kIsWeb (a
// const false on the Dart VM), so it cannot be exercised in a VM widget test.
// What IS testable — and load-bearing — is the catalog gate the tool grid and
// each screen consult: PiBackend.servedToolIds / PiBackend.canServe. The one
// that would bite silently is the dns naming mismatch, so it gets its own case.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend.dart';

void main() {
  tearDown(() => PiBackend.debugSetAvailable(false));

  test('servedToolIds carries the three Phase B tools plus the front door', () {
    expect(PiBackend.servedToolIds, containsAll(<String>{
      'ping',
      'traceroute',
      'dns-lookup',
      'test-my-connection',
    }));
  });

  test('the catalog id is dns-lookup, never the dns route name', () {
    // The proxy ROUTE is `/toolboxapi/dns`, but the CATALOG id the gate keys on
    // is `dns-lookup`. If this ever flips to `dns`, the grid gate would pass
    // while every fetch 404s (or vice-versa). Pin both halves.
    expect(PiBackend.servedToolIds, contains('dns-lookup'));
    expect(PiBackend.servedToolIds, isNot(contains('dns')));
  });

  test('canServe is true only for served ids when a Pi backend is present', () {
    PiBackend.debugSetAvailable(true);
    for (final String id in <String>['ping', 'traceroute', 'dns-lookup']) {
      expect(PiBackend.canServe(id), isTrue, reason: id);
    }
    expect(PiBackend.canServe('dns'), isFalse); // route name, not a catalog id
    expect(PiBackend.canServe('nope'), isFalse);
  });

  test('canServe is false for everything when no Pi backend is present', () {
    PiBackend.debugSetAvailable(false);
    for (final String id in PiBackend.servedToolIds) {
      expect(PiBackend.canServe(id), isFalse, reason: id);
    }
  });
}
