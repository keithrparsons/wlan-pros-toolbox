// Tests for the HTTP Methods & Headers reference screen.
//
// The datasets are reproduced verbatim from the verified protocols dataset
// (Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 3): the
// HTTP methods with their RFC 9110 safe / idempotent flags, plus the common
// request and response headers. These tests assert the load-bearing flag
// combinations (the ones people get wrong: PUT/DELETE idempotent-but-unsafe,
// POST/PATCH neither) plus phone/tablet/desktop widget tests confirming the
// read-only screen renders without overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/http_methods_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('HTTP methods — safe/idempotent per RFC 9110', () {
    HttpMethod methodFor(String name) => HttpMethodsScreen.methods
        .firstWhere((HttpMethod m) => m.method == name);

    test('GET = safe + idempotent', () {
      final HttpMethod m = methodFor('GET');
      expect(m.safe, isTrue);
      expect(m.idempotent, isTrue);
    });

    test('POST = neither safe nor idempotent', () {
      final HttpMethod m = methodFor('POST');
      expect(m.safe, isFalse);
      expect(m.idempotent, isFalse);
    });

    test('PUT = idempotent but not safe', () {
      final HttpMethod m = methodFor('PUT');
      expect(m.safe, isFalse);
      expect(m.idempotent, isTrue);
    });

    test('DELETE = idempotent but not safe', () {
      final HttpMethod m = methodFor('DELETE');
      expect(m.safe, isFalse);
      expect(m.idempotent, isTrue);
    });

    test('PATCH = neither safe nor idempotent (RFC 5789)', () {
      final HttpMethod m = methodFor('PATCH');
      expect(m.safe, isFalse);
      expect(m.idempotent, isFalse);
    });

    test('nine methods, no em dash in any purpose', () {
      expect(HttpMethodsScreen.methods.length, 9);
      for (final HttpMethod m in HttpMethodsScreen.methods) {
        expect(m.purpose.contains('—'), isFalse, reason: 'no em dash');
      }
    });
  });

  group('HTTP headers', () {
    test('Authorization is a request header; WWW-Authenticate a response one',
        () {
      expect(
        HttpMethodsScreen.requestHeaders
            .any((HttpHeader h) => h.name == 'Authorization'),
        isTrue,
      );
      expect(
        HttpMethodsScreen.responseHeaders
            .any((HttpHeader h) => h.name == 'WWW-Authenticate'),
        isTrue,
      );
    });

    test('request + response header tables are non-empty', () {
      expect(HttpMethodsScreen.requestHeaders, isNotEmpty);
      expect(HttpMethodsScreen.responseHeaders, isNotEmpty);
    });
  });

  group('HttpMethodsScreen widget', () {
    testWidgets('renders title and all three table headings in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const HttpMethodsScreen(),
          ),
        );
        expect(find.text('HTTP Methods & Headers'), findsWidgets);
        expect(find.text('Methods'), findsOneWidget);
        expect(find.text('Common request headers'), findsOneWidget);
        expect(find.text('Common response headers'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1800), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const HttpMethodsScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
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
