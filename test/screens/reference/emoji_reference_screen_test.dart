// Tests for the Top 30 Emoji reference screen.
//
// Two layers:
//  1. Data assertions against the public `EmojiReferenceScreen.emoji` const —
//     the same single source the UI renders. Locks the row count to 30, the
//     ranks to a contiguous 1..30, and the rank-1 anchor to its CLDR name.
//     Catches silent drift from the Deliverables source.
//  2. Widget tests in phone/tablet/desktop viewports — pump the screen, assert
//     the title and the rank-1 row render, assert NO "Literal" column header
//     is present (Keith's instruction omits the literal field), and assert no
//     RenderFlex overflow at 320/375/768/1280 (the commonUse text is long and
//     must wrap, never clip).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/emoji_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('EmojiReferenceScreen.emoji dataset', () {
    EmojiEntry byRank(int rank) =>
        EmojiReferenceScreen.emoji.firstWhere((EmojiEntry e) => e.rank == rank);

    test('contains exactly 30 rows', () {
      expect(EmojiReferenceScreen.emoji, hasLength(30));
    });

    test('ranks are a contiguous 1..30 in order', () {
      final List<int> ranks =
          EmojiReferenceScreen.emoji.map((EmojiEntry e) => e.rank).toList();
      expect(ranks, List<int>.generate(30, (int i) => i + 1));
    });

    test('rank 1 is face with tears of joy', () {
      final EmojiEntry first = byRank(1);
      expect(first.name, 'face with tears of joy');
      expect(first.emoji, '😂');
    });

    test('rank 2 is the default red heart', () {
      final EmojiEntry second = byRank(2);
      expect(second.name, 'red heart');
      expect(second.emoji, '❤️');
    });

    test('rank 30 is the smirking face (current ordering, 2026-06-01)', () {
      final EmojiEntry last = byRank(30);
      expect(last.name, 'smirking face');
      expect(last.emoji, '😏');
    });

    test('every row carries a non-empty name, glyph, and common-use note', () {
      for (final EmojiEntry e in EmojiReferenceScreen.emoji) {
        expect(e.name.trim(), isNotEmpty, reason: 'rank ${e.rank} name');
        expect(e.emoji.trim(), isNotEmpty, reason: 'rank ${e.rank} glyph');
        expect(e.commonUse.trim(), isNotEmpty, reason: 'rank ${e.rank} use');
      }
    });
  });

  group('EmojiReferenceScreen widget', () {
    testWidgets('renders title and the rank-1 row in a phone viewport',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EmojiReferenceScreen(),
          ),
        );
        await tester.pump();

        // App-bar title.
        expect(find.text('Top 30 Emoji'), findsOneWidget);
        // The rank-1 row renders its CLDR name and rank badge.
        expect(find.text('face with tears of joy'), findsOneWidget);
        expect(find.text('#1'), findsOneWidget);
      });
    });

    testWidgets('renders NO Literal column header (Keith\'s instruction)',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EmojiReferenceScreen(),
          ),
        );
        await tester.pump();

        // The literal field is omitted entirely — no header, no cell text.
        expect(find.text('Literal'), findsNothing);
        // The dataset's literal copy must not leak through anywhere either.
        expect(find.text('Crying-laughing face'), findsNothing);
      });
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (WidgetTester tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      await _withViewport(tester, Size(width, 1600), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const EmojiReferenceScreen(),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      });
    }
  });
}

/// Run [body] with the test view sized to [size], then restore — mirrors the
/// `_withViewport` helper in test/widget_test.dart and the sibling reference
/// screen tests.
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
