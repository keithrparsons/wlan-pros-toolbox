// Widget tests for the redesigned home tiles (Ticket 3, mockups 01/05).
//
// Covers: the search field is present and navigates; each tile shows the live
// tool-count badge and the example-tools line; NO NEW pill renders anywhere in
// this build (Keith, 2026-06-03 — nothing is new to a user yet); the grid
// renders all categories; no RenderFlex overflow at 320/375/768/1440.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
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
        // Resources pins '42' = 10 cards + 32 online resources), else the live
        // tool count.
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
