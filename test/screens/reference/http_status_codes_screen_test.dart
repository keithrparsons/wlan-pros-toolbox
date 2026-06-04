// Tests for the HTTP Status Codes reference screen.
//
// Layers, mirroring the 802.11 Reason Codes test:
//   1. Data-integrity assertions against the public static dataset — guards
//      that codes are not invented, are unique, sit in their class range, and
//      that known anchors match the IANA registry (404 Not Found, 200 OK,
//      511 Network Authentication Required, 418 (Unused)).
//   2. Widget tests in phone/tablet/desktop viewports — render a known code,
//      filter by code number / reason phrase / keyword, and reach the honest
//      empty state; plus a no-overflow sweep.
//   3. Registration assertions — catalog tile, router route, and help entry all
//      present and consistent for the new id.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/http_status_codes_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Flatten every entry across all classes.
List<HttpStatusEntry> _allEntries() => <HttpStatusEntry>[
      for (final HttpStatusClass c in HttpStatusCodesScreen.classes) ...c.entries,
    ];

void main() {
  group('HTTP status dataset', () {
    test('exposes exactly five classes, 1xx through 5xx in order', () {
      expect(
        HttpStatusCodesScreen.classes
            .map((HttpStatusClass c) => c.lowerBound)
            .toList(),
        <int>[100, 200, 300, 400, 500],
      );
      expect(
        HttpStatusCodesScreen.classes
            .map((HttpStatusClass c) => c.label)
            .toList(),
        <String>[
          '1xx Informational',
          '2xx Success',
          '3xx Redirection',
          '4xx Client Error',
          '5xx Server Error',
        ],
      );
    });

    test('no duplicate code numbers', () {
      final List<int> codes =
          _allEntries().map((HttpStatusEntry e) => e.code).toList();
      expect(codes.toSet().length, codes.length,
          reason: 'duplicate HTTP status code(s) in the dataset');
    });

    test('every code sits in its class range (lowerBound..lowerBound+99)', () {
      for (final HttpStatusClass c in HttpStatusCodesScreen.classes) {
        for (final HttpStatusEntry e in c.entries) {
          expect(e.code, greaterThanOrEqualTo(c.lowerBound),
              reason: '${e.code} below ${c.label} range');
          expect(e.code, lessThan(c.lowerBound + 100),
              reason: '${e.code} above ${c.label} range');
        }
      }
    });

    test('every entry carries a non-empty reason phrase and meaning', () {
      for (final HttpStatusEntry e in _allEntries()) {
        expect(e.reason.trim(), isNotEmpty, reason: '${e.code} reason');
        expect(e.meaning.trim(), isNotEmpty, reason: '${e.code} meaning');
      }
    });

    test('known IANA anchors match verbatim', () {
      final Map<int, String> byCode = <int, String>{
        for (final HttpStatusEntry e in _allEntries()) e.code: e.reason,
      };
      expect(byCode[200], 'OK');
      expect(byCode[301], 'Moved Permanently');
      expect(byCode[404], 'Not Found');
      expect(byCode[418], '(Unused)');
      expect(byCode[429], 'Too Many Requests');
      expect(byCode[451], 'Unavailable For Legal Reasons');
      expect(byCode[500], 'Internal Server Error');
      expect(byCode[503], 'Service Unavailable');
      expect(byCode[511], 'Network Authentication Required');
    });

    test('codes are sorted ascending within each class', () {
      for (final HttpStatusClass c in HttpStatusCodesScreen.classes) {
        final List<int> codes =
            c.entries.map((HttpStatusEntry e) => e.code).toList();
        final List<int> sorted = List<int>.of(codes)..sort();
        expect(codes, sorted, reason: '${c.label} not in ascending order');
      }
    });
  });

  group('registration', () {
    test('catalog tile present in quick-reference / Protocols, live', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final ToolEntry tile = qr.tools.firstWhere(
        (ToolEntry t) => t.id == 'http-status-codes',
      );
      expect(tile.title, 'HTTP Status Codes');
      expect(tile.routeName, '/tools/http-status-codes');
      expect(tile.isLive, isTrue);
      expect(tile.subgroup, 'Protocols');
    });

    test('route resolves to a registered builder', () {
      expect(
        AppRouter.routes.containsKey('/tools/http-status-codes'),
        isTrue,
      );
    });

    test('keyword vocabulary carries an entry for the tool', () {
      expect(kToolKeywords.containsKey('http-status-codes'), isTrue);
      expect(kToolKeywords['http-status-codes'], isNotEmpty);
    });
  });

  testWidgets('renders codes and filters in a phone viewport', (tester) async {
    await _withViewport(tester, const Size(375, 900), () async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const HttpStatusCodesScreen(),
        ),
      );
      await tester.pump();

      // Title + a known code/reason render on first paint.
      expect(find.text('HTTP Status Codes'), findsOneWidget);
      expect(find.text('Not Found'), findsOneWidget);

      // Filter by code number — 404 survives, an unrelated 2xx code drops out.
      await tester.enterText(find.byType(TextField), '404');
      await tester.pump();
      expect(find.text('Not Found'), findsOneWidget);
      expect(find.text('OK'), findsNothing);

      // Filter by reason phrase / keyword — "redirect" matches the 3xx codes.
      await tester.enterText(find.byType(TextField), 'redirect');
      await tester.pump();
      expect(find.text('Temporary Redirect'), findsOneWidget);
      expect(find.text('Permanent Redirect'), findsOneWidget);
      expect(find.text('Not Found'), findsNothing);

      // A query that matches nothing reaches the honest empty state.
      await tester.enterText(find.byType(TextField), 'zzzznope');
      await tester.pump();
      expect(find.text('No match'), findsOneWidget);
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const HttpStatusCodesScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Run [body] with the test view sized to [size], then restore. Mirrors the
/// `_withViewport` helper in the reason-codes test.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
