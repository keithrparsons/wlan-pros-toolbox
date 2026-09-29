// Guards for two text fixes found on 2026-09-28 for Toolbox 1.11.0.
//
// 1. Why Two Devices Disagree: in Present, Up and Down move the AP one metre,
//    or one foot when lengths are imperial
//    (devices_disagree_controller.dart, nudgeDistance). The help and the
//    Teacher's Guide said only "a meter".
// 2. The Teacher's Guide lists every tool on each Wi-Fi Classroom shelf. Its
//    Airtime and Access list had fallen behind the catalog: Voice Priority,
//    End to End and What an Interferer Costs were missing.
//
// 2026-09-29 (Keith): tool descriptions moved out of the Teacher's Guide into
// the Field Manual, which is now the one detailed reference; the guide keeps
// presenting and lesson sequences. So a copy that can fall behind no longer
// exists, and these guards now check the Field Manual instead: the Devices
// Disagree entry says 1 m (1 ft), and every live Airtime and Access tool has a
// Teaching it section. The guide itself must not grow a tool list again.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

Map<String, dynamic> _help() =>
    (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
            as Map<String, dynamic>)['tools']
        as Map<String, dynamic>;

String _manual() => File('assets/guides/field-manual.md').readAsStringSync();

/// The Field Manual entry under `### <name>`, up to the next heading.
String _manualEntry(String name) {
  final String fm = _manual();
  final int start = fm.indexOf('### $name\n');
  expect(start, isNonNegative, reason: 'no "### $name" in the Field Manual');
  final int end = fm.indexOf(RegExp(r'\n##'), start + 4);
  return fm.substring(start, end < 0 ? fm.length : end);
}

void main() {
  test('Why Two Devices Disagree help: Up and Down move the AP 1 m, or 1 ft '
      'in imperial', () {
    final List<dynamic> how =
        (_help()['devices-disagree'] as Map<String, dynamic>)['howToUse']
            as List<dynamic>;
    final String present = how.cast<String>().firstWhere(
      (String s) => s.contains('Present'),
    );
    expect(present, contains('1 m (1 ft'));
    expect(present, isNot(contains('a meter')));
  });

  test('Field Manual: Why Two Devices Disagree says 1 m, or 1 ft in '
      'imperial', () {
    final String entry = _manualEntry('Why Two Devices Disagree');
    expect(entry, contains('1 m (1 ft'));
    expect(entry, isNot(contains('a meter')));
  });

  test('Field Manual: every live Airtime and Access tool has a Teaching it '
      'section', () {
    final List<ToolEntry> shelf = <ToolEntry>[
      for (final ToolCategory c in kToolCategories)
        for (final ToolEntry t in c.tools)
          if (t.isLive && t.subgroup == 'Airtime and Access') t,
    ];
    expect(shelf, isNotEmpty);
    final Map<String, dynamic> help = _help();
    for (final ToolEntry t in shelf) {
      final String name =
          (help[t.id] as Map<String, dynamic>)['name'] as String;
      expect(
        _manualEntry(name),
        contains('**Teaching it'),
        reason: '${t.id} ("$name") has no Teaching it in the Field Manual',
      );
    }
  });

  test("Teacher's Guide: no shelf-by-shelf tool list (the Field Manual holds "
      'those)', () {
    final String guide = File(
      'assets/guides/teachers-guide.md',
    ).readAsStringSync();
    expect(guide, isNot(contains('## What each shelf teaches')));
    expect(guide, contains('Field Manual'));
  });
}
