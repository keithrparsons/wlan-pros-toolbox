// No internal notes ship. Keith, 2026-09-24: "Internal notes should NEVER ship!"
//
// educational_resources.json is bundled into every build, so any field in it is
// readable by anyone who unpacks the app, whether or not a screen displays it.
// Seven entries carried a `notes` field recording who granted permission and
// how; that record now lives outside the app repo. This test fails if a
// `notes` field, or any other field the app does not use, comes back.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no educational resource ships a notes field or an unknown field', () {
    final Map<String, dynamic> decoded = jsonDecode(
      File('assets/data/educational_resources.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final List<dynamic> resources = decoded['resources'] as List<dynamic>;

    const Set<String> allowed = <String>{
      'id', 'title', 'summary', 'description', 'url', 'topic', 'cost',
      'level', 'tags', 'approval',
    };

    for (final dynamic r in resources) {
      final Map<String, dynamic> entry = r as Map<String, dynamic>;
      final Set<String> extra = entry.keys.toSet().difference(allowed);
      expect(extra, isEmpty,
          reason: '${entry['id']} ships field(s) $extra. Internal notes never '
              'ship; keep them outside the app repo.');
    }
  });
}
