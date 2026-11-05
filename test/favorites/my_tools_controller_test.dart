// My Tools controller: add, remove, the ten cap, replace, reorder, the non-drag
// moves, clear-all, the persistence round trip, and silent pruning of ids the
// catalog no longer carries (spec: Deliverables/2026-10-03-toolbox-my-tools).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_controller.dart';

/// Real catalog ids, in catalog order, so the default (catalog) known-id check
/// is the one under test.
final List<String> _ids = <String>[
  for (final ToolCategory c in kToolCategories)
    for (final ToolEntry t in c.tools) t.id,
];

Future<List<String>?> _stored() async =>
    (await SharedPreferences.getInstance()).getStringList(
      MyToolsController.prefsKey,
    );

Future<MyToolsController> _filled(int n) async {
  final MyToolsController c = MyToolsController();
  for (int i = 0; i < n; i++) {
    expect(await c.add(_ids[i]), MyToolsAddResult.added);
  }
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the catalog has enough tools for these tests', () {
    expect(_ids.length, greaterThan(MyToolsController.maxTools + 2));
  });

  test('starts empty with nothing stored', () async {
    final MyToolsController c = MyToolsController();
    await c.load();
    expect(c.isEmpty, isTrue);
    expect(c.ids, isEmpty);
  });

  group('add', () {
    test('appends in order, persists, and notifies', () async {
      final MyToolsController c = MyToolsController();
      int notified = 0;
      c.addListener(() => notified++);
      expect(await c.add(_ids[0]), MyToolsAddResult.added);
      expect(await c.add(_ids[1]), MyToolsAddResult.added);
      expect(c.ids, <String>[_ids[0], _ids[1]]);
      expect(c.tools.map((ToolEntry t) => t.id), c.ids);
      expect(notified, 2);
      expect(await _stored(), <String>[_ids[0], _ids[1]]);
    });

    test('a duplicate changes nothing', () async {
      final MyToolsController c = await _filled(1);
      expect(await c.add(_ids[0]), MyToolsAddResult.alreadyPresent);
      expect(c.ids, <String>[_ids[0]]);
    });

    test('an id that is not in the catalog is refused', () async {
      final MyToolsController c = MyToolsController();
      expect(await c.add('no-such-tool'), MyToolsAddResult.unknown);
      expect(c.isEmpty, isTrue);
      expect(await _stored(), isNull);
    });
  });

  group('the ten cap', () {
    test('maxTools is ten', () {
      expect(MyToolsController.maxTools, 10);
    });

    test('the eleventh add reports full and changes nothing', () async {
      final MyToolsController c = await _filled(10);
      expect(c.isFull, isTrue);
      expect(await c.add(_ids[10]), MyToolsAddResult.full);
      expect(c.length, 10);
      expect(c.contains(_ids[10]), isFalse);
      expect((await _stored())!.length, 10);
    });

    test('a stored list longer than ten loads as its first ten', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MyToolsController.prefsKey: _ids.take(12).toList(),
      });
      final MyToolsController c = MyToolsController();
      await c.load();
      expect(c.ids, _ids.take(10).toList());
      expect(await _stored(), _ids.take(10).toList());
    });
  });

  group('replace', () {
    test('puts the new tool in the old one\'s position', () async {
      final MyToolsController c = await _filled(10);
      expect(await c.replace(_ids[3], _ids[10]), isTrue);
      expect(c.ids[3], _ids[10]);
      expect(c.contains(_ids[3]), isFalse);
      expect(c.length, 10);
      expect((await _stored())![3], _ids[10]);
    });

    test('refuses a missing old id, an unknown new id, or a duplicate', () async {
      final MyToolsController c = await _filled(3);
      final List<String> before = c.ids;
      expect(await c.replace(_ids[9], _ids[10]), isFalse);
      expect(await c.replace(_ids[0], 'no-such-tool'), isFalse);
      expect(await c.replace(_ids[0], _ids[1]), isFalse);
      expect(c.ids, before);
    });
  });

  group('remove', () {
    test('removes and persists', () async {
      final MyToolsController c = await _filled(3);
      expect(await c.remove(_ids[1]), isTrue);
      expect(c.ids, <String>[_ids[0], _ids[2]]);
      expect(await _stored(), <String>[_ids[0], _ids[2]]);
    });

    test('removing an absent id reports false and does not notify', () async {
      final MyToolsController c = await _filled(1);
      int notified = 0;
      c.addListener(() => notified++);
      expect(await c.remove(_ids[5]), isFalse);
      expect(notified, 0);
    });
  });

  group('reorder (final-index convention, onReorderItem)', () {
    test('moves an item down and up', () async {
      final MyToolsController c = await _filled(4);
      await c.reorder(0, 2);
      expect(c.ids, <String>[_ids[1], _ids[2], _ids[0], _ids[3]]);
      await c.reorder(3, 0);
      expect(c.ids, <String>[_ids[3], _ids[1], _ids[2], _ids[0]]);
      expect(await _stored(), c.ids);
    });

    test('out-of-range targets clamp; a bad source is ignored', () async {
      final MyToolsController c = await _filled(3);
      await c.reorder(0, 99);
      expect(c.ids, <String>[_ids[1], _ids[2], _ids[0]]);
      await c.reorder(7, 0);
      expect(c.ids, <String>[_ids[1], _ids[2], _ids[0]]);
    });

    test('moveUp / moveDown, the non-drag path, stop at the ends', () async {
      final MyToolsController c = await _filled(3);
      expect(await c.moveUp(_ids[0]), isFalse);
      expect(await c.moveDown(_ids[2]), isFalse);
      expect(await c.moveDown(_ids[0]), isTrue);
      expect(c.ids, <String>[_ids[1], _ids[0], _ids[2]]);
      expect(await c.moveUp(_ids[2]), isTrue);
      expect(c.ids, <String>[_ids[1], _ids[2], _ids[0]]);
      expect(await _stored(), c.ids);
    });
  });

  group('clear all', () {
    test('empties the list, persists the empty list, and notifies', () async {
      final MyToolsController c = await _filled(10);
      int notified = 0;
      c.addListener(() => notified++);
      await c.clear();
      expect(c.isEmpty, isTrue);
      expect(notified, 1);
      expect(await _stored(), isEmpty);

      final MyToolsController fresh = MyToolsController();
      await fresh.load();
      expect(fresh.isEmpty, isTrue);
    });

    test('clearing an empty list does nothing', () async {
      final MyToolsController c = MyToolsController();
      int notified = 0;
      c.addListener(() => notified++);
      await c.clear();
      expect(notified, 0);
      expect(await _stored(), isNull);
    });

    test('the list can be refilled after a clear', () async {
      final MyToolsController c = await _filled(10);
      await c.clear();
      expect(await c.add(_ids[11]), MyToolsAddResult.added);
      expect(c.ids, <String>[_ids[11]]);
    });
  });

  group('persistence', () {
    test('round trip: a fresh controller loads the same ordered list', () async {
      final MyToolsController a = await _filled(4);
      await a.reorder(3, 0);
      final MyToolsController b = MyToolsController();
      await b.load();
      expect(b.ids, a.ids);
    });

    test('unknown ids and duplicates are dropped silently on load, and the '
        'cleaned list is written back', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MyToolsController.prefsKey: <String>[
          _ids[0],
          'tool-removed-from-catalog',
          _ids[1],
          _ids[0],
        ],
      });
      final MyToolsController c = MyToolsController();
      await c.load();
      expect(c.ids, <String>[_ids[0], _ids[1]]);
      expect(await _stored(), <String>[_ids[0], _ids[1]]);
    });

    test('an injected known-id check decides what is unknown', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MyToolsController.prefsKey: <String>['a', 'b', 'c'],
      });
      final MyToolsController c = MyToolsController(
        isKnownId: (String id) => id != 'b',
      );
      await c.load();
      expect(c.ids, <String>['a', 'c']);
    });

    test('a clean stored list is not rewritten', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MyToolsController.prefsKey: <String>[_ids[0]],
      });
      final MyToolsController c = MyToolsController();
      await c.load();
      expect(c.ids, <String>[_ids[0]]);
    });
  });
}
