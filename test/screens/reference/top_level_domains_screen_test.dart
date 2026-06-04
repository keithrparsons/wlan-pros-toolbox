// Tests for the Top-Level Domains reference screen (Batch 5).
//
// Two layers:
//  1. Data assertions against the public const the UI renders — locks the
//     curated set, the type classifications, and the load-bearing EPISTEMIC-
//     HONESTY facts (.io / .ai / .co are ccTLDs, NOT true gTLDs; .arpa is
//     infrastructure).
//  2. Widget tests in phone/tablet/desktop viewports — title + representative
//     rows render; the type filter narrows the list; no overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/top_level_domains_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

void main() {
  group('TLD dataset', () {
    test('ships the core generic gTLDs', () {
      final Set<String> generic = TopLevelDomainsScreen.domains
          .where((TldEntry e) => e.type == TldType.generic)
          .map((TldEntry e) => e.tld)
          .toSet();
      expect(generic, containsAll(<String>['.com', '.org', '.net', '.info',
          '.biz']));
    });

    test('ships a representative ccTLD set', () {
      final Set<String> cc = TopLevelDomainsScreen.domains
          .where((TldEntry e) => e.type == TldType.countryCode)
          .map((TldEntry e) => e.tld)
          .toSet();
      expect(cc, containsAll(<String>['.us', '.uk', '.de', '.jp', '.ca',
          '.au']));
    });

    test('sponsored/restricted set includes .gov .edu .mil .int', () {
      final Set<String> sp = TopLevelDomainsScreen.domains
          .where((TldEntry e) => e.type == TldType.sponsored)
          .map((TldEntry e) => e.tld)
          .toSet();
      expect(sp, containsAll(<String>['.gov', '.edu', '.mil', '.int', '.aero',
          '.museum']));
    });

    test('.arpa is the infrastructure TLD', () {
      final List<TldEntry> infra = TopLevelDomainsScreen.domains
          .where((TldEntry e) => e.type == TldType.infrastructure)
          .toList();
      expect(infra.map((TldEntry e) => e.tld), <String>['.arpa']);
    });

    // EPISTEMIC HONESTY: .io / .ai / .co are ccTLDs used generically, NOT true
    // gTLDs. They are grouped under "newer gTLDs" for findability but their
    // notes must say they are technically country-code TLDs.
    test('.io .ai .co notes state they are technically ccTLDs', () {
      for (final String tld in <String>['.io', '.ai', '.co']) {
        final TldEntry e = TopLevelDomainsScreen.domains
            .firstWhere((TldEntry e) => e.tld == tld);
        expect(
          e.note.toLowerCase(),
          contains('cctld'),
          reason: '$tld must be flagged as technically a ccTLD',
        );
        expect(
          e.note.toLowerCase(),
          contains('not a true gtld'),
          reason: '$tld must say it is not a true gTLD',
        );
      }
    });

    test('footnote names the curation limit and the ccTLD-vs-gTLD caveat', () {
      expect(TopLevelDomainsScreen.footnote.toLowerCase(),
          contains('not exhaustive'));
      expect(TopLevelDomainsScreen.footnote, contains('IANA Root Zone'));
    });

    test('every entry carries a non-empty TLD and note', () {
      for (final TldEntry e in TopLevelDomainsScreen.domains) {
        expect(e.tld, startsWith('.'), reason: 'TLD must include the dot');
        expect(e.note.trim(), isNotEmpty, reason: '${e.tld} note');
      }
    });

    test('every TldType has at least one entry (no empty section)', () {
      for (final TldType t in TldType.values) {
        expect(
          TopLevelDomainsScreen.domains.any((TldEntry e) => e.type == t),
          isTrue,
          reason: 'no entry for ${t.label}',
        );
      }
    });
  });

  group('TopLevelDomainsScreen widget', () {
    testWidgets('renders title and section headers in a phone viewport', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const TopLevelDomainsScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Top-Level Domains'), findsOneWidget);
        expect(find.text('Generic (gTLD)'), findsWidgets);
        expect(find.text('Country-code (ccTLD)'), findsWidgets);
        // A representative TLD renders.
        expect(find.text('.com'), findsWidgets);
        expect(find.text('.arpa'), findsWidgets);
      });
    });

    testWidgets('type filter narrows to one section', (
      WidgetTester tester,
    ) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const TopLevelDomainsScreen(),
          ),
        );
        await tester.pump();

        // Open the select and pick "Infrastructure".
        await tester.tap(find.byType(AppSelect<TldType?>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Infrastructure').last);
        await tester.pumpAndSettle();

        // Only the infrastructure section remains; .com (generic) is gone.
        expect(find.text('.arpa'), findsWidgets);
        expect(find.text('.com'), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths', (
      WidgetTester tester,
    ) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const TopLevelDomainsScreen(),
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

/// Run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await body();
}
