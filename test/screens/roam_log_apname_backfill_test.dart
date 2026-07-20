// Roaming Log — AP-name backfill at RENDER time (Felix, 2026-07-19).
//
// THE BUG THESE GUARD. [RoamDetector] captures `toApName` at the INSTANT the
// BSSID changes. The AP-name beacon scan is fire-and-forget, so a roam TO an AP
// whose name has never been decoded records a null name — and the appended
// event is never backfilled. Seconds later the shared [ApNameCache] knows the
// name, but that history row stays frozen at BSSID-only. Field-reproduced on a
// live deployment where EVERY AP is provisioned with a name, so those rows were
// lost-race rows, not honest nulls.
//
// THE HAZARD THESE ALSO GUARD, which is the more dangerous half. Resolving a
// name by BSSID means a WRONG KEY renders a REAL AP name against the WRONG
// BSSID — authoritative-looking fabricated data, inside a report a consultant
// hands to a client. So these cases assert BOTH directions: the name appears
// when it is genuinely known, AND no name ever appears when it is not.
//
// Every case seeds the cache with a LITERAL lowercase key (the form the cache
// actually keys on) rather than by calling the normalizer, so a test can never
// pass by agreeing with a broken normalizer about a wrong key.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/roaming_log_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ap_name_cache.dart';
import 'package:wlan_pros_toolbox/services/network/roam_detector.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A roam event with the from/to names and BSSIDs the case cares about; every
/// other field is fixed so the assertions read against a stable row.
RoamEvent _event({
  required String fromBssid,
  required String toBssid,
  String? fromApName,
  String? toApName,
}) =>
    RoamEvent(
      at: DateTime(2026, 7, 19, 14, 30, 5),
      ssid: 'SummitConf',
      fromBssid: fromBssid,
      toBssid: toBssid,
      rssiDbm: -62,
      fromRssiDbm: -74,
      snrDb: 31,
      fromChannel: 44,
      toChannel: 149,
      fromBand: '5 GHz',
      toBand: '5 GHz',
      fromApName: fromApName,
      toApName: toApName,
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  setUp(ApNameCache.instance.clear);
  tearDown(ApNameCache.instance.clear);

  group('render-time backfill — the name appears once the cache knows it', () {
    test('copy report: a null captured name is filled from the cache', () {
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07');

      final String? report = buildRoamLogCopyText(
        events: <RoamEvent>[
          _event(
            fromBssid: 'a4:83:e7:00:11:22',
            toBssid: 'a4:83:e7:00:33:44',
            // Both null at capture: the scan had not resolved yet.
          ),
        ],
        network: 'SummitConf',
      );

      expect(report, isNotNull);
      expect(report, contains('Ballroom-AP-07'));
    });

    test('exported HTML: a null captured name is filled from the cache', () {
      // The export matters most — this file is handed to a client.
      ApNameCache.instance.cacheName('a4:83:e7:00:33:44', 'Ballroom-AP-12');

      final String? html = buildRoamLogShareHtml(
        events: <RoamEvent>[
          _event(
            fromBssid: 'a4:83:e7:00:11:22',
            toBssid: 'a4:83:e7:00:33:44',
          ),
        ],
        network: 'SummitConf',
      );

      expect(html, isNotNull);
      expect(html, contains('Ballroom-AP-12'));
    });

    testWidgets('on-screen row: a null captured name is filled from the cache',
        (WidgetTester tester) async {
      ApNameCache.instance
        ..cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07')
        ..cacheName('a4:83:e7:00:33:44', 'Ballroom-AP-12');

      await tester.pumpWidget(_wrap(buildRoamRowForTest(
        _event(
          fromBssid: 'a4:83:e7:00:11:22',
          toBssid: 'a4:83:e7:00:33:44',
        ),
        1,
      )));

      expect(find.text('Ballroom-AP-07'), findsOneWidget);
      expect(find.text('Ballroom-AP-12'), findsOneWidget);
    });

    test('both from AND to sides are resolved, not just one', () {
      ApNameCache.instance
        ..cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07')
        ..cacheName('a4:83:e7:00:33:44', 'Ballroom-AP-12');

      final RoamEvent e = _event(
        fromBssid: 'a4:83:e7:00:11:22',
        toBssid: 'a4:83:e7:00:33:44',
      );

      expect(e.resolvedFromApName(), 'Ballroom-AP-07');
      expect(e.resolvedToApName(), 'Ballroom-AP-12');
    });
  });

  group('THE NORMALIZATION GUARD — a drifted key must not silently miss', () {
    // The cache keys on the trimmed+lowercased BSSID. If a call site ever
    // hand-rolls its own normalizer, or drops normalization entirely, these
    // cases MISS and fail. A miss is the whole bug class: it is one edit away
    // from a lookup that hits the WRONG entry.
    test('uppercase BSSID on the event still resolves the lowercase key', () {
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07');

      final RoamEvent e = _event(
        fromBssid: 'A4:83:E7:00:11:22',
        toBssid: 'a4:83:e7:00:33:44',
      );

      expect(e.resolvedFromApName(), 'Ballroom-AP-07');
    });

    test('surrounding whitespace on the event BSSID still resolves', () {
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07');

      final RoamEvent e = _event(
        fromBssid: '  a4:83:e7:00:11:22  ',
        toBssid: 'a4:83:e7:00:33:44',
      );

      expect(e.resolvedFromApName(), 'Ballroom-AP-07');
    });

    test('mixed case AND whitespace together still resolve, end to end in HTML',
        () {
      ApNameCache.instance.cacheName('a4:83:e7:00:33:44', 'Ballroom-AP-12');

      final String? html = buildRoamLogShareHtml(
        events: <RoamEvent>[
          _event(
            fromBssid: 'a4:83:e7:00:11:22',
            toBssid: ' A4:83:E7:00:33:44 ',
          ),
        ],
        network: 'SummitConf',
      );

      expect(html, contains('Ballroom-AP-12'));
    });
  });

  group('HONEST-NULL SURVIVES — no name is ever fabricated', () {
    test('a BSSID absent from the cache renders BSSID-only, no name', () {
      // A genuinely unnamed AP. The cache holds a name for a DIFFERENT BSSID, so
      // any fallback to "the nearest" or "the only" entry would show it here.
      ApNameCache.instance.cacheName('a4:83:e7:99:99:99', 'Some-Other-AP');

      final RoamEvent e = _event(
        fromBssid: 'a4:83:e7:00:11:22',
        toBssid: 'a4:83:e7:00:33:44',
      );

      expect(e.resolvedFromApName(), isNull);
      expect(e.resolvedToApName(), isNull);

      final String? report =
          buildRoamLogCopyText(events: <RoamEvent>[e], network: 'SummitConf');
      final String? html =
          buildRoamLogShareHtml(events: <RoamEvent>[e], network: 'SummitConf');

      expect(report, isNot(contains('Some-Other-AP')));
      expect(html, isNot(contains('Some-Other-AP')));
      // The row still identifies the AP by its address.
      expect(report, contains(':11:22'));
    });

    testWidgets('on-screen: an uncached BSSID shows no name widget',
        (WidgetTester tester) async {
      ApNameCache.instance.cacheName('a4:83:e7:99:99:99', 'Some-Other-AP');

      await tester.pumpWidget(_wrap(buildRoamRowForTest(
        _event(
          fromBssid: 'a4:83:e7:00:11:22',
          toBssid: 'a4:83:e7:00:33:44',
        ),
        1,
      )));

      expect(find.text('Some-Other-AP'), findsNothing);
      expect(find.text(':11:22'), findsOneWidget);
    });

    test('a blank BSSID resolves to no name', () {
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07');

      expect(
        resolveApName(capturedName: null, bssid: '   '),
        isNull,
        reason: 'a blank BSSID has no key and must never borrow one',
      );
      expect(resolveApName(capturedName: null, bssid: ''), isNull);
      expect(resolveApName(capturedName: null, bssid: null), isNull);
    });

    test('an unparseable BSSID resolves to no name, never a nearest match', () {
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07');

      expect(resolveApName(capturedName: null, bssid: 'not-a-bssid'), isNull);
      // A PREFIX of a real key must not hit it — the lookup is exact-key only.
      expect(resolveApName(capturedName: null, bssid: 'a4:83:e7'), isNull);
    });

    test('a blank captured name with an uncached BSSID stays null', () {
      expect(
        resolveApName(capturedName: '   ', bssid: 'a4:83:e7:00:11:22'),
        isNull,
      );
    });
  });

  group('PRECEDENCE — a captured name is never overwritten by the cache', () {
    test('a differing cache value does NOT replace the captured name', () {
      // The nightmare case: the cache disagrees with what was actually observed
      // at the roam. What was captured on the event wins, always.
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'WRONG-FROM-CACHE');

      final RoamEvent e = _event(
        fromBssid: 'a4:83:e7:00:11:22',
        toBssid: 'a4:83:e7:00:33:44',
        fromApName: 'Captured-At-Roam',
      );

      expect(e.resolvedFromApName(), 'Captured-At-Roam');
      expect(
        resolveApName(
          capturedName: 'Captured-At-Roam',
          bssid: 'a4:83:e7:00:11:22',
        ),
        'Captured-At-Roam',
      );
    });

    test('the captured name survives into the copy report and the HTML', () {
      ApNameCache.instance.cacheName('a4:83:e7:00:33:44', 'WRONG-FROM-CACHE');

      final RoamEvent e = _event(
        fromBssid: 'a4:83:e7:00:11:22',
        toBssid: 'a4:83:e7:00:33:44',
        toApName: 'Captured-At-Roam',
      );

      final String? report =
          buildRoamLogCopyText(events: <RoamEvent>[e], network: 'SummitConf');
      final String? html =
          buildRoamLogShareHtml(events: <RoamEvent>[e], network: 'SummitConf');

      expect(report, contains('Captured-At-Roam'));
      expect(report, isNot(contains('WRONG-FROM-CACHE')));
      expect(html, contains('Captured-At-Roam'));
      expect(html, isNot(contains('WRONG-FROM-CACHE')));
    });

    testWidgets('on-screen: the captured name wins over the cache',
        (WidgetTester tester) async {
      ApNameCache.instance.cacheName('a4:83:e7:00:11:22', 'WRONG-FROM-CACHE');

      await tester.pumpWidget(_wrap(buildRoamRowForTest(
        _event(
          fromBssid: 'a4:83:e7:00:11:22',
          toBssid: 'a4:83:e7:00:33:44',
          fromApName: 'Captured-At-Roam',
        ),
        1,
      )));

      expect(find.text('Captured-At-Roam'), findsOneWidget);
      expect(find.text('WRONG-FROM-CACHE'), findsNothing);
    });
  });

  group('accessibility — the screen-reader label carries the resolved name', () {
    testWidgets('the row Semantics label announces the backfilled name',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      ApNameCache.instance
        ..cacheName('a4:83:e7:00:11:22', 'Ballroom-AP-07')
        ..cacheName('a4:83:e7:00:33:44', 'Ballroom-AP-12');

      await tester.pumpWidget(_wrap(buildRoamRowForTest(
        _event(
          fromBssid: 'a4:83:e7:00:11:22',
          toBssid: 'a4:83:e7:00:33:44',
        ),
        1,
      )));

      // A sighted user reading the backfilled name and a screen-reader user
      // hearing only the BSSID would be two different truths on one row.
      expect(
        find.bySemanticsLabel(RegExp(r'Ballroom-AP-07.*Ballroom-AP-12')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
