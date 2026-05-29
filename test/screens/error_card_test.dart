// Tests for the shared LookupErrorCard error presentation (Vera MEDIUM-1).
//
// Two layers:
//   1. errorPresentationFor() — the pure kind → title/icon/retryable mapping.
//      Locks in the title text per kind and, critically, that ONLY the
//      recoverable kinds (timeout, rateLimited, transport) are retryable.
//   2. LookupErrorCard widget — that the "Try again" control renders for
//      retryable kinds and is absent for non-retryable ones, and that the
//      precise service message is always shown as the body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/error_card.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('errorPresentationFor', () {
    test('recoverable kinds are retryable with distinct titles', () {
      expect(
        errorPresentationFor(JsonHttpErrorKind.timeout).title,
        'Timed out',
      );
      expect(
        errorPresentationFor(JsonHttpErrorKind.timeout).retryable,
        isTrue,
      );

      expect(
        errorPresentationFor(JsonHttpErrorKind.rateLimited).title,
        'Rate-limited',
      );
      expect(
        errorPresentationFor(JsonHttpErrorKind.rateLimited).retryable,
        isTrue,
      );

      expect(
        errorPresentationFor(JsonHttpErrorKind.transport).title,
        'Cannot reach API',
      );
      expect(
        errorPresentationFor(JsonHttpErrorKind.transport).retryable,
        isTrue,
      );
    });

    test('non-recoverable kinds are not retryable', () {
      for (final JsonHttpErrorKind kind in <JsonHttpErrorKind>[
        JsonHttpErrorKind.badUrl,
        JsonHttpErrorKind.httpStatus,
        JsonHttpErrorKind.badJson,
      ]) {
        expect(
          errorPresentationFor(kind).retryable,
          isFalse,
          reason: '$kind must not offer a plain retry',
        );
      }
    });

    test('null kind is the input/validation case — "Check your input", no retry',
        () {
      final LookupErrorPresentation p = errorPresentationFor(null);
      expect(p.title, 'Check your input');
      expect(p.retryable, isFalse);
    });

    test('every kind maps to a non-empty title', () {
      for (final JsonHttpErrorKind kind in JsonHttpErrorKind.values) {
        expect(errorPresentationFor(kind).title, isNotEmpty);
      }
    });
  });

  group('LookupErrorCard widget', () {
    Future<void> pump(
      WidgetTester tester, {
      required JsonHttpErrorKind? kind,
      required String message,
      required VoidCallback onRetry,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: LookupErrorCard(
              errorKind: kind,
              message: message,
              onRetry: onRetry,
            ),
          ),
        ),
      );
    }

    testWidgets('shows Try again and invokes onRetry for a recoverable kind',
        (tester) async {
      int retries = 0;
      await pump(
        tester,
        kind: JsonHttpErrorKind.timeout,
        message: 'The lookup timed out after 12s.',
        onRetry: () => retries++,
      );

      expect(find.text('Timed out'), findsOneWidget);
      expect(find.text('The lookup timed out after 12s.'), findsOneWidget);

      final Finder retry = find.text('Try again');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      expect(retries, 1);
    });

    testWidgets('hides Try again for a non-recoverable kind', (tester) async {
      await pump(
        tester,
        kind: JsonHttpErrorKind.httpStatus,
        message: 'The lookup API returned HTTP 500.',
        onRetry: () {},
      );

      expect(find.text('API error'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('hides Try again for the input/validation (null) case',
        (tester) async {
      await pump(
        tester,
        kind: null,
        message: 'Enter a valid IPv4/IPv6 address or an ASN.',
        onRetry: () {},
      );

      expect(find.text('Check your input'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });
}
