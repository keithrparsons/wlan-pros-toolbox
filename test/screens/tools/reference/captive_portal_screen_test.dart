// Connected, No Internet: Captive Portals: wiring + screen tests.
//
// Guards:
//  (a) the catalog / route / keyword / help wiring for `captive-portal`
//      (Wi-Fi Classroom, Guided Lessons shelf, guide content type);
//  (b) the lesson renders every section header in dark and light, and on a
//      phone-width screen without overflow;
//  (c) the step-through: Back and Reset disabled at the start, Step disabled
//      at the end, the switch changes the reply at the check step, and the
//      Wi-Fi Calling line only changes at the sign-in.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/content_type.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/captive_portal_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<String> _sectionTitles = <String>[
  'The short answer',
  'Step through it',
  'Two ways to say sign in first',
  'Why Wi-Fi Calling waits for the sign-in',
  'In a hotel, an airport or on a plane',
  'Where these facts come from',
];

Widget _harness({required bool light}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: const CaptivePortalScreen(),
);

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'captive-portal');

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((Widget w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label)).onPressed != null;

Future<void> _bringWalkthroughIntoView(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Step 1 of 5: Association'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  // Centered, so the button is never left under the app bar.
  await Scrollable.ensureVisible(
    tester.element(_button(label)),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
  await tester.tap(_button(label));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  group('catalog + route + keyword + help wiring', () {
    test('the id is a live Guided Lesson in Wi-Fi Classroom', () {
      final ToolEntry entry = _entry();
      expect(entry.title, kCaptivePortalTitle);
      expect(entry.routeName, '/tools/captive-portal');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guided Lessons');
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'captive-portal'),
      );
      expect(cat.id, 'wifi-classroom');
      expect(contentTypeFor(entry, cat.id), ContentType.guide);
    });

    test('the route is registered and follows /tools/<id>', () {
      expect(AppRouter.routes.containsKey(AppRouter.captivePortal), isTrue);
      expect(AppRouter.captivePortal, '/tools/captive-portal');
      expect(kCaptivePortalToolId, 'captive-portal');
    });

    test('search keywords are registered', () {
      expect(
        kToolKeywords['captive-portal'],
        containsAll(<String>['captive portal', 'hotel wi-fi', 'wi-fi calling']),
      );
    });

    test('the help entry exists', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      expect(store.forId('captive-portal')?.name, kCaptivePortalTitle);
    });
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets('every section header renders (${light ? 'light' : 'dark'})', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_harness(light: light));
      await tester.pumpAndSettle();
      expect(find.text(kCaptivePortalTitle), findsOneWidget);
      for (final String title in _sectionTitles) {
        await tester.scrollUntilVisible(
          find.text(title),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(title), findsOneWidget, reason: title);
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
    await tester.pumpWidget(_harness(light: false));
    await _bringWalkthroughIntoView(tester);
    for (int i = 0; i < 4; i++) {
      await _press(tester, 'Step');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('step-through: buttons, switch, and the Wi-Fi Calling line', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness(light: false));
    await _bringWalkthroughIntoView(tester);

    expect(_enabled(tester, 'Back'), isFalse);
    expect(_enabled(tester, 'Reset'), isFalse);
    expect(_enabled(tester, 'Step'), isTrue);
    expect(find.text('Wi-Fi link up'), findsOneWidget);
    expect(find.text('Held'), findsOneWidget);

    // Step 2, announced: option 114 in the address reply.
    await _press(tester, 'Step');
    expect(find.text('Step 2 of 5: Get an address'), findsOneWidget);
    expect(find.text('Portal announced'), findsOneWidget);

    // Step 3, announced: a straight answer, nothing intercepted.
    await _press(tester, 'Step');
    expect(find.text('Step 3 of 5: Ask the network'), findsOneWidget);
    expect(find.text('Intercepted'), findsNothing);

    // Flip the switch at the same step: the probe comes back as the page.
    await Scrollable.ensureVisible(
      tester.element(find.text('Intercepts')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intercepts'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 5: Probe'), findsOneWidget);
    expect(find.text('Intercepted'), findsOneWidget);
    expect(find.textContaining('Waits for the sign-in'), findsOneWidget);

    // Step 4: the sign-in opens the internet, and Wi-Fi Calling can connect.
    await _press(tester, 'Step');
    expect(find.text('Step 4 of 5: Sign in'), findsOneWidget);
    expect(find.textContaining('Can connect'), findsOneWidget);
    expect(find.text('Open'), findsWidgets);

    await _press(tester, 'Step');
    expect(find.text('Step 5 of 5: Online'), findsOneWidget);
    expect(_enabled(tester, 'Step'), isFalse);

    await _press(tester, 'Reset');
    expect(find.text('Step 1 of 5: Association'), findsOneWidget);
    expect(_enabled(tester, 'Back'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
