// EducationalResourcesService unit tests — JSON parsing (incl. malformed-row
// tolerance), topic grouping in `_meta.topics` order, free-text search across
// title/summary/description/topic/tags, and the approval field surviving onto
// the model. Most tests use a small in-memory fixture; the last group loads the
// REAL bundled asset to prove all 45 entries parse and group into the 7 topics.

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
    test('parses the 45 curated entries into the 7 topic groups', () {
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
      // 2026-08-09: added three Hamina-adjacent community tools under the
      // existing "Tools and utilities" topic (42 -> 45) — Robin Decloedt's
      // Hamina Attenuation Object Library, Kjetil Teigen Hansen's teigenRF
      // tools, and Joel Crane's Hamina Clipboard Tools. All three sit in an
      // existing topic, so the group count is unchanged.
      final File asset = File('assets/data/educational_resources.json');
      expect(asset.existsSync(), isTrue,
          reason: 'bundled asset must exist at assets/data/');
      final String raw = asset.readAsStringSync();

      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(raw);
      expect(real.count, 45);

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

      // Every entry lands in exactly one group; counts sum to 45.
      final int sum = groups.fold<int>(
          0, (int acc, ResourceGroup g) => acc + g.count);
      expect(sum, 45);

      // _meta.count agrees with the parsed entry count (data-integrity guard).
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      expect((decoded['_meta'] as Map<String, dynamic>)['count'], 45);
    });

    // 2026-08-09, part one: outreach was complete for everything shipped
    // before that date. Keith: "I have already contact ALL the educational
    // resource owners, and they have each responded positively" / "clear the 27
    // outreach to educational resources ... no need to carry that". The 27
    // previously-pending entries became 'approved'; the 15 that never needed
    // permission stayed 'not_required'.
    //
    // 2026-08-09, part two: three entries were added the same day and are the
    // FIRST use of the staging state the enum was deliberately kept parseable
    // for. Keith emailed all three owners that day. Kjetil Teigen Hansen
    // replied within the day and his entry is 'approved'; Robin Decloedt and
    // Joel Crane had not replied, so their two rows stay staged. The earlier
    // version of this test asserted the pending set was EMPTY, which would have
    // blocked exactly the case the enum comment promised to support.
    //
    // NAMED, NOT COUNTED, on purpose. An id set still fails if a THIRD entry
    // drifts into pending_outreach, or if one of these two is flipped to
    // 'approved' without the row's `notes` being updated to say who replied.
    // A bare count would let one silently swap for another.
    //
    // divdyn-wifi-design-flowchart also moved not_required -> approved in this
    // change (its own notes recorded an explicit grant from Devin Akin). With
    // Hansen's reply that makes 29 approved and 14 not_required, up from 27
    // and 15.
    test('only the two unanswered 2026-08-09 additions are pending outreach',
        () {
      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(
              File('assets/data/educational_resources.json')
                  .readAsStringSync());

      final Set<String> pending = real.all
          .where((EducationalResource e) =>
              e.approval == ResourceApproval.pendingOutreach)
          .map((EducationalResource e) => e.id)
          .toSet();
      expect(
        pending,
        <String>{
          'robinwifi-hamina-objects',
          'potatofi-hamina-clipboard',
        },
        reason: 'outreach completed 2026-08-08 for every earlier entry; only '
            'the 2026-08-09 additions whose owners have not replied may be '
            'staged. Found: ${pending.join(", ")}',
      );

      expect(
        real.all
            .where((EducationalResource e) =>
                e.approval == ResourceApproval.approved)
            .length,
        29,
      );
      expect(
        real.all
            .where((EducationalResource e) =>
                e.approval == ResourceApproval.notRequired)
            .length,
        14,
      );
    });

    // THE ROUND-TRIP ASSERTION. 'pending_outreach' had no bundled user before
    // today, so nothing proved the token survives the asset -> parser -> model
    // path on real data. It matters here more than for the other two values:
    // `ResourceApprovalToken.parse` degrades an unrecognized token to `unknown`
    // WITHOUT throwing, so a typo in the JSON ('pending-outreach', 'pending')
    // would render an entry with a silently wrong approval state and no test
    // would notice. Asserting on the PARSED model rather than on the JSON text
    // is the whole point: reading the string back out of the file would pass
    // even when the parser rejects it.
    test('the staged additions round-trip to pendingOutreach on the model', () {
      final EducationalResourcesService real =
          EducationalResourcesService.fromJson(
              File('assets/data/educational_resources.json')
                  .readAsStringSync());

      for (final String id in <String>[
        'robinwifi-hamina-objects',
        'potatofi-hamina-clipboard',
      ]) {
        final EducationalResource? e = real.byId(id);
        expect(e, isNotNull, reason: '$id missing from the bundled asset');
        expect(e!.approval, ResourceApproval.pendingOutreach,
            reason: '$id did not parse to pendingOutreach');
        expect(e.topic, 'Tools and utilities');
        expect(e.cost, ResourceCost.free);
      }

      // Kjetil Teigen Hansen replied to Keith the same day ("Share it! Yes!"),
      // so his entry is the one 2026-08-09 addition that is already approved.
      // One reply must not cascade into three approvals.
      expect(real.byId('teigenrf-ai-tools')?.approval,
          ResourceApproval.approved);
      expect(real.byId('teigenrf-ai-tools')?.url,
          'https://tools.teigenrf.org/',
          reason: 'the author asked for the shorter address 2026-08-09');

      // The corrected defect row: its notes recorded an explicit grant while
      // the value said no permission was ever needed.
      expect(real.byId('divdyn-wifi-design-flowchart')?.approval,
          ResourceApproval.approved);
      // The row whose VALUE was right and whose NOTE was stale.
      expect(real.byId('frame-exchange-reference')?.approval,
          ResourceApproval.approved);
    });

    // THE NOTE/VALUE CONTRADICTION GUARD. Two rows shipped with an `approval`
    // value that its own `notes` prose contradicted: 'divdyn-wifi-design-
    // flowchart' sat at 'not_required' while its note recorded that the owner
    // explicitly granted approval, and 'frame-exchange-reference' moved to
    // 'approved' in the 2026-08-09 sweep while its note still read "Approval
    // pending owner outreach" from 2026-06-12. Nothing caught either, because
    // `notes` is prose the model never parses.
    //
    // This is a NARROW PHRASE GUARD, not a semantic checker. It knows two
    // phrasings and no more: a note that says outreach is pending may not sit
    // on 'approved', and a note that says approval was explicitly granted may
    // not sit on 'not_required'. It cannot read a sentence it has not been
    // taught. It is here because it fails red on exactly the two rows that
    // were wrong.
    test('no entry notes contradict the approval value', () {
      final Map<String, dynamic> decoded = jsonDecode(
              File('assets/data/educational_resources.json').readAsStringSync())
          as Map<String, dynamic>;
      final List<dynamic> rows = decoded['resources'] as List<dynamic>;

      final List<String> contradictions = <String>[];
      for (final dynamic row in rows) {
        final Map<String, dynamic> r = row as Map<String, dynamic>;
        final String notes = (r['notes'] as String? ?? '').toLowerCase();
        final String approval = (r['approval'] as String? ?? '').toLowerCase();
        final String id = r['id'] as String? ?? '(no id)';
        if (notes.isEmpty) continue;

        final bool notesSayPending = notes.contains('approval pending') ||
            notes.contains('pending owner outreach');
        if (notesSayPending && approval != 'pending_outreach') {
          contradictions.add('$id: notes say outreach pending, approval='
              '$approval');
        }

        final bool notesSayGranted =
            notes.contains('approval explicitly granted');
        if (notesSayGranted && approval != 'approved') {
          contradictions.add('$id: notes say approval granted, approval='
              '$approval');
        }
      }

      expect(contradictions, isEmpty,
          reason: 'approval value contradicts its own notes for: '
              '${contradictions.join(" | ")}');
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
