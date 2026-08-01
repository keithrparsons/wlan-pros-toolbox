// BSS Load (802.11 element ID 11) decoder — the shared, pure-Dart seam that
// turns a raw beacon / probe-response IE blob into the three numbers a WLAN
// engineer actually wants off an AP: how many stations are associated, how busy
// the AP senses the medium to be, and how much admission capacity is left.
//
// Pure Dart. No Flutter import, no network, no platform APIs, no state — every
// function is a total function of its bytes, so this is unit-testable without a
// widget pump. Raw IE blobs reach it on macOS (CoreWLAN `informationElementData`
// via the `connectedApIeBlob` channel) and on Windows (the connected-BSS IE blob
// read by the FFI path). iOS exposes no IEs at all, so on iOS the honest answer
// is [BssLoadUnavailableReason.absent] with no blob to decode — never a guess
// (GL-005 / [[feedback_app_blames_the_wifi]]).
//
// ── PROVENANCE ───────────────────────────────────────────────────────────────
// A constant whose origin is not written down is a constant nobody can check.
// Each tier below says how strongly the number is pinned and where to re-check
// it.
//
// The element is "BSS Load" in IEEE 802.11-2012 and later; older 802.11e-era and
// vendor material (and Wireshark's own tag label) call it "QBSS Load".
//
// PINNED, HIGH — Wireshark's IEEE 802.11 dissector, the reference decoder for
// this element, read at commit b1f51ff4fab901b4e8d71cdf1ad3f4c53cc1b6d9
// (`master`, retrieved 2026-07-31):
//
//   * `epan/dissectors/packet-ieee80211.h:386`
//       `#define TAG_QBSS_LOAD                 11`
//     → the element ID is 11 (0x0B). See [kEidBssLoad].
//
//   * `epan/dissectors/packet-ieee80211.c:32219-32220` (the function's own
//     header comment) gives the standard clause numbers:
//       `/* 7.3.2.28 BSS Load element (11) */`
//       `/* 8.4.2.30 in 802.11-2012 */`
//     → IEEE 802.11-2012 § 8.4.2.30 (§ 7.3.2.28 in the 802.11e-era numbering)
//       is the normative text. The standard itself is paywalled and was NOT
//       read directly for this build; the clause numbers are carried from the
//       dissector so a reader with a copy can go check the wording.
//
//   * `packet-ieee80211.c:32228` — `if ((tag_len < 4) || (tag_len > 5))` emits a
//     length error and decodes NOTHING.
//     → a length outside 4..5 is not a BSS Load element. See
//       [BssLoadUnavailableReason.malformedLength]. Note this is the reference
//       decoder REFUSING an over-length element rather than decoding the first
//       five octets and ignoring a tail; this decoder follows it.
//
//   * `packet-ieee80211.c:32253-32258` — the 5-octet form (Wireshark labels it
//     "802.11e CCA Version", i.e. QBSS Version 2), verbatim field-for-field:
//       Station Count               offset 0, 2 octets, `ENC_LITTLE_ENDIAN`
//       Channel Utilization         offset 2, 1 octet,  rendered `100*cu/255` %
//       Available Admission Cap.    offset 3, 2 octets, `ENC_LITTLE_ENDIAN`,
//                                   rendered `adc*32` µs/s
//     → the multi-octet fields are LITTLE-ENDIAN (the classic bug in hand-rolled
//       IE decoders; [_u16le] is the one place byte order is decided, and
//       `bss_load_decoder_test.dart` proves it with a vector whose two octets
//       differ). The `/255` and `*32` conversions are [kChannelUtilizationFullScale]
//       and [kAdmissionCapacityUnitMicrosecondsPerSecond].
//
//   * `packet-ieee80211.c:32236-32243` — the 4-octet form, which Wireshark labels
//     `" Cisco QBSS Version 1 - non CCA"`:
//       Station Count               offset 0, 2 octets, `ENC_LITTLE_ENDIAN`
//       Channel Utilization         offset 2, 1 octet
//       Available Admission Cap.    offset 3, **1** octet  ← different width
//     → the vendor form rides the SAME element ID 11 and is told apart only by
//       its length. Its admission-capacity semantics are one octet wide and are
//       NOT the standard's 32 µs/s field, so decoding it with the standard
//       layout would read a plausible-looking wrong number. This decoder
//       therefore recognizes it and refuses it:
//       [BssLoadUnavailableReason.ciscoQbssVersion1]. Do not "add support" for
//       it without a live Cisco capture pinning what that octet means.
//
// CORROBORATING, HIGH (unit only) — IEEE 802.11-06/725r0, "Normative Text
// Proposal for resolving LB83 comments related to Access Category Service Load",
// Ganesh Venkatesan and Emily H. Qi (Intel), May 2006,
// https://mentor.ieee.org/802.11/dcn/06/11-06-0725-00-000v-available-admission-capacity.doc
// (retrieved 2026-07-31), verbatim:
//
//   "The Available Admission Capacity field is 2 octets long and contains an
//    unsigned integer that specifies the remaining amount of medium time
//    available via explicit admission control for the corresponding UP traffic,
//    in units of 32 microsecond periods per 1 second."
//
// READ THE SCOPE OF THAT CITATION BEFORE REUSING IT: that document defines a
// SEPARATE element — the per-User-Priority "QBSS Available Admission Capacity"
// element proposed at 802.11k D4.0 § 7.3.2.41 — not the BSS Load element decoded
// here. It corroborates the 32 µs/s UNIT and the 2-octet width; it is not a
// citation for element 11's layout. That layout is pinned to the dissector above.
//
// DERIVED, ARITHMETIC — [kAdmissionCapacityFullScale] = 31250. A second of
// medium time is 1 000 000 µs, and the field counts 32 µs periods per second, so
// 1 000 000 / 32 = 31 250 raw units represent 100% of the medium available. This
// is a derivation, not a quotation: no source read for this file states the
// number, and the 16-bit field can physically carry values above it. An
// out-of-range value is reported, never clamped and never silently rendered as
// ">100%" — see [BssLoad.admissionCapacityExceedsFullScale].
//
// NOT HANDLED HERE (a different element, deliberately left alone) — Cisco's
// Aironet Extensions IE (tag 133) carries its own `QBSS V2 - CCA` sub-element,
// subtype 14, with a fourth field ("Call Admission Limit") and a fifth
// ("G.711 CU Quantum") that element 11 does not have
// (`packet-ieee80211.c:21772` and `:21846-21851`). It is not element 11 and is
// out of scope for this decoder.
//
// ── HONESTY CONTRACT ─────────────────────────────────────────────────────────
// Three outcomes that a lesser type collapses into one, and must not:
//
//   1. ABSENT      — no element 11 in the blob. The AP did not advertise BSS
//                    Load (many do not; it is optional), or the platform gave us
//                    no IEs at all.
//   2. UNAVAILABLE — an element 11 IS present but this build will not decode it
//                    (wrong length, the Cisco 4-octet variant, or a header whose
//                    declared length is clipped by the end of the buffer).
//   3. ZERO        — a perfectly good reading whose numbers happen to be 0. An
//                    idle AP with no associated stations and a quiet channel is
//                    a REAL measurement and must read as one.
//
// Case 2 splits further, and the split matters more than it looks: a CLIPPED
// element 11 must not report as case 1. The shared TLV walker in
// `ie_parser.dart` drops a truncated tail without signalling — correctly, that
// is what makes it total and never-throwing — so a decoder that only sees the
// walker's output cannot tell "the AP sent no element 11" from "our capture was
// cut through the middle of element 11". [decodeBssLoad] therefore re-examines
// the raw bytes the walker stopped at, purely to tell those two apart, and
// reports [BssLoadUnavailableReason.truncated] with both the declared and the
// available value length. It does NOT re-implement the walk and it does NOT
// decode a clipped element — that would be padding with zeros by another name.
//
// A field we could not read is not a field that is zero. [decodeBssLoad] returns
// a sealed [BssLoadReading] so a caller cannot accidentally treat case 1 or 2 as
// case 3; [decodeBssLoadOrNull] is the convenience for callers that genuinely
// only want the numbers.

import 'ie_parser.dart';

// ── Pinned constants ─────────────────────────────────────────────────────────

/// Element ID 11 (0x0B) — the BSS Load element ("QBSS Load" in 802.11e-era and
/// vendor material).
///
/// PINNED: Wireshark `epan/dissectors/packet-ieee80211.h:386`
/// (`#define TAG_QBSS_LOAD 11`) at commit b1f51ff4.
const int kEidBssLoad = 11;

/// Value length in octets of the standard (802.11-2012 § 8.4.2.30) BSS Load
/// element: Station Count (2) + Channel Utilization (1) + Available Admission
/// Capacity (2).
const int kBssLoadStandardValueLength = 5;

/// Value length in octets of the Cisco "QBSS Version 1 - non CCA" variant, which
/// rides the same element ID 11 with a 1-octet admission-capacity field.
///
/// PINNED: Wireshark `packet-ieee80211.c:32234-32243` at commit b1f51ff4.
const int kBssLoadCiscoV1ValueLength = 4;

/// Raw Channel Utilization octet that means 100% busy. The field is a LINEAR
/// 0..255 scale, so percent = raw * 100 / 255 — reporting the raw octet as a
/// percentage would show "128" for a half-busy channel, which is both wrong and
/// plausible.
///
/// PINNED: Wireshark `packet-ieee80211.c:32256` renders `100*cu/255` (integer
/// division; this decoder keeps the fractional precision and exposes the raw
/// octet alongside).
const int kChannelUtilizationFullScale = 255;

/// One raw unit of Available Admission Capacity, in microseconds of medium time
/// per second.
///
/// PINNED: Wireshark `packet-ieee80211.c:32258` renders `adc*32` µs/s;
/// corroborated verbatim by IEEE 802.11-06/725r0 (see the file header, and read
/// the scope note there before reusing that citation).
const int kAdmissionCapacityUnitMicrosecondsPerSecond = 32;

/// Raw Available Admission Capacity that represents 100% of the medium being
/// available: 1 000 000 µs in a second / 32 µs per unit = 31 250.
///
/// DERIVED (arithmetic), not quoted from any source read for this file. The
/// 16-bit field can carry a larger value; see
/// [BssLoad.admissionCapacityExceedsFullScale].
const int kAdmissionCapacityFullScale = 31250;

// ── Types ────────────────────────────────────────────────────────────────────

/// Why a BSS Load reading is not available. Machine-branchable, so a readout can
/// say the true thing rather than falling back to a zero.
enum BssLoadUnavailableReason {
  /// No element ID 11 could be identified in the blob: the AP does not
  /// advertise BSS Load (it is optional), or the platform handed us no
  /// information elements (iOS), or the blob was empty or ended before an
  /// element-11 header was reached.
  ///
  /// A blob whose element-11 header IS present but whose declared length
  /// overruns the buffer is [truncated], NOT this — see that member for why the
  /// distinction is load-bearing.
  ///
  /// EDGE, deliberate: a blob whose final byte is `0x0B` with no length octet
  /// after it reports `absent`. A TLV header is two octets, so one trailing byte
  /// is not an element-11 header — it is indistinguishable from stray tail
  /// garbage, and calling it a truncated element 11 would assert an element we
  /// cannot actually see.
  absent,

  /// An element ID 11 header was present — both its ID and length octets — but
  /// its declared value length runs past the end of the buffer, so the value
  /// octets are not all there. The capture was clipped; the AP's advertisement
  /// was not.
  ///
  /// THIS IS NOT [absent], AND THE DIFFERENCE IS THE WHOLE POINT. Collapsing a
  /// clipped capture into "no element 11 was present" makes the app say "this AP
  /// does not advertise BSS Load" about an AP that plainly does, blaming the
  /// network for a defect in our own byte handling
  /// ([[feedback_app_blames_the_wifi]]). [BssLoadUnavailable.valueLength] carries
  /// the DECLARED length and [BssLoadUnavailable.availableLength] the number of
  /// value octets actually present, so a readout can say "element 11 present,
  /// declared 5 octets, 2 available" instead of a false absence.
  ///
  /// Only [decodeBssLoad], which sees the raw bytes, can report this.
  /// [decodeBssLoadFromElements] cannot — see its doc.
  truncated,

  /// An element ID 11 was present with exactly [kBssLoadCiscoV1ValueLength]
  /// value octets — the Cisco "QBSS Version 1 - non CCA" variant, whose
  /// admission-capacity field is one octet with different semantics. Recognized
  /// and deliberately NOT decoded: the standard layout would produce a
  /// plausible wrong number. See the file header.
  ciscoQbssVersion1,

  /// An element ID 11 was present with a value length that is neither 4 nor 5.
  /// Too short to hold the fields, or longer than the element is defined to be.
  /// Wireshark treats both as a length error and decodes nothing
  /// (`packet-ieee80211.c:32228`); so does this decoder — no reading past the
  /// end, no padding with zeros, no decoding a prefix of an element we do not
  /// recognize.
  malformedLength,
}

/// A decoded BSS Load element: the AP's own advertised view of its load.
///
/// Both the human-facing conversion and the raw on-the-wire octet are kept, so a
/// pro-facing readout can show "47% (120/255)" without re-deriving anything.
class BssLoad {
  const BssLoad({
    required this.stationCount,
    required this.rawChannelUtilization,
    required this.rawAdmissionCapacity,
  });

  /// Number of STAs currently associated with this BSS. Unsigned, 2 octets
  /// little-endian on the wire, so 0..65535.
  ///
  /// This is the AP's own count and is not a client census: it says nothing
  /// about how much traffic those stations generate.
  final int stationCount;

  /// The Channel Utilization octet as read off the wire, in its on-the-wire
  /// units — 0..255, where 255 means 100% busy. UNCONVERTED, not unmasked: the
  /// octet is taken `& 0xff`, so a platform channel that hands up a `List<int>`
  /// carrying a value outside byte range yields that value's low octet here
  /// rather than propagating an impossible number. No wire octet can exceed
  /// 0xff, so the mask changes nothing for real captures. Use
  /// [channelUtilizationPercent] for display.
  final int rawChannelUtilization;

  /// The Available Admission Capacity value as read off the wire, in its
  /// on-the-wire units — 2 octets little-endian, each `& 0xff` (see
  /// [rawChannelUtilization] for why), in units of 32 µs of medium time per
  /// second. Use [admissionCapacityPercent] or
  /// [admissionCapacityMicrosecondsPerSecond] for display.
  final int rawAdmissionCapacity;

  /// Percentage of time the AP sensed the medium as busy, by physical OR virtual
  /// carrier sense, over its measurement window: 0.0..100.0.
  ///
  /// This is the AP's own sense of the medium and not a measurement made by this
  /// device. Two APs on the same channel can honestly report different numbers.
  double get channelUtilizationPercent =>
      rawChannelUtilization * 100 / kChannelUtilizationFullScale;

  /// Remaining medium time available via explicit admission control, in
  /// microseconds per second.
  int get admissionCapacityMicrosecondsPerSecond =>
      rawAdmissionCapacity * kAdmissionCapacityUnitMicrosecondsPerSecond;

  /// Remaining admission capacity as a percentage of one full second of medium
  /// time (raw 31250 = 100%).
  ///
  /// NOT clamped: a non-conformant AP can advertise a raw value above
  /// [kAdmissionCapacityFullScale], which yields a value above 100 here. Check
  /// [admissionCapacityExceedsFullScale] before rendering it as a gauge, and
  /// show the out-of-range fact rather than a silently capped bar.
  double get admissionCapacityPercent =>
      rawAdmissionCapacity * 100 / kAdmissionCapacityFullScale;

  /// True when [rawAdmissionCapacity] exceeds the 31250 that represents a full
  /// second of medium time — i.e. the AP advertised more than 100% available,
  /// which is not physically meaningful and marks the value as untrustworthy.
  bool get admissionCapacityExceedsFullScale =>
      rawAdmissionCapacity > kAdmissionCapacityFullScale;

  @override
  bool operator ==(Object other) =>
      other is BssLoad &&
      other.stationCount == stationCount &&
      other.rawChannelUtilization == rawChannelUtilization &&
      other.rawAdmissionCapacity == rawAdmissionCapacity;

  @override
  int get hashCode =>
      Object.hash(stationCount, rawChannelUtilization, rawAdmissionCapacity);

  @override
  String toString() => 'BssLoad(stationCount: $stationCount, '
      'rawChannelUtilization: $rawChannelUtilization, '
      'rawAdmissionCapacity: $rawAdmissionCapacity)';
}

/// Outcome of reading BSS Load from an IE blob.
///
/// A sealed result (not a bare nullable) so the caller must branch on "we have a
/// reading" versus "we do not, and here is why" — the three states in the file
/// header's honesty contract cannot collapse into a zero.
sealed class BssLoadReading {
  const BssLoadReading();

  /// The reading when one was decoded, else null.
  BssLoad? get valueOrNull =>
      this is BssLoadDecoded ? (this as BssLoadDecoded).load : null;

  /// True for [BssLoadDecoded].
  bool get isDecoded => this is BssLoadDecoded;
}

/// A well-formed 5-octet BSS Load element was found and decoded. All-zero fields
/// are a legitimate reading (an idle AP on a quiet channel), not an absence.
class BssLoadDecoded extends BssLoadReading {
  const BssLoadDecoded(this.load);

  final BssLoad load;

  @override
  bool operator ==(Object other) =>
      other is BssLoadDecoded && other.load == load;

  @override
  int get hashCode => load.hashCode;

  @override
  String toString() => 'BssLoadDecoded($load)';
}

/// No BSS Load reading is available, and [reason] says which of the honest
/// not-a-number cases applies.
class BssLoadUnavailable extends BssLoadReading {
  const BssLoadUnavailable(
    this.reason, {
    this.valueLength,
    this.availableLength,
  });

  /// Machine-branchable cause.
  final BssLoadUnavailableReason reason;

  /// The value length the element ID 11 DECLARED in its length octet, when an
  /// element was present. Null for [BssLoadUnavailableReason.absent] — there was
  /// no element to measure. Carried so a pro readout can say "element 11
  /// present, length 7" instead of a bare shrug.
  ///
  /// For [BssLoadUnavailableReason.truncated] this is what the element CLAIMED,
  /// not what arrived; [availableLength] is what arrived.
  final int? valueLength;

  /// The number of value octets actually present in the buffer, when that is
  /// FEWER than [valueLength]. Set only for [BssLoadUnavailableReason.truncated].
  ///
  /// Null everywhere else, and null means "the element was complete", i.e. all
  /// [valueLength] octets were there — it does not mean "unknown". A readout
  /// wanting the count in every case reads `availableLength ?? valueLength`.
  final int? availableLength;

  @override
  bool operator ==(Object other) =>
      other is BssLoadUnavailable &&
      other.reason == reason &&
      other.valueLength == valueLength &&
      other.availableLength == availableLength;

  @override
  int get hashCode => Object.hash(reason, valueLength, availableLength);

  @override
  String toString() => 'BssLoadUnavailable(${reason.name}, '
      'valueLength: $valueLength, availableLength: $availableLength)';
}

// ── Public API ───────────────────────────────────────────────────────────────

/// Decodes the BSS Load element from a raw beacon / probe-response IE blob
/// [ieBytes].
///
/// Total and side-effect-free: never throws on malformed, truncated, empty, or
/// non-Wi-Fi input — every failure path returns a [BssLoadUnavailable] naming
/// its cause. Walking is delegated to the shared bounds-checked TLV walker in
/// `ie_parser.dart`, which stops cleanly at a truncated tail.
///
/// Because the walker stops at a truncated tail SILENTLY — it yields the element
/// and nothing more, which is exactly the property that makes it total — this
/// function then inspects the bytes the walker did not consume, and only for one
/// question: was the element it stopped at an element 11? If so the answer is
/// [BssLoadUnavailableReason.truncated], never `absent`. See
/// [_truncatedElement11AtTail].
///
/// Precedence, in order:
///   1. a decoded element 11 anywhere in the walked region wins outright;
///   2. otherwise the FIRST complete element 11 that failed to decode is
///      reported — it precedes any truncated tail by construction, so this
///      preserves the "first element 11 seen" contract of
///      [decodeBssLoadFromElements];
///   3. otherwise a truncated element 11 at the tail;
///   4. otherwise [BssLoadUnavailableReason.absent].
BssLoadReading decodeBssLoad(List<int> ieBytes) {
  final List<InformationElement> elements =
      walkInformationElements(ieBytes).toList(growable: false);
  final BssLoadReading reading = decodeBssLoadFromElements(elements);
  if (reading is BssLoadDecoded) return reading;
  if (reading is BssLoadUnavailable &&
      reading.reason != BssLoadUnavailableReason.absent) {
    return reading;
  }
  return _truncatedElement11AtTail(ieBytes, elements) ?? reading;
}

/// Decoder variant taking pre-parsed [elements] (from [walkInformationElements]
/// or a platform channel that already TLV-split the blob). Same contract as
/// [decodeBssLoad].
///
/// BSS Load appears at most once in a well-formed beacon. If a blob nonetheless
/// carries several element-11s, the FIRST one that decodes wins; if none decode,
/// the reason reported is that of the FIRST element 11 seen, so the diagnosis
/// matches what a sniffer would show at the top of the frame.
///
/// KNOWN LIMIT, and the reason [decodeBssLoad] exists as more than a wrapper:
/// this variant CANNOT report [BssLoadUnavailableReason.truncated]. Pre-parsed
/// elements are all the elements that survived a bounds check, so a clipped
/// element 11 was already dropped before this function saw anything, and the
/// honest answer available here is `absent`. Callers holding the raw bytes must
/// prefer [decodeBssLoad], which can tell those two apart.
BssLoadReading decodeBssLoadFromElements(
  Iterable<InformationElement> elements,
) {
  BssLoadUnavailable? firstFailure;
  for (final InformationElement ie in elements) {
    if (ie.id != kEidBssLoad) continue;
    final BssLoadReading reading = decodeBssLoadValue(ie.bytes);
    if (reading is BssLoadDecoded) return reading;
    firstFailure ??= reading as BssLoadUnavailable;
  }
  return firstFailure ??
      const BssLoadUnavailable(BssLoadUnavailableReason.absent);
}

/// Decodes the VALUE octets of a single element ID 11 (the `[id][len]` header
/// already stripped, as [walkInformationElements] yields them).
///
/// Exposed so a platform layer that already isolated the element — or a test
/// working from a hand-built vector — can decode without rebuilding a TLV blob.
/// Never throws and never reads past the end of [value].
BssLoadReading decodeBssLoadValue(List<int> value) {
  final int len = value.length;
  if (len == kBssLoadCiscoV1ValueLength) {
    // Recognized vendor variant — honest refusal, not a mis-decode.
    return BssLoadUnavailable(
      BssLoadUnavailableReason.ciscoQbssVersion1,
      valueLength: len,
    );
  }
  if (len != kBssLoadStandardValueLength) {
    return BssLoadUnavailable(
      BssLoadUnavailableReason.malformedLength,
      valueLength: len,
    );
  }
  return BssLoadDecoded(
    BssLoad(
      stationCount: _u16le(value, 0),
      rawChannelUtilization: value[2] & 0xff,
      rawAdmissionCapacity: _u16le(value, 3),
    ),
  );
}

/// Convenience for callers that only want the numbers: the decoded [BssLoad], or
/// null for every not-available case.
///
/// Prefer [decodeBssLoad] anywhere the DIFFERENCE between "the AP does not
/// advertise BSS Load" and "we saw an element we refuse to decode" is worth
/// showing — which, on a pro-facing readout, it usually is.
BssLoad? decodeBssLoadOrNull(List<int> ieBytes) =>
    decodeBssLoad(ieBytes).valueOrNull;

// ── Internals ────────────────────────────────────────────────────────────────

/// Octets in a non-extended IE header: `[id][len]`.
const int _kIeHeaderLength = 2;

/// Returns a [BssLoadUnavailableReason.truncated] reading when the bytes the TLV
/// walker refused to consume begin with an element-11 header whose declared
/// length overruns [ieBytes]; null otherwise.
///
/// HOW THE TAIL IS LOCATED, and why this is not a second parser. Every element
/// the walker yielded consumed exactly `2 + bytes.length` contiguous octets
/// starting at 0, so summing that over [walked] gives the offset where the walk
/// stopped. That offset is derived FROM the walker's own output, so this cannot
/// drift out of agreement with `ie_parser.dart` the way a re-implemented walk
/// could — and `ie_parser.dart` is untouched, its never-throws property intact.
///
/// WHY THE RESIDUE IS UNAMBIGUOUS. `walkInformationElements` loops while
/// `i + 2 <= n` and breaks only when a declared length overruns. So after it
/// returns, the unconsumed residue is exactly one of:
///   * 0 or 1 octets — the loop ran out normally; there is no header to read;
///   * ≥ 2 octets — the loop `break`ed, and the octets at the stop offset ARE an
///     element header whose declared length overruns the buffer.
/// Residue ≥ 2 therefore means "a truncated element starts here", with no
/// guessing. This is why the check does not scan the blob for a stray `0x0B`:
/// an `11` byte inside an SSID or a rates element is a value octet, not an
/// element, and searching for it would invent elements that are not there.
///
/// NOTHING IS DECODED FROM THE CLIPPED ELEMENT. Its value octets are counted,
/// never read as fields — a partial element padded out to five octets is the
/// zero-fill guess this whole file exists to refuse.
BssLoadUnavailable? _truncatedElement11AtTail(
  List<int> ieBytes,
  List<InformationElement> walked,
) {
  int consumed = 0;
  for (final InformationElement ie in walked) {
    consumed += _kIeHeaderLength + ie.bytes.length;
  }
  final int residue = ieBytes.length - consumed;
  if (residue < _kIeHeaderLength) return null;
  if ((ieBytes[consumed] & 0xff) != kEidBssLoad) return null;
  return BssLoadUnavailable(
    BssLoadUnavailableReason.truncated,
    valueLength: ieBytes[consumed + 1] & 0xff,
    availableLength: residue - _kIeHeaderLength,
  );
}

/// Reads an unsigned 16-bit LITTLE-ENDIAN integer at [offset].
///
/// The one place byte order is decided in this file. 802.11 multi-octet fields
/// are little-endian (Wireshark `ENC_LITTLE_ENDIAN` on both `qbss_scount` and
/// `qbss_adc`, `packet-ieee80211.c:32254` and `:32257`), and getting this
/// backwards is the classic IE-decoder bug: it is invisible on any test vector
/// whose two octets happen to be equal.
///
/// The caller has already length-checked [value]; the `& 0xff` masks defend
/// against a platform channel handing up a `List<int>` with values outside byte
/// range rather than a `Uint8List`.
int _u16le(List<int> value, int offset) =>
    (value[offset] & 0xff) | ((value[offset + 1] & 0xff) << 8);
