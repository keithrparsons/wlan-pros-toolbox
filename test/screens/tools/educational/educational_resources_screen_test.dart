// EducationalResourcesScreen widget tests — the directory renders a "Reference
// Cards" section at the top (from injected cards), then the online-resource
// topic groups; filter chips under the search switch between sections; free-text
// search collapses to matching online resources. A pre-built service and an
// explicit card list are injected so the tests do not depend on the bundled
// asset load or the live catalog. A tall viewport is used so all list rows are
// laid out (a ListView only builds on-screen children).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/educational_resources_screen.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "_meta": {
    "title": "Educational Resources",
    "topics": [
      "Tools and utilities",
      "Podcasts"
    ]
  },
  "resources": [
    {
      "id": "alpha-tool", "title": "Alpha Tool", "summary": "A handy tool.",
      "description": "Body.", "url": "https://example.com/tool",
      "topic": "Tools and utilities", "cost": "free", "level": "all",
      "tags": ["tool"], "approval": "pending_outreach"
    },
    {
      "id": "beta-pod", "title": "Beta Podcast", "summary": "A Wi-Fi podcast.",
      "description": "Body.", "url": "https://example.com/pod",
      "topic": "Podcasts", "cost": "free", "level": "all",
      "tags": ["destination", "podcast"], "approval": "pending_outreach"
    }
  ]
}
''';

const List<ToolEntry> _cards = <ToolEntry>[
  ToolEntry(
    id: 'bubble-diagram',
    title: 'WLAN Pros Bubble Diagram',
    description: 'Wi-Fi design decision bubble diagram',
    routeName: '/tools/bubble-diagram',
    isLive: true,
  ),
  ToolEntry(
    id: 'top-20-checklist',
    title: 'Top 20 Wi-Fi Checklist',
    description: 'The Top 20 Wi-Fi design checklist',
    routeName: '/tools/top-20-checklist',
    isLive: true,
  ),
];

EducationalResourcesService _svc() =>
    EducationalResourcesService.fromJson(_fixture);

/// Pump the screen on a tall viewport so the whole list is laid out (cards +
/// both topic groups all build), and reset it on teardown.
Future<void> _pump(WidgetTester tester, EducationalResourcesService svc) async {
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: EducationalResourcesScreen(service: svc, cards: _cards),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders the Reference Cards section header + a card title',
      (tester) async {
    await _pump(tester, _svc());

    // The Reference Cards section renders above the topic groups, with at least
    // one card title visible.
    expect(find.text('WLAN Pros Bubble Diagram'), findsOneWidget);
    expect(find.text('Top 20 Wi-Fi Checklist'), findsOneWidget);
    // The "Reference Cards" string appears in the section header AND the chip,
    // so it is present at least twice.
    expect(find.text('Reference Cards'), findsWidgets);
  });

  testWidgets('renders topic group headers and resource rows', (tester) async {
    await _pump(tester, _svc());

    // Resource rows: title + summary present.
    expect(find.text('Alpha Tool'), findsOneWidget);
    expect(find.text('A handy tool.'), findsOneWidget);
    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('A Wi-Fi podcast.'), findsOneWidget);
    // Topic strings render as a header AND a filter chip, so >= 1 each.
    expect(find.text('Tools and utilities'), findsWidgets);
    expect(find.text('Podcasts'), findsWidgets);
  });

  testWidgets('filter chips are present (All + Reference Cards + topics)',
      (tester) async {
    await _pump(tester, _svc());

    expect(find.text('All'), findsOneWidget);
    // Reference Cards + two topics each appear at least as a chip.
    expect(find.text('Reference Cards'), findsWidgets);
    expect(find.text('Tools and utilities'), findsWidgets);
    expect(find.text('Podcasts'), findsWidgets);
  });

  testWidgets('selecting the Reference Cards chip hides the online topics',
      (tester) async {
    await _pump(tester, _svc());

    // The chip renders above the section header, so `.first` is the chip.
    await tester.tap(find.text('Reference Cards').first);
    await tester.pump();

    // Cards still show; online resources are filtered out.
    expect(find.text('WLAN Pros Bubble Diagram'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('Beta Podcast'), findsNothing);
  });

  testWidgets('selecting a topic chip shows only that topic and hides cards',
      (tester) async {
    await _pump(tester, _svc());

    await tester.tap(find.text('Podcasts').first);
    await tester.pump();

    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    // Reference cards are hidden when a topic filter is active.
    expect(find.text('WLAN Pros Bubble Diagram'), findsNothing);
  });

  testWidgets('live search filters rows, hides cards + chips, collapses groups',
      (tester) async {
    await _pump(tester, _svc());

    await tester.enterText(find.byType(TextField), 'podcast');
    await tester.pump();

    // Only the matching online resource survives; the tool, its group header,
    // the cards, and the chips are all gone.
    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('WLAN Pros Bubble Diagram'), findsNothing);
    expect(find.text('All'), findsNothing); // chip row hidden while typing
    // "Podcasts" now only renders as the surviving group header.
    expect(find.text('Podcasts'), findsOneWidget);
  });

  testWidgets('shows the honest no-match state when nothing matches',
      (tester) async {
    await _pump(tester, _svc());

    await tester.enterText(find.byType(TextField), 'zzznotathing');
    await tester.pump();

    expect(find.textContaining('No resources match'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('Beta Podcast'), findsNothing);
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final EducationalResourcesService svc = _svc();
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 2000);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: EducationalResourcesScreen(service: svc, cards: _cards),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });
}
