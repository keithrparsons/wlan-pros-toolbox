// My Tools and Educational Resources (Keith, 2026-10-09: "yes, make them
// addable", after Ferney's beta report on build 26100490 that nothing in
// Educational Resources could be added).
//
// Every row kind in the directory adds through the shared flow: an online
// resource, the reference card (Ham Radio Study Resources, a catalog tool) and
// the Field Manual. Long-press, right-click and the context-menu key all work.
// A resource then shows on the home section with its title and a leading
// glyph, opens its detail screen, counts toward the ten, and removes, reorders
// and clears like a tool. Saved resource ids survive a resource list that has
// not loaded, and are dropped once it has loaded without them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_controller.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_item.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_section.dart';
import 'package:wlan_pros_toolbox/screens/guides/guide_reader_screen.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/educational_resource_detail_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/educational_resources_screen.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

final List<ToolEntry> _tools = <ToolEntry>[
  for (final ToolCategory c in kToolCategories) ...c.tools,
];

final ToolEntry _ham = _tools.firstWhere(
  (ToolEntry t) => t.id == 'ham-study-resources',
);

EducationalResource _resource(String id, String title, String topic) =>
    EducationalResource(
      id: id,
      title: title,
      summary: 'Summary of $title.',
      description: 'About $title.',
      url: 'https://example.com/$id',
      topic: topic,
      cost: ResourceCost.free,
      level: ResourceLevel.all,
      tags: const <String>[],
      approval: ResourceApproval.notRequired,
    );

final EducationalResource _blog = _resource(
  'test-blog',
  'Test Wi-Fi Blog',
  'Blogs',
);
final EducationalResource _podcast = _resource(
  'test-podcast',
  'Test Wi-Fi Podcast',
  'Podcasts',
);
final List<EducationalResource> _resources = <EducationalResource>[
  _blog,
  _podcast,
];

Future<void> _pump(
  WidgetTester tester,
  MyToolsController controller,
  Widget home, {
  Size size = const Size(800, 2000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MyToolsScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: home,
        onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
          settings: s,
          builder: (_) => Scaffold(body: Text('route:${s.name}')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _directory() => EducationalResourcesScreen(
  service: EducationalResourcesService.fromEntries(_resources),
  cards: <ToolEntry>[_ham],
);

Future<void> _rightClick(WidgetTester tester, Finder f) async {
  await tester.tap(f, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

/// Tabs until keyboard focus is inside [f]; fails if it never gets there.
Future<void> _tabTo(WidgetTester tester, Finder f) async {
  for (int i = 0; i < 30; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        find
            .descendant(of: f, matching: find.byWidget(focused.widget))
            .evaluate()
            .isNotEmpty) {
      return;
    }
  }
  fail('Tab never reached the row');
}

final Finder _section = find.byKey(const ValueKey<String>('my-tools-section'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MyToolsResources.instance.use(_resources);
  });
  tearDown(MyToolsResources.instance.reset);

  group('adding from Educational Resources', () {
    testWidgets('long-press on a resource adds it, and again removes it', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, _directory());

      await tester.longPress(find.text(_blog.title));
      await tester.pumpAndSettle();
      expect(c.ids, <String>['resource:test-blog']);
      expect(find.text('Added ${_blog.title} to My Tools'), findsOneWidget);

      await tester.longPress(find.text(_blog.title));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      expect(find.text('Removed ${_blog.title} from My Tools'), findsOneWidget);
    });

    testWidgets('long-press works in every topic, not just the first', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, _directory());
      await tester.longPress(find.text(_podcast.title));
      await tester.pumpAndSettle();
      expect(c.ids, <String>['resource:test-podcast']);
    });

    testWidgets('right-click on a resource opens the one-item menu', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, _directory());

      await _rightClick(tester, find.text(_blog.title));
      expect(find.byType(PopupMenuItem<bool>), findsOneWidget);
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(c.ids, <String>['resource:test-blog']);

      await _rightClick(tester, find.text(_blog.title));
      expect(find.text('Remove from My Tools'), findsOneWidget);
      await tester.tap(find.text('Remove from My Tools'));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
    });

    testWidgets('the context-menu key on a focused resource opens the menu', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, _directory());
      final Finder row = find.ancestor(
        of: find.text(_blog.title),
        matching: find.byType(InkWell),
      );
      await _tabTo(tester, row);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<bool>), findsOneWidget);
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(c.ids, <String>['resource:test-blog']);
    });

    testWidgets('the Field Manual and the reference card add too', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, _directory());

      await tester.longPress(find.text('Field Manual'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text(_ham.title));
      await tester.pumpAndSettle();
      expect(c.ids, <String>['guide:field-manual', 'ham-study-resources']);
    });

    testWidgets('a resource in My Tools says so to a screen reader', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await c.add(myToolsResourceId(_blog.id));
      await _pump(tester, c, _directory());
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'Test Wi-Fi Blog\..*In My Tools\.$')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('a resource in My Tools', () {
    testWidgets('shows beside a tool on the home section, with its title', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await c.add(_tools[0].id);
      await c.add(myToolsResourceId(_blog.id));
      await _pump(tester, c, const HomeScreen());

      expect(_section, findsOneWidget);
      expect(
        find.descendant(of: _section, matching: find.text(_tools[0].title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _section, matching: find.text(_blog.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _section, matching: find.byType(MyToolsItemIcon)),
        findsNWidgets(2),
      );
    });

    testWidgets('tapping it opens its detail screen', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await c.add(myToolsResourceId(_blog.id));
      await _pump(tester, c, const HomeScreen());

      await tester.tap(
        find.descendant(of: _section, matching: find.text(_blog.title)),
      );
      await tester.pumpAndSettle();
      final EducationalResourceDetailScreen detail = tester.widget(
        find.byType(EducationalResourceDetailScreen),
      );
      expect(detail.resource.id, _blog.id);
    });

    testWidgets('the Field Manual tile opens the Field Manual reader', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await c.add(kMyToolsFieldManualId);
      await _pump(tester, c, const HomeScreen());

      await tester.tap(
        find.descendant(of: _section, matching: find.text('Field Manual')),
      );
      // The reader keeps a spinner going while it loads the manual, so settle
      // by pumping the route transition rather than waiting for idle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final GuideReaderScreen reader = tester.widget(
        find.byType(GuideReaderScreen),
      );
      expect(reader.assetPath, kFieldManualAsset);
    });

    testWidgets('Remove in Edit mode takes it off', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await c.add(_tools[0].id);
      await c.add(myToolsResourceId(_blog.id));
      await _pump(tester, c, const HomeScreen());

      await tester.tap(find.byKey(const ValueKey<String>('my-tools-edit')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('my-tools-remove-resource:test-blog'),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.ids, <String>[_tools[0].id]);
    });

    testWidgets('Move up in Edit mode reorders it ahead of a tool', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await c.add(_tools[0].id);
      await c.add(myToolsResourceId(_blog.id));
      await _pump(tester, c, const HomeScreen());

      await tester.tap(find.byKey(const ValueKey<String>('my-tools-edit')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('my-tools-up-resource:test-blog')),
      );
      await tester.pumpAndSettle();
      expect(c.ids, <String>['resource:test-blog', _tools[0].id]);
    });

    testWidgets('Clear all clears resources too', (WidgetTester tester) async {
      final MyToolsController c = MyToolsController();
      await c.add(_tools[0].id);
      await c.add(myToolsResourceId(_blog.id));
      await _pump(tester, c, const HomeScreen());

      await tester.tap(find.byKey(const ValueKey<String>('my-tools-edit')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('my-tools-clear-all')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove all 2 tools from My Tools?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      expect(_section, findsNothing);
    });

    testWidgets('it counts toward the ten: the eleventh asks to replace', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      for (int i = 0; i < 9; i++) {
        await c.add(_tools[i].id);
      }
      await c.add(myToolsResourceId(_podcast.id));
      expect(c.isFull, isTrue);
      await _pump(tester, c, _directory());

      await tester.longPress(find.text(_blog.title));
      await tester.pumpAndSettle();
      expect(find.text('My Tools is full'), findsOneWidget);
      // The resource already in the list is offered for replacement too.
      expect(
        find.byKey(const ValueKey<String>('replace-resource:test-podcast')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('replace-resource:test-podcast')),
      );
      await tester.pumpAndSettle();
      expect(c.length, MyToolsController.maxTools);
      expect(c.ids.last, 'resource:test-blog');
      expect(c.contains('resource:test-podcast'), isFalse);
      expect(
        find.text('Replaced ${_podcast.title} with ${_blog.title}'),
        findsOneWidget,
      );
    });
  });

  group('stored ids', () {
    test(
      'a saved resource survives a resource list that has not loaded',
      () async {
        MyToolsResources.instance.reset();
        SharedPreferences.setMockInitialValues(<String, Object>{
          MyToolsController.prefsKey: <String>[
            _tools[0].id,
            'resource:test-blog',
          ],
        });
        final MyToolsController c = MyToolsController();
        await c.load();
        expect(c.ids, <String>[_tools[0].id, 'resource:test-blog']);
        // Not resolvable yet, so not shown; nothing is lost.
        expect(c.items.map((MyToolsItem i) => i.id), <String>[_tools[0].id]);
      },
    );

    test('a resource the build no longer carries is dropped on load', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MyToolsController.prefsKey: <String>[
          'resource:test-blog',
          'resource:retired-resource',
          'guide:field-manual',
        ],
      });
      final MyToolsController c = MyToolsController();
      await c.load();
      expect(c.ids, <String>['resource:test-blog', 'guide:field-manual']);
    });

    test(
      'bundled resource ids are unique and never collide with a tool id',
      () {
        final Map<String, dynamic> json =
            jsonDecode(
                  File(
                    'assets/data/educational_resources.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final List<String> resourceIds = <String>[
          for (final Object? r in json['resources'] as List<Object?>)
            (r! as Map<String, dynamic>)['id'] as String,
        ];
        expect(resourceIds.toSet().length, resourceIds.length);
        final Set<String> toolIds = <String>{
          for (final ToolEntry t in _tools) t.id,
          kMyToolsFieldManualId,
        };
        for (final String id in resourceIds) {
          expect(toolIds, isNot(contains(myToolsResourceId(id))));
          // The raw ids do not collide either, today.
          expect(toolIds, isNot(contains(id)));
        }
      },
    );
  });
}
