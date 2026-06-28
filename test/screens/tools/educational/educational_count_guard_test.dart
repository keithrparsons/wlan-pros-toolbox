// Counter guard — the Educational Resources home-tile badge shows a pinned
// countLabelOverride rather than the live tool count (the in-app references).
// This test asserts that override equals the true total: the number of in-app
// reference tools in the catalog category + the bundled JSON `_meta.count` (the
// online-resource count). If a tool is added/removed, or the dataset's count
// changes, the override must be updated in lockstep or this test fails — the
// number cannot silently drift.
//
// 2026-06-06: the in-app references are now 11 = the 10 PDF reference cards +
// Antenna Fundamentals (moved here from Quick Reference, BF6-3).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

void main() {
  test('educational-resources countLabelOverride == cards + JSON _meta.count',
      () {
    final ToolCategory edu = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'educational-resources',
    );

    // In-app reference tools live in the category's `tools` list (10 PDF cards
    // + Antenna Fundamentals, moved here 2026-06-06 BF6-3; + Ham Radio Study
    // Resources, added 2026-06-28).
    final int cardCount = edu.tools.length;
    expect(cardCount, 12,
        reason: 'expected 10 PDF reference cards + Antenna Fundamentals + '
            'Ham Radio Study Resources');

    // Online-resource count from the bundled dataset's _meta block.
    final File asset = File('assets/data/educational_resources.json');
    expect(asset.existsSync(), isTrue,
        reason: 'bundled educational_resources.json must exist');
    final Map<String, dynamic> decoded =
        jsonDecode(asset.readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> meta = decoded['_meta'] as Map<String, dynamic>;
    final int onlineCount = meta['count'] as int;

    final int expectedTotal = cardCount + onlineCount;

    expect(
      edu.countLabelOverride,
      isNotNull,
      reason: 'educational-resources must pin a countLabelOverride',
    );
    expect(
      edu.countLabelOverride,
      '$expectedTotal',
      reason: 'tile badge ($expectedTotal) = $cardCount cards + '
          '$onlineCount online resources; update the override if either changes',
    );
  });
}
