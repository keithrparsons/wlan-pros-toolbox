// WifiToolsComparisonService — an offline, bundled reference comparing
// professional Wi-Fi survey, design, spectrum, and troubleshooting toolkits,
// grouped by the activity they serve.
//
// WHAT IT DOES: indexes a curated, vendor-interviewed comparison
// (assets/data/wifi_tools_comparison.json, declared in pubspec.yaml) of the
// toolkit configurations a Wi-Fi professional assembles, grouped by the four
// activities (Design / Validation / Spectrum Analysis / Troubleshooting). Each
// config carries its vendor, product, cost model, up-front cost, 3-year TCO, and
// a neutral capability note. A separate per-vendor summary list and a
// "typical toolkit" roll-up ride alongside.
//
// OFFLINE / NO NETWORK: the table is a bundled asset loaded and parsed ONCE at
// screen open and held for the process lifetime. No HTTP, no `dart:io`, NO
// Flutter imports — the screen reads the asset string via rootBundle and hands
// it to `WifiToolsComparisonService.fromJson`, so the logic is pure Dart and
// unit-testable from an in-memory string (mirrors OpticalTransceiverService).
//
// NEUTRALITY + HONESTY (GL-005 / GL-007 / Pax brief 2026-06-05):
//  - This is a CAPABILITY AND COST REFERENCE, not a ranking. There is no rank,
//    no score, no "best" field in the schema — that absence is the neutrality
//    guarantee. Configs sort alphabetically by vendor within each activity (the
//    service preserves asset order, which the asset already sorts).
//  - TCO and up-front figures are MODELED ESTIMATES carried verbatim from the
//    source workbook plus a date-stamp and a modeled-estimate disclaimer in
//    `meta`. The service never invents, rounds, or recomputes a price; an
//    unparseable amount is dropped to null, never faked.
//  - The dataset ships with a beta-review note (vendors are being consulted on
//    the figures) and a no-logos note (trademarks/photos pending written
//    permission). Tamosoft is intentionally absent from the dataset (removed by
//    Keith 2026-06-05); the service contains no Tamosoft-specific handling — it
//    simply renders whatever vendors the asset lists.
//
// An unmatched query returns empty activities, never a fabricated config.

import 'dart:convert';

/// Cost / license model for a config — a category aid only. The human-readable
/// label always carries the authoritative fact (label-not-color, GL-003
/// §8.13 rule 2).
enum WifiToolCostModel { perpetual, subscription, oneTime, quote, unknown }

extension WifiToolCostModelParse on WifiToolCostModel {
  static WifiToolCostModel fromToken(String token) {
    switch (token.trim().toLowerCase()) {
      case 'perpetual':
        return WifiToolCostModel.perpetual;
      case 'subscription':
        return WifiToolCostModel.subscription;
      case 'one-time':
      case 'one time':
      case 'onetime':
        return WifiToolCostModel.oneTime;
      case 'quote':
        return WifiToolCostModel.quote;
      default:
        return WifiToolCostModel.unknown;
    }
  }

  /// Short human label for the cost-model chip. Always paired with the text
  /// (never color-only meaning).
  String get label {
    switch (this) {
      case WifiToolCostModel.perpetual:
        return 'Perpetual';
      case WifiToolCostModel.subscription:
        return 'Subscription';
      case WifiToolCostModel.oneTime:
        return 'One-time';
      case WifiToolCostModel.quote:
        return 'Quote';
      case WifiToolCostModel.unknown:
        return 'See vendor';
    }
  }
}

/// The disclaimer / date-stamp / neutrality bundle from the asset `_meta`. Every
/// string is surfaced on-screen so no honesty caveat lives only in the data.
class WifiToolsComparisonMeta {
  const WifiToolsComparisonMeta({
    required this.pricingDate,
    required this.pricingNote,
    required this.estimateNote,
    required this.betaNote,
    required this.neutralityNote,
    required this.noLogosNote,
    required this.currency,
    required this.tcoLabel,
    required this.source,
  });

  /// Human pricing date-stamp (e.g. `July 2026`).
  final String pricingDate;

  /// "Pricing as of `<date>`, confirm current pricing with the vendor" line.
  final String pricingNote;

  /// "Figures are modeled estimates" disclaimer (GL-005 truthfulness rule).
  final String estimateNote;

  /// "This comparison is in beta review; vendors are being consulted" line.
  final String betaNote;

  /// "This is not a ranking; alphabetical; assembled across vendors" framing.
  final String neutralityNote;

  /// "No logos or product photos; permission pending" line.
  final String noLogosNote;

  /// Currency code for the figures (e.g. `USD`).
  final String currency;

  /// Label for the total-cost column (e.g. `3-year TCO`).
  final String tcoLabel;

  /// Provenance string.
  final String source;

  static WifiToolsComparisonMeta fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    return WifiToolsComparisonMeta(
      pricingDate: str('pricingDate'),
      pricingNote: str('pricingNote'),
      estimateNote: str('estimateNote'),
      betaNote: str('betaNote'),
      neutralityNote: str('neutralityNote'),
      noLogosNote: str('noLogosNote'),
      currency: str('currency').isEmpty ? 'USD' : str('currency'),
      tcoLabel: str('tcoLabel').isEmpty ? '3-year TCO' : str('tcoLabel'),
      source: str('source'),
    );
  }

  static const WifiToolsComparisonMeta empty = WifiToolsComparisonMeta(
    pricingDate: '',
    pricingNote: '',
    estimateNote: '',
    betaNote: '',
    neutralityNote: '',
    noLogosNote: '',
    currency: 'USD',
    tcoLabel: '3-year TCO',
    source: '',
  );
}

/// One toolkit configuration within an activity (e.g. "Ekahau AI Pro + Connect"
/// under Design).
class WifiToolConfig {
  const WifiToolConfig({
    required this.vendor,
    required this.product,
    required this.costModel,
    required this.upFront,
    required this.tco3yr,
    required this.notes,
  });

  /// Vendor name (e.g. `Ekahau`). Authoritative.
  final String vendor;

  /// Product / bundle name (e.g. `Ekahau AI Pro + Connect`). Authoritative.
  final String product;

  /// Cost / license model category aid.
  final WifiToolCostModel costModel;

  /// Up-front cost in the asset currency, or null when not given. A modeled
  /// estimate, never recomputed by the service.
  final int? upFront;

  /// 3-year total cost of ownership in the asset currency, or null when not
  /// given. A modeled estimate, never recomputed by the service.
  final int? tco3yr;

  /// One-line neutral capability note (verbatim from the dataset, including any
  /// "does not include …" scope flag).
  final String notes;

  static int? _intOrNull(Object? v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) {
      final String t = v.trim();
      if (t.isEmpty) return null;
      return int.tryParse(t);
    }
    return null;
  }

  /// Build from a decoded JSON map. Returns null when the row has no vendor or
  /// product so a structurally broken row is dropped, never rendered blank.
  static WifiToolConfig? fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    final String vendor = str('vendor');
    final String product = str('product');
    if (vendor.isEmpty || product.isEmpty) return null;

    return WifiToolConfig(
      vendor: vendor,
      product: product,
      costModel: WifiToolCostModelParse.fromToken(str('costModel')),
      upFront: _intOrNull(map['upFront']),
      tco3yr: _intOrNull(map['tco3yr']),
      notes: str('notes'),
    );
  }

  /// Lowercased haystack for substring search across every human-facing field
  /// plus the activity title (injected by the activity).
  String searchHaystack(String activityTitle) => <String>[
        vendor,
        product,
        notes,
        activityTitle,
        costModel.label,
      ].join(' ').toLowerCase();
}

/// One activity grouping (Design / Validation / Spectrum / Troubleshooting)
/// holding its configs in asset order.
class WifiToolActivity {
  const WifiToolActivity({
    required this.id,
    required this.title,
    required this.intro,
    required this.configs,
  });

  /// Stable activity id (e.g. `design`).
  final String id;

  /// Display title (e.g. `Wi-Fi Design`).
  final String title;

  /// Neutral one-paragraph explanation of the activity (verbatim from dataset).
  final String intro;

  /// Configs in this activity, in asset order (the asset sorts alphabetically by
  /// vendor).
  final List<WifiToolConfig> configs;

  /// A copy of this activity with only [matched] configs; returns null when the
  /// match is empty so the activity is dropped from results rather than shown
  /// empty.
  WifiToolActivity? withConfigs(List<WifiToolConfig> matched) {
    if (matched.isEmpty) return null;
    return WifiToolActivity(
      id: id,
      title: title,
      intro: intro,
      configs: List<WifiToolConfig>.unmodifiable(matched),
    );
  }

  static WifiToolActivity? fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    final String title = str('title');
    if (title.isEmpty) return null;

    final String id = str('id');

    final List<WifiToolConfig> configs = <WifiToolConfig>[];
    final Object? rawConfigs = map['configs'];
    if (rawConfigs is List) {
      for (final Object? row in rawConfigs) {
        if (row is Map<String, dynamic>) {
          final WifiToolConfig? c = WifiToolConfig.fromMap(row);
          if (c != null) configs.add(c);
        }
      }
    }
    if (configs.isEmpty) return null;

    return WifiToolActivity(
      id: id.isEmpty ? title.toLowerCase() : id,
      title: title,
      intro: str('intro'),
      configs: List<WifiToolConfig>.unmodifiable(configs),
    );
  }
}

/// One "typical professional toolkit" roll-up row.
class WifiToolkit {
  const WifiToolkit({
    required this.vendor,
    required this.product,
    required this.tco3yr,
    required this.notes,
  });

  final String vendor;
  final String product;
  final int? tco3yr;
  final String notes;

  static WifiToolkit? fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    final String vendor = str('vendor');
    final String product = str('product');
    if (vendor.isEmpty || product.isEmpty) return null;

    return WifiToolkit(
      vendor: vendor,
      product: product,
      tco3yr: WifiToolConfig._intOrNull(map['tco3yr']),
      notes: str('notes'),
    );
  }
}

/// One per-vendor neutral summary + its verified link-outs.
class WifiToolVendor {
  const WifiToolVendor({
    required this.name,
    required this.summary,
    required this.website,
    required this.docs,
  });

  final String name;
  final String summary;

  /// Vendor website URL (https). May be empty.
  final String website;

  /// Docs / support URL (`https`). May be empty.
  final String docs;

  static WifiToolVendor? fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    final String name = str('name');
    if (name.isEmpty) return null;

    return WifiToolVendor(
      name: name,
      summary: str('summary'),
      website: str('website'),
      docs: str('docs'),
    );
  }
}

/// Parses and indexes the Wi-Fi tools comparison; answers a substring search
/// over the configs (preserving activity order) and exposes the toolkit roll-up,
/// the per-vendor summaries, and the disclaimer meta.
class WifiToolsComparisonService {
  WifiToolsComparisonService.fromParts({
    required this.meta,
    required List<WifiToolActivity> activities,
    required List<WifiToolkit> toolkits,
    required List<WifiToolVendor> vendors,
  })  : _activities = List<WifiToolActivity>.unmodifiable(activities),
        _toolkits = List<WifiToolkit>.unmodifiable(toolkits),
        _vendors = List<WifiToolVendor>.unmodifiable(vendors);

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service when
  /// the document is unusable.
  factory WifiToolsComparisonService.fromJson(String jsonString) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      return WifiToolsComparisonService.empty();
    }
    if (decoded is! Map<String, dynamic>) {
      return WifiToolsComparisonService.empty();
    }

    final Object? rawMeta = decoded['_meta'];
    final WifiToolsComparisonMeta meta = rawMeta is Map<String, dynamic>
        ? WifiToolsComparisonMeta.fromMap(rawMeta)
        : WifiToolsComparisonMeta.empty;

    final List<WifiToolActivity> activities = <WifiToolActivity>[];
    final Object? rawActivities = decoded['activities'];
    if (rawActivities is List) {
      for (final Object? row in rawActivities) {
        if (row is Map<String, dynamic>) {
          final WifiToolActivity? a = WifiToolActivity.fromMap(row);
          if (a != null) activities.add(a);
        }
      }
    }

    final List<WifiToolkit> toolkits = <WifiToolkit>[];
    final Object? rawToolkits = decoded['toolkits'];
    if (rawToolkits is List) {
      for (final Object? row in rawToolkits) {
        if (row is Map<String, dynamic>) {
          final WifiToolkit? t = WifiToolkit.fromMap(row);
          if (t != null) toolkits.add(t);
        }
      }
    }

    final List<WifiToolVendor> vendors = <WifiToolVendor>[];
    final Object? rawVendors = decoded['vendors'];
    if (rawVendors is List) {
      for (final Object? row in rawVendors) {
        if (row is Map<String, dynamic>) {
          final WifiToolVendor? v = WifiToolVendor.fromMap(row);
          if (v != null) vendors.add(v);
        }
      }
    }

    return WifiToolsComparisonService.fromParts(
      meta: meta,
      activities: activities,
      toolkits: toolkits,
      vendors: vendors,
    );
  }

  factory WifiToolsComparisonService.empty() =>
      WifiToolsComparisonService.fromParts(
        meta: WifiToolsComparisonMeta.empty,
        activities: const <WifiToolActivity>[],
        toolkits: const <WifiToolkit>[],
        vendors: const <WifiToolVendor>[],
      );

  /// Disclaimer / date-stamp / neutrality bundle. Surfaced on-screen in full.
  final WifiToolsComparisonMeta meta;

  final List<WifiToolActivity> _activities;
  final List<WifiToolkit> _toolkits;
  final List<WifiToolVendor> _vendors;

  /// All activities, in asset (editorial) order: Design, Validation, Spectrum,
  /// Troubleshooting.
  List<WifiToolActivity> get activities => _activities;

  /// The "typical professional toolkit" roll-up rows, in asset order.
  List<WifiToolkit> get toolkits => _toolkits;

  /// The per-vendor neutral summaries + link-outs, in asset order.
  List<WifiToolVendor> get vendors => _vendors;

  /// Total number of configs across all activities.
  int get configCount =>
      _activities.fold<int>(0, (int n, WifiToolActivity a) => n + a.configs.length);

  /// Number of distinct vendors carried in the per-vendor list.
  int get vendorCount => _vendors.length;

  /// Search the configs by substring across vendor, product, notes, cost model,
  /// and activity title (case-insensitive).
  ///
  /// Returns the activities IN ASSET ORDER, each holding only its matching
  /// configs; activities with no match are dropped. An empty / whitespace query
  /// returns every activity unfiltered (so the screen shows the full grouped
  /// comparison before the user types). Honesty: a no-match query returns an
  /// empty list, never a fabricated activity or config.
  List<WifiToolActivity> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _activities;

    final List<WifiToolActivity> out = <WifiToolActivity>[];
    for (final WifiToolActivity activity in _activities) {
      final List<WifiToolConfig> matched = activity.configs
          .where((WifiToolConfig c) => c.searchHaystack(activity.title).contains(q))
          .toList();
      final WifiToolActivity? narrowed = activity.withConfigs(matched);
      if (narrowed != null) out.add(narrowed);
    }
    return out;
  }
}
