// EducationalResourcesService unit tests — JSON parsing (incl. malformed-row
// tolerance), topic grouping in `_meta.topics` order, free-text search across
// title/summary/description/topic/tags, attribution scoping to the destination
// buckets, and the approval field surviving onto the model. Most tests use a
// small in-memory fixture; the last group loads the REAL bundled asset to prove
// all 52 entries parse and group into the 7 topics.

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
    ],
    "attribution": "Inspired by wlan-talks.net by Victor Njoroge.",
    "attribution_scope": "destinations only"
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

    test('reads the title and attribution from _meta', () {
      expect(svc.title, 'Educational Resources');
      expect(svc.attribution, 'Inspired by wlan-talks.net by Victor Njoroge.');
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

  group('attribution scope', () {
    test('destination topics are credited; canonical buckets are not', () {
      expect(svc.isDestinationTopic('Podcasts'), isTrue);
      expect(svc.isDestinationTopic('Independent blogs and experts'), isTrue);
      expect(svc.isDestinationTopic('Tools and utilities'), isFalse);
      expect(
        svc.isDestinationTopic('Vendor documentation and design guides'),
        isFalse,
      );
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
    test('parses all 52 entries into the 7 topic groups', () {
      // Load the actual bundled JSON from disk (not via rootBundle, so no
      // Flutter binding is needed) and prove the production dataset is healthy.
      final File asset = File('assets/data/educational_resources.json');
      expect(asset.existsSync(), isTrue,
          reason: 'bundled asset must exist at assets/data/');
      final String raw = asset.readAsStringSync();

      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(raw);
      expect(real.count, 52);

      final List<ResourceGroup> groups = real.grouped();
      expect(groups.length, 7);

      // Every entry lands in exactly one group; counts sum to 52.
      final int sum = groups.fold<int>(
          0, (int acc, ResourceGroup g) => acc + g.count);
      expect(sum, 52);

      // The credited attribution is present and names the wlan-talks source.
      expect(real.attribution, contains('wlan-talks.net'));

      // _meta.count agrees with the parsed entry count (data-integrity guard).
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      expect((decoded['_meta'] as Map<String, dynamic>)['count'], 52);
    });
  });
}
