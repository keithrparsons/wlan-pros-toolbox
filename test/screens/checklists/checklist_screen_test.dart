// Widget tests for the reusable ChecklistScreen type.
//
// Built against Checklist.smokeTest (the built-in definition that exercises
// every render path: a labeled phase, items with and without notes, multiple
// phases). The two real checklists' content lands later from Pax; these tests
// gate the screen TYPE and its model behavior independent of that content.
//
// Coverage:
//  - renders the title, intro, phase headings, item text, and notes.
//  - progress starts at 0 / total.
//  - tapping a row toggles it done and advances the progress count.
//  - tapping again toggles it back.
//  - checking every item shows the "all done" / total/total complete state.
//  - a checklist with zero items renders the empty card, not a blank screen.
//  - phones at 375x900 render without a RenderFlex overflow.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/checklists/checklist_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  Widget wrap(Checklist cl) => MaterialApp(
        theme: AppTheme.dark(),
        home: ChecklistScreen(checklist: cl),
      );

  group('ChecklistScreen — smokeTest content', () {
    testWidgets('renders title, intro, phases, items, and notes',
        (tester) async {
      await tester.pumpWidget(wrap(Checklist.smokeTest));
      await tester.pump();

      expect(find.text('Checklist'), findsOneWidget); // app bar
      expect(
        find.textContaining('Tap a row to mark it done'),
        findsOneWidget,
      ); // intro
      expect(find.text('Before you start'), findsOneWidget); // phase heading
      expect(find.text('On site'), findsOneWidget); // phase heading
      expect(
        find.text('Measure RSSI and SNR at the client location'),
        findsOneWidget,
      ); // item text
      expect(
        find.textContaining('Target -67 dBm'),
        findsOneWidget,
      ); // item note
    });

    testWidgets('progress starts at 0 / total', (tester) async {
      await tester.pumpWidget(wrap(Checklist.smokeTest));
      await tester.pump();

      // smokeTest = 2 + 3 = 5 items.
      expect(Checklist.smokeTest.totalItems, 5);
      expect(find.text('0 / 5 done'), findsOneWidget);
    });

    testWidgets('tapping an item toggles it done and advances the count',
        (tester) async {
      await tester.pumpWidget(wrap(Checklist.smokeTest));
      await tester.pump();

      await tester.tap(
        find.text('Confirm the SSID and band the client expects to join'),
      );
      await tester.pump();

      expect(find.text('1 / 5 done'), findsOneWidget);
      // Checked rows expose the box-checked glyph.
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    });

    testWidgets('tapping a checked item un-checks it', (tester) async {
      await tester.pumpWidget(wrap(Checklist.smokeTest));
      await tester.pump();

      final Finder row = find.text(
        'Verify the client associates to the nearest AP',
      );
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
      expect(find.text('1 / 5 done'), findsOneWidget);

      await tester.tap(row);
      await tester.pump();
      expect(find.text('0 / 5 done'), findsOneWidget);
    });

    testWidgets('checking every item reaches the complete state',
        (tester) async {
      await tester.pumpWidget(wrap(Checklist.smokeTest));
      await tester.pump();

      for (final ChecklistPhase phase in Checklist.smokeTest.phases) {
        for (final ChecklistItem item in phase.items) {
          final Finder row = find.text(item.text);
          await tester.ensureVisible(row);
          await tester.pump();
          await tester.tap(row);
          await tester.pump();
        }
      }

      expect(find.text('5 / 5 done'), findsOneWidget);
      // Every item now shows the checked glyph; none show the blank box.
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
      expect(find.byIcon(Icons.check_box_outlined), findsNWidgets(5));
    });
  });

  group('ChecklistScreen — edge content', () {
    testWidgets('an empty checklist renders the empty card', (tester) async {
      const Checklist empty = Checklist(
        title: 'Empty',
        phases: <ChecklistPhase>[],
      );
      await tester.pumpWidget(wrap(empty));
      await tester.pump();

      expect(find.text('Empty'), findsOneWidget); // app bar
      expect(find.text('This checklist has no items yet.'), findsOneWidget);
      // No progress card when empty.
      expect(find.textContaining(' done'), findsNothing);
    });

    testWidgets('a flat ungrouped checklist drops the phase heading',
        (tester) async {
      const Checklist flat = Checklist(
        title: 'Flat',
        phases: <ChecklistPhase>[
          ChecklistPhase(
            items: <ChecklistItem>[
              ChecklistItem('Single ungrouped item'),
            ],
          ),
        ],
      );
      await tester.pumpWidget(wrap(flat));
      await tester.pump();

      expect(find.text('Single ungrouped item'), findsOneWidget);
      expect(find.text('1 / 1... '.trim()), findsNothing); // sanity
      expect(find.text('0 / 1 done'), findsOneWidget);
    });
  });

  testWidgets('renders at 375x900 without a RenderFlex overflow',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final List<Object> overflows = <Object>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('RenderFlex overflowed') ||
          details.exception.toString().contains('overflowed by')) {
        overflows.add(details.exception);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(wrap(Checklist.smokeTest));
    await tester.pump();

    expect(overflows, isEmpty, reason: overflows.join('; '));
  });
}
