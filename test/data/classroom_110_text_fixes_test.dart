// Guards for two text fixes found on 2026-09-28 for Toolbox 1.11.0.
//
// 1. Why Two Devices Disagree: in Present, Up and Down move the AP one metre,
//    or one foot when lengths are imperial
//    (devices_disagree_controller.dart, nudgeDistance). The help and the
//    Teacher's Guide said only "a meter".
// 2. The Teacher's Guide lists every tool on each Wi-Fi Classroom shelf. Its
//    Airtime and Access list had fallen behind the catalog: Voice Priority,
//    End to End and What an Interferer Costs were missing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

Map<String, dynamic> _help() =>
    (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
            as Map<String, dynamic>)['tools']
        as Map<String, dynamic>;

/// The Teacher's Guide section under `### <shelf>`, up to the next heading.
String _guideSection(String shelf) {
  final String guide = File(
    'assets/guides/teachers-guide.md',
  ).readAsStringSync();
  final int start = guide.indexOf('### $shelf\n');
  expect(start, isNonNegative, reason: 'no "### $shelf" in the guide');
  final int end = guide.indexOf(RegExp(r'\n##'), start + 4);
  return guide.substring(start, end < 0 ? guide.length : end);
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

  test("Teacher's Guide: Why Two Devices Disagree says 1 m, or 1 ft in "
      'imperial', () {
    final String rf = _guideSection('RF and Propagation');
    final String line = rf
        .split('\n')
        .firstWhere((String l) => l.contains('**Why Two Devices Disagree.**'));
    expect(line, contains('1 m (1 ft'));
    expect(line, isNot(contains('a meter')));
  });

  test("Teacher's Guide: the Airtime and Access list names every live tool "
      'on that shelf', () {
    final String section = _guideSection('Airtime and Access');
    final List<ToolEntry> shelf = <ToolEntry>[
      for (final ToolCategory c in kToolCategories)
        for (final ToolEntry t in c.tools)
          if (t.isLive && t.subgroup == 'Airtime and Access') t,
    ];
    expect(shelf, isNotEmpty);
    for (final ToolEntry t in shelf) {
      // A catalog title may carry a parenthetical the guide leaves out:
      // "What an Interferer Costs (and how a NIC hears the air)".
      final String short = t.title.split(' (').first;
      expect(
        section,
        contains('**$short'),
        reason: '${t.id} ("${t.title}") is not in the guide list',
      );
    }
  });
}
