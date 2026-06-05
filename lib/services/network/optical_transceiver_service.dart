// OpticalTransceiverService — an offline, bundled reference of optical Ethernet
// transceiver variants (1G–400G) plus the SFP→OSFP form-factor ladder.
//
// WHAT IT DOES: indexes a curated, verified table (assets/data/
// optical_transceivers.json, declared in pubspec.yaml) of the optical modules a
// network pro actually orders, grouped by speed tier, and answers the field's
// single most-asked question — "which module, and how far will it go?" — with a
// trustworthy reach-per-fiber number. It also carries the 9-row form-factor
// table (max rate / lanes / power envelope).
//
// OFFLINE / NO NETWORK: the table is a bundled asset loaded and parsed ONCE at
// startup and cached in memory for the process lifetime. No HTTP, no `dart:io`,
// NO Flutter imports — the screen reads the asset string via rootBundle and
// hands it to `OpticalTransceiverService.fromJson`, so the logic is pure Dart
// and unit-testable from an in-memory string (mirrors PortReferenceService).
//
// HONESTY (GL-005): IEEE-ratified variants are neutral; vendor / coherent
// variants (ZR/ZX/EX, 400G-ZR) carry `vendor == true` and a `reachCaveat`
// preserved verbatim from the dataset ("loss-budget dependent"). The service
// NEVER strips that hedge and NEVER presents a vendor reach as an IEEE figure —
// the `vendor` flag is what the screen renders as the amber VENDOR chip. An
// unmatched query returns empty tiers, never a fabricated row.
//
// ASSET SOURCE: Pax verification brief 2026-06-05 (IEEE 802.3 standards tables +
// Cisco / FS.com vendor datasheets). Provenance is recorded in the asset `_meta`.

import 'dart:convert';

/// Whether a fiber spec is multimode, single-mode, or both — a category aid
/// only; the human-readable `fiber` string always carries the authoritative
/// fact (label-not-color, per GL-003 §8.13 rule 2).
enum OpticalFiberKind { mmf, smf, mixed }

extension OpticalFiberKindParse on OpticalFiberKind {
  static OpticalFiberKind fromToken(String token) {
    switch (token.trim().toLowerCase()) {
      case 'mmf':
        return OpticalFiberKind.mmf;
      case 'smf':
        return OpticalFiberKind.smf;
      default:
        return OpticalFiberKind.mixed;
    }
  }
}

/// Connector class — LC/SC duplex vs MPO parallel. Used only to tint the
/// connector chip; the `connector` string carries the real value.
enum OpticalConnectorKind { lc, mpo }

extension OpticalConnectorKindParse on OpticalConnectorKind {
  static OpticalConnectorKind fromToken(String token) {
    return token.trim().toLowerCase() == 'mpo'
        ? OpticalConnectorKind.mpo
        : OpticalConnectorKind.lc;
  }
}

/// One optical transceiver variant (e.g. 10GBASE-SR, 400GBASE-ZR).
class OpticalVariant {
  const OpticalVariant({
    required this.designation,
    required this.rate,
    required this.reach,
    required this.fiber,
    required this.fiberKind,
    required this.wavelength,
    required this.connector,
    required this.connectorKind,
    required this.notes,
    required this.vendor,
    required this.reachCaveat,
  });

  /// IEEE / vendor designation string (e.g. `100GBASE-LR4`).
  final String designation;

  /// Data rate (e.g. `100 Gbps`).
  final String rate;

  /// Reach — IEEE maximum on the listed fiber. The field's most-asked number.
  final String reach;

  /// Fiber spec string (e.g. `MMF (OM3-OM4)`, `SMF (OS2)`). Authoritative.
  final String fiber;

  /// Fiber category aid (mmf / smf / mixed).
  final OpticalFiberKind fiberKind;

  /// Wavelength (e.g. `850 nm`, `~1295-1310 nm (4x LWDM)`).
  final String wavelength;

  /// Connector spec string (e.g. `LC`, `MPO-12`). Authoritative.
  final String connector;

  /// Connector category aid (lc / mpo).
  final OpticalConnectorKind connectorKind;

  /// One-line plain-language note (verbatim from the dataset).
  final String notes;

  /// True for vendor / coherent variants that are NOT IEEE-ratified. Drives the
  /// amber VENDOR chip and the loss-budget caveat. Never inferred at render —
  /// the asset is the source of truth so the hedge can never be lost.
  final bool vendor;

  /// The verbatim "loss-budget dependent" caveat shown in the warning token
  /// beside the reach for vendor rows. Empty for IEEE rows.
  final String reachCaveat;

  /// Build from a decoded JSON map. Returns null when the row is structurally
  /// broken (no designation) so a bad asset row is dropped, never rendered
  /// blank.
  static OpticalVariant? fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    final String designation = str('designation');
    if (designation.isEmpty) return null;

    final Object? rawVendor = map['vendor'];
    final bool vendor = rawVendor is bool ? rawVendor : false;

    return OpticalVariant(
      designation: designation,
      rate: str('rate'),
      reach: str('reach'),
      fiber: str('fiber'),
      fiberKind: OpticalFiberKindParse.fromToken(str('fiberKind')),
      wavelength: str('wavelength'),
      connector: str('connector'),
      connectorKind: OpticalConnectorKindParse.fromToken(str('connectorKind')),
      notes: str('notes'),
      vendor: vendor,
      reachCaveat: str('reachCaveat'),
    );
  }

  /// Lowercased haystack for substring search: every human-facing field plus
  /// the tier label (injected by the tier) so "100g", "lr4", "850 nm", "mpo",
  /// "om4", and "reach"-style numeric tokens all match.
  String searchHaystack(String tierLabel) => <String>[
        designation,
        rate,
        reach,
        fiber,
        wavelength,
        connector,
        notes,
        tierLabel,
        vendor ? 'vendor' : 'ieee',
      ].join(' ').toLowerCase();
}

/// A speed tier (e.g. 10G / SFP+) holding its ordered variants. `lead` marks the
/// commonly-ordered tiers (10G/25G/100G) the screen surfaces first.
class OpticalTier {
  const OpticalTier({
    required this.tier,
    required this.formFactor,
    required this.lead,
    required this.entries,
  });

  /// Short tier label (e.g. `100G`).
  final String tier;

  /// The form factor this tier rides in (e.g. `QSFP28`).
  final String formFactor;

  /// True for the commonly-ordered lead tiers (10G/25G/100G).
  final bool lead;

  /// Variants in this tier, in asset order.
  final List<OpticalVariant> entries;

  /// A copy of this tier with only the variants that match [query] (already
  /// matched by the service); returns null when nothing matches so the tier is
  /// dropped from results rather than shown empty.
  OpticalTier? withEntries(List<OpticalVariant> matched) {
    if (matched.isEmpty) return null;
    return OpticalTier(
      tier: tier,
      formFactor: formFactor,
      lead: lead,
      entries: List<OpticalVariant>.unmodifiable(matched),
    );
  }

  static OpticalTier? fromMap(Map<String, dynamic> map) {
    final Object? rawTier = map['tier'];
    final String tier = rawTier is String ? rawTier.trim() : '';
    if (tier.isEmpty) return null;

    final Object? rawFf = map['formFactor'];
    final String formFactor = rawFf is String ? rawFf.trim() : '';

    final Object? rawLead = map['lead'];
    final bool lead = rawLead is bool ? rawLead : false;

    final List<OpticalVariant> entries = <OpticalVariant>[];
    final Object? rawEntries = map['entries'];
    if (rawEntries is List) {
      for (final Object? row in rawEntries) {
        if (row is Map<String, dynamic>) {
          final OpticalVariant? v = OpticalVariant.fromMap(row);
          if (v != null) entries.add(v);
        }
      }
    }
    if (entries.isEmpty) return null;

    return OpticalTier(
      tier: tier,
      formFactor: formFactor,
      lead: lead,
      entries: List<OpticalVariant>.unmodifiable(entries),
    );
  }
}

/// One form-factor table row (e.g. QSFP28 / 100 Gbps / 4 lanes / ~3.5-4.5 W).
class OpticalFormFactor {
  const OpticalFormFactor({
    required this.formFactor,
    required this.maxRate,
    required this.lanes,
    required this.power,
    required this.notes,
  });

  final String formFactor;
  final String maxRate;
  final String lanes;
  final String power;
  final String notes;

  static OpticalFormFactor? fromMap(Map<String, dynamic> map) {
    String str(String key) {
      final Object? v = map[key];
      return v is String ? v.trim() : '';
    }

    final String formFactor = str('formFactor');
    if (formFactor.isEmpty) return null;

    return OpticalFormFactor(
      formFactor: formFactor,
      maxRate: str('maxRate'),
      lanes: str('lanes'),
      power: str('power'),
      notes: str('notes'),
    );
  }
}

/// Parses and indexes the optical-transceiver table; answers a substring search
/// over the variants (preserving tier order) and exposes the form-factor table.
class OpticalTransceiverService {
  OpticalTransceiverService.fromParts({
    required List<OpticalTier> tiers,
    required List<OpticalFormFactor> formFactors,
  })  : _tiers = List<OpticalTier>.unmodifiable(tiers),
        _formFactors = List<OpticalFormFactor>.unmodifiable(formFactors);

  /// Build from the raw asset JSON string. Tolerant of malformed rows: bad
  /// entries are skipped, never thrown. Returns an empty-but-valid service if
  /// the document has no usable `tiers`.
  factory OpticalTransceiverService.fromJson(String jsonString) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      return OpticalTransceiverService.fromParts(
        tiers: const <OpticalTier>[],
        formFactors: const <OpticalFormFactor>[],
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return OpticalTransceiverService.fromParts(
        tiers: const <OpticalTier>[],
        formFactors: const <OpticalFormFactor>[],
      );
    }

    final List<OpticalTier> tiers = <OpticalTier>[];
    final Object? rawTiers = decoded['tiers'];
    if (rawTiers is List) {
      for (final Object? row in rawTiers) {
        if (row is Map<String, dynamic>) {
          final OpticalTier? t = OpticalTier.fromMap(row);
          if (t != null) tiers.add(t);
        }
      }
    }

    final List<OpticalFormFactor> ffs = <OpticalFormFactor>[];
    final Object? rawFfs = decoded['formFactors'];
    if (rawFfs is List) {
      for (final Object? row in rawFfs) {
        if (row is Map<String, dynamic>) {
          final OpticalFormFactor? f = OpticalFormFactor.fromMap(row);
          if (f != null) ffs.add(f);
        }
      }
    }

    return OpticalTransceiverService.fromParts(tiers: tiers, formFactors: ffs);
  }

  final List<OpticalTier> _tiers;
  final List<OpticalFormFactor> _formFactors;

  /// All tiers, in asset (editorial) order — lead tiers first.
  List<OpticalTier> get tiers => _tiers;

  /// The form-factor ladder table (SFP → OSFP).
  List<OpticalFormFactor> get formFactors => _formFactors;

  /// Total number of optical variants across all tiers.
  int get variantCount =>
      _tiers.fold<int>(0, (int n, OpticalTier t) => n + t.entries.length);

  /// Number of form-factor rows.
  int get formFactorCount => _formFactors.length;

  /// Search the variants by substring across designation, reach, fiber,
  /// wavelength, connector, notes, and tier label (case-insensitive).
  ///
  /// Returns the tiers IN ASSET ORDER, each holding only its matching variants;
  /// tiers with no match are dropped. An empty / whitespace query returns every
  /// tier unfiltered (so the screen shows the full grouped table before the user
  /// types). Honesty: a no-match query returns an empty list, never a fabricated
  /// tier or row.
  List<OpticalTier> search(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return _tiers;

    final List<OpticalTier> out = <OpticalTier>[];
    for (final OpticalTier tier in _tiers) {
      final List<OpticalVariant> matched = tier.entries
          .where((OpticalVariant v) => v.searchHaystack(tier.tier).contains(q))
          .toList();
      final OpticalTier? narrowed = tier.withEntries(matched);
      if (narrowed != null) out.add(narrowed);
    }
    return out;
  }
}
