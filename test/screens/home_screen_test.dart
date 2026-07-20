// Widget tests for the consumer front-door home (Option A, 2026-06-03).
//
// Covers: the "Check My Connection" hero renders and routes to Test My
// Connection; the search field is present (now at the BOTTOM) and navigates;
// each tile shows the live tool-count badge and the example-tools line; NO NEW
// pill renders anywhere in this build (Keith, 2026-06-03 — nothing is new to a
// user yet); the grid renders all categories; the TILE GRID stretches to 3 then
// 4 columns on wide desktop widths and reflows back down to 2/1 on narrow ones
// (Kjetil desktop beta finding, 2026-06-07); no RenderFlex overflow across the
// phone → 4-column desktop width band.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/guides/guide_reader_screen.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _app({Map<String, WidgetBuilder>? routes}) => MaterialApp(
      theme: AppTheme.dark(),
      home: const HomeScreen(),
      routes: routes ?? <String, WidgetBuilder>{},
    );

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

void main() {
  testWidgets(
    'the About action exposes an accessible NAME, not just a tooltip '
    '(WCAG 2.2 AA SC 4.1.2)',
    (tester) async {
      await _withViewport(tester, const Size(800, 1200), () async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();

        // `tooltip: 'About'` maps to AXHelp, not AXTitle; the explicit Semantics
        // label is the accessible name. Removing it (the mutation) → red.
        expect(find.bySemanticsLabel('About this app'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('About this app')),
          isSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            label: 'About this app',
          ),
          reason: 'the About action must read as a named, enabled button to AT',
        );

        handle.dispose();
      });
    },
  );

  testWidgets('the Check My Connection hero renders at the top', (
    tester,
  ) async {
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(
        find.text('Is it your Wi-Fi or your Internet?'),
        findsOneWidget,
      );
      expect(find.text('Check My Connection'), findsOneWidget);
      // The lime "START HERE" eyebrow and the descriptive subline were removed
      // (2026-06-04) to reclaim iOS vertical space — assert they are gone.
      expect(find.text('START HERE'), findsNothing);
      expect(
        find.text(
          'One tap tells you which side is slow, and what to tell support.',
        ),
        findsNothing,
      );
    });
  });

  testWidgets('tapping the hero CTA pushes the testMyConnection route', (
    tester,
  ) async {
    bool pushedTest = false;
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(
        _app(
          routes: <String, WidgetBuilder>{
            AppRouter.testMyConnection: (_) {
              pushedTest = true;
              return const Scaffold(body: Text('Test My Connection screen'));
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      expect(pushedTest, isTrue);
    });
  });

  testWidgets('the "How this app works" entry renders and opens the reader', (
    tester,
  ) async {
    // markdown_widget's VisibilityDetector leaves a pending timer otherwise.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // The compact app-orientation entry is present (Option A restructure:
      // re-labeled from "New here? A Guide for Everyone" to app orientation).
      expect(find.text('How this app works'), findsOneWidget);
      expect(find.text('A 5-minute tour of the app'), findsOneWidget);

      // Tapping it opens the in-app reader on the user guide.
      await tester.tap(find.text('How this app works'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final Finder reader = find.byType(GuideReaderScreen);
      expect(reader, findsOneWidget);
      expect(
        tester.widget<GuideReaderScreen>(reader).assetPath,
        kUserGuideAsset,
      );
    });
  });

  testWidgets('the home search field is present and pushes /search', (
    tester,
  ) async {
    bool pushedSearch = false;
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(
        _app(
          routes: <String, WidgetBuilder>{
            AppRouter.search: (_) {
              pushedSearch = true;
              return const Scaffold(body: Text('Search screen'));
            },
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Search all tools…'), findsOneWidget);
      await tester.tap(find.text('Search all tools…'));
      await tester.pumpAndSettle();
      expect(pushedSearch, isTrue);
    });
  });

  testWidgets('each tile shows its live count badge and example-tools line', (
    tester,
  ) async {
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      for (final ToolCategory cat in kToolCategories) {
        final int liveCount = cat.tools.where((ToolEntry t) => t.isLive).length;
        // The tile badge shows countLabelOverride when set (e.g. Educational
        // Resources pins '48' = 11 in-app references + 37 online resources),
        // else the live tool count.
        final String badge = cat.countLabelOverride ?? '$liveCount';
        expect(
          find.text(badge),
          findsWidgets,
          reason: 'expected a count badge "$badge" for ${cat.title}',
        );
        // The example-tools line (curated, joined by " · ").
        if (cat.exampleToolTitles.isNotEmpty) {
          expect(
            find.text(cat.exampleToolTitles.join(' · ')),
            findsOneWidget,
            reason: 'expected the example line for ${cat.title}',
          );
        }
      }
    });
  });

  testWidgets('no NEW pill renders anywhere in this build', (tester) async {
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      // Keith (2026-06-03): isNew is false on everything; the NEW pill capability
      // exists but must not render now.
      expect(find.text('NEW'), findsNothing);
      // And no category in the catalog is flagged new in this build.
      expect(kToolCategories.any((ToolCategory c) => c.isNew), isFalse);
    });
  });

  testWidgets('the grid renders one tile per catalog category', (tester) async {
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      for (final ToolCategory cat in kToolCategories) {
        expect(find.text(cat.title), findsOneWidget);
      }
    });
  });

  // The tile grid must use WIDTH-BASED breakpoints (not platform detection) so a
  // Mac window resized narrow reflows back to 2/1 columns exactly like a phone.
  // gridCrossAxisCountFor: <440 → 1, ≥440 → 2, ≥720 → 3, ≥1100 → 4.
  for (final ({double width, int columns}) c in <({double width, int columns})>[
    (width: 320, columns: 1), // phone (single column)
    (width: 390, columns: 1), // phone (single column)
    (width: 440, columns: 2), // 2-column lower bound
    (width: 680, columns: 2), // old content cap — still 2-up
    (width: 720, columns: 3), // 3-column lower bound (was unreachable pre-fix)
    (width: 820, columns: 3), // mid desktop / large iPad — 3-up
    (width: 1100, columns: 4), // 4-column lower bound
    (width: 1280, columns: 4), // wide desktop — 4-up (grid cap)
    (width: 1600, columns: 4), // ultrawide — capped at 4, no 5th column
  ]) {
    testWidgets(
      'the tile grid shows ${c.columns} column(s) at ${c.width.toInt()}px wide',
      (tester) async {
        await _withViewport(tester, Size(c.width, 1200), () async {
          await tester.pumpWidget(_app());
          await tester.pumpAndSettle();

          final SliverGrid grid = tester.widget<SliverGrid>(
            find.byType(SliverGrid),
          );
          final delegate =
              grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
          expect(
            delegate.crossAxisCount,
            c.columns,
            reason: 'expected ${c.columns} grid column(s) at ${c.width.toInt()}px',
          );
        });
      },
    );
  }

  for (final Size size in <Size>[
    const Size(320, 900),
    const Size(375, 900),
    const Size(390, 900),
    const Size(440, 900), // 2-column lower bound (IA-redesign density gate)
    const Size(680, 900), // content-cap width, 2-column
    const Size(768, 1100),
    const Size(820, 1100), // 3-column desktop / large iPad
    const Size(1280, 1100), // 4-column wide desktop
    const Size(1440, 1100),
  ]) {
    testWidgets(
      'no RenderFlex overflow at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await _withViewport(tester, size, () async {
          final List<Object> overflows = <Object>[];
          final FlutterExceptionHandler? previous = FlutterError.onError;
          FlutterError.onError = (FlutterErrorDetails details) {
            final String s = details.exception.toString();
            if (s.contains('overflowed')) {
              overflows.add(details.exception);
            } else {
              previous?.call(details);
            }
          };
          addTearDown(() => FlutterError.onError = previous);

          await tester.pumpWidget(_app());
          await tester.pumpAndSettle();

          expect(
            overflows,
            isEmpty,
            reason: 'overflow at ${size.width.toInt()}x${size.height.toInt()}: '
                '${overflows.join("; ")}',
          );
        });
      },
    );
  }
}
