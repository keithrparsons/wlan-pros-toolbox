// EducationalResourcesService — load the bundled Educational Resources directory
// (a curated list of Wi-Fi learning destinations) from a bundled JSON asset,
// fully offline.
//
// WHAT IT DOES: parses the 52-entry combined dataset
// (assets/data/educational_resources.json, declared in pubspec.yaml) into typed
// Dart models, groups them by `topic` (the 7 editorial topic groups), and
// answers a free-text search consistent with the app's other reference/list
// screens (substring match across title, summary, description, topic, and tags).
//
// OFFLINE / NO NETWORK: the directory is a bundled asset, loaded and parsed once
// at screen open. No HTTP, NO Flutter imports — the screen reads the asset
// string via rootBundle and hands it to `EducationalResourcesService.fromJson`,
// so the logic is pure Dart and unit-testable from an in-memory string. (Opening
// a resource's website does use the network, but that is the system browser via
// url_launcher on the detail screen, not this service.)
//
// HONESTY: an unmatched query returns an empty result, never a fabricated row.
// A malformed entry is dropped, not rendered as a blank line.
//
// ATTRIBUTION: the destinations portion of the directory (the wlan-talks library
// — conference archives, YouTube, podcasts, independent blogs, training) is
// credited "Inspired by wlan-talks.net by Victor Njoroge" per `_meta.attribution`
// and scoped per `_meta.attribution_scope` to the destinations buckets only. The
// service exposes [attribution] and the [destinationTopics] set so the screen can
// place the credit only under the destination groups, never on the canonical
// tools / vendor-doc entries.
//
// APPROVAL: every entry carries an `approval` field ('not_required' /
// 'pending_outreach') driving Keith's pre-publish pruning. This build shows ALL
// 52 entries (the field is kept on the model so a future pre-publish filter is
// trivial — it is NOT used to hide anything here).

import 'dart:convert';

/// Cost tier of a resource, as published in the dataset.
enum ResourceCost { free, mixed, paid, unknown }

extension ResourceCostLabel on ResourceCost {
  /// Human-facing badge label.
  String get label {
    switch (this) {
      case ResourceCost.free:
        return 'Free';
      case ResourceCost.mixed:
        return 'Free + paid';
      case ResourceCost.paid:
        return 'Paid';
      case ResourceCost.unknown:
        return 'Cost varies';
    }
  }

  /// Parse a wire token (case-insensitive). Unknown tokens map to
  /// [ResourceCost.unknown] so a new/typo'd value renders an honest neutral
  /// badge rather than dropping the field.
  static ResourceCost parse(String token) {
    switch (token.trim().toLowerCase()) {
      case 'free':
        return ResourceCost.free;
      case 'mixed':
        return ResourceCost.mixed;
      case 'paid':
        return ResourceCost.paid;
      default:
        return ResourceCost.unknown;
    }
  }
}

/// Audience level of a resource, as published in the dataset.
enum ResourceLevel { all, beginner, intermediate, advanced, unknown }

extension ResourceLevelLabel on ResourceLevel {
  /// Human-facing badge label.
  String get label {
    switch (this) {
      case ResourceLevel.all:
        return 'All levels';
      case ResourceLevel.beginner:
        return 'Beginner';
      case ResourceLevel.intermediate:
        return 'Intermediate';
      case ResourceLevel.advanced:
        return 'Advanced';
      case ResourceLevel.unknown:
        return 'Any level';
    }
  }

  /// Parse a wire token (case-insensitive). Unknown tokens map to
  /// [ResourceLevel.unknown].
  static ResourceLevel parse(String token) {
    switch (token.trim().toLowerCase()) {
      case 'all':
        return ResourceLevel.all;
      case 'beginner':
        return ResourceLevel.beginner;
      case 'intermediate':
        return ResourceLevel.intermediate;
      case 'advanced':
        return ResourceLevel.advanced;
      default:
        return ResourceLevel.unknown;
    }
  }
}

/// Pre-publish approval status. Metadata only in this build — kept on the model
/// so a future "hide pending_outreach before public publish" filter is a
/// one-line `where`, never a re-parse.
enum ResourceApproval { notRequired, pendingOutreach, unknown }

extension ResourceApprovalToken on ResourceApproval {
  /// Parse a wire token (case-insensitive).
  static ResourceApproval parse(String token) {
    switch (token.trim().toLowerCase()) {
      case 'not_required':
        return ResourceApproval.notRequired;
      case 'pending_outreach':
        return ResourceApproval.pendingOutreach;
      default:
        return ResourceApproval.unknown;
    }
  }
}

/// One educational resource entry.
class EducationalResource {
  const EducationalResource({
    required this.id,
    required this.title,
    required this.summary,
    required this.description,
    required this.url,
    required this.topic,
    required this.cost,
    required this.level,
    required this.tags,
    required this.approval,
  });

  /// Stable identifier (kebab-case).
  final String id;

  /// Resource title.
  final String title;

  /// One-line summary shown on the directory list row.
  final String summary;

  /// One-to-two-paragraph offline reading copy shown on the detail screen.
  final String description;

  /// Destination URL, opened in the system browser from the detail screen.
  final String url;

  /// Editorial topic group (one of the 7 `_meta.topics`).
  final String topic;

  /// Cost tier.
  final ResourceCost cost;

  /// Audience level.
  final ResourceLevel level;

  /// Free-form tags.
  final List<String> tags;

  /// Pre-publish approval status (metadata; not used to hide entries here).
  final ResourceApproval approval;

  /// Build from a decoded JSON map. Returns null when the row is malformed
  /// (missing id/title/topic, or no usable url) so a bad asset row is dropped
  /// rather than crashing the load or rendering a blank line.
  static EducationalResource? fromMap(Map<String, dynamic> map) {
    final String id = _str(map['id']);
    final String title = _str(map['title']);
    final String topic = _str(map['topic']);
    final String url = _str(map['url']);
    if (id.isEmpty || title.isEmpty || topic.isEmpty || url.isEmpty) {
      return null;
    }

    final List<String> tags = <String>[];
    final Object? rawTags = map['tags'];
    if (rawTags is List) {
      for (final Object? t in rawTags) {
        if (t is String && t.trim().isNotEmpty) tags.add(t.trim());
      }
    }

    return EducationalResource(
      id: id,
      title: title,
      summary: _str(map['summary']),
      description: _str(map['description']),
      url: url,
      topic: topic,
      cost: ResourceCostLabel.parse(_str(map['cost'])),
      level: ResourceLevelLabel.parse(_str(map['level'])),
      tags: List<String>.unmodifiable(tags),
      approval: ResourceApprovalToken.parse(_str(map['approval'])),
    );
  }

  static String _str(Object? v) => v is String ? v.trim() : '';
}

/// A topic group: a header plus the resources under it, in asset order.
class ResourceGroup {
  const ResourceGroup({required this.topic, required this.resources});

  /// The topic name (the group header).
  final String topic;

  /// Resources in this topic, in asset order.
  final List<EducationalResource> resources;

  /// Number of resources in the group.
  int get count => resources.length;
}

/// Indexes the Educational Resources directory and answers grouping + search.
class EducationalResourcesService {
  /// Build directly from parsed entries (used by tests and by [fromJson]).
  EducationalResourcesService.fromEntries(
    List<EducationalResource> entries, {
    this.title = 'Educational Resources',
    this.attribution = '',
    Set<String>? topicOrder,
  })  : _entries = List<EducationalResource>.unmodifiable(entries),
        _topicOrder = topicOrder == null
            ? null
            : List<String>.unmodifiable(topicOrder);

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `resources` array.
  factory EducationalResourcesService.fromJson(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      return EducationalResourcesService.fromEntries(
        const <EducationalResource>[],
      );
    }

    final List<EducationalResource> entries = parseEntries(decoded);

    String title = 'Educational Resources';
    String attribution = '';
    Set<String>? topicOrder;
    final Object? meta = decoded['_meta'];
    if (meta is Map<String, dynamic>) {
      final String t = EducationalResource._str(meta['title']);
      if (t.isNotEmpty) title = t;
      attribution = EducationalResource._str(meta['attribution']);
      final Object? rawTopics = meta['topics'];
      if (rawTopics is List) {
        final List<String> order = <String>[];
        for (final Object? x in rawTopics) {
          if (x is String && x.trim().isNotEmpty) order.add(x.trim());
        }
        if (order.isNotEmpty) topicOrder = order.toSet();
      }
    }

    return EducationalResourcesService.fromEntries(
      entries,
      title: title,
      attribution: attribution,
      topicOrder: topicOrder,
    );
  }

  final List<EducationalResource> _entries;

  /// The editorial topic order from `_meta.topics`, or null when absent (then
  /// groups fall back to first-seen order). Preserved as an ordered set.
  final List<String>? _topicOrder;

  /// Directory title from `_meta.title`.
  final String title;

  /// The destinations attribution line from `_meta.attribution`. Display ONLY
  /// in association with the [destinationTopics] groups (never on the canonical
  /// tools / vendor-doc groups) per `_meta.attribution_scope`.
  final String attribution;

  /// The topic groups whose entries are the wlan-talks "destinations" set the
  /// [attribution] credit applies to (per `_meta.attribution_scope`). These are
  /// the five destination buckets; the two canonical buckets — "Tools and
  /// utilities" and "Vendor documentation and design guides" — are deliberately
  /// excluded so the credit never attaches to the vendor-doc / tools entries.
  static const Set<String> destinationTopics = <String>{
    'Conference and talk archives',
    'YouTube channels',
    'Podcasts',
    'Independent blogs and experts',
    'Training and certification',
  };

  /// `true` when [topic] is one of the credited destination buckets.
  bool isDestinationTopic(String topic) => destinationTopics.contains(topic);

  /// All entries, in asset order.
  List<EducationalResource> get all => _entries;

  /// Number of entries loaded.
  int get count => _entries.length;

  /// Parse the decoded asset document into a list of entries. Static + pure so
  /// the parse is unit-testable without constructing a service.
  static List<EducationalResource> parseEntries(Map<String, dynamic> decoded) {
    final Object? rawResources = decoded['resources'];
    if (rawResources is! List) return const <EducationalResource>[];
    final List<EducationalResource> out = <EducationalResource>[];
    for (final Object? row in rawResources) {
      if (row is Map<String, dynamic>) {
        final EducationalResource? e = EducationalResource.fromMap(row);
        if (e != null) out.add(e);
      }
    }
    return out;
  }

  /// Look up a single resource by id, or null when absent.
  EducationalResource? byId(String id) {
    for (final EducationalResource e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Group [entries] (default: all) by `topic`, ordered by `_meta.topics` when
  /// present (then any unlisted topic appended in first-seen order), otherwise
  /// purely first-seen. Empty topics are omitted.
  List<ResourceGroup> grouped([List<EducationalResource>? entries]) {
    final List<EducationalResource> source = entries ?? _entries;

    // Bucket by topic, preserving asset order within each bucket.
    final Map<String, List<EducationalResource>> buckets =
        <String, List<EducationalResource>>{};
    final List<String> firstSeen = <String>[];
    for (final EducationalResource e in source) {
      final List<EducationalResource> bucket =
          buckets.putIfAbsent(e.topic, () {
        firstSeen.add(e.topic);
        return <EducationalResource>[];
      });
      bucket.add(e);
    }

    // Header order: the editorial `_meta.topics` order first (only those that
    // actually have entries), then any topic not listed there, first-seen.
    final List<String> order = <String>[];
    final List<String>? editorial = _topicOrder;
    if (editorial != null) {
      for (final String t in editorial) {
        if (buckets.containsKey(t) && !order.contains(t)) order.add(t);
      }
    }
    for (final String t in firstSeen) {
      if (!order.contains(t)) order.add(t);
    }

    return <ResourceGroup>[
      for (final String t in order)
        ResourceGroup(topic: t, resources: buckets[t]!),
    ];
  }

  /// Case-insensitive substring search across title, summary, description,
  /// topic, and tags. Whitespace-only or empty query returns all entries (in
  /// asset order) so the screen shows the full directory before the user types.
  /// Results preserve asset order so grouping stays stable.
  List<EducationalResource> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((EducationalResource e) {
      if (e.title.toLowerCase().contains(q)) return true;
      if (e.summary.toLowerCase().contains(q)) return true;
      if (e.description.toLowerCase().contains(q)) return true;
      if (e.topic.toLowerCase().contains(q)) return true;
      for (final String tag in e.tags) {
        if (tag.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }
}
