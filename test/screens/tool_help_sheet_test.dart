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
    expect(find.text('Algorithm & formula'), findsOneWidget);
    expect(find.text('Worked example'), findsOneWidget);
    expect(find.text('Field notes'), findsOneWidget);

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
