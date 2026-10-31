// My Tools widgets: the home section appears only when the list is non-empty
// and sits directly under the Check My Connection hero; the star toggles with
// a state-stating label; the eleventh add opens the list-is-full dialog;
// Edit mode reorders (drag and the non-drag buttons), removes, and clears all
// behind a confirmation; long-press on a tool row adds and removes; so do a
// right-click and the context-menu key (Shift-F10) on a focused row.

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_controller.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_star_button.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/screens/search_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

final List<ToolEntry> _tools = <ToolEntry>[
  for (final ToolCategory c in kToolCategories) ...c.tools,
];

Future<void> _pump(
  WidgetTester tester,
  MyToolsController controller,
  Widget home, {
  Size size = const Size(800, 1400),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MyToolsScope(
      controller: controller,
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: home,
        // Any named route resolves to a stub, so a tile tap is observable.
        onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
          settings: s,
          builder: (_) => Scaffold(body: Text('route:${s.name}')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<MyToolsController> _filled(int n) async {
  final MyToolsController c = MyToolsController();
  for (int i = 0; i < n; i++) {
    await c.add(_tools[i].id);
  }
  return c;
}

Widget _starScreen(ToolEntry tool) => Scaffold(
  appBar: AppBar(
    title: Text(tool.title),
    actions: <Widget>[MyToolsStarButton(toolId: tool.id)],
  ),
  body: const SizedBox.shrink(),
);

final Finder _section = find.byKey(const ValueKey<String>('my-tools-section'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('home section', () {
    testWidgets('absent while the list is empty: home is unchanged', (
      WidgetTester tester,
    ) async {
      await _pump(tester, MyToolsController(), const HomeScreen());
      expect(_section, findsNothing);
      expect(find.text('My Tools'), findsNothing);
    });

    testWidgets('appears with the first tool, directly under the hero and '
        'above the search field', (WidgetTester tester) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, const HomeScreen());
      await c.add(_tools[0].id);
      await tester.pumpAndSettle();

      expect(_section, findsOneWidget);
      expect(find.text('My Tools'), findsOneWidget);
      final double heroBottom = tester
          .getBottomLeft(find.text('Check My Connection'))
          .dy;
      final double sectionTop = tester.getTopLeft(_section).dy;
      final double searchTop = tester
          .getTopLeft(find.text('Search all tools…'))
          .dy;
      expect(sectionTop, greaterThan(heroBottom));
      expect(searchTop, greaterThan(tester.getBottomLeft(_section).dy));
    });

    testWidgets('disappears when the last tool is removed', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = await _filled(1);
      await _pump(tester, c, const HomeScreen());
      expect(_section, findsOneWidget);
      await c.remove(_tools[0].id);
      await tester.pumpAndSettle();
      expect(_section, findsNothing);
    });

    testWidgets('shows tools in list order and a tap opens the tool route', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = await _filled(3);
      await c.reorder(2, 0);
      await _pump(tester, c, const HomeScreen());
      final List<double> ys = <double>[
        for (final String id in c.ids)
          tester
              .getTopLeft(find.byKey(ValueKey<String>('my-tools-tile-$id')))
              .dy,
      ];
      // Two columns: list order runs left to right, then down.
      expect(ys[0], ys[1]);
      expect(ys[2], greaterThan(ys[0]));

      await tester.tap(
        find.byKey(ValueKey<String>('my-tools-tile-${c.ids.first}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('route:${_tools[2].routeName}'), findsOneWidget);
    });

    const List<String> longNames = <String>[
      'interferer-cost',
      'mesh-extenders-explained',
      'down-the-stack',
      'guest-discovery',
      'box-vs-hand',
      'location-rssi-ftm',
      'cameras-doorbells-explained',
      'devices-to-internet-explained',
      'wpa2-password',
      'db-rules',
    ];

    for (final double width in <double>[320, 375, 440, 1280]) {
      testWidgets('view mode is two columns at $width wide, and the ten '
          'longest names fit without overflow, in view and edit mode', (
        WidgetTester tester,
      ) async {
        for (final ThemeData theme in <ThemeData>[
          AppTheme.dark(),
          AppTheme.light(),
        ]) {
          final MyToolsController c = MyToolsController();
          for (final String id in longNames) {
            expect(await c.add(id), MyToolsAddResult.added, reason: id);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await _pump(
            tester,
            c,
            const HomeScreen(),
            size: Size(width, 2400),
            theme: theme,
          );
          expect(tester.takeException(), isNull);
          for (int i = 0; i < 10; i += 2) {
            final Rect a = tester.getRect(
              find.byKey(ValueKey<String>('my-tools-tile-${c.ids[i]}')),
            );
            final Rect b = tester.getRect(
              find.byKey(ValueKey<String>('my-tools-tile-${c.ids[i + 1]}')),
            );
            expect(a.top, b.top, reason: 'pair $i shares a row');
            expect(a.height, b.height, reason: 'pair $i is equal height');
            expect(a.right, lessThan(b.left));
          }
          // Titles wrap to at most two lines, then ellipsize.
          for (final Text t in tester.widgetList<Text>(
            find.descendant(of: _section, matching: find.byType(Text)),
          )) {
            if (t.data == 'My Tools' || t.data == 'Edit') continue;
            expect(t.maxLines, 2);
            expect(t.overflow, TextOverflow.ellipsis);
          }
          // Edit mode with the same long names: no overflow either (Vera's
          // advisory raised the row's right padding to AppSpacing.xs).
          await tester.tap(find.byKey(const ValueKey<String>('my-tools-edit')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }

    for (final double width in <double>[320, 375, 440, 1280]) {
      testWidgets('ten tools lay out without overflow at $width wide, view '
          'and edit mode, dark and light', (WidgetTester tester) async {
        for (final ThemeData theme in <ThemeData>[
          AppTheme.dark(),
          AppTheme.light(),
        ]) {
          final MyToolsController c = await _filled(10);
          await tester.pumpWidget(const SizedBox.shrink());
          await _pump(
            tester,
            c,
            const HomeScreen(),
            size: Size(width, 2400),
            theme: theme,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey<String>('my-tools-edit')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  group('star button', () {
    testWidgets('toggles with a label that states the action', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final MyToolsController c = MyToolsController();
      final ToolEntry tool = _tools[0];
      await _pump(tester, c, _starScreen(tool));

      expect(find.bySemanticsLabel('Add to My Tools'), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey<String>('my-tools-star-${tool.id}')),
      );
      await tester.pumpAndSettle();
      expect(c.ids, <String>[tool.id]);
      expect(find.bySemanticsLabel('Remove from My Tools'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('Added ${tool.title} to My Tools'), findsOneWidget);

      await tester.tap(
        find.byKey(ValueKey<String>('my-tools-star-${tool.id}')),
      );
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      expect(find.bySemanticsLabel('Add to My Tools'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('meets the 48dp target', (WidgetTester tester) async {
      final ToolEntry tool = _tools[0];
      await _pump(tester, MyToolsController(), _starScreen(tool));
      final Size s = tester.getSize(
        find.byKey(ValueKey<String>('my-tools-star-${tool.id}')),
      );
      expect(s.width, greaterThanOrEqualTo(48));
      expect(s.height, greaterThanOrEqualTo(48));
    });

    testWidgets('renders nothing without a scope or for an unknown id', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: _starScreen(_tools[0])));
      expect(find.byType(IconButton), findsNothing);
      await _pump(
        tester,
        MyToolsController(),
        const Scaffold(body: MyToolsStarButton(toolId: 'no-such-tool')),
      );
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('list is full', () {
    testWidgets('the eleventh star asks which to replace; picking one '
        'replaces it in place', (WidgetTester tester) async {
      final MyToolsController c = await _filled(10);
      final ToolEntry incoming = _tools[10];
      await _pump(tester, c, _starScreen(incoming));

      await tester.tap(
        find.byKey(ValueKey<String>('my-tools-star-${incoming.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('My Tools is full'), findsOneWidget);
      for (int i = 0; i < 10; i++) {
        expect(
          find.byKey(ValueKey<String>('replace-${_tools[i].id}')),
          findsOneWidget,
        );
      }

      await tester.tap(find.byKey(ValueKey<String>('replace-${_tools[4].id}')));
      await tester.pumpAndSettle();
      expect(find.text('My Tools is full'), findsNothing);
      expect(c.length, 10);
      expect(c.ids[4], incoming.id);
      expect(c.contains(_tools[4].id), isFalse);
      expect(
        find.text('Replaced ${_tools[4].title} with ${incoming.title}'),
        findsOneWidget,
      );
    });

    testWidgets('cancel changes nothing', (WidgetTester tester) async {
      final MyToolsController c = await _filled(10);
      final List<String> before = c.ids;
      final ToolEntry incoming = _tools[10];
      await _pump(tester, c, _starScreen(incoming));
      await tester.tap(
        find.byKey(ValueKey<String>('my-tools-star-${incoming.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('My Tools is full'), findsNothing);
      expect(c.ids, before);
    });
  });

  group('edit mode', () {
    Future<MyToolsController> openEdit(WidgetTester tester, int n) async {
      final MyToolsController c = await _filled(n);
      await _pump(tester, c, const HomeScreen());
      await tester.tap(find.byKey(const ValueKey<String>('my-tools-edit')));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('move up / move down reorder without dragging', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final MyToolsController c = await openEdit(tester, 3);
      final String a = _tools[0].id;
      final String b = _tools[1].id;

      expect(
        find.bySemanticsLabel('Move ${_tools[0].title} down'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey<String>('my-tools-down-$a')));
      await tester.pumpAndSettle();
      expect(c.ids.take(2), <String>[b, a]);

      await tester.tap(find.byKey(ValueKey<String>('my-tools-up-$a')));
      await tester.pumpAndSettle();
      expect(c.ids.take(2), <String>[a, b]);

      // Ends are disabled, not hidden.
      final IconButton firstUp = tester.widget(
        find.byKey(ValueKey<String>('my-tools-up-$a')),
      );
      expect(firstUp.onPressed, isNull);
      handle.dispose();
    });

    testWidgets('drag by the handle reorders', (WidgetTester tester) async {
      final MyToolsController c = await openEdit(tester, 3);
      final String first = c.ids.first;
      final Finder handle = find.descendant(
        of: find.byKey(ValueKey<String>('my-tools-edit-$first')),
        matching: find.byIcon(Icons.drag_indicator),
      );
      final TestGesture g = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 16));
      for (int i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(c.ids.first, isNot(first));
      expect(c.ids, contains(first));
    });

    testWidgets('remove takes a tool out', (WidgetTester tester) async {
      final MyToolsController c = await openEdit(tester, 2);
      await tester.tap(
        find.byKey(ValueKey<String>('my-tools-remove-${_tools[0].id}')),
      );
      await tester.pumpAndSettle();
      expect(c.ids, <String>[_tools[1].id]);
    });

    testWidgets('Done returns to view mode', (WidgetTester tester) async {
      await openEdit(tester, 2);
      await tester.tap(find.byKey(const ValueKey<String>('my-tools-done')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('my-tools-edit-list')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('my-tools-edit')), findsOne);
    });

    testWidgets('Clear all asks first, and cancel keeps the list', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = await openEdit(tester, 10);
      await tester.tap(
        find.byKey(const ValueKey<String>('my-tools-clear-all')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove all 10 tools from My Tools?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.length, 10);
      expect(_section, findsOneWidget);
    });

    testWidgets('Clear all, confirmed, empties the list and the section '
        'disappears', (WidgetTester tester) async {
      final MyToolsController c = await openEdit(tester, 10);
      await tester.tap(
        find.byKey(const ValueKey<String>('my-tools-clear-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      expect(_section, findsNothing);
      expect(find.text('Cleared My Tools'), findsOneWidget);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(MyToolsController.prefsKey), isEmpty);

      // A later first add starts in view mode, not edit mode.
      await c.add(_tools[0].id);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('my-tools-edit')), findsOne);
    });
  });

  group('long-press on a tool row', () {
    Widget rows() => Scaffold(
      body: ListView(
        children: <Widget>[
          ToolRow(key: const ValueKey<String>('row0'), tool: _tools[0]),
        ],
      ),
    );

    testWidgets('adds, then removes, with a confirmation', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, rows());
      await tester.longPress(find.byKey(const ValueKey<String>('row0')));
      await tester.pumpAndSettle();
      expect(c.ids, <String>[_tools[0].id]);
      expect(find.text('Added ${_tools[0].title} to My Tools'), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey<String>('row0')));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
    });

    testWidgets('a tap still opens the tool, not My Tools', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, rows());
      await tester.tap(find.byKey(const ValueKey<String>('row0')));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      expect(find.text('route:${_tools[0].routeName}'), findsOneWidget);
    });

    testWidgets('screen readers get a named action and the row says when it '
        'is in My Tools', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, rows());
      final SemanticsNode node = tester.getSemantics(
        find.byKey(const ValueKey<String>('row0')),
      );
      final SemanticsData data = node.getSemanticsData();
      expect(data.customSemanticsActionIds, isNotEmpty);
      final CustomSemanticsAction action = CustomSemanticsAction.getAction(
        data.customSemanticsActionIds!.first,
      )!;
      expect(action.label, 'Add to My Tools');

      await c.add(_tools[0].id);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(const ValueKey<String>('row0'))).label,
        endsWith('In My Tools.'),
      );
      handle.dispose();
    });

    testWidgets('no scope, no long-press wiring and no custom action', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(home: rows()));
      final SemanticsData data = tester
          .getSemantics(find.byKey(const ValueKey<String>('row0')))
          .getSemanticsData();
      expect(data.customSemanticsActionIds ?? <int>[], isEmpty);
      final InkWell ink = tester.widget(
        find.descendant(
          of: find.byKey(const ValueKey<String>('row0')),
          matching: find.byType(InkWell),
        ),
      );
      expect(ink.onLongPress, isNull);
      handle.dispose();
    });
  });

  // Keith, 2026-10-31, on TestFlight 1.13.0: he could not find how to add a
  // tool. Press and hold has nothing on screen to show it, so each row shows
  // the star.
  group('star on a tool row', () {
    Widget rows() => Scaffold(
      body: ListView(
        children: <Widget>[
          ToolRow(key: const ValueKey<String>('row0'), tool: _tools[0]),
        ],
      ),
    );
    final Finder star = find.byKey(
      ValueKey<String>('my-tools-star-${_tools[0].id}'),
    );

    testWidgets('a tap on the star adds, then removes, without opening the '
        'tool', (WidgetTester tester) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, rows());
      expect(find.byIcon(Icons.star_border), findsOneWidget);

      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(c.ids, <String>[_tools[0].id]);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('route:${_tools[0].routeName}'), findsNothing);

      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
    });

    testWidgets('no scope, no star', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: rows()));
      expect(star, findsNothing);
    });
  });

  group('right-click and context-menu key on a tool row', () {
    Widget rows(ToolEntry tool) => Scaffold(
      body: ListView(
        children: <Widget>[
          ToolRow(key: const ValueKey<String>('row'), tool: tool),
        ],
      ),
    );
    final Finder row = find.byKey(const ValueKey<String>('row'));

    Future<void> rightClick(WidgetTester tester, Finder f) async {
      await tester.tap(f, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
    }

    /// Tabs until keyboard focus is inside [f]; fails if it never gets there.
    Future<void> tabTo(WidgetTester tester, Finder f) async {
      for (int i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final BuildContext? focused =
            FocusManager.instance.primaryFocus?.context;
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

    Future<void> contextMenuKey(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
    }

    Future<void> shiftF10(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('right-click adds, then removes, with a one-item menu', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      final ToolEntry tool = _tools[0];
      await _pump(tester, c, rows(tool));

      await rightClick(tester, row);
      expect(find.byType(PopupMenuItem<bool>), findsOneWidget);
      expect(find.text('Add to My Tools'), findsOneWidget);
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(c.ids, <String>[tool.id]);
      expect(find.text('Added ${tool.title} to My Tools'), findsOneWidget);

      await rightClick(tester, row);
      expect(find.byType(PopupMenuItem<bool>), findsOneWidget);
      expect(find.text('Remove from My Tools'), findsOneWidget);
      await tester.tap(find.text('Remove from My Tools'));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
      expect(find.text('Removed ${tool.title} from My Tools'), findsOneWidget);
    });

    testWidgets('right-click then dismissing the menu changes nothing', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, rows(_tools[0]));
      await rightClick(tester, row);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<bool>), findsNothing);
      expect(c.isEmpty, isTrue);
    });

    testWidgets('context-menu key on the Tab-focused row adds, then removes, '
        'all from the keyboard', (WidgetTester tester) async {
      final MyToolsController c = MyToolsController();
      final ToolEntry tool = _tools[0];
      await _pump(tester, c, rows(tool));
      await tabTo(tester, row);

      await contextMenuKey(tester);
      expect(find.text('Add to My Tools'), findsOneWidget);
      // Choose the item with the keyboard: arrow into the menu, then Enter.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.ids, <String>[tool.id]);

      await tabTo(tester, row);
      await contextMenuKey(tester);
      expect(find.text('Remove from My Tools'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
    });

    testWidgets('Shift-F10 on the focused row opens the same menu', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = MyToolsController();
      final ToolEntry tool = _tools[0];
      await _pump(tester, c, rows(tool));
      await tabTo(tester, row);
      await shiftF10(tester);
      expect(find.text('Add to My Tools'), findsOneWidget);
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(c.ids, <String>[tool.id]);

      await tabTo(tester, row);
      await shiftF10(tester);
      expect(find.text('Remove from My Tools'), findsOneWidget);
      await tester.tap(find.text('Remove from My Tools'));
      await tester.pumpAndSettle();
      expect(c.isEmpty, isTrue);
    });

    testWidgets('F10 without Shift opens nothing', (WidgetTester tester) async {
      await _pump(tester, MyToolsController(), rows(_tools[0]));
      await tabTo(tester, row);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<bool>), findsNothing);
    });

    testWidgets('right-click on a full list opens the replace dialog', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = await _filled(10);
      final ToolEntry incoming = _tools[10];
      await _pump(tester, c, rows(incoming));
      await rightClick(tester, row);
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(find.text('My Tools is full'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey<String>('replace-${_tools[2].id}')));
      await tester.pumpAndSettle();
      expect(c.length, 10);
      expect(c.ids[2], incoming.id);
      expect(
        find.text('Replaced ${_tools[2].title} with ${incoming.title}'),
        findsOneWidget,
      );
    });

    testWidgets('context-menu key on a full list opens the replace dialog', (
      WidgetTester tester,
    ) async {
      final MyToolsController c = await _filled(10);
      final List<String> before = c.ids;
      final ToolEntry incoming = _tools[10];
      await _pump(tester, c, rows(incoming));
      await tabTo(tester, row);
      await contextMenuKey(tester);
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(find.text('My Tools is full'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.ids, before);
    });

    testWidgets('works on the real category list', (WidgetTester tester) async {
      final MyToolsController c = MyToolsController();
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory k) => k.id == 'rf-calculators',
      );
      await _pump(tester, c, CategoryScreen(category: cat));
      final ToolRow first = tester
          .widgetList<ToolRow>(find.byType(ToolRow))
          .firstWhere((ToolRow r) => r.tool.isLive);
      await rightClick(tester, find.byWidget(first));
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(c.ids, <String>[first.tool.id]);
    });

    testWidgets('works on search results', (WidgetTester tester) async {
      final MyToolsController c = MyToolsController();
      await _pump(tester, c, const SearchScreen(initialQuery: 'channel'));
      final ToolRow first = tester
          .widgetList<ToolRow>(find.byType(ToolRow))
          .firstWhere((ToolRow r) => r.tool.isLive);
      await rightClick(tester, find.byWidget(first));
      await tester.tap(find.text('Add to My Tools'));
      await tester.pumpAndSettle();
      expect(c.ids, <String>[first.tool.id]);
    });

    testWidgets('no scope: right-click and the menu key open nothing', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: rows(_tools[0])));
      await rightClick(tester, row);
      expect(find.byType(PopupMenuItem<bool>), findsNothing);
      await tabTo(tester, row);
      await contextMenuKey(tester);
      expect(find.byType(PopupMenuItem<bool>), findsNothing);
    });
  });
}
