// EducationalResourcesService unit tests — JSON parsing (incl. malformed-row
// tolerance), topic grouping in `_meta.topics` order, free-text search across
// title/summary/description/topic/tags, and the approval field surviving onto
// the model. Most tests use a small in-memory fixture; the last group loads the
// REAL bundled asset to prove all 42 entries parse and group into the 7 topics.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';

const String _fixture = '''
{
  "_meta": {
    "title": "Educational Resources",
    "count": 4,
    "topics": [
      "Tools and utilities",
      "Vendor documentation and design guides",
      "Podcasts",
      "Independent blogs and experts"
    ]
  },
  "resources": [
    {
      "id": "a-tool",
      "title": "Alpha Tool",
      "summary": "A handy tool.",
      "description": "Para one.\\n\\nPara two.",
      "url": "https://example.com/tool",
      "topic": "Tools and utilities",
      "cost": "free",
      "level": "intermediate",
      "tags": ["tool", "reference"],
      "approval": "pending_outreach"
    },
    {
      "id": "vendor-doc",
      "title": "Vendor Doc",
      "summary": "Official vendor guide.",
      "description": "Read this.",
      "url": "https://example.com/doc",
      "topic": "Vendor documentation and design guides",
      "cost": "free",
      "level": "advanced",
      "tags": ["docs"],
      "approval": "not_required"
    },
    {
      "id": "a-podcast",
      "title": "Beta Podcast",
      "summary": "A Wi-Fi podcast.",
      "description": "Listen.",
      "url": "https://example.com/pod",
      "topic": "Podcasts",
      "cost": "free",
      "level": "all",
      "tags": ["destination", "podcast"],
      "approval": "pending_outreach"
    },
    {
      "id": "a-blog",
      "title": "Gamma Blog",
      "summary": "An independent Wi-Fi blog.",
      "description": "Deep dives on packet analysis.",
      "url": "https://example.com/blog",
      "topic": "Independent blogs and experts",
      "cost": "mixed",
      "level": "advanced",
      "tags": ["destination", "blog", "packet-analysis"],
      "approval": "pending_outreach"
    }
  ]
}
''';

void main() {
  final EducationalResourcesService svc =
      EducationalResourcesService.fromJson(_fixture);

  group('parse', () {
    test('loads every well-formed row', () {
      expect(svc.count, 4);
      expect(
        svc.all.map((EducationalResource e) => e.id),
        containsAll(<String>['a-tool', 'vendor-doc', 'a-podcast', 'a-blog']),
      );
    });

    test('maps every field, including enums and tags', () {
      final EducationalResource? tool = svc.byId('a-tool');
      expect(tool, isNotNull);
      expect(tool!.title, 'Alpha Tool');
      expect(tool.cost, ResourceCost.free);
      expect(tool.level, ResourceLevel.intermediate);
      expect(tool.approval, ResourceApproval.pendingOutreach);
      expect(tool.tags, <String>['tool', 'reference']);
      expect(tool.url, 'https://example.com/tool');
    });

    test('keeps the approval field for a future pre-publish filter', () {
      // The field is metadata only — nothing is hidden in this build, but a
      // future filter must be a trivial `where`.
      final List<EducationalResource> publishable = svc.all
          .where((EducationalResource e) =>
              e.approval == ResourceApproval.notRequired)
          .toList();
      expect(publishable.map((EducationalResource e) => e.id),
          <String>['vendor-doc']);
      // And ALL entries are still present (nothing hidden).
      expect(svc.count, 4);
    });

    test('reads the title from _meta', () {
      expect(svc.title, 'Educational Resources');
    });

    test('drops malformed rows but keeps the good ones', () {
      const String bad = '''
      {
        "resources": [
          { "id": "ok", "title": "Good", "url": "https://x", "topic": "T",
            "summary": "", "description": "", "cost": "free", "level": "all",
            "tags": [], "approval": "not_required" },
          { "title": "no-id", "url": "https://x", "topic": "T" },
          { "id": "no-url", "title": "No URL", "topic": "T" },
          { "id": "no-topic", "title": "No Topic", "url": "https://x" }
        ]
      }
      ''';
      final EducationalResourcesService s =
          EducationalResourcesService.fromJson(bad);
      expect(s.count, 1);
      expect(s.all.single.id, 'ok');
    });

    test('garbage document yields an empty-but-valid service', () {
      expect(EducationalResourcesService.fromJson('[]').count, 0);
      expect(EducationalResourcesService.fromJson('{"nope": true}').count, 0);
    });
  });

  group('grouping by topic', () {
    test('groups into topic buckets in _meta.topics order', () {
      final List<ResourceGroup> groups = svc.grouped();
      expect(
        groups.map((ResourceGroup g) => g.topic),
        <String>[
          'Tools and utilities',
          'Vendor documentation and design guides',
          'Podcasts',
          'Independent blogs and experts',
        ],
      );
      // Empty topics from _meta.topics are not rendered as groups.
      expect(groups.every((ResourceGroup g) => g.count > 0), isTrue);
    });

    test('counts add up to the total', () {
      final int sum = svc
          .grouped()
          .fold<int>(0, (int acc, ResourceGroup g) => acc + g.count);
      expect(sum, svc.count);
    });

    test('grouping a filtered subset only includes matched entries', () {
      final List<EducationalResource> hits = svc.search('podcast');
      final List<ResourceGroup> groups = svc.grouped(hits);
      expect(groups.length, 1);
      expect(groups.single.topic, 'Podcasts');
      expect(groups.single.resources.single.id, 'a-podcast');
    });
  });

  group('search', () {
    test('empty / whitespace query returns the full list in asset order', () {
      expect(svc.search('').length, svc.count);
      expect(svc.search('   ').length, svc.count);
      expect(svc.search('').first.id, 'a-tool');
    });

    test('matches title, topic, and tags case-insensitively', () {
      expect(svc.search('ALPHA').single.id, 'a-tool');
      expect(svc.search('podcasts').map((e) => e.id), contains('a-podcast'));
      expect(
        svc.search('packet-analysis').single.id,
        'a-blog',
      );
    });

    test('matches the description body', () {
      expect(svc.search('Deep dives').single.id, 'a-blog');
    });

    test('no match returns empty, not a fabricated row', () {
      expect(svc.search('zzznotathing'), isEmpty);
    });
  });

  group('real bundled asset', () {
    test('parses the 42 curated entries into the 7 topic groups', () {
      // Load the actual bundled JSON from disk (not via rootBundle, so no
      // Flutter binding is needed) and prove the production dataset is healthy.
      // Curated 2026-06-04: independent-author/community materials only; the
      // megavendor/product documentation ("Vendor documentation and design
      // guides") topic was removed per Keith, and one archived planner entry
      // was later dropped (32 -> 31). Batch 2026-06-04 appended 5
      // independent-author entries (31 -> 36), all within the existing 6 topics.
      // Batch 2026-06-05 (v1.1) appended 3 entries (Frame by Frame, Divergent
      // Dynamics, Wireshark 802.11 Wiki) and enhanced the CWNP entry in place
      // (36 -> 39). 2026-06-06 (BF6-21): removed the two Wi-Fi Design Day
      // entries (they charge for the videos) → 39 -> 37. 2026-06-07: removed the
      // dead MackenzieWiFi link (37 -> 36), then added WiFi Training under a new
      // "Training Providers" topic and moved the CWNP cert entry into it
      // (36 -> 37); that 7th topic takes the group count 6 -> 7. MackenzieWiFi
      // was re-added 2026-06-08 (site back over http), 37 -> 38. 2026-06-12:
      // added Jonathan Davis's Frame Exchange Reference under the existing
      // "Independent blogs and experts" topic (38 -> 39); still within the
      // existing 7 topics, so the group count is unchanged. 2026-06-12: added
      // Devin Akin's Wi-Fi Design Flowchart (divdyn.com) under the same
      // "Independent blogs and experts" topic (39 -> 40), Devin-approved; still
      // within the existing 7 topics, so the group count is unchanged. 2026-06-25:
      // added the WLAN Pros "Reading a Connection Report" guide under the existing
      // "Tools and utilities" topic (40 -> 41); still within the existing 7
      // topics, so the group count is unchanged. 2026-07-27: added WiFrizzy
      // (Eva Santos, CWNE #521, wifrizzy.io) under the existing "Independent
      // blogs and experts" topic (41 -> 42), marked pending_outreach; still
      // within the existing 7 topics, so the group count is unchanged.
      final File asset = File('assets/data/educational_resources.json');
      expect(asset.existsSync(), isTrue,
          reason: 'bundled asset must exist at assets/data/');
      final String raw = asset.readAsStringSync();

      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(raw);
      expect(real.count, 42);

      final List<ResourceGroup> groups = real.grouped();
      expect(groups.length, 7);

      // The new Training Providers group holds the paid/commercial training
      // destinations: the CWNP cert ladder (moved here) and WiFi Training.
      final ResourceGroup providers = groups.firstWhere(
        (ResourceGroup g) => g.topic == 'Training Providers',
        orElse: () => throw StateError('Training Providers group missing'),
      );
      expect(
        providers.resources.map((EducationalResource e) => e.id).toSet(),
        <String>{'dest-cwnp-certification', 'train-wifitraining'},
      );

      // The vendor-doc topic is intentionally gone (curation guard).
      expect(
        groups.every((ResourceGroup g) =>
            g.topic != 'Vendor documentation and design guides'),
        isTrue,
        reason: 'megavendor/product docs were removed per Keith 2026-06-04',
      );

      // Every entry lands in exactly one group; counts sum to 42.
      final int sum = groups.fold<int>(
          0, (int acc, ResourceGroup g) => acc + g.count);
      expect(sum, 42);

      // _meta.count agrees with the parsed entry count (data-integrity guard).
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      expect((decoded['_meta'] as Map<String, dynamic>)['count'], 42);
    });

    // 2026-08-09: outreach is complete. Keith: "I have already contact ALL the
    // educational resource owners, and they have each responded positively" /
    // "clear the 27 outreach to educational resources ... no need to carry
    // that". The 27 previously-pending entries became 'approved'; the 15 that
    // never needed permission stay 'not_required'.
    test('no bundled entry is still pending outreach', () {
      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(
              File('assets/data/educational_resources.json')
                  .readAsStringSync());

      final Iterable<String> pending = real.all
          .where((EducationalResource e) =>
              e.approval == ResourceApproval.pendingOutreach)
          .map((EducationalResource e) => e.id);
      expect(pending, isEmpty,
          reason: 'outreach completed 2026-08-08; still pending: '
              '${pending.join(", ")}');

      expect(
        real.all
            .where((EducationalResource e) =>
                e.approval == ResourceApproval.approved)
            .length,
        27,
      );
      expect(
        real.all
            .where((EducationalResource e) =>
                e.approval == ResourceApproval.notRequired)
            .length,
        15,
      );
    });

    // THE PAIRING GUARD. `ResourceApprovalToken.parse` degrades an unrecognized
    // token to `unknown` instead of throwing, so a wire value the enum does not
    // know fails SILENTLY — the entry still renders, just with a wrong approval
    // state. That is precisely how a data-only edit (JSON changed, enum not)
    // would slip through unnoticed. This asserts every bundled token resolves.
    test('every bundled approval token is recognized by the parser', () {
      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(
              File('assets/data/educational_resources.json')
                  .readAsStringSync());

      final Iterable<String> unresolved = real.all
          .where((EducationalResource e) =>
              e.approval == ResourceApproval.unknown)
          .map((EducationalResource e) => e.id);
      expect(unresolved, isEmpty,
          reason: 'approval token not handled in ResourceApprovalToken.parse '
              'for: ${unresolved.join(", ")}');
    });
  });

  group('approval parsing', () {
    test('parses every wire token, case-insensitively', () {
      expect(ResourceApprovalToken.parse('not_required'),
          ResourceApproval.notRequired);
      expect(
          ResourceApprovalToken.parse('approved'), ResourceApproval.approved);
      expect(ResourceApprovalToken.parse('  APPROVED  '),
          ResourceApproval.approved);
      expect(ResourceApprovalToken.parse('pending_outreach'),
          ResourceApproval.pendingOutreach);
    });

    test('an unrecognized token degrades to unknown rather than throwing', () {
      // Documents the silent-failure mode the pairing guard above exists for.
      expect(ResourceApprovalToken.parse('cleared'), ResourceApproval.unknown);
      expect(ResourceApprovalToken.parse(''), ResourceApproval.unknown);
    });
  });
}
