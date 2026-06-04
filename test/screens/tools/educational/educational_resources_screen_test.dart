// EducationalResourcesScreen widget tests — the directory list groups by topic,
// renders rows (title + summary), filters live on search, shows the no-match
// state, and renders the destinations attribution ONLY under destination topic
// groups (never on the canonical tools/vendor-doc groups). A pre-built service
// is injected so the tests do not depend on the bundled asset load.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    ],
    "attribution": "Inspired by wlan-talks.net by Victor Njoroge.",
    "attribution_scope": "destinations only"
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

EducationalResourcesService _svc() =>
    EducationalResourcesService.fromJson(_fixture);

Widget _harness(EducationalResourcesService svc) => MaterialApp(
      theme: AppTheme.dark(),
      home: EducationalResourcesScreen(service: svc),
    );

void main() {
  testWidgets('renders topic group headers and resource rows', (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    // Both topic headers present.
    expect(find.text('Tools and utilities'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);

    // Rows: title + summary.
    expect(find.text('Alpha Tool'), findsOneWidget);
    expect(find.text('A handy tool.'), findsOneWidget);
    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('A Wi-Fi podcast.'), findsOneWidget);
  });

  testWidgets('shows the destinations credit only under destination groups',
      (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    // The credit text appears exactly once — under "Podcasts" (a destination
    // topic), NOT under "Tools and utilities" (a canonical bucket).
    expect(
      find.text('Inspired by wlan-talks.net by Victor Njoroge.'),
      findsOneWidget,
    );
  });

  testWidgets('live search filters rows and collapses empty groups',
      (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'podcast');
    await tester.pump();

    // Only the podcast survives; the tool and its group header are gone.
    expect(find.text('Beta Podcast'), findsOneWidget);
    expect(find.text('Alpha Tool'), findsNothing);
    expect(find.text('Tools and utilities'), findsNothing);
    expect(find.text('Podcasts'), findsOneWidget);
  });

  testWidgets('shows the honest no-match state when nothing matches',
      (tester) async {
    await tester.pumpWidget(_harness(_svc()));
    await tester.pump();

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
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(_harness(svc));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });
}
