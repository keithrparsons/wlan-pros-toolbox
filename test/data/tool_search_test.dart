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
      // Wi-Fi Channels, Channel Map (quick-reference), the channel-allocation
      // cards, Wi-Fi Information (test-network, keyword), throughput/etc.
      expect(distinctCategoryCount(hits), greaterThanOrEqualTo(3));
      // Spot-check some expected tools are present.
      final Set<String> ids = hits.map((ToolSearchHit h) => h.tool.id).toSet();
      expect(ids.contains('wifi-channels'), isTrue);
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
