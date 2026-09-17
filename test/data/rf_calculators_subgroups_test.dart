// rf-calculators has no single-tool subgroups, and no tool was lost making
// that true. Keith, 2026-09-17: "we don't want to LOSE the runts, just put
// them under a different category."
//
// SCOPE NOTE, because the difference matters. Keith was offered a WIDENED
// anti-decay guard covering every category and chose the narrower option: fix
// these two. So this file asserts rf-calculators ONLY. It is not the global
// guard he declined, and it must not grow into one by accident -- widening it
// would surface work in categories nobody has ruled on, which is the reason he
// said no.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

ToolCategory get _rfCalc =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == 'rf-calculators');

Map<String, List<String>> _subgroups(ToolCategory c) {
  final Map<String, List<String>> out = <String, List<String>>{};
  for (final ToolEntry t in c.tools) {
    final String? sg = t.subgroup;
    if (sg == null) continue;
    out.putIfAbsent(sg, () => <String>[]).add(t.id);
  }
  return out;
}

void main() {
  test('no rf-calculators subgroup holds fewer than two tools', () {
    final Map<String, List<String>> groups = _subgroups(_rfCalc);
    final Iterable<String> runts = groups.entries
        .where((MapEntry<String, List<String>> e) => e.value.length < 2)
        .map((MapEntry<String, List<String>> e) => '${e.key} (${e.value})');
    expect(runts, isEmpty,
        reason: 'a one-tool section is a heading pretending to be a shelf; '
            'merge it into its nearest neighbor rather than deleting the tool');
  });

  test('THE TOOLS SURVIVED THE MOVE, by id and by route', () {
    // The failure this guards against is not a missing section. It is a tool
    // quietly disappearing while the section count looks healthier.
    for (final MapEntry<String, String> pair in <String, String>{
      'hear-frequency': '/tools/hear-frequency',
      'architectural-scale': '/tools/architectural-scale',
    }.entries) {
      final ToolEntry t = _rfCalc.tools.firstWhere(
        (ToolEntry e) => e.id == pair.key,
        orElse: () => throw StateError('${pair.key} left rf-calculators'),
      );
      expect(t.routeName, pair.value,
          reason: 'ids and routes back tests, help entries and the keyword '
              'index; re-shelving must never touch them');
      expect(t.isLive, isTrue);
    }
  });

  test('they landed where the ruling put them', () {
    final Map<String, List<String>> groups = _subgroups(_rfCalc);
    expect(groups['Utilities & Generators'], contains('hear-frequency'));
    expect(groups['Conversions'], contains('architectural-scale'));
    expect(groups.containsKey('Learn / RF intuition'), isFalse);
    expect(groups.containsKey('AEC & Documentation'), isFalse);
  });

  test('the shared name Ham Radio is untouched in BOTH categories', () {
    // Subgroups are scoped per category, so the same name can live in two of
    // them. This tool move must not have reached across into the other one.
    final ToolCategory qr = kToolCategories
        .firstWhere((ToolCategory c) => c.id == 'quick-reference');
    expect(_subgroups(qr).containsKey('Ham Radio'), isTrue);
    expect(_subgroups(_rfCalc).containsKey('Ham Radio'), isTrue);
  });

  test('AEC & Documentation is now retired in EVERY category', () {
    // This test first asserted the opposite, on the strength of a source
    // comment claiming quick-reference still held a section by that name. The
    // 2026-09-16 reorg had absorbed it and the comment was stale. Recorded
    // here rather than quietly rewritten, because the next person to read this
    // file may be carrying the same wrong belief.
    for (final ToolCategory c in kToolCategories) {
      expect(_subgroups(c).containsKey('AEC & Documentation'), isFalse,
          reason: 'still present in ${c.id}');
    }
  });
}
