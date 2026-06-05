// ConnectedApCache unit tests (Batch 8, item 1).
//
// The shared cache holds the most-recent connected-AP reading so the Wi-Fi
// Information tool's read is visible to Interface Info without re-running the
// iOS Shortcut. These tests cover: store + read, the ignore-empty rule (a
// transient all-null payload never clears a good cached value), the updatedAt
// stamp, listener notification, and clear.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';

void main() {
  group('ConnectedApCache', () {
    test('starts cold (no reading)', () {
      final cache = ConnectedApCache();
      expect(cache.latest, isNull);
      expect(cache.hasReading, isFalse);
      expect(cache.updatedAt, isNull);
    });

    test('update stores a reading with data and stamps the time', () {
      final cache = ConnectedApCache();
      const ap = ConnectedAp(ssid: 'KeithNet', bssid: 'a4:83:e7:00:11:22');
      cache.update(ap);
      expect(cache.latest, same(ap));
      expect(cache.hasReading, isTrue);
      expect(cache.updatedAt, isNotNull);
    });

    test('a null update is ignored', () {
      final cache = ConnectedApCache();
      cache.update(null);
      expect(cache.hasReading, isFalse);
    });

    test('an all-null (data-empty) reading is ignored', () {
      final cache = ConnectedApCache();
      cache.update(const ConnectedAp());
      expect(cache.hasReading, isFalse);
      expect(cache.latest, isNull);
    });

    test('a data-empty reading does NOT clear a good cached value', () {
      final cache = ConnectedApCache();
      const good = ConnectedAp(ssid: 'KeithNet');
      cache.update(good);
      // A later empty cycle (link blip / empty payload) must not wipe the cache.
      cache.update(const ConnectedAp());
      expect(cache.latest, same(good));
      expect(cache.hasReading, isTrue);
    });

    test('a newer reading replaces the previous one', () {
      final cache = ConnectedApCache();
      cache.update(const ConnectedAp(ssid: 'Old'));
      const fresh = ConnectedAp(ssid: 'New', rssiDbm: -42);
      cache.update(fresh);
      expect(cache.latest, same(fresh));
      expect(cache.latest?.ssid, 'New');
    });

    test('notifies listeners on a real update, not on an ignored one', () {
      final cache = ConnectedApCache();
      int notifications = 0;
      cache.addListener(() => notifications++);

      cache.update(const ConnectedAp(ssid: 'KeithNet')); // real → notify
      cache.update(null); // ignored → no notify
      cache.update(const ConnectedAp()); // empty → no notify

      expect(notifications, 1);
    });

    test('clear resets to the cold state and notifies', () {
      final cache = ConnectedApCache();
      cache.update(const ConnectedAp(ssid: 'KeithNet'));
      int notifications = 0;
      cache.addListener(() => notifications++);

      cache.clear();
      expect(cache.latest, isNull);
      expect(cache.updatedAt, isNull);
      expect(cache.hasReading, isFalse);
      expect(notifications, 1);
    });
  });
}
