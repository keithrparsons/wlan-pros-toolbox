// Client Capabilities — what the device in the user's hand can actually do on
// Wi-Fi, and, for every field, WHERE that answer came from.
//
// Step 2 of the Client Capabilities build (spec:
// Deliverables/2026-07-31-client-capabilities-spec/SPEC.md). Pure Dart apart
// from `@immutable`: no platform channels, no assets, no I/O. The resolvers in
// `client_capability_resolver.dart` do the reading; this file only holds the
// shape of an answer.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE ONE RULE THIS FILE EXISTS TO ENFORCE
//
// A type that cannot express "unknown" will always be handed a guess. So there
// is no way to hold a Wi-Fi capability value in this app except through
// [Capability], and there is no way to construct a KNOWN capability without
// naming BOTH the tier it came from and a non-empty pin describing the exact
// source. The pin check throws in release builds too — an assert would let a
// pin-less value ship the moment asserts are stripped.
//
// Three consequences, all deliberate:
//
//  1. Unknown is per FIELD, not per device. A device whose standard we know but
//     whose maximum MCS index we do not renders one known row and one unknown
//     row. See [ClientCapabilities].
//  2. A lower tier can never silently masquerade as a higher one. There is no
//     tier value meaning "unknown" ([CapabilityTier] has exactly the two tiers
//     that can produce a value), and a value DERIVED from other capabilities
//     inherits the WEAKEST tier among its inputs, computed mechanically by
//     [Capability.derive] rather than asserted by the caller.
//  3. Absence carries a reason, never a blank. [CapabilityUnknownReason] makes
//     the screen say "your operating system does not report this" instead of
//     rendering an empty cell that reads as an oversight.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHAT A "KNOWN" VALUE STILL MIGHT NOT BE
//
// Some platform APIs answer a narrower question than the one we are asking.
// macOS `CWChannelWidth` has no 320 MHz case, so a Wi-Fi 7 Mac reporting 160 MHz
// through that enum may simply have hit the vocabulary's ceiling. That is a
// limit of the measurement, not of the radio, and reporting it as an exact
// "160 MHz" would be a quiet falsehood. [CapabilityBound.atLeast] exists for
// exactly this, and it propagates through [Capability.derive] the same way the
// tier does.

import 'package:flutter/foundation.dart' show immutable;

import 'wifi_details.dart' show WiFiBand;
import 'wifi_phy_rate_service.dart' show WifiPhyRateService, WifiStd;

/// Where a KNOWN capability value came from.
///
/// There is deliberately no member for "unknown". Unknown is not a source; it
/// is the absence of one, and it lives in [UnknownCapability]. Ordering is
/// load-bearing: a lower [index] is a stronger tier, and [Capability.derive]
/// takes the weakest (highest index) tier among its inputs.
enum CapabilityTier {
  /// Tier 1 — the operating system told us, live, on this device.
  livePlatformQuery('Read from this device'),

  /// Tier 2 — a published per-model table shipped with the app.
  ///
  /// Weaker than tier 1 because it is a claim about a model, not a reading from
  /// the radio in front of us, and because it goes stale when the publisher
  /// updates the document.
  publishedTable('Published specification for this model');

  const CapabilityTier(this.label);

  /// Short human label for the screen. No trailing punctuation.
  final String label;

  /// True when `this` is a weaker (later, less direct) tier than [other].
  bool isWeakerThan(CapabilityTier other) => index > other.index;
}

/// Whether a known value is exact, or only a floor.
enum CapabilityBound {
  /// The value is what the source reports, with no known truncation.
  exact,

  /// The real value is this OR HIGHER. Used when the source's own vocabulary
  /// cannot express a larger answer (see the macOS `CWChannelWidth` note in the
  /// file header). Renders as "160 MHz or more", never as "160 MHz".
  atLeast;

  /// The weaker of two bounds. [atLeast] wins, because a computation over a
  /// floor produces a floor.
  static CapabilityBound weakest(CapabilityBound a, CapabilityBound b) =>
      (a == CapabilityBound.atLeast || b == CapabilityBound.atLeast)
          ? CapabilityBound.atLeast
          : CapabilityBound.exact;
}

/// Why a capability is not known.
///
/// Every one of these is a first-class answer the screen can show. None of them
/// is an error state, and none of them is a reason to substitute a default.
enum CapabilityUnknownReason {
  /// The operating system exposes no API that reports this.
  platformDoesNotExpose('Your operating system does not report this'),

  /// This platform reads from a published table and this model is not in it.
  deviceNotInTable('This device model is not in our table'),

  /// An OS permission is required and has not been granted.
  permissionNotGranted('Needs permission before it can be read'),

  /// The platform call ran and came back with nothing usable, or failed.
  queryFailed('The system did not return a value'),

  /// No reader has been built for this platform yet.
  noReaderForPlatform('Not available on this platform yet'),

  /// A value computed from other capabilities, at least one of which is
  /// unknown. The detail names which one.
  derivedInputUnknown('Needs a value we do not have'),

  /// Every input was known, but the combination has no defined answer in the
  /// standard, so there is nothing honest to compute.
  notComputable('No defined value for this combination');

  const CapabilityUnknownReason(this.label);

  /// Sentence-case human label for the screen. No trailing period; the screen
  /// decides its own punctuation.
  final String label;
}

/// A single Wi-Fi capability value that may honestly be absent.
///
/// Sealed, so a caller cannot read a value without handling the unknown case.
/// Construct with [Capability.known] or [Capability.unknown]; compute one from
/// others with [Capability.derive].
@immutable
sealed class Capability<T extends Object> {
  const Capability();

  /// A value we actually have, with the tier and pin that justify it.
  ///
  /// [pin] must be non-empty and must name a checkable source, e.g.
  /// `'macOS CoreWLAN CWInterface.supportedWLANChannels()'` or
  /// `'Apple Platform Deployment, Wi-Fi specifications, iPhone16,1 row'`.
  /// Throws [ArgumentError] on a blank pin, in release builds as well as debug.
  factory Capability.known(
    T value, {
    required CapabilityTier tier,
    required String pin,
    CapabilityBound bound,
  }) = KnownCapability<T>;

  /// An honest absence, with the reason it is absent.
  const factory Capability.unknown(
    CapabilityUnknownReason reason, {
    String? detail,
  }) = UnknownCapability<T>;

  /// True when a value is present.
  bool get isKnown;

  /// The value, or null when unknown.
  ///
  /// Prefer a `switch` over the sealed type where the unknown branch needs its
  /// own copy. This accessor exists for arithmetic and comparisons, and it can
  /// never hand back a fabricated value because there is nothing to fabricate
  /// from.
  T? get valueOrNull;

  /// The tier of a known value, or null when unknown.
  CapabilityTier? get tierOrNull;

  /// The bound of a known value, or null when unknown.
  CapabilityBound? get boundOrNull;

  /// Compute a capability from other capabilities, without letting the result
  /// claim more than its weakest input.
  ///
  /// Returns [CapabilityUnknownReason.derivedInputUnknown] naming the first
  /// unknown input, so nothing is computed from a value we do not have. When
  /// every input is known, [compute] runs; returning null from [compute] means
  /// "the inputs were all known but the combination has no defined answer", and
  /// yields [CapabilityUnknownReason.notComputable].
  ///
  /// The result's tier is the WEAKEST tier among [inputs] and its bound is the
  /// weakest bound among them. Neither is passed in, so neither can be
  /// overstated by a caller.
  static Capability<R> derive<R extends Object>({
    required Map<String, Capability<Object>> inputs,
    required String pin,
    required R? Function() compute,
  }) {
    CapabilityTier? weakestTier;
    CapabilityBound bound = CapabilityBound.exact;
    for (final MapEntry<String, Capability<Object>> entry in inputs.entries) {
      final Capability<Object> input = entry.value;
      switch (input) {
        case UnknownCapability<Object>():
          return Capability<R>.unknown(
            CapabilityUnknownReason.derivedInputUnknown,
            detail: entry.key,
          );
        case KnownCapability<Object>(:final CapabilityTier tier):
          if (weakestTier == null || tier.isWeakerThan(weakestTier)) {
            weakestTier = tier;
          }
          bound = CapabilityBound.weakest(bound, input.bound);
      }
    }
    if (weakestTier == null) {
      // No inputs at all. A "derived" value with nothing to derive from would
      // be a fabrication wearing a derivation's clothes.
      return Capability<R>.unknown(
        CapabilityUnknownReason.derivedInputUnknown,
        detail: 'no inputs',
      );
    }
    final R? computed = compute();
    if (computed == null) {
      return Capability<R>.unknown(
        CapabilityUnknownReason.notComputable,
        detail: pin,
      );
    }
    return KnownCapability<R>(
      computed,
      tier: weakestTier,
      pin: pin,
      bound: bound,
    );
  }
}

/// A capability we have a value for.
@immutable
final class KnownCapability<T extends Object> extends Capability<T> {
  /// Creates a known capability. Throws [ArgumentError] when [pin] is blank —
  /// a value with no checkable source is the thing this whole file exists to
  /// prevent, so the check runs in release builds too.
  KnownCapability(
    this.value, {
    required this.tier,
    required String pin,
    this.bound = CapabilityBound.exact,
  }) : pin = pin.trim() {
    if (this.pin.isEmpty) {
      throw ArgumentError.value(
        pin,
        'pin',
        'A known capability must name its source. Use Capability.unknown() '
            'when there is no source.',
      );
    }
  }

  /// The value.
  final T value;

  /// Which tier produced it.
  final CapabilityTier tier;

  /// Whether the value is exact or a floor.
  final CapabilityBound bound;

  /// The checkable source: an API call, a document plus the row inside it, or
  /// the derivation. Never blank.
  final String pin;

  @override
  bool get isKnown => true;

  @override
  T? get valueOrNull => value;

  @override
  CapabilityTier? get tierOrNull => tier;

  @override
  CapabilityBound? get boundOrNull => bound;

  @override
  bool operator ==(Object other) =>
      other is KnownCapability<T> &&
      other.value == value &&
      other.tier == tier &&
      other.bound == bound &&
      other.pin == pin;

  @override
  int get hashCode => Object.hash(value, tier, bound, pin);

  @override
  String toString() =>
      'KnownCapability($value, tier: ${tier.name}, bound: ${bound.name}, '
      'pin: $pin)';
}

/// A capability we honestly do not have a value for.
@immutable
final class UnknownCapability<T extends Object> extends Capability<T> {
  /// Creates an honest absence.
  const UnknownCapability(this.reason, {this.detail});

  /// Why it is absent.
  final CapabilityUnknownReason reason;

  /// Optional specifics, e.g. which input was missing or which model was
  /// looked up and not found.
  final String? detail;

  @override
  bool get isKnown => false;

  @override
  T? get valueOrNull => null;

  @override
  CapabilityTier? get tierOrNull => null;

  @override
  CapabilityBound? get boundOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is UnknownCapability<T> &&
      other.reason == reason &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(reason, detail);

  @override
  String toString() => 'UnknownCapability(${reason.name}'
      '${detail == null ? '' : ', detail: $detail'})';
}

/// The Wi-Fi capabilities of one device, every field independently knowable.
///
/// Build one with [ClientCapabilities.allUnknown] and copy known fields in, so
/// a reader that resolves two of five fields cannot accidentally leave the
/// other three holding stale or defaulted values.
@immutable
class ClientCapabilities {
  /// Creates a capability set. Every field is required so a new field can never
  /// be silently omitted by an existing reader.
  const ClientCapabilities({
    required this.bands,
    required this.standards,
    required this.maxChannelWidthMhz,
    required this.spatialStreams,
    required this.maxMcsIndex,
    required this.osReportedMaxPhyRateMbps,
    this.deviceIdentifier,
    this.deviceName,
    this.tableVersion,
    this.notes = const <String>[],
  });

  /// Every field unknown, for one stated reason. This is tier 3 — a device we
  /// do not recognise on a platform we cannot query — and it is a first-class
  /// state, not an error.
  // NOT const: the initializer list constructs UnknownCapability from
  // parameters, which a const constructor cannot do.
  ClientCapabilities.allUnknown(
    CapabilityUnknownReason reason, {
    String? detail,
    this.deviceIdentifier,
    this.deviceName,
    this.tableVersion,
    this.notes = const <String>[],
  })  : bands = UnknownCapability<Set<WiFiBand>>(reason, detail: detail),
        standards = UnknownCapability<Set<WifiStd>>(reason, detail: detail),
        maxChannelWidthMhz = UnknownCapability<int>(reason, detail: detail),
        spatialStreams = UnknownCapability<int>(reason, detail: detail),
        maxMcsIndex = UnknownCapability<int>(reason, detail: detail),
        osReportedMaxPhyRateMbps =
            UnknownCapability<int>(reason, detail: detail);

  /// Frequency bands the radio supports.
  final Capability<Set<WiFiBand>> bands;

  /// Wi-Fi generations the radio supports, as the PHY-rate math names them
  /// (HT / VHT / HE / EHT). Pre-HT modes (802.11a/b/g) are out of scope: they
  /// have no entry in the rate tables and no bearing on a modern ceiling.
  final Capability<Set<WifiStd>> standards;

  /// Widest channel the radio supports, in MHz.
  final Capability<int> maxChannelWidthMhz;

  /// Spatial streams the radio supports.
  final Capability<int> spatialStreams;

  /// Highest MCS index the radio supports.
  final Capability<int> maxMcsIndex;

  /// A maximum PHY rate the OPERATING SYSTEM reports directly, in Mbps.
  ///
  /// Android's `WifiInfo.getMaxSupportedTxLinkSpeedMbps()` is the case this
  /// field exists for. It is a better anchor than [theoreticalMaxPhyRateMbps]
  /// wherever it is available, because it is the platform's own answer rather
  /// than our reconstruction of one, so a surface that has both should lead
  /// with this and treat the derived figure as the fallback.
  ///
  /// It is NOT interchangeable with the derived ceiling: Android's figure is
  /// scoped to the current link's capabilities, so the two can legitimately
  /// disagree. Show both with their own labels rather than reconciling them.
  final Capability<int> osReportedMaxPhyRateMbps;

  /// Machine model identifier, e.g. `iPhone16,1`. Null when unread.
  final String? deviceIdentifier;

  /// Marketing model name, e.g. `iPhone 15 Pro`. Null when unread.
  final String? deviceName;

  /// Version stamp of the published table a tier-2 answer came from, so a stale
  /// table is visible rather than invisible. Null when no table was consulted.
  final String? tableVersion;

  /// Reader notes worth showing next to the values, e.g. a platform limit that
  /// explains why a field is a floor rather than an exact figure.
  final List<String> notes;

  /// The newest standard the radio supports, or unknown.
  ///
  /// Derived, so it can never be stronger than [standards]. Returns
  /// [CapabilityUnknownReason.notComputable] on an empty standard set: knowing
  /// the set is empty is not the same as knowing which standard is highest.
  Capability<WifiStd> get highestStandard => Capability.derive<WifiStd>(
        inputs: <String, Capability<Object>>{'supported standards': standards},
        pin: 'highest member of the supported-standard set',
        compute: () {
          final Set<WifiStd>? set = standards.valueOrNull;
          if (set == null || set.isEmpty) return null;
          return set.reduce(
            (WifiStd a, WifiStd b) => a.index >= b.index ? a : b,
          );
        },
      );

  /// The guard interval a theoretical ceiling should assume for [std]: the
  /// SHORTEST symbol time the standard defines, which is the fastest the
  /// standard permits.
  ///
  /// Derived from [WifiPhyRateService.sym] and [WifiPhyRateService.giKeys]
  /// rather than hardcoded, so if a table is corrected this follows it instead
  /// of quietly disagreeing with it. Only keys present in BOTH tables are
  /// eligible. Returns null for a standard with no usable key.
  static String? fastestGuardIntervalKeyFor(WifiStd std) {
    final Map<String, double>? symbols = WifiPhyRateService.sym[std];
    final List<String>? offered = WifiPhyRateService.giKeys[std];
    if (symbols == null || offered == null) return null;
    String? best;
    double? bestSymbolUs;
    for (final String key in offered) {
      final double? us = symbols[key];
      if (us == null || us <= 0) continue;
      if (bestSymbolUs == null || us < bestSymbolUs) {
        bestSymbolUs = us;
        best = key;
      }
    }
    return best;
  }

  /// Theoretical maximum PHY rate in Mbps for this device.
  ///
  /// CONTEXT, NOT A HEADLINE. This is the number the radio could produce with
  /// the widest channel, every spatial stream, the highest MCS and the shortest
  /// guard interval, all at once, on a link with nothing else happening. No real
  /// device sustains it. The comparison surface must never present it as a
  /// target, and must never present the distance from it as a fault.
  ///
  /// Every input must be known. A missing spatial-stream count yields unknown,
  /// not an assumed 2x2 — assuming 2x2 is precisely how a fabricated ceiling
  /// gets shipped.
  Capability<double> get theoreticalMaxPhyRateMbps {
    final Capability<WifiStd> std = highestStandard;
    return Capability.derive<double>(
      inputs: <String, Capability<Object>>{
        'supported standards': std,
        'maximum channel width': maxChannelWidthMhz,
        'spatial streams': spatialStreams,
        'maximum MCS index': maxMcsIndex,
      },
      pin: 'WifiPhyRateService.phyRateMbps over the highest known standard, '
          'widest channel, all spatial streams, highest MCS and the shortest '
          'guard interval that standard defines',
      compute: () {
        final WifiStd? s = std.valueOrNull;
        final int? width = maxChannelWidthMhz.valueOrNull;
        final int? streams = spatialStreams.valueOrNull;
        final int? mcs = maxMcsIndex.valueOrNull;
        if (s == null || width == null || streams == null || mcs == null) {
          return null;
        }
        final String? gi = fastestGuardIntervalKeyFor(s);
        if (gi == null) return null;
        // Null here means the standard/width/MCS combination has no defined
        // answer, e.g. a 320 MHz width reported against HE. Capability.derive
        // turns that into notComputable rather than substituting a narrower
        // width the device never claimed.
        return WifiPhyRateService.phyRateMbps(
          std: s,
          bandwidthMHz: width,
          mcs: mcs,
          streams: streams,
          giKey: gi,
        );
      },
    );
  }

  /// A FAVORABLE estimate of achievable throughput, in Mbps.
  ///
  /// [WifiPhyRateService.eff] runs 0.70 to 0.80 of the PHY rate. Jim Vajda's
  /// published range for actual throughput is 40 to 60 percent
  /// (framebyframewifi.net, 4 September 2023), so this estimate sits ABOVE the
  /// top of the range a working link is expected to deliver. It is exposed so
  /// the app can be explicit about that, never so a measured result can be
  /// scored against it.
  Capability<double> get favorableThroughputEstimateMbps {
    final Capability<WifiStd> std = highestStandard;
    final Capability<double> phy = theoreticalMaxPhyRateMbps;
    return Capability.derive<double>(
      inputs: <String, Capability<Object>>{
        'theoretical maximum PHY rate': phy,
        'supported standards': std,
      },
      pin: 'theoretical maximum PHY rate multiplied by '
          'WifiPhyRateService.eff, which is an optimistic factor',
      compute: () {
        final double? rate = phy.valueOrNull;
        final WifiStd? s = std.valueOrNull;
        if (rate == null || s == null) return null;
        final double? factor = WifiPhyRateService.eff[s];
        if (factor == null) return null;
        return rate * factor;
      },
    );
  }

  /// The weakest tier among the fields we actually know, or null when nothing
  /// is known. Lets the screen state its own provenance in one line without
  /// overstating it.
  CapabilityTier? get weakestKnownTier {
    CapabilityTier? weakest;
    for (final Capability<Object> field in allFields.values) {
      final CapabilityTier? tier = field.tierOrNull;
      if (tier == null) continue;
      if (weakest == null || tier.isWeakerThan(weakest)) weakest = tier;
    }
    return weakest;
  }

  /// True when not one field resolved. The screen shows its honest-unknown
  /// state rather than a grid of empty rows.
  bool get isEntirelyUnknown =>
      allFields.values.every((Capability<Object> f) => !f.isKnown);

  /// The five READ fields, labelled. Derived values are not included: they are
  /// computed from these, so counting them would double-count provenance.
  Map<String, Capability<Object>> get allFields => <String, Capability<Object>>{
        'Bands': bands,
        'Wi-Fi generations': standards,
        'Maximum channel width': maxChannelWidthMhz,
        'Spatial streams': spatialStreams,
        'Maximum MCS index': maxMcsIndex,
        'Maximum rate reported by the OS': osReportedMaxPhyRateMbps,
      };

  /// Returns a copy with any field this set does not know filled in from
  /// [other], each field keeping ITS OWN tier and pin.
  ///
  /// This is how tier 2 fills a tier-1 gap without the result claiming to be
  /// tier 1. A known field is never overwritten, so a live reading always wins
  /// over a table, and no merge can quietly upgrade a value's provenance.
  ClientCapabilities fillGapsFrom(ClientCapabilities other) =>
      ClientCapabilities(
        bands: bands.isKnown ? bands : other.bands,
        standards: standards.isKnown ? standards : other.standards,
        maxChannelWidthMhz: maxChannelWidthMhz.isKnown
            ? maxChannelWidthMhz
            : other.maxChannelWidthMhz,
        spatialStreams:
            spatialStreams.isKnown ? spatialStreams : other.spatialStreams,
        maxMcsIndex: maxMcsIndex.isKnown ? maxMcsIndex : other.maxMcsIndex,
        osReportedMaxPhyRateMbps: osReportedMaxPhyRateMbps.isKnown
            ? osReportedMaxPhyRateMbps
            : other.osReportedMaxPhyRateMbps,
        deviceIdentifier: deviceIdentifier ?? other.deviceIdentifier,
        deviceName: deviceName ?? other.deviceName,
        tableVersion: tableVersion ?? other.tableVersion,
        notes: <String>[...notes, ...other.notes],
      );

  @override
  String toString() => 'ClientCapabilities(device: $deviceIdentifier, '
      'bands: $bands, standards: $standards, '
      'maxChannelWidthMhz: $maxChannelWidthMhz, '
      'spatialStreams: $spatialStreams, maxMcsIndex: $maxMcsIndex)';
}
