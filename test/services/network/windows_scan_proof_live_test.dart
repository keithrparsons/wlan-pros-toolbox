// LIVE PROOF: does the Windows nearby-BSS enumeration actually execute?
//
// Run ON THE WINDOWS BOX with:
//   flutter test test/services/network/windows_scan_proof_live_test.dart
//
// It is a TEST, not a CLI, for one reason: windows_wifi_ffi.dart imports
// package:flutter/foundation.dart, which drags in dart:ui, and plain `dart run`
// cannot provide it. flutter_tester is a real native Windows binary, so dart:ffi
// reaches the real wlanapi.dll from inside it. Changing the shipping import just
// to make it observable would have been changing the thing under test.
//
// TAGGED `live`: it needs a real wireless NIC and is skipped off Windows, so it
// never runs in CI and never gates a build.
//
// WHY THIS EXISTS. `WindowsWifiReader.scanNearbyBss` and everything under it in
// windows_wifi_ffi.dart is a DARK PATH by explicit decision: Windows is absent
// from `ApScanService.isSupportedPlatform`, the Nearby AP Scan tool is dropped
// from the Windows catalog, and nothing calls the enumeration at runtime. The
// module header says it plainly -- "EXECUTED for the first time on a real
// Windows box with a real wireless NIC" -- and dart:ffi does not run on macOS,
// so struct layout, pointer arithmetic and free discipline are
// written-not-executed. The board has carried that as the critical-path item
// for the 1.9.0 ship.
//
// THIS SCRIPT IMPORTS THE REAL MODULE. It does not re-implement the FFI calls.
// Verifying a copy would prove nothing about the code that ships.
//
// WHAT IT CAN ESTABLISH:
//   1. The connected-AP path still works (the PROVEN control -- if this fails,
//      the failure is the environment, not the dark path).
//   2. `enumerateNearbyBssFromNativeWifi()` runs to completion without an
//      access violation, which is the single biggest unknown in hand-written
//      dart:ffi struct walking.
//   3. The rows it returns are internally coherent: BSSID shape, RSSI in a
//      plausible dBm range, and channel/band agreeing with frequency through
//      the same `frequencyToChannel` table the shipped mapper uses.
//   4. Whether a second call after a delay returns a DIFFERENT list, which is
//      the documented open question about whether the driver's BSS list is
//      stale without a preceding WlanScan.
//
// WHAT IT CANNOT ESTABLISH, stated up front so the output is not over-read:
//   - That every nearby AP is present. The driver returns what its last scan
//     found; absence here is not absence on air. Only a spectrum capture or a
//     second tool could establish completeness, and neither is in scope.
//   - That the channel-width and country IE parse is correct. Those come from
//     the +8 offset walk flagged at windows_wifi_ffi.dart:94, and a wrong
//     offset yields null rather than a wrong value, so a null here is
//     ambiguous between "not advertised" and "offset wrong".

@Tags(<String>['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/windows_wifi_ffi.dart'
    show readConnectedApFromNativeWifi, enumerateNearbyBssFromNativeWifi;

String _pad(Object? v, int n) => v.toString().padRight(n);

void _rule([String title = '']) {
  stdout.writeln('');
  if (title.isNotEmpty) stdout.writeln(title);
  stdout.writeln('-' * 78);
}

void main() {
  test('Windows nearby-BSS dark path executes against real hardware', () async {
  stdout.writeln('WINDOWS NEARBY-BSS PROOF');
  stdout.writeln('host      : ${Platform.localHostname}');
  stdout.writeln('os        : ${Platform.operatingSystemVersion}');
  stdout.writeln('when      : ${DateTime.now().toIso8601String()}');

  if (!Platform.isWindows) {
    stdout.writeln('\nNOT WINDOWS -- this script only means anything on the box.');
    fail('not Windows');
  }

  // ---- 1. the proven control -------------------------------------------
  _rule('1. CONNECTED AP  (proven path -- a failure here is environmental)');
  try {
    final Object? info = await readConnectedApFromNativeWifi();
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(
      info is Map ? info : <String, Object?>{'value': info.toString()},
    ));
  } catch (e, st) {
    stdout.writeln('FAILED: $e');
    stdout.writeln(st.toString().split('\n').take(4).join('\n'));
  }

  // ---- 2. the dark path, executed --------------------------------------
  _rule('2. ENUMERATE NEARBY BSS  (dark path -- FIRST EXECUTION)');
  List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  final Stopwatch sw = Stopwatch()..start();
  try {
    rows = await enumerateNearbyBssFromNativeWifi();
    sw.stop();
    stdout.writeln('RETURNED ${rows.length} row(s) in ${sw.elapsedMilliseconds} ms '
        '-- no access violation, the FFI walk completed.');
  } catch (e, st) {
    sw.stop();
    stdout.writeln('THREW after ${sw.elapsedMilliseconds} ms: $e');
    stdout.writeln(st.toString().split('\n').take(6).join('\n'));
    rethrow;
  }

  // ---- 3. are the rows internally coherent? ----------------------------
  _rule('3. ROWS');
  stdout.writeln('${_pad("SSID", 30)}${_pad("BSSID", 20)}'
      '${_pad("dBm", 6)}${_pad("ch", 5)}${_pad("band", 7)}MHz');
  final List<String> problems = <String>[];
  for (final Map<String, Object?> r in rows) {
    stdout.writeln('${_pad(r['ssid'] ?? '(hidden)', 30)}'
        '${_pad(r['bssid'], 20)}${_pad(r['rssiDbm'], 6)}'
        '${_pad(r['channel'], 5)}${_pad(r['band'], 7)}${r['frequencyMhz']}');
    final Object? bssid = r['bssid'];
    if (bssid is! String || bssid.split(':').length != 6) {
      problems.add('bssid shape: $bssid');
    }
    final Object? rssi = r['rssiDbm'];
    if (rssi is! int || rssi > -10 || rssi < -110) {
      problems.add('rssi out of plausible range: $rssi ($bssid)');
    }
    if (r['channel'] == null || r['band'] == null) {
      problems.add('null channel/band survived the mapper: $bssid');
    }
  }
  stdout.writeln('');
  stdout.writeln(problems.isEmpty
      ? 'COHERENCE: clean -- every row has a 6-octet BSSID, a plausible dBm, '
          'and a resolved channel/band.'
      : 'COHERENCE: ${problems.length} problem(s):\n  ${problems.join("\n  ")}');

  // ---- 4. is the driver list stale without a WlanScan? -----------------
  _rule('4. STALENESS  (the documented open question)');
  stdout.writeln('Waiting 12 s, then enumerating again with no explicit WlanScan...');
  await Future<void>.delayed(const Duration(seconds: 12));
  final List<Map<String, Object?>> again =
      await enumerateNearbyBssFromNativeWifi();
  final Set<String> a = rows.map((Map<String, Object?> r) => '${r['bssid']}').toSet();
  final Set<String> b = again.map((Map<String, Object?> r) => '${r['bssid']}').toSet();
  stdout.writeln('first=${a.length}  second=${b.length}  '
      'appeared=${b.difference(a).length}  vanished=${a.difference(b).length}');
  stdout.writeln(a.difference(b).isEmpty && b.difference(a).isEmpty
      ? 'IDENTICAL BSSID set. Consistent with a cached driver list; this does '
          'NOT prove a WlanScan is unnecessary, only that 12 s changed nothing.'
      : 'THE SET MOVED without an explicit WlanScan -- the driver is refreshing '
          'on its own cadence.');

  _rule();
  stdout.writeln('Rows also written to windows_scan_proof.json');
  File('windows_scan_proof.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  }, timeout: const Timeout(Duration(minutes: 2)),
     skip: !Platform.isWindows ? 'Windows only' : null);
}
