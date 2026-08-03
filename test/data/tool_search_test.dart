// Unit tests for the cross-category tool search engine (Ticket 1).
//
// Covers: a real query spanning multiple categories (the mockup-04 "channel"
// case), keyword-only matches setting matchedOn == keyword, empty/no-match
// returning empty, title-first ordering, the web-gate being respected (search
// reads kToolCategories), and the distinct-category count.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_search.dart';

void main() {
  group('searchTools', () {
    test('empty / whitespace query returns no hits', () {
      expect(searchTools(''), isEmpty);
      expect(searchTools('   '), isEmpty);
    });

    test('a no-match query returns no hits', () {
      expect(searchTools('zzzznotarealterm'), isEmpty);
    });

    test('"channel" matches across at least 3 categories (mockup 04)', () {
      final List<ToolSearchHit> hits = searchTools('channel');
      expect(hits, isNotEmpty);
      // Channel Map (quick-reference), the channel-allocation cards, Wi-Fi
      // Information (test-network, keyword), throughput/etc. (The plainer
      // Wi-Fi Channels table was removed 2026-06-06 — BF6-13.)
      expect(distinctCategoryCount(hits), greaterThanOrEqualTo(3));
      // Spot-check some expected tools are present.
      final Set<String> ids = hits.map((ToolSearchHit h) => h.tool.id).toSet();
      expect(ids.contains('channel-map'), isTrue);
    });

    test('a keyword-only hit reports matchedOn == keyword + the term', () {
      // "nslookup" is a keyword of dns-lookup, not in its title/description.
      final List<ToolSearchHit> hits = searchTools('nslookup');
      final ToolSearchHit dns = hits.firstWhere(
        (ToolSearchHit h) => h.tool.id == 'dns-lookup',
      );
      expect(dns.matchedOn, ToolMatchField.keyword);
      expect(dns.matchedKeyword, 'nslookup');
    });

    test('a title hit reports matchedOn == title with no matchedKeyword', () {
      final List<ToolSearchHit> hits = searchTools('fresnel');
      final ToolSearchHit fresnel = hits.firstWhere(
        (ToolSearchHit h) => h.tool.id == 'fresnel',
      );
      expect(fresnel.matchedOn, ToolMatchField.title);
      expect(fresnel.matchedKeyword, isNull);
    });

    test('results are ordered title hits first, then description, then keyword',
        () {
      final List<ToolSearchHit> hits = searchTools('channel');
      // Each tier's first index must not precede a stronger tier.
      int lastTier = -1;
      for (final ToolSearchHit h in hits) {
        expect(
          h.matchedOn.index,
          greaterThanOrEqualTo(lastTier),
          reason: 'hits must be grouped strongest-tier-first',
        );
        lastTier = h.matchedOn.index;
      }
    });

    test('within a tier, hits are alphabetical by title', () {
      final List<ToolSearchHit> hits = searchTools('channel');
      final List<String> titleTierTitles = hits
          .where((ToolSearchHit h) => h.matchedOn == ToolMatchField.title)
          .map((ToolSearchHit h) => h.tool.title.toLowerCase())
          .toList();
      final List<String> sorted = <String>[...titleTierTitles]..sort();
      expect(titleTierTitles, sorted);
    });

    test('category scope limits hits to that category', () {
      final List<ToolSearchHit> scoped = searchTools(
        'channel',
        categoryId: 'quick-reference',
      );
      expect(scoped, isNotEmpty);
      expect(
        scoped.every((ToolSearchHit h) => h.categoryId == 'quick-reference'),
        isTrue,
      );
    });

    // THE DEAD-END KEYWORD, 2026-08-02. Pax's iptoolkits survey found that
    // `vlsm` existed only as a search keyword on `ipv4-subnet`
    // (Deliverables/2026-08-02-iptoolkits-survey/BRIEF.md:88), with no VLSM
    // tool behind it. Searching for it returned a plausible-looking answer
    // from a calculator that cannot carve a block into right-sized subnets,
    // which is worse than returning nothing: a no-match tells you to look
    // elsewhere. The keyword now points at `subnet-planner`.
    //
    // This guards the FIX, so it must fail if the keyword drifts back or if
    // the tile it points at goes away.
    test('"vlsm" resolves to a tool that can actually carve a block', () {
      final List<ToolSearchHit> hits = searchTools('vlsm');
      expect(hits, isNotEmpty, reason: 'vlsm must not be a dead-end search');
      final Set<String> ids = hits.map((ToolSearchHit h) => h.tool.id).toSet();
      expect(ids, contains('subnet-planner'));
      expect(
        ids,
        isNot(contains('ipv4-subnet')),
        reason: 'the single-subnet calculator cannot do VLSM; surfacing it '
            'for this term is the defect, not the fix',
      );
    });

    test('the subnet-planner tile is live and routed', () {
      final ToolSearchHit hit = searchTools(
        'vlsm',
      ).firstWhere((ToolSearchHit h) => h.tool.id == 'subnet-planner');
      expect(hit.tool.isLive, isTrue);
      expect(hit.tool.routeName, '/tools/subnet-planner');
    });

    test('the other new address-math terms resolve too', () {
      // Every term Pax named as uncovered, checked against the tile that now
      // answers it. A term with no tool behind it is the same defect as vlsm.
      const Map<String, String> termToTool = <String, String>{
        'supernet': 'subnet-planner',
        'summarization': 'subnet-planner',
        'route summary': 'subnet-planner',
        'eui-64': 'mac-oui-lookup',
        'randomized mac': 'mac-oui-lookup',
        'locally administered': 'mac-oui-lookup',
        'slaac': 'mac-oui-lookup',
        'transfer time': 'transfer-time',
        'bandwidth calculator': 'transfer-time',
        'ip range': 'ipv4-subnet',
      };
      termToTool.forEach((String term, String toolId) {
        final Set<String> ids = searchTools(
          term,
        ).map((ToolSearchHit h) => h.tool.id).toSet();
        expect(
          ids,
          contains(toolId),
          reason: '"$term" must reach $toolId',
        );
      });
    });

    test('search reads the (web-gated) kToolCategories list', () {
      // Every hit's category must be one that is actually in kToolCategories —
      // proving the engine reads the gated UI list, not the raw catalog.
      final Set<String> visibleCategoryIds =
          kToolCategories.map((ToolCategory c) => c.id).toSet();
      for (final ToolSearchHit h in searchTools('ping')) {
        expect(visibleCategoryIds.contains(h.categoryId), isTrue);
      }
    });
  });
}
