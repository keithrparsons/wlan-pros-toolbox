// Widget tests for the consumer front-door home (Option A, 2026-06-03).
//
// Covers: the "Check My Connection" hero renders and routes to Test My
// Connection; the search field is present (now at the BOTTOM) and navigates;
// each tile shows the live tool-count badge and the example-tools line; NO NEW
// pill renders anywhere in this build (Keith, 2026-06-03 — nothing is new to a
// user yet); the grid renders all categories; no RenderFlex overflow at
// 320/375/768/1440.

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

  testWidgets('the "A Guide for Everyone" entry renders and opens the reader', (
    tester,
  ) async {
    // markdown_widget's VisibilityDetector leaves a pending timer otherwise.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    await _withViewport(tester, const Size(800, 1200), () async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // The compact home entry is present (Keith: small, near the front door).
      expect(find.text('New here? A Guide for Everyone'), findsOneWidget);
      expect(find.text('A plain-language tour of the app'), findsOneWidget);

      // Tapping it opens the in-app reader on the user guide.
      await tester.tap(find.text('New here? A Guide for Everyone'));
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

  for (final Size size in <Size>[
    const Size(320, 900),
    const Size(375, 900),
    const Size(390, 900),
    const Size(440, 900), // 2-column lower bound (IA-redesign density gate)
    const Size(680, 900), // content-cap width, 2-column
    const Size(768, 1100),
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
