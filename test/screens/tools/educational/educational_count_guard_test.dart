// Counter guard — the Educational Resources home-tile badge shows a pinned
// countLabelOverride rather than the live tool count (the in-app references).
// This test asserts that override equals the true total the Educational
// Resources screen advertises in its "$total curated places" intro:
//   in-app reference cards (catalog category tools)
//   + 1 in-app Field Manual (the "In-Depth Guide" the screen always counts)
//   + the bundled JSON `_meta.count` (the online-resource count).
// If a tool is added/removed, or the dataset's count changes, the override must
// be updated in lockstep or this test fails — the number cannot silently drift,
// and the home badge can never again contradict the screen header.
//
// 2026-06-06: the in-app references are now 11 = the 10 PDF reference cards +
// Antenna Fundamentals (moved here from Quick Reference, BF6-3).
// 2026-07-02: added the +1 Field Manual term. The screen's intro counts the
// in-app Field Manual (educational_resources_screen.dart: `1 + _cards.length +
// svc.count`) but the override had omitted it, so the badge (54) contradicted
// the header (55). The guard now includes it so both surfaces stay in step.

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
    expect(cardCount, 13,
        reason: 'expected 10 PDF reference cards + Antenna Fundamentals + '
            'Ham Radio Study Resources + Spectrum Analysis');

    // Online-resource count from the bundled dataset's _meta block.
    final File asset = File('assets/data/educational_resources.json');
    expect(asset.existsSync(), isTrue,
        reason: 'bundled educational_resources.json must exist');
    final Map<String, dynamic> decoded =
        jsonDecode(asset.readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> meta = decoded['_meta'] as Map<String, dynamic>;
    final int onlineCount = meta['count'] as int;

    // The in-app Field Manual ("In-Depth Guide") is a bundled reader entry the
    // screen always counts in its intro total but that does NOT live in the
    // catalog category `tools` list. Mirror the screen's `1 +` term here so the
    // guard total equals what the header shows.
    const int fieldManualCount = 1;

    final int expectedTotal = cardCount + fieldManualCount + onlineCount;

    expect(
      edu.countLabelOverride,
      isNotNull,
      reason: 'educational-resources must pin a countLabelOverride',
    );
    expect(
      edu.countLabelOverride,
      '$expectedTotal',
      reason: 'tile badge ($expectedTotal) = $cardCount cards + '
          '$fieldManualCount Field Manual + $onlineCount online resources; '
          'this must equal the screen header total (1 + cards + online). '
          'Update the override if any term changes',
    );
  });
}
