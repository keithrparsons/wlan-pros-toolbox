// Why the TV and the Printer Vanish on Guest Wi-Fi: wiring + screen tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for `guest-discovery`
//      (Wi-Fi Classroom, Guided Lessons shelf, guide content type);
//  (b) every section header renders in dark and light, and the step-through
//      lays out at a phone width without overflow;
//  (c) the step-through: the question stops at the router on the guest
//      network and at the access point with isolation, and the list shows
//      the TV and the printer only on the same network;
//  (d) no product name appears anywhere on the screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/content_type.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/guest_discovery_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';

const List<String> _sectionTitles = <String>[
  'The short answer',
  'Step through it',
  'Why the question stays local',
  'Two ways a network keeps devices apart',
  'What to do about it',
  'Where these facts come from',
];

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const GuestDiscoveryScreen(),
);

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'guest-discovery');

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label)).onPressed != null;

Future<void> _center(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  await _center(tester, _button(label));
  await tester.tap(_button(label));
  await tester.pumpAndSettle();
}

/// A segment of the switch. Scoped to the toggle: the hop rows and the
/// section 4 cards share words like Guest network.
Finder _segment(String label) => find.descendant(
  of: find.byWidgetPredicate((Widget w) => w is AppToggle),
  matching: find.text(label),
);

Future<void> _pick(WidgetTester tester, String segment) async {
  await _center(tester, _segment(segment));
  await tester.tap(_segment(segment));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(_harness(light: false));
  await tester.scrollUntilVisible(
    find.text('Step 1 of 3: The phone asks'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, kGuestDiscoveryTitle);
      expect(entry.routeName, '/tools/guest-discovery');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'guest-discovery'),
      );
      expect(cat.id, 'wifi-classroom');
      expect(contentTypeFor(entry, cat.id), ContentType.guide);
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(AppRouter.routes.containsKey(AppRouter.guestDiscovery), isTrue);
      expect(AppRouter.guestDiscovery, '/tools/guest-discovery');
      expect(kGuestDiscoveryToolId, 'guest-discovery');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['guest-discovery'],
        containsAll(<String>['guest network', 'mdns', 'client isolation']),
      );
    });

    test('the help entry exists and names no product', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(store.forId('guest-discovery')?.name, kGuestDiscoveryTitle);
      final String raw = await rootBundle.loadString(
        'assets/help/tool_help.json',
      );
      final int start = raw.indexOf('"guest-discovery": {');
      final String entry = raw.substring(start, raw.indexOf('\n    },', start));
      expect(
        RegExp(
          r'AirPlay|AirPrint|Bonjour|Chromecast|Apple|Google',
        ).hasMatch(entry),
        isFalse,
      );
    });
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('every section header renders, and no product is named '
        '(${light ? 'light' : 'dark'})', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(light: light));
      await tester.pumpAndSettle();
      expect(find.text(kGuestDiscoveryTitle), findsOneWidget);
      final RegExp banned = RegExp(
        r'AirPlay|AirPrint|Bonjour|Chromecast|Apple|Google',
      );
      for (final String title in _sectionTitles) {
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(title), findsOneWidget, reason: title);
        for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
          final String s = t.data ?? t.textSpan?.toPlainText() ?? '';
          expect(banned.hasMatch(s), isFalse, reason: s);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone width: the step-through lays out without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);
    for (final String mode in <String>['Same', 'Guest', 'Isolation']) {
      await _pick(tester, mode);
      await _press(tester, 'Step');
      await _press(tester, 'Step');
      expect(tester.takeException(), isNull, reason: mode);
      await _press(tester, 'Reset');
    }
  });

  testWidgets('step-through: where the question stops, and what is found', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester);

    expect(_enabled(tester, 'Back'), isFalse);
    expect(_enabled(tester, 'Reset'), isFalse);
    expect(find.textContaining('224.0.0.251'), findsWidgets);

    // Guest network (the default): stops at the router.
    await _press(tester, 'Step');
    expect(find.text('Step 2 of 3: Where the question goes'), findsOneWidget);
    expect(find.text('The question stops here'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Router, Between the two networks: Stops it here'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('The TV, Main network: Never heard it'),
      findsOneWidget,
    );

    // Isolation at the same step: stops at the access point.
    await _pick(tester, 'Isolation');
    expect(
      find.bySemanticsLabel(
        'Access point, Main network, client isolation on: Stops it here',
      ),
      findsOneWidget,
    );

    await _press(tester, 'Step');
    expect(
      find.text("Step 3 of 3: What the phone's list shows"),
      findsOneWidget,
    );
    expect(find.text('Nothing found'), findsOneWidget);
    expect(_enabled(tester, 'Step'), isFalse);

    // Same network: both answer and both show up.
    await _pick(tester, 'Same');
    expect(find.text('Nothing found'), findsNothing);
    expect(find.text('The question stops here'), findsNothing);
    expect(
      find.bySemanticsLabel('The printer, Main network: Heard it and answered'),
      findsOneWidget,
    );

    await _press(tester, 'Reset');
    expect(find.text('Step 1 of 3: The phone asks'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
