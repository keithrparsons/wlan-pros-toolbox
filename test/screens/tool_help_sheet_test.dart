// ToolHelpSheet widget tests.
//
// Coverage:
// - A full calculator-shaped entry renders every section heading present
//   (Purpose, Why it's in the toolbox, How to use, Inputs, Algorithm & formula,
//   Worked example, Field notes) and the verbatim field-note text (GL-005).
// - A reference-shaped entry (no inputs, null algorithm/example) SKIPS those
//   sections — the sheet shows only what the entry carries.
// - Section headings are exposed as Semantics headers (WCAG 1.3.1).
// - The copy affordance ("Copy help") is present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_sheet.dart';

const ToolHelp _calc = ToolHelp(
  id: 'fspl',
  name: 'Free Space Path Loss',
  category: 'Calculators & Tools',
  purpose: 'Computes the path loss between transmitter and receiver.',
  whyHere: 'The starting point of any link budget.',
  howToUse: <String>[
    'Enter the frequency and pick its unit.',
    'Enter the distance and pick its unit.',
    'Read the path loss in dB.',
  ],
  inputs: <ToolHelpInput>[
    ToolHelpInput(name: 'Frequency', unit: 'GHz', range: 'must be > 0'),
    ToolHelpInput(name: 'Distance', unit: 'km', range: 'must be > 0'),
  ],
  algorithm: 'FSPL(dB) = 20·log10(f) + 20·log10(d) + 92.45',
  example: '5 GHz, 1 km -> 106.4 dB.',
  topNotes: <String>['Read this before the numbers: it is a floor, not a truth.'],
  fieldNotes: <String>[
    'Free space only. Real-world links always lose more, so use this as a '
        'floor, not a prediction.',
  ],
  source: 'fspl_screen.dart',
);

const ToolHelp _reference = ToolHelp(
  id: 'wifi-channels',
  name: 'Wi-Fi Channels',
  category: 'Quick Reference',
  purpose: 'Lists channels, center frequencies, and widths by band.',
  whyHere: 'Look up a channel without leaving the field.',
  howToUse: <String>[],
  inputs: <ToolHelpInput>[],
  algorithm: null,
  example: null,
  topNotes: <String>[],
  fieldNotes: <String>['DFS channels may require radar avoidance.'],
  source: 'wifi_channels_screen.dart',
);

Future<void> _pumpSheet(WidgetTester tester, ToolHelp help) async {
  // Pump the sheet body directly (not via showModalBottomSheet) so the test
  // does not depend on a host route; the widget under test is ToolHelpSheet.
  tester.view.physicalSize = const Size(600, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: ToolHelpSheet(help: help)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders every section of a full calculator entry', (
    tester,
  ) async {
    await _pumpSheet(tester, _calc);

    expect(find.text('Free Space Path Loss'), findsOneWidget);
    expect(find.text('Purpose'), findsOneWidget);
    expect(find.text("Why it's in the toolbox"), findsOneWidget);
    expect(find.text('How to use'), findsOneWidget);
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Worked example'), findsOneWidget);
    expect(find.text('Field notes'), findsOneWidget);

    // Algorithm & formula is intentionally NOT rendered in the customer-facing
    // sheet, even when the entry carries algorithm data (it stays as internal
    // reference in the model/JSON only).
    expect(find.text('Algorithm & formula'), findsNothing);
    expect(
      find.textContaining('FSPL(dB) = 20'),
      findsNothing,
    );

    // The Close affordance lives at the top, reachable without scrolling.
    expect(find.bySemanticsLabel('Close help'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    // The input field names render.
    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);

    // The field-note caveat renders verbatim (GL-005).
    expect(
      find.textContaining('use this as a floor, not a prediction'),
      findsOneWidget,
    );

    // The §8.16 copy affordance is present (labelled "Copy help").
    expect(
      find.bySemanticsLabel('Copy help'),
      findsOneWidget,
    );
  });

  testWidgets(
      'lead topNotes render at the TOP — ABOVE the Purpose section — so the '
      'trust context is visible without scrolling', (tester) async {
    await _pumpSheet(tester, _calc);

    // The lead note renders verbatim...
    final Finder lead =
        find.textContaining('Read this before the numbers');
    expect(lead, findsOneWidget);
    // ...under a quiet "Read first" heading that is a real Semantics header, so
    // screen-reader heading navigation reaches the priority notes (WCAG 1.3.1).
    final Finder heading = find.text('Read first');
    expect(heading, findsOneWidget);
    final SemanticsHandle handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(heading),
      matchesSemantics(label: 'Read first', isHeader: true),
    );
    handle.dispose();
    // ...and the whole lead block sits ABOVE the Purpose heading (smaller dy =
    // higher on screen).
    final double leadY = tester.getTopLeft(lead).dy;
    final double headingY = tester.getTopLeft(heading).dy;
    final double purposeY = tester.getTopLeft(find.text('Purpose')).dy;
    expect(headingY, lessThan(purposeY));
    expect(
      leadY,
      lessThan(purposeY),
      reason: 'topNotes must render above Purpose (at the very top of the sheet)',
    );
  });

  test('the model carries topNotes as a distinct lead list, separate from '
      'fieldNotes (parsed from the JSON topNotes key)', () {
    // The lead list is populated and kept SEPARATE from the bottom field notes,
    // so the renderer + copy text can place it first without duplicating it.
    expect(_calc.topNotes, isNotEmpty);
    expect(_calc.topNotes.first, startsWith('Read this before the numbers'));
    expect(_calc.fieldNotes, isNotEmpty);
    expect(_calc.topNotes, isNot(equals(_calc.fieldNotes)));
  });

  testWidgets('skips inputs/algorithm/example for a reference entry', (
    tester,
  ) async {
    await _pumpSheet(tester, _reference);

    // Present sections.
    expect(find.text('Purpose'), findsOneWidget);
    expect(find.text("Why it's in the toolbox"), findsOneWidget);
    expect(find.text('Field notes'), findsOneWidget);

    // Skipped sections — no inputs, null algorithm/example, no how-to steps.
    expect(find.text('Inputs'), findsNothing);
    expect(find.text('Algorithm & formula'), findsNothing);
    expect(find.text('Worked example'), findsNothing);
    expect(find.text('How to use'), findsNothing);
  });

  testWidgets('section headings are exposed as accessibility headers', (
    tester,
  ) async {
    await _pumpSheet(tester, _calc);

    final SemanticsHandle handle = tester.ensureSemantics();
    // The Purpose heading carries the header flag (WCAG 1.3.1).
    expect(
      tester.getSemantics(find.text('Purpose')),
      matchesSemantics(label: 'Purpose', isHeader: true),
    );
    handle.dispose();
  });
}
