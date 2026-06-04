// EducationalResourceDetailScreen widget tests — renders title/topic/badges/
// description/tags, the "Open website" button invokes the injected launcher with
// the EXACT resource url, the destinations credit shows only on a destination
// resource, and the AppCopyAction writes a plain-text payload carrying the
// metadata WORDS (cost/level) to the clipboard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/educational_resource_detail_screen.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const EducationalResource _destinationResource = EducationalResource(
  id: 'beta-pod',
  title: 'Beta Podcast',
  summary: 'A Wi-Fi podcast.',
  description: 'First paragraph.\n\nSecond paragraph.',
  url: 'https://example.com/pod',
  topic: 'Podcasts',
  cost: ResourceCost.free,
  level: ResourceLevel.all,
  tags: <String>['destination', 'podcast'],
  approval: ResourceApproval.pendingOutreach,
);

const EducationalResource _canonicalResource = EducationalResource(
  id: 'alpha-tool',
  title: 'Alpha Tool',
  summary: 'A handy tool.',
  description: 'Tool body.',
  url: 'https://example.com/tool',
  topic: 'Tools and utilities',
  cost: ResourceCost.mixed,
  level: ResourceLevel.intermediate,
  tags: <String>['tool'],
  approval: ResourceApproval.pendingOutreach,
);

Widget _harness(
  EducationalResource r, {
  Future<bool> Function(Uri url)? launcher,
}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: EducationalResourceDetailScreen(resource: r, launcher: launcher),
    );

void main() {
  testWidgets('renders title, topic, badges, description, and tags',
      (tester) async {
    await tester.pumpWidget(_harness(_destinationResource));
    await tester.pump();

    expect(find.text('Beta Podcast'), findsWidgets); // app bar + body title
    expect(find.text('Podcasts'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget); // cost badge word
    expect(find.text('All levels'), findsOneWidget); // level badge word
    expect(find.text('First paragraph.'), findsOneWidget);
    expect(find.text('Second paragraph.'), findsOneWidget);
    expect(find.text('podcast'), findsOneWidget); // tag chip
    expect(find.text('Open website'), findsOneWidget);
  });

  testWidgets('Open website invokes the launcher with the exact url',
      (tester) async {
    Uri? launched;
    await tester.pumpWidget(
      _harness(
        _destinationResource,
        launcher: (Uri u) async {
          launched = u;
          return true;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open website'));
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched.toString(), 'https://example.com/pod');
  });

  testWidgets('a failed launch surfaces an honest error with the link',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        _destinationResource,
        launcher: (Uri u) async => false,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open website'));
    await tester.pump();

    expect(find.textContaining('Could not open the browser'), findsOneWidget);
    expect(find.textContaining('https://example.com/pod'), findsOneWidget);
  });

  testWidgets('destinations credit shows on a destination resource',
      (tester) async {
    await tester.pumpWidget(_harness(_destinationResource));
    await tester.pump();
    expect(
      find.text('Inspired by wlan-talks.net by Victor Njoroge.'),
      findsOneWidget,
    );
  });

  testWidgets('destinations credit is absent on a canonical resource',
      (tester) async {
    await tester.pumpWidget(_harness(_canonicalResource));
    await tester.pump();
    expect(
      find.text('Inspired by wlan-talks.net by Victor Njoroge.'),
      findsNothing,
    );
  });

  testWidgets('copy action writes the metadata words to the clipboard',
      (tester) async {
    // Intercept the platform clipboard channel.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(_harness(_canonicalResource));
    await tester.pump();

    await tester.tap(find.byTooltip('Copy results'));
    await tester.pump();
    // AppCopyAction (§8.16) starts a 1.5s confirm-revert timer; let it elapse
    // so no Timer is pending when the widget tree is torn down.
    await tester.pump(const Duration(milliseconds: 1600));

    expect(copied, isNotNull);
    // Every metadata WORD survives to the clipboard (§8.16 content contract):
    expect(copied, contains('Alpha Tool'));
    expect(copied, contains('Topic: Tools and utilities'));
    expect(copied, contains('Cost: Free + paid')); // 'mixed' → worded
    expect(copied, contains('Level: Intermediate'));
    expect(copied, contains('https://example.com/tool'));
    expect(copied, contains('Tool body.'));
  });
}
