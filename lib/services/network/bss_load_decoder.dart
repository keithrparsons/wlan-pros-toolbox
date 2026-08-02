// BSS Load (802.11 element ID 11) decoder — the shared, pure-Dart seam that
// turns a raw beacon / probe-response IE blob into the three numbers a WLAN
// engineer actually wants off an AP: how many stations are associated, how busy
// the AP senses the medium to be, and how much admission capacity is left.
//
// Pure Dart. No Flutter import, no network, no platform APIs, no state — every
// function is a total function of its bytes, so this is unit-testable without a
// widget pump. Raw IE blobs reach it on macOS (CoreWLAN `informationElementData`
// via the `connectedApIeBlob` channel) and on Windows (the connected-BSS IE blob
// read by the FFI path).
//
// A PLATFORM THAT HANDS US NO BYTES SAYS NOTHING ABOUT THE AP, and this file
// will not let a caller spell that as though it did. iOS exposes no IEs at all;
// macOS yields none when Location is unauthorized, Wi-Fi is off, or no scanned
// BSS matches the connected BSSID; and `connectedApIeBlob` is wired for macOS
// only today, so every other platform hands up a null blob (see `ApIeBlob` in
// `wifi_info_service.dart`, whose `ieBytes` is a `Uint8List?` for exactly these
// reasons). All of those are
// [BssLoadUnavailableReason.noInformationElementsProvided] — never `absent`,
// which is a claim about the AP (GL-005 / [[feedback_app_blames_the_wifi]]).
//
// Two things make that the answer a caller gets by writing the obvious thing
// rather than by reading this paragraph. [decodeBssLoad] takes a NULLABLE blob,
// so `decodeBssLoad(apIeBlob.ieBytes)` is correct with no null-handling at the
// call site; and an EMPTY blob reads the same way, so the `?? const []` spelling
// of the same call is correct too. A beacon always carries at least an SSID
// element, so zero elements means we were handed nothing — never that the AP
// advertised nothing.
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
// Outcomes that a lesser type collapses into one, and must not.
//
// THESE ARE NAMED AND NOT NUMBERED, ON PURPOSE, AND ANYTHING CITING THEM MUST
// CITE THE NAME. An ordinal is a label rather than a fact, so inserting an
// outcome renumbers every later one and silently falsifies every sentence that
// cited a number — and unlike a rename, there is nothing to grep for. That is
// not hypothetical: NOTHING TO READ was inserted here, and two sentences
// elsewhere in this file went on addressing the old numbering without a
// character of either changing.
//
// WHAT THE GUARD ON THIS BLOCK ACTUALLY DOES, AND WHAT IT DOES NOT — stated
// here rather than only in the guard, because a reader of this file never opens
// that one, and an earlier version of this paragraph claimed a guarantee the
// instrument does not deliver. `bss_load_ordinal_reference_guard_test.dart`
// reads the entries below BY NAME and fails the build when: an entry stops
// being a bare upper-case name (a `1.`, `1)`, `(1)` or a positional roman
// prefix each fail); the mirror of this list in `bss_load_decoder_test.dart`
// stops matching it member for member; the list gets SHORTER than four; prose
// in this file, its test file or the `ie_parser.dart` pair cites a numbered
// list by ordinal; or a sentence in the two BSS Load files states a count of
// these outcomes that is not the number of entries below. IT IS A TEXT CHECK
// AND IT DOES NOT READ ENGLISH, so an author can still write a stale sentence
// in a shape it does not recognize; the guard's own SCOPE paragraph enumerates
// the shapes it misses. Tripwire on the mistake that actually happened, not a
// proof that the mistake is impossible.
//
// THE INDENTATION BELOW IS LOAD-BEARING: an entry is a name at three spaces,
// its prose continues at five. Do not reformat it — but a reformat is now LOUD
// rather than quiet, and that repair is worth knowing about, because for two
// rounds it was the reverse. Every line in this block indented two spaces or
// more is READ as an entry and then judged, so an entry written with the wrong
// dash, or at four spaces, fails by name instead of vanishing from the set; and
// a line at five spaces that reads like an entry head fails too. What a parser
// silently skips, it silently passes, and every check downstream of it quietly
// becomes a claim about a shorter list.
//
//   ABSENT — the blob was walked to its END and held no element 11. The AP did
//     not advertise BSS Load (many do not; it is optional). THE ONLY OUTCOME
//     HERE THAT CLAIMS ANYTHING ABOUT THE AP.
//   NOTHING TO READ — no information elements reached us at all: a null blob
//     (the platform does not expose IEs, or would not this time) or an empty
//     one. A statement about the platform, never about the AP.
//     [BssLoadUnavailableReason.noInformationElementsProvided].
//   UNAVAILABLE — an element 11 IS present but this build will not decode it
//     (wrong length, the Cisco 4-octet variant, or a header whose declared
//     length is clipped by the end of the buffer), or the capture was cut
//     before we could tell whether one was there at all, or nobody told us
//     whether the capture was whole
//     ([BssLoadUnavailableReason.blobCompletenessNotStated]).
//   ZERO — a perfectly good reading whose numbers happen to be 0. An idle AP
//     with no associated stations and a quiet channel is a REAL measurement and
//     must read as one.
//
// ABSENT IS THE ONE THAT KEEPS BEING OVER-CLAIMED, in two separate directions.
//
// A CLIPPED CAPTURE IS NOT AN ABSENCE. The shared TLV walker in `ie_parser.dart`
// drops a truncated tail without signalling — correctly, that is what makes it
// total and never-throwing — so a decoder that only sees the walker's output
// cannot tell "the AP sent no element 11" from "our capture was cut before we
// could tell". The second reported as the first is the app blaming the Wi-Fi for
// a defect in our own byte handling ([[feedback_app_blames_the_wifi]]).
//
// AN EMPTY HAND IS NOT AN ABSENCE EITHER, and it is the wider of the two: every
// platform that does not expose IEs, and every macOS read that Location or a
// powered-down radio defeats, arrives here as no bytes. See the top of this file.
//
// [decodeBssLoad] therefore asks `ie_parser.dart` where the walk stopped
// ([informationElementWalkTail]) and reports one of these, and only these:
//
// THE COUNT IS DELIBERATELY NOT STATED. This bullet list is NOT the honesty
// contract above — these are walk outcomes and they include `truncated` and
// `malformedLength`, while the contract includes ZERO, which is not a bullet.
// The two lists coincidentally had the same length, and a sentence that said so
// went stale the moment a bullet was added: no instrument derives this list's
// size, so a number here would be a claim nothing checks. Name the reason, do
// not count the reasons.
//
//   * nothing was handed to us — a null or empty blob →
//     [BssLoadUnavailableReason.noInformationElementsProvided];
//   * the clipped element at the tail IS element 11 →
//     [BssLoadUnavailableReason.truncated] with the declared AND the available
//     value length (or [BssLoadUnavailableReason.malformedLength] when the
//     declared length is one element 11 cannot have);
//   * the walk stopped short somewhere ELSE, so element 11 may have been in the
//     part that was cut →
//     [BssLoadUnavailableReason.clippedWithoutSeeingElement11].
//     THIS IS THE COMMON CASE IN PRACTICE: element 11 sits well down a beacon,
//     so a clip is likelier to land before it than on it;
//   * the walk consumed every octet of a non-empty blob and none of them was
//     element 11 → [BssLoadUnavailableReason.absent], the only reading that says
//     anything about the AP.
//
// Nothing re-implements the walk and nothing decodes a clipped element — that
// would be padding with zeros by another name.
//
// WHAT THIS DECODER STILL CANNOT SEE, stated rather than papered over: a capture
// clipped exactly on an element boundary is byte-for-byte identical to a
// complete blob. There is no evidence in the bytes, so such a blob reads as
// `absent`. Only the layer that capped the buffer knows, and a platform layer
// that truncates an IE blob owes the decoder that fact rather than letting it
// guess. [decodeBssLoadFromElements] takes it as a required argument for exactly
// this reason — an [IeBlobCompleteness], not a bool, so a layer that genuinely
// cannot answer says [IeBlobCompleteness.notStated] instead of being forced to
// assert a clip it has no evidence for.
//
// A field we could not read is not a field that is zero, and that is what the
// type is shaped to protect: [decodeBssLoad] returns a sealed [BssLoadReading],
// so a MEASUREMENT never arrives on the ABSENT, NOTHING TO READ or UNAVAILABLE
// branches. There is no station count, no channel utilization and no admission
// capacity to reach for on any of them. (UNAVAILABLE does carry numbers —
// [BssLoadUnavailable.valueLength] and [BssLoadUnavailable.availableLength] are
// the octet counts of the element we refused, and a readout is invited to print
// them; they are diagnostics about our own read, never the AP's load.)
//
// WHAT THE SEAL DOES AND DOES NOT COMPEL, because the previous wording said the
// compiler forces a branch and it does not. A caller that SWITCHES on the sealed
// type gets exhaustiveness: add a subclass and every switch stops compiling.
// A caller that does not switch is not forced to — [BssLoadReading.valueOrNull]
// and [BssLoadReading.isDecoded] are on the base class deliberately, so the
// collapse to `BssLoad?` is available without one. That is a designed escape
// hatch, not a hole, and [decodeBssLoadOrNull] is its named form: it is
// literally `decodeBssLoad(ieBytes).valueOrNull`. Naming it does not make it the
// only route to it. What the seal buys is that the collapse must be WRITTEN —
// `valueOrNull` is a word a reviewer can see and grep — rather than happening by
// default because the return type was nullable.

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

/// What a caller knows about whether an information-element blob was consumed to
/// its end.
///
/// THIS EXISTS BECAUSE A BOOL COULD NOT SAY "I WAS NOT TOLD". The parameter it
/// replaces was `required bool blobWalkedToEnd`, and false had to carry both
/// "the walk stopped short" and "nobody told me either way". Those are not the
/// same fact, and collapsing them made [decodeBssLoadFromElements] answer
/// [BssLoadUnavailableReason.clippedWithoutSeeingElement11] — which states in
/// its own doc that the capture WAS clipped — to a caller handing over a
/// perfectly whole set of elements. A false statement about our own byte
/// handling is the safe direction to be wrong in, but it is still wrong, and a
/// type that cannot express "unknown" gets handed a guess forever
/// ([[feedback_type_must_express_unknown]]).
///
/// NAMED, NEVER NUMBERED, like everything else in this file. Do not switch on
/// index and do not cite a member by position.
enum IeBlobCompleteness {
  /// Every octet of the source blob was accounted for by a well-formed element.
  /// [InformationElementWalkTail.isComplete] answers this for a raw blob, and a
  /// platform channel that TLV-split the bytes itself knows whether it consumed
  /// them all.
  walkedToEnd,

  /// The walk stopped before the end of the source: a declared length overran
  /// the buffer, or the buffer ended part-way through a header. The caller
  /// POSITIVELY KNOWS the capture was cut.
  stoppedShort,

  /// The caller was never told, and is saying so rather than guessing.
  ///
  /// This is not a weaker [stoppedShort]. It is the honest answer for a platform
  /// channel that hands up pre-split elements without saying whether it consumed
  /// the whole blob, and it produces
  /// [BssLoadUnavailableReason.blobCompletenessNotStated] rather than a claim
  /// that anything was clipped.
  notStated,
}

/// Why a BSS Load reading is not available. Machine-branchable, so a readout can
/// say the true thing rather than falling back to a zero.
enum BssLoadUnavailableReason {
  /// A non-empty blob was walked to its END and held no element ID 11: this AP
  /// does not advertise BSS Load (it is optional and many do not).
  ///
  /// THIS IS A STATEMENT ABOUT THE AP, AND IT IS THE ONLY MEMBER OF THIS ENUM
  /// THAT MAKES ONE. It is earned by two things together, and both are checked:
  ///
  ///   * EVERY OCTET WAS ACCOUNTED FOR. If the walk stopped short — a declared
  ///     length overrunning the buffer, or a lone dangling header octet — then
  ///     element 11 may simply have been in the part that was cut off, and the
  ///     honest answer is [clippedWithoutSeeingElement11] or [truncated].
  ///     `absent` needs [InformationElementWalkTail.isComplete] to be true.
  ///   * THERE WERE OCTETS TO ACCOUNT FOR. A null or empty blob is not an AP
  ///     that advertised nothing, it is a platform that told us nothing, and it
  ///     is [noInformationElementsProvided]. A beacon always carries at least an
  ///     SSID element, so a walk that yields no elements at all never happened
  ///     over anything an AP actually sent.
  ///
  /// KNOWN LIMIT, and it lives outside this decoder. A capture clipped exactly
  /// on an element boundary is byte-for-byte identical to a complete blob, so
  /// nothing in the bytes can distinguish them and this decoder will report
  /// `absent`. Only the layer that capped the buffer knows, and a platform layer
  /// that truncates an IE blob must say so rather than let a decoder guess.
  absent,

  /// No information elements reached this decoder at all: the blob was null, or
  /// it was empty.
  ///
  /// THIS IS A STATEMENT ABOUT THE PLATFORM, NOT ABOUT THE AP, and separating it
  /// from [absent] is why this member exists. `absent` says "this AP does not
  /// advertise BSS Load". Rendering that on a device that simply cannot see
  /// information elements is the app blaming the Wi-Fi for its own blind spot
  /// ([[feedback_app_blames_the_wifi]], [[feedback_type_must_express_unknown]]).
  ///
  /// HOW WIDE THIS IS, because it is much wider than one platform. iOS exposes
  /// no information elements at all. macOS yields none when Location is
  /// unauthorized, when Wi-Fi is off, when no interface exists, when no scanned
  /// BSS matches the connected BSSID, or when that BSS carried no IE data. And
  /// `connectedApIeBlob` is wired for macOS only today, so every other platform
  /// returns a null blob without touching a channel. `ApIeBlob.ieBytes` in
  /// `wifi_info_service.dart` is a `Uint8List?` for all of those reasons, and
  /// [decodeBssLoad] accepts that null directly.
  ///
  /// A readout branching on this should say what it can see, not what the AP
  /// does: "information elements are not available on this device" is true;
  /// "this AP does not advertise BSS Load" is not.
  ///
  /// Both [BssLoadUnavailable.valueLength] and
  /// [BssLoadUnavailable.availableLength] are null here — nothing was read, so
  /// there is nothing to count.
  noInformationElementsProvided,

  /// The walk stopped BEFORE the end of the blob without ever reaching a
  /// decidable element 11: some earlier element's declared length overran the
  /// buffer, or the buffer ended one octet into a header. Element 11 may or may
  /// not have been advertised — the capture ended before we could tell.
  ///
  /// THE NAME CLAIMS EXACTLY THOSE TWO FACTS AND NO THIRD ONE. The capture was
  /// clipped, and no element 11 was seen. It deliberately does NOT say the clip
  /// landed *before* element 11, because that would assert element 11 is in the
  /// blob somewhere — which is the very thing this member exists to say we
  /// cannot know. (For one commit it was called `clippedBeforeElement11`. In a
  /// file whose whole thesis is that a member name must not over-claim, the name
  /// was the one place the thesis had not been applied.)
  ///
  /// WHY THIS IS NOT [absent], AND WHY THE DIFFERENCE IS THE WHOLE POINT.
  /// Element 11 sits well down a beacon, after the SSID, the rates and the DS
  /// parameter set, so a capture clipped at a random offset is FAR likelier to
  /// be cut before element 11 than exactly on it. Reporting those clips as
  /// `absent` makes the app say "this AP does not advertise BSS Load" about an
  /// AP that plainly does, on the strength of our own truncated buffer — the app
  /// blaming the Wi-Fi for a defect in our byte handling
  /// ([[feedback_app_blames_the_wifi]]).
  ///
  /// WHY IT IS NOT [truncated] EITHER. Nothing here identifies an element 11.
  /// The clipped element at the stop offset carries some other id, or carries no
  /// readable length at all. Claiming a truncated element 11 would be the
  /// mirror-image over-claim: inventing an element the bytes never named.
  ///
  /// Both [BssLoadUnavailable.valueLength] and
  /// [BssLoadUnavailable.availableLength] are null here — no element 11 was seen,
  /// so there is nothing to count.
  clippedWithoutSeeingElement11,

  /// No element 11 was among the elements handed to us, and the caller did not
  /// say whether the source blob had been consumed to its end
  /// ([IeBlobCompleteness.notStated]).
  ///
  /// THE NAME CLAIMS A GAP IN WHAT WE WERE TOLD, AND NOTHING ABOUT THE CAPTURE.
  /// That is the entire reason this member exists. It is the sibling of
  /// [clippedWithoutSeeingElement11], and the difference between them is not
  /// severity — it is who knows what. `clippedWithoutSeeingElement11` is a
  /// POSITIVE claim that the capture was cut. Before this member existed, an
  /// uncertain caller had no way to avoid making that claim: the parameter was a
  /// bool, false was the only non-committal value, and false meant "clipped". So
  /// the decoder asserted a defect in our own byte handling that nobody had
  /// evidence for ([[feedback_type_must_express_unknown]]).
  ///
  /// WHY IT IS NOT [absent], WHICH IS THE WHOLE POINT OF NOT GUESSING. `absent`
  /// says this AP does not advertise BSS Load, and earning that requires knowing
  /// every octet was accounted for. We do not know that here. Reporting `absent`
  /// on an unstated blob is the app blaming the Wi-Fi for a gap in its own
  /// information ([[feedback_app_blames_the_wifi]]), and it is the failure this
  /// member is shaped to make impossible rather than merely discouraged.
  ///
  /// WHY IT IS NOT [noInformationElementsProvided] EITHER. Elements DID reach
  /// us — the platform is not blind, and saying it is would be a different false
  /// statement. An empty set with completeness unstated is still this member,
  /// because a walk that yielded nothing over an unknown extent cannot be told
  /// from a walk that was cut before the first element.
  ///
  /// [decodeBssLoad] NEVER PRODUCES THIS. It reads the raw bytes and asks
  /// `ie_parser.dart` where the walk stopped, so it always knows; the walk
  /// outcomes listed in the file header are unchanged and still complete for
  /// that entry point. Only [decodeBssLoadFromElements] can report it, and only
  /// when its caller says [IeBlobCompleteness.notStated].
  ///
  /// A readout on this branch may say the reading could not be established and
  /// why. It may never say the AP does not advertise BSS Load, and it may never
  /// say the capture was clipped.
  ///
  /// Both [BssLoadUnavailable.valueLength] and
  /// [BssLoadUnavailable.availableLength] are null here — no element 11 was
  /// seen, so there is nothing to count.
  blobCompletenessNotStated,

  /// An element ID 11 header was present — both its ID and length octets — it
  /// declared a length the element is ALLOWED to have (4 or 5), and that length
  /// runs past the end of the buffer, so the value octets are not all there. The
  /// capture was clipped; the AP's advertisement was not.
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
  /// THE DECLARED LENGTH IS VETTED BEFORE THIS IS REPORTED. This member's second
  /// sentence — "the AP's advertisement was not clipped" — is a positive claim
  /// about a well-formed element, so it may only be made about a length that
  /// could belong to a well-formed element. A clipped header declaring 7, or
  /// 200, or 255 is reported as [malformedLength] instead: `tag_len` outside
  /// 4..5 is not a BSS Load element (`packet-ieee80211.c:32228`), and the header
  /// alone disqualifies it whether the capture was clipped or not.
  ///
  /// A DECLARED 0 IS NOT AN EXAMPLE OF THAT, and naming it as one sent a reader
  /// looking for a case the bytes cannot produce: zero value octets always fit,
  /// so a header declaring 0 never overruns and the walk never stops on it.
  /// `[11, 0]` is a COMPLETE element 11 with an empty value, diagnosed on the
  /// ordinary path — also [malformedLength], but with a null
  /// [BssLoadUnavailable.availableLength], because nothing was cut. Pinned by
  /// `bss_load_decoder_test.dart`, "declared 0 can never be clipped".
  ///
  /// A declared length of 4 stays here rather than becoming
  /// [ciscoQbssVersion1]: 4 is a legal length, but the vendor variant's four
  /// value octets never arrived, so naming it would assert an element we did not
  /// see. [BssLoadUnavailable.valueLength] is 4 and a readout that cares can say
  /// "declared as the Cisco 4-octet variant, clipped".
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

  /// An element ID 11 header declared a value length that is neither 4 nor 5.
  /// Too short to hold the fields, or longer than the element is defined to be.
  /// Wireshark treats both as a length error and decodes nothing
  /// (`packet-ieee80211.c:32228`); so does this decoder — no reading past the
  /// end, no padding with zeros, no decoding a prefix of an element we do not
  /// recognize.
  ///
  /// Reported for a COMPLETE element with a bad length and for a CLIPPED header
  /// with a bad length alike, because the length octet alone settles it. The two
  /// are told apart by [BssLoadUnavailable.availableLength]: null when every
  /// declared octet arrived, and a count when the buffer ended early.
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
/// reading" versus "we do not, and here is why" — ABSENT, NOTHING TO READ and
/// UNAVAILABLE in the file header's honesty contract cannot collapse into a ZERO
/// reading.
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
  /// element 11 was seen. Carried so a pro readout can say "element 11 present,
  /// length 7" instead of a bare shrug.
  ///
  /// NULL MEANS NO ELEMENT 11 WAS SEEN, NOT "LENGTH ZERO" — that is
  /// [BssLoadUnavailableReason.absent],
  /// [BssLoadUnavailableReason.clippedWithoutSeeingElement11] and
  /// [BssLoadUnavailableReason.noInformationElementsProvided]. A zero-length
  /// element 11 really was seen and carries `valueLength: 0`.
  ///
  /// For [BssLoadUnavailableReason.truncated], and for a clipped header reported
  /// as [BssLoadUnavailableReason.malformedLength], this is what the element
  /// CLAIMED, not what arrived; [availableLength] is what arrived.
  final int? valueLength;

  /// The number of value octets actually present in the buffer, when that is
  /// FEWER than [valueLength] — i.e. the buffer ended part-way through the
  /// element. Set for [BssLoadUnavailableReason.truncated] and for a CLIPPED
  /// header reported as [BssLoadUnavailableReason.malformedLength].
  ///
  /// Null in two different situations, and a readout must not print it either
  /// way without checking [reason]:
  ///   * an element 11 was seen and was COMPLETE — all [valueLength] octets
  ///     arrived ([malformedLength] on a whole element, or
  ///     [ciscoQbssVersion1]);
  ///   * no element 11 was seen at all, so there is nothing to count ([absent],
  ///     [clippedWithoutSeeingElement11], [noInformationElementsProvided]) —
  ///     [valueLength] is null there too.
  ///
  /// It never means "unknown". `availableLength ?? valueLength` is the octet
  /// count of an element that WAS seen and yields null when none was — check
  /// [reason] first.
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
/// [ieBytes] IS NULLABLE ON PURPOSE. `ApIeBlob.ieBytes` is a `Uint8List?` and is
/// null on every platform that does not expose information elements and on every
/// macOS read that Location, a powered-down radio or a BSSID mismatch defeats.
/// Passing that null straight in yields
/// [BssLoadUnavailableReason.noInformationElementsProvided] — a statement about
/// the platform — so no caller has to know that `absent` would have been a
/// statement about the AP. An empty blob reads the same way, so the
/// `decodeBssLoad(blob ?? const [])` spelling is correct too.
///
/// Total and side-effect-free: never throws on null, malformed, truncated, empty
/// or non-Wi-Fi input — every failure path returns a [BssLoadUnavailable] naming
/// its cause. Walking is delegated to the shared bounds-checked TLV walker in
/// `ie_parser.dart`, which stops cleanly at a truncated tail.
///
/// WHAT THE WALKER DOES WITH A CLIPPED ELEMENT, stated exactly, because getting
/// it backwards is what invites zero-padding: it does NOT yield it, not even
/// partially. It drops the clipped element entirely and stops, silently — which
/// is exactly the property that makes it total, and exactly why a decoder that
/// only sees the walk cannot tell a clip from an absence. So this function also
/// inspects the octets the walk did not consume, for one question: was the
/// element it stopped at an element 11? If so the answer is
/// [BssLoadUnavailableReason.truncated] when the declared length is one element
/// 11 may have and [BssLoadUnavailableReason.malformedLength] when it is not —
/// never `absent` either way. See [_clippedElement11AtTail], and
/// `ie_parser_test.dart` for the walker's side of that contract.
///
/// Precedence, in order. THIS LIST KEEPS ITS NUMBERS BECAUSE THE ORDER IS THE
/// CONTENT — each step means "otherwise" — but every step also carries a NAME,
/// and anything citing a step from elsewhere cites the NAME. This list has
/// already been renumbered once by an insertion, and an ordinal quoted in
/// another paragraph goes stale in total silence.
///
/// The NAME is the part the guard can enforce, so it does, and the enforcement
/// is stated exactly rather than generally, because the general version of this
/// sentence was false for two gate rounds. `bss_load_ordinal_reference_guard_test.dart`
/// reads EVERY indented line between "Precedence, in order." and "The blob is
/// walked twice", and fails the build when one of them is not `N. NAME — prose`:
/// a step written `7)` used to be invisible to it rather than rejected, so an
/// unnamed step passed while this paragraph claimed it could not. The numbers
/// must also run 1..n without a gap. Calling these "steps" is deliberate, and
/// the noun `step` is in the guard's refused set exactly as `rule` and `case`
/// are — this paragraph is where a reader learns the word, so it is where the
/// hole was.
///   1. DECODED — a decoded element 11 anywhere in the walked region wins
///      outright;
///   2. EXAMINED — otherwise the FIRST complete element 11 that failed to decode
///      is reported; it precedes any clipped tail by construction, so this
///      preserves the "first element 11 seen" contract of
///      [decodeBssLoadFromElements];
///   3. CLIPPED-11 — otherwise a clipped element 11 at the tail, as
///      [BssLoadUnavailableReason.truncated] when its declared length is one
///      element 11 may have and [BssLoadUnavailableReason.malformedLength] when
///      it is not;
///   4. CLIPPED-ELSEWHERE — otherwise, if the walk did not reach the end of the
///      blob, [BssLoadUnavailableReason.clippedWithoutSeeingElement11]; something
///      was cut, and element 11 may have been in it;
///   5. NOTHING-PROVIDED — otherwise, if nothing was handed to us at all,
///      [BssLoadUnavailableReason.noInformationElementsProvided];
///   6. ABSENT — otherwise [BssLoadUnavailableReason.absent], the ONLY reading
///      that claims anything about the AP.
///
/// The blob is walked twice — once for the elements, once for the tail. Both
/// walks are lazy, total and pure over a buffer of at most a few hundred octets,
/// and the alternative is re-deriving the stop offset here, in a module that
/// does not own the loop.
BssLoadReading decodeBssLoad(List<int>? ieBytes) {
  if (ieBytes == null) {
    return const BssLoadUnavailable(
      BssLoadUnavailableReason.noInformationElementsProvided,
    );
  }
  final InformationElementWalkTail tail = informationElementWalkTail(ieBytes);
  final BssLoadReading reading = decodeBssLoadFromElements(
    walkInformationElements(ieBytes),
    // NEVER [IeBlobCompleteness.notStated] HERE. This entry point holds the raw
    // bytes and the walk tail, so it always knows; passing "not stated" from a
    // place that can answer would be manufacturing an uncertainty.
    blobCompleteness: tail.isComplete
        ? IeBlobCompleteness.walkedToEnd
        : IeBlobCompleteness.stoppedShort,
  );
  if (reading is BssLoadDecoded) return reading;

  final BssLoadUnavailable unavailable = reading as BssLoadUnavailable;

  // An element 11 we actually EXAMINED outranks anything at the tail, which is
  // the EXAMINED rule above. `valueLength` is exactly that question — its own
  // doc is "NULL MEANS NO ELEMENT 11 WAS SEEN" — so it is asked directly rather
  // than by enumerating which reasons imply it. An enumeration would need
  // editing every time a member is added and would fail silently when it was
  // not; this cannot go stale, and a test can kill it.
  if (unavailable.valueLength != null) return unavailable;

  return _clippedElement11AtTail(tail) ?? unavailable;
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
/// elements are all the elements that SURVIVED a bounds check, so a clipped
/// element 11 was already dropped before this function saw anything. Callers
/// holding the raw bytes must prefer [decodeBssLoad], which can tell a clipped
/// element 11 from every other kind of clip.
///
/// [blobCompleteness] IS REQUIRED BECAUSE THE ANSWER IS NOT DERIVABLE HERE, and
/// a rule that lives only in a doc comment is a trap set for the first caller who
/// does not read it. Pass [IeBlobCompleteness.walkedToEnd] only when every octet
/// of the source blob was accounted for by a well-formed element —
/// [InformationElementWalkTail.isComplete] answers it for a raw blob, and a
/// platform channel that TLV-split the bytes itself knows whether it consumed
/// them all. With [IeBlobCompleteness.stoppedShort] and no element 11 among
/// [elements], the reading is
/// [BssLoadUnavailableReason.clippedWithoutSeeingElement11] rather than a false
/// `absent`: element 11 may have been in the part that was cut.
///
/// A CALLER THAT GENUINELY DOES NOT KNOW SAYS SO, AND IT COSTS NOTHING TO SAY.
/// [IeBlobCompleteness.notStated] yields
/// [BssLoadUnavailableReason.blobCompletenessNotStated], which claims a gap in
/// what we were told and claims nothing whatever about the capture or the AP.
///
/// THIS PARAMETER USED TO BE A BOOL, AND THE BOOL LIED. There was no third
/// value, so an uncertain caller had to pass false, and false meant
/// [BssLoadUnavailableReason.clippedWithoutSeeingElement11] — which states in
/// its own doc that the capture WAS clipped. A caller handing over a perfectly
/// whole set of elements was told we cut it. That was defended as the safe
/// direction to be wrong in, and it was: a false claim about OUR OWN byte
/// handling beats `absent`, which is the app blaming the Wi-Fi
/// ([[feedback_app_blames_the_wifi]]). But safe-to-be-wrong is not right, and a
/// type that cannot express "unknown" will be handed a guess every time
/// ([[feedback_type_must_express_unknown]]). Keith ruled on 2026-08-02 that the
/// decoder gains the member; it was done while there were still no non-test
/// callers and the change was free.
///
/// AN EMPTY [elements] WITH [IeBlobCompleteness.walkedToEnd] IS NOT `absent`
/// EITHER, and this entry point can tell on its own: a walk that reached the end
/// of its source having yielded nothing can only have run over an empty source,
/// and a beacon always carries at least an SSID element. So the source held no
/// information elements — [BssLoadUnavailableReason.noInformationElementsProvided],
/// a statement about whatever handed us the bytes rather than about the AP. Both
/// entry points decide this in this one place, so they cannot drift apart.
///
/// AN EMPTY [elements] WITH [IeBlobCompleteness.notStated] IS NOT THAT, THOUGH.
/// The argument above turns on the walk having reached the end, which is exactly
/// what an unstated blob does not tell us: an empty hand over an unknown extent
/// cannot be told from a walk cut before the first element. It reports
/// [BssLoadUnavailableReason.blobCompletenessNotStated].
BssLoadReading decodeBssLoadFromElements(
  Iterable<InformationElement> elements, {
  required IeBlobCompleteness blobCompleteness,
}) {
  BssLoadUnavailable? firstFailure;
  bool sawAnyElement = false;
  for (final InformationElement ie in elements) {
    sawAnyElement = true;
    if (ie.id != kEidBssLoad) continue;
    final BssLoadReading reading = decodeBssLoadValue(ie.bytes);
    if (reading is BssLoadDecoded) return reading;
    firstFailure ??= reading as BssLoadUnavailable;
  }
  // An element 11 that was SEEN settles the reading on its own merits, whatever
  // the caller knows about the tail — so this returns before completeness is
  // consulted at all.
  if (firstFailure != null) return firstFailure;
  switch (blobCompleteness) {
    case IeBlobCompleteness.stoppedShort:
      return const BssLoadUnavailable(
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
      );
    case IeBlobCompleteness.notStated:
      // BEFORE THE MEMBER EXISTED THIS FELL INTO THE BRANCH ABOVE and asserted a
      // clip nobody had evidence for. Named, so it can never silently rejoin it:
      // rejoining it turns four tests RED, which was measured, not assumed.
      return const BssLoadUnavailable(
        BssLoadUnavailableReason.blobCompletenessNotStated,
      );
    case IeBlobCompleteness.walkedToEnd:
      if (!sawAnyElement) {
        return const BssLoadUnavailable(
          BssLoadUnavailableReason.noInformationElementsProvided,
        );
      }
      return const BssLoadUnavailable(BssLoadUnavailableReason.absent);
  }
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
/// advertise BSS Load", "we saw an element we refuse to decode" and "this device
/// gave us no information elements at all" is worth showing — which, on a
/// pro-facing readout, it always is. This function collapses all three into
/// null, which is the right shape only for a caller that genuinely wants nothing
/// but the numbers.
BssLoad? decodeBssLoadOrNull(List<int>? ieBytes) =>
    decodeBssLoad(ieBytes).valueOrNull;

// ── Internals ────────────────────────────────────────────────────────────────

/// Turns the clipped element the walk stopped at into a BSS Load diagnosis, or
/// null when there is nothing at the tail that names element 11.
///
/// WHERE THE ARITHMETIC LIVES, AND WHY NOT HERE. Locating the stop offset is a
/// fact about the walk, so it belongs beside the walk:
/// [informationElementWalkTail] derives it from `walkInformationElements`' own
/// output, in the module that owns the loop, and is pinned by
/// `ie_parser_test.dart`. What is left in this file is the part that is about
/// BSS Load rather than about TLVs — which element id we care about, and which
/// declared lengths element 11 is allowed to have.
///
/// THE DECLARED LENGTH IS VETTED BEFORE `truncated` IS CLAIMED. A `tag_len`
/// outside 4..5 is not a BSS Load element (`packet-ieee80211.c:32228`), and a
/// clipped header does not get a weaker rule than a complete one: reporting
/// `[11, 255]` as `truncated` would assert a well-formed 255-octet element 11
/// that the reference decoder says cannot exist. The header alone disqualifies
/// it, so it is [BssLoadUnavailableReason.malformedLength] with the declared
/// length it claimed and the count that actually arrived.
///
/// NOTHING IS DECODED FROM THE CLIPPED ELEMENT. Its value octets are counted,
/// never read as fields — a partial element padded out to five octets is the
/// zero-fill guess this whole file exists to refuse.
BssLoadUnavailable? _clippedElement11AtTail(InformationElementWalkTail tail) {
  final TruncatedInformationElement? clipped = tail.truncatedElement;
  if (clipped == null) return null;
  if (clipped.id != kEidBssLoad) return null;

  final int declared = clipped.declaredLength;
  final bool declaredLengthIsOneElement11MayHave =
      declared == kBssLoadStandardValueLength ||
          declared == kBssLoadCiscoV1ValueLength;

  return BssLoadUnavailable(
    declaredLengthIsOneElement11MayHave
        ? BssLoadUnavailableReason.truncated
        : BssLoadUnavailableReason.malformedLength,
    valueLength: declared,
    availableLength: clipped.availableLength,
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
