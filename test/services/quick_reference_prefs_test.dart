// Unit tests for QuickReferencePrefs: Favorites and Recents on the Quick
// Reference screen, stored on the device through shared_preferences.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/quick_reference_prefs.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('starts empty with nothing stored', () async {
    final QuickReferencePrefs p = QuickReferencePrefs();
    await p.load();
    expect(p.favorites, isEmpty);
    expect(p.recents, isEmpty);
  });

  test('toggleFavorite adds, removes, and persists', () async {
    final QuickReferencePrefs p = QuickReferencePrefs();
    await p.load();
    await p.toggleFavorite('mcs-index');
    await p.toggleFavorite('db-reference');
    expect(p.favorites, <String>['mcs-index', 'db-reference']);
    expect(p.isFavorite('mcs-index'), isTrue);

    await p.toggleFavorite('mcs-index');
    expect(p.favorites, <String>['db-reference']);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QuickReferencePrefs.favoritesKey), <String>[
      'db-reference',
    ]);
  });

  test('recordOpened is most recent first, without duplicates', () async {
    final QuickReferencePrefs p = QuickReferencePrefs();
    await p.recordOpened('a');
    await p.recordOpened('b');
    await p.recordOpened('a');
    expect(p.recents, <String>['a', 'b']);
  });

  test('Recents keeps only the last 10', () async {
    final QuickReferencePrefs p = QuickReferencePrefs();
    for (int i = 0; i < 12; i++) {
      await p.recordOpened('t$i');
    }
    expect(p.recents, hasLength(QuickReferencePrefs.maxRecents));
    expect(p.recents.first, 't11');
    expect(p.recents.last, 't2');
  });

  test('clearRecents empties the list and the store', () async {
    final QuickReferencePrefs p = QuickReferencePrefs();
    await p.recordOpened('a');
    await p.clearRecents();
    expect(p.recents, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QuickReferencePrefs.recentsKey), isEmpty);
  });

  test('load restores both lists from a previous session', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      QuickReferencePrefs.favoritesKey: <String>['wpa-security'],
      QuickReferencePrefs.recentsKey: <String>['x', 'y'],
    });
    final QuickReferencePrefs p = QuickReferencePrefs();
    await p.load();
    expect(p.favorites, <String>['wpa-security']);
    expect(p.recents, <String>['x', 'y']);
  });
}
