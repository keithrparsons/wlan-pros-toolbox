// THE CREDIT THIS FEATURE OWES, AND WHY IT IS GUARDED.
//
// The Educational Resources category exists because of wlan-talks.net. The
// credit line was specified on 2026-06-03 and written into the destinations
// source file with the instruction "Display this credit line in the Educational
// Resources category when this destinations set ships." The set shipped. The
// credit did not: it was dropped at merge, it sat in a key nothing read, and the
// CRM asserted for three months that the app was crediting him when it was not.
//
// Victor Gatuna gave explicit permission on 2026-09-15. These tests exist so the
// credit cannot go missing again without something going red.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> loadMeta() async {
    final String raw =
        await rootBundle.loadString('assets/data/educational_resources.json');
    return (jsonDecode(raw) as Map<String, dynamic>)['_meta']
        as Map<String, dynamic>;
  }

  test('the shipped asset carries a non-empty credit line', () async {
    final Map<String, dynamic> meta = await loadMeta();
    final Object? a = meta['attribution'];
    expect(a, isA<String>(),
        reason: '_meta.attribution is the credit this feature owes; it was '
            'dropped once already and must not be dropped again');
    expect((a as String).trim(), isNotEmpty);
  });

  test('the service parses the credit off _meta', () async {
    final String raw =
        await rootBundle.loadString('assets/data/educational_resources.json');
    final EducationalResourcesService svc =
        EducationalResourcesService.fromJson(raw);
    final Map<String, dynamic> meta = await loadMeta();
    expect(svc.attribution, meta['attribution'],
        reason: 'the screen renders svc.attribution, so a parse that silently '
            'returns empty is the exact failure this feature already had');
  });

  test('the DISPLAY credit carries no dates and no internal process', () async {
    final Map<String, dynamic> meta = await loadMeta();
    final String shown = meta['attribution'] as String;

    expect(RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(shown), isFalse,
        reason: 'a date in the credit line means provenance leaked into the '
            'display string; provenance belongs in _meta.attribution_note');
    for (final String banned in <String>[
      'shipped',
      'specified',
      'Njoroge',
      'CRM',
      // 'Keith' was on this list and came off it, Vera 2026-09-15: it would
      // block a legitimate future credit that names him. The list guards
      // yesterday's vocabulary and is the weakest of the three checks here.
      // The date regex and the length ceiling below are the structural ones.
    ]) {
      expect(shown.toLowerCase(), isNot(contains(banned.toLowerCase())),
          reason: 'the credit line names the creator and the site, nothing '
              'else. "$banned" is internal and must stay in attribution_note.');
    }
    expect(shown.length, lessThan(90),
        reason: 'the credit is one short line under the intro, not a paragraph');
  });

  test('attribution_note is internal and is NOT read by the service', () async {
    final String raw =
        await rootBundle.loadString('assets/data/educational_resources.json');
    final Map<String, dynamic> meta = await loadMeta();
    expect(meta['attribution_note'], isA<String>(),
        reason: 'the provenance is kept, just not displayed');

    final EducationalResourcesService svc =
        EducationalResourcesService.fromJson(raw);
    expect(svc.attribution, isNot(contains('attribution_note')));
    expect(svc.attribution, isNot(equals(meta['attribution_note'])));
  });

  // The RENDER assertion lives in educational_resources_screen_test.dart,
  // which pumps the real screen off a fixture. It is not here because
  // rootBundle.loadString inside testWidgets never resolves without
  // tester.runAsync, and the first version of this file hung forever on
  // exactly that. A test that hangs is worse than no test: it reports
  // nothing and it stalls the suite.
}
