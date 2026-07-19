// Shared AP-name cache — cross-adapter behavior (feature/shared-apname-cache).
//
// The name cache and scan throttle used to live per-adapter, so every screen
// started COLD: even after the Roaming Log decoded an AP's name, a freshly-opened
// Wi-Fi Info screen (its own adapter) re-ran the slow beacon scan. These tests
// prove the cache is now app-wide via [ApNameCache.instance]:
//   1. A name decoded by adapter A is served by a SEPARATE adapter B on B's
//      FIRST fetch with ZERO scans on B — the instant cross-screen hit.
//   2. A genuinely-new BSSID triggers EXACTLY ONE throttled scan app-wide across
//      two adapters — the throttle timestamp is shared, so the second adapter
//      does not re-storm the radio for the same not-yet-known BSSID.
//   3. (HIGH-1 regression) A throttle-DEFERRED adapter still reports the WINNING
//      adapter's in-flight scan as its `pendingApNameScan`, so a non-polling
//      screen (Interface Info) that awaits it genuinely waits and re-reads once
//      the name lands — instead of awaiting null and re-reading against a still
//      empty cache, never to re-read again.
//   4. A FAILED scan clears its in-flight entry, so a BSSID is never wedged as
//      permanently "pending" and a later fetch can scan again.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ap_name_cache.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

/// One non-extended IE element: [id][len][...data].
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// A synthetic UniFi (Ubiquiti) Tag 221 AP-name IE: OUI 00:15:6D, type 0x01.
List<int> _unifiNameBlob(String name) =>
    _ie(221, <int>[0x00, 0x15, 0x6D, 0x01, ...name.codeUnits]);

Map<String, Object?> _wifiInfoMap(String bssid) => <String, Object?>{
      'ssid': 'KeithNet',
      'bssid': bssid,
      'poweredOn': true,
      'locationAuthorized': true,
    };

Map<String, Object?> _blob(String? bssid, List<int>? ieBytes) => <String, Object?>{
      'ieBytes': ieBytes == null ? null : Uint8List.fromList(ieBytes),
      'bssid': bssid,
      'locationAuthorized': true,
    };

/// A counting fake WifiInfoService (platform macos). [scanCount] records how
/// many times the beacon-IE scan channel was hit, so a per-adapter scan count
/// (or a shared app-wide count) can be asserted.
///
/// [gate], when set, holds the scan channel open until the test completes it —
/// standing in for the real ~30s CoreWLAN beacon scan, so a second adapter can
/// fetch WHILE the first adapter's scan is genuinely still in flight. [failScan]
/// makes the scan channel throw, standing in for a CoreWLAN read that errors.
class _CountingService {
  _CountingService({
    required this.wifiInfo,
    required this.ieBlob,
    this.gate,
    this.failScan = false,
  });

  Map<dynamic, dynamic>? wifiInfo;
  Map<dynamic, dynamic>? ieBlob;
  Completer<void>? gate;
  bool failScan;
  int scanCount = 0;

  WifiInfoService get service => WifiInfoService(
        platformOverride: 'macos',
        invoke: (String method, [dynamic args]) async {
          switch (method) {
            case 'getWifiInfo':
              return wifiInfo;
            case 'connectedApIeBlob':
              scanCount++;
              if (gate != null) await gate!.future;
              if (failScan) throw StateError('CoreWLAN scan failed');
              return ieBlob;
            default:
              return null;
          }
        },
      );
}

void main() {
  // These tests exercise the app-wide singleton directly, so reset it between
  // cases to keep each start cold.
  setUp(() => ApNameCache.instance.clear());

  test(
    'a name decoded by adapter A is served by a SEPARATE adapter B on B\'s '
    'FIRST fetch, with NO scan on B (instant cross-screen hit)',
    () async {
      const String bssid = 'aa:bb:cc:dd:ee:ff';

      // Adapter A (e.g. the Roaming Log sampler) decodes and caches the name.
      final _CountingService fakeA = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapterA =
          MacWifiInfoAdapter(service: fakeA.service, enrichApName: true);

      await adapterA.fetch(); // honest-null first read, schedules the scan
      await adapterA.pendingApNameScan; // scan resolves, caches into the singleton
      expect(fakeA.scanCount, 1);

      // Adapter B is a DIFFERENT instance with its OWN service (a freshly-opened
      // Wi-Fi Info screen). It shares the app-wide cache, so its FIRST fetch
      // serves the name instantly — B never touches its scan channel.
      final _CountingService fakeB = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapterB =
          MacWifiInfoAdapter(service: fakeB.service, enrichApName: true);

      final ConnectedAp firstOnB = await adapterB.fetch();
      expect(firstOnB.apName, 'UAP-Lobby'); // instant, no cold-start wait
      await adapterB.pendingApNameScan; // nothing was scheduled
      expect(fakeB.scanCount, 0); // B NEVER scanned — the whole point
    },
  );

  test(
    'a not-yet-known BSSID triggers EXACTLY ONE scan app-wide across two '
    'adapters (the throttle is shared, not per-screen)',
    () async {
      const String bssid = '11:22:33:44:55:66';
      final DateTime clock = DateTime(2026, 7, 19, 12, 0, 0);

      // ONE counting service shared by both adapters, so scanCount is the
      // app-wide total. The scan returns no IE data → no name is ever cached,
      // so ONLY the shared throttle can stop a second scan.
      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, null),
      );

      final MacWifiInfoAdapter adapterA = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => clock,
      );
      final MacWifiInfoAdapter adapterB = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => clock,
      );

      // Adapter A scans first and stamps the shared last-scan timestamp.
      await adapterA.fetch();
      await adapterA.pendingApNameScan;
      expect(fake.scanCount, 1);

      // Adapter B, at the same instant, sees A's shared timestamp inside the
      // floor and DEFERS — it does not re-scan the same not-yet-known BSSID.
      await adapterB.fetch();
      await adapterB.pendingApNameScan;
      expect(fake.scanCount, 1); // still one scan app-wide, not two
    },
  );

  // HIGH-1 regression. Hoisting the throttle into the singleton without also
  // hoisting the in-flight scan left a throttle-deferred adapter with NO handle
  // on the winner's scan: it reported `pendingApNameScan == null`, so Interface
  // Info's await fell through to `Future.value()`, re-read on the next microtask
  // against a still-empty cache, and then NEVER re-read again — the name did not
  // appear until the user hit Refresh by hand.
  test(
    'a throttle-DEFERRED adapter reports the WINNING adapter\'s in-flight scan '
    'as pendingApNameScan, and awaiting it yields the decoded name',
    () async {
      const String bssid = 'aa:bb:cc:00:11:22';
      final DateTime t0 = DateTime(2026, 7, 19, 12, 0, 0);

      // Adapter A = the Roaming Log sampler. Its scan is held open by the gate,
      // standing in for the real ~30s CoreWLAN beacon scan.
      final Completer<void> scanGate = Completer<void>();
      final _CountingService fakeA = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
        gate: scanGate,
      );
      final MacWifiInfoAdapter adapterA = MacWifiInfoAdapter(
        service: fakeA.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => t0,
      );

      // T: A stamps the shared throttle and starts the long scan.
      await adapterA.fetch();
      expect(fakeA.scanCount, 1);
      expect(adapterA.pendingApNameScan, isNotNull);

      // T+2s: the user opens Interface Info. Adapter B misses the cache, and the
      // shared timestamp is only 2s old — inside the 30s floor — so B is
      // DEFERRED and schedules no scan of its own.
      final _CountingService fakeB = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
      );
      final MacWifiInfoAdapter adapterB = MacWifiInfoAdapter(
        service: fakeB.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => t0.add(const Duration(seconds: 2)),
      );

      final ConnectedAp firstOnB = await adapterB.fetch();
      expect(firstOnB.apName, isNull); // honest-null: nothing decoded yet
      expect(fakeB.scanCount, 0); // dedupe intact — B did NOT re-scan

      // THE REGRESSION: B must still have something to wait on — A's scan.
      // Null here is what silently killed Interface Info's auto re-read.
      final Future<void>? pendingOnB = adapterB.pendingApNameScan;
      expect(
        pendingOnB,
        isNotNull,
        reason: 'a deferred adapter must expose the winner\'s in-flight scan, '
            'else the awaiting screen re-reads against an empty cache and '
            'never re-reads again',
      );

      // ~T+30s: A's scan resolves and caches into the singleton.
      scanGate.complete();
      await pendingOnB; // must genuinely WAIT for A's scan, not fall through

      // And the await must have been worth it: B's re-read now has the name.
      final ConnectedAp reReadOnB = await adapterB.fetch();
      expect(reReadOnB.apName, 'UAP-Lobby');
      expect(fakeB.scanCount, 0); // still exactly one scan app-wide
    },
  );

  test(
    'a FAILED scan clears its in-flight entry, so the BSSID is not wedged as '
    'permanently pending and a later fetch can scan again',
    () async {
      const String bssid = 'de:ad:be:ef:00:01';
      final DateTime t0 = DateTime(2026, 7, 19, 12, 0, 0);
      DateTime clock = t0;

      final _CountingService fake = _CountingService(
        wifiInfo: _wifiInfoMap(bssid),
        ieBlob: _blob(bssid, _unifiNameBlob('UAP-Lobby')),
        failScan: true,
      );
      final MacWifiInfoAdapter adapter = MacWifiInfoAdapter(
        service: fake.service,
        enrichApName: true,
        apNameRescanFloor: const Duration(seconds: 30),
        now: () => clock,
      );

      // First scan fails. Awaiting it must resolve (not throw) — the screen has
      // to get its turn back to re-read honestly.
      await adapter.fetch();
      await adapter.pendingApNameScan;
      expect(fake.scanCount, 1);
      expect(ApNameCache.instance.nameFor(bssid), isNull); // honest-null

      // Past the throttle floor the BSSID must be scannable again, which it is
      // only if the failed scan cleared its in-flight entry.
      clock = t0.add(const Duration(seconds: 31));
      fake.failScan = false;
      await adapter.fetch();
      expect(fake.scanCount, 2, reason: 'a failed scan must not wedge the BSSID');
      await adapter.pendingApNameScan;
      expect(ApNameCache.instance.nameFor(bssid), 'UAP-Lobby');
    },
  );
}
