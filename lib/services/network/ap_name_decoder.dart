// AP-name-from-beacon decoder — the shared, pure-Dart seam every platform
// (macOS / Android / Windows / WLAN Pi — NOT iOS, which has no IE access) plugs
// into to recover the vendor-advertised access-point name from a beacon /
// probe-response IE blob.
//
// There is no standard 802.11 "AP name." Vendors ride it in one of two IE
// shapes (per Pax's decode reference,
// Deliverables/2026-07-17-ap-name-beacon-vendor-decode/brief.md):
//
//   1. Tag 133 (0x85) — Cisco Aironet Extensions IE. Name is a 16-byte
//      zero-padded ASCII field at VALUE-offset 10. Meraki reuses this
//      (CCX-Naming), so one decoder covers both.
//   2. Tag 221 (0xDD) — vendor-specific, OUI-prefixed. Aruba / Mist / Ruckus /
//      Aerohive / Extreme / Ubiquiti (and Cisco IOS-XE 17.18.2+) carry an ASCII
//      name after the 3-byte OUI + a vendor type/subtype byte.
//
// HONESTY IS THE WHOLE POINT (GL-005 / [[feedback_app_blames_the_wifi]]):
//   * Absent IE, unknown OUI, or a malformed / truncated payload → null. Never a
//     name guessed from a BSSID, never mojibake.
//   * The exact name OFFSET inside each Tag 221 payload is UNVERIFIED in Pax's
//     brief (§6: "for EVERY Tag 221 vendor, the exact byte offset … are
//     UNVERIFIED here … I did not fabricate a single offset"). Those vendors are
//     therefore RECOGNIZED (the OUI dispatches) but return null — an honest "not
//     yet decodable" — rather than slicing a guessed substring out of the
//     payload. Each offset is a clearly-marked `null` in [_tag221Specs], trivial
//     to fill once a live capture pins the byte layout.
//   * The ONLY name offset given by the brief is the Cisco Tag-133 value-offset
//     10, and even that is MEDIUM confidence (reverse-engineered, Wireshark
//     treats Tag 133 as opaque `wlan.aironet.data`). It is pinned below as a
//     named constant with its source, to confirm against one Cisco capture.
//
// This module contains NO platform / native sourcing — that lands per platform
// (macOS via CoreWLAN `informationElementData`, Windows via the connected-BSS IE
// blob already in hand, Android via `ScanResult.getInformationElements()`, WLAN
// Pi via monitor mode). This is only the decoder + the vendor-dispatch table.

import 'dart:typed_data';

import 'ie_parser.dart';

/// A Wi-Fi vendor whose AP-name IE this decoder recognizes. Recognition
/// (dispatch) is independent of whether the name is currently DECODABLE — see
/// [_tag221Specs], where an unverified name offset yields an honest null.
enum ApNameVendor {
  /// Cisco Aironet / CCX (Tag 133, and Tag 221 OUI 00:40:96). Also Meraki.
  ciscoAironet,

  /// Aruba / HPE (Tag 221 OUI 00:0B:86).
  aruba,

  /// Mist / Juniper (Tag 221 OUI 5C:5B:35).
  mist,

  /// Ruckus / CommScope (Tag 221 OUI 00:13:92).
  ruckus,

  /// Aerohive (Tag 221 OUI 00:19:77).
  aerohive,

  /// Extreme Networks (Tag 221 OUI 00:E0:2B).
  extreme,

  /// Ubiquiti / UniFi (Tag 221 OUI 00:15:6D).
  ubiquiti,
}

// ── Cisco Aironet Extensions IE (Tag 133) — the one pinned name offset ───────

/// Element ID 133 (0x85) — Cisco Aironet Extensions IE (CCX IE). Not OUI-wrapped.
const int _kAironetIeId = 133;

/// VALUE-offset of the 16-byte zero-padded ASCII device-name field inside the
/// Tag-133 value (`data[10..25]`), followed by a client-count byte at offset 26.
///
/// Confidence: MEDIUM. Source: reverse-engineered Aironet-IE layout in
/// enukane/StationCountObservatory (https://github.com/enukane/StationCountObservatory).
/// Wireshark does NOT break out this sub-field (it exposes only opaque
/// `wlan.aironet.data`), so this offset must be confirmed against one real Cisco
/// capture before it is treated as HIGH confidence. Until then it is the app's
/// best-pinned name offset and is used, because a wrong offset yields a
/// non-printable slice → null (see [_decodeAsciiName]), not a fabricated name.
const int _kAironetNameOffset = 10;

/// Width of the Aironet name field: 16 bytes (name + null pad), max 15 chars.
const int _kAironetNameLen = 16;

// ── Tag 221 OUI dispatch table — PINNED (Wireshark epan/oui.h, HIGH) ─────────
//
// The 3-byte OUI constants are exact (Pax §1, from Wireshark epan/oui.h,
// retrieved 2026-07-17). They are the dispatch KEYS. The per-vendor name OFFSET
// is a separate, UNVERIFIED datum — every one below is `null` pending a capture.

/// Per-vendor Tag-221 decode spec.
///
/// [nameOffset] is the ABSOLUTE byte offset of the ASCII name within the element
/// VALUE bytes (`value[0]` is the first OUI byte; the 3-byte OUI + vendor-type
/// byte occupy 0–3, so a name that starts right after them is at offset 4). A
/// `null` offset means "recognized vendor, offset not yet verified" — the decoder
/// returns honest null rather than guessing.
///
/// [requiredVendorType], when non-null, gates decoding on `value[3]`: a vendor
/// can carry several vendor-specific elements under one OUI, and only the one
/// whose type/subtype byte matches is the AP-name element. A mismatch returns
/// null (a different element, not a name).
///
/// [maxNameChars] caps a decoded name to the vendor's documented ceiling, or is
/// null when the wire format is not length-capped (the name runs to the end of
/// the element and is bounded only by the element length).
class _Tag221Spec {
  const _Tag221Spec(
    this.vendor, {
    this.nameOffset,
    this.requiredVendorType,
    this.maxNameChars,
  });

  final ApNameVendor vendor;
  final int? nameOffset;
  final int? requiredVendorType;
  final int? maxNameChars;
}

/// Packs a 3-byte OUI into a single int key (`oui[0]<<16 | oui[1]<<8 | oui[2]`).
int _ouiKey(int a, int b, int c) => (a << 16) | (b << 8) | c;

/// OUI → decode spec. Dispatch keys are HIGH-confidence (Wireshark epan/oui.h);
/// every name offset is UNVERIFIED (null) until a live capture pins it.
final Map<int, _Tag221Spec> _tag221Specs = <int, _Tag221Spec>{
  // Cisco Aironet / CCX — 00:40:96 (OUI_CISCOWL). IOS-XE 17.18.2+ vendor form,
  // ≤32 chars. Offset UNVERIFIED — needs a 17.18.2+ capture / the mrn-cciew PCAP.
  _ouiKey(0x00, 0x40, 0x96):
      const _Tag221Spec(ApNameVendor.ciscoAironet, nameOffset: null, maxNameChars: 32),
  // Aruba / HPE — 00:0B:86 (OUI_ARUBA), ≤30 chars. Offset UNVERIFIED — read
  // `wlan.aruba.type` dissector / one capture.
  _ouiKey(0x00, 0x0B, 0x86):
      const _Tag221Spec(ApNameVendor.aruba, nameOffset: null, maxNameChars: 30),
  // Mist / Juniper — 5C:5B:35 (OUI_MIST), ≤32 chars. Offset UNVERIFIED — the
  // dissector + PCAP in Wireshark GitLab issue #15415 pin it; read before wiring.
  _ouiKey(0x5C, 0x5B, 0x35):
      const _Tag221Spec(ApNameVendor.mist, nameOffset: null, maxNameChars: 32),
  // Ruckus / CommScope — 00:13:92 (OUI_RUCKUS), ≤64 chars (RFC 1034). Offset
  // UNVERIFIED — directly readable from the named `wlan.vs.ruckus.apname`
  // dissector branch (Adrian Granados). Highest-confidence Tag 221 candidate.
  _ouiKey(0x00, 0x13, 0x92):
      const _Tag221Spec(ApNameVendor.ruckus, nameOffset: null, maxNameChars: 64),
  // Aerohive — 00:19:77 (OUI_AEROHIVE), ≤32 chars, no spaces. Offset UNVERIFIED
  // — read the named `wlan.vs.aerohive.hostname` dissector branch.
  _ouiKey(0x00, 0x19, 0x77):
      const _Tag221Spec(ApNameVendor.aerohive, nameOffset: null, maxNameChars: 32),
  // Extreme — 00:E0:2B (OUI_EXTREME), ≤32 chars. Offset UNVERIFIED. Confirm
  // whether current firmware emits under 00:19:77 (Aerohive) or 00:E0:2B.
  _ouiKey(0x00, 0xE0, 0x2B):
      const _Tag221Spec(ApNameVendor.extreme, nameOffset: null, maxNameChars: 32),
  // Ubiquiti / UniFi — 00:15:6D (OUI_UBIQUITI). UniFi Network 10.1.67+, per-SSID
  // "Show AP Name in Beacon". PINNED from the Wireshark master dissector
  // (HIGH, dissector-pinned): the element value is `OUI(3) | vendor_type(1) |
  // name(ASCII, to end)`. vendor_type 0x01 = AP Name (UBIQUITI_APNAME in
  // packet-ieee80211.c); the name is NOT length-prefixed and runs to the end of
  // the element, so nameOffset = 4 and the length is bounded only by the element
  // length (the dissector does not cap it — do not hard-cap here). A Ubiquiti
  // element with a different vendor_type is a different element → null.
  // Sources: Wireshark epan/oui.h (OUI_UBIQUITI 0x00156D) + packet-ieee80211.c
  // (UBIQUITI_APNAME 0x01, name-to-end ASCII), pinned by Mack 2026-07-17. Still
  // to self-confirm on the wire: that live 10.1.67+ firmware emits type 0x01 —
  // the vendor-type gate makes a wrong assumption fail safe to null, not a guess.
  _ouiKey(0x00, 0x15, 0x6D): const _Tag221Spec(
    ApNameVendor.ubiquiti,
    requiredVendorType: 0x01,
    nameOffset: 4,
    maxNameChars: null, // name runs to end; bounded by the element length only
  ),
};

// ── Public API ───────────────────────────────────────────────────────────────

/// Decodes the vendor-advertised AP name from a raw beacon / probe-response IE
/// blob [ieBytes], or null when no name can be honestly recovered.
///
/// Total and side-effect-free: it never throws on malformed, truncated, empty,
/// or non-Wi-Fi input — every bounds failure returns null. A null result means
/// one of: no name IE present; the network's AP does not advertise a name
/// (config-off, or a vendor like MikroTik that has no such feature); the vendor
/// IS recognized but its name offset is not yet verified in this build; or the
/// decoded bytes were not clean printable ASCII (a guard against mojibake).
String? decodeApName(List<int> ieBytes) =>
    decodeApNameFromElements(walkInformationElements(ieBytes));

/// Decoder variant taking pre-parsed [elements] (from [walkInformationElements]
/// or a platform channel that already TLV-split the blob). Same honesty
/// contract as [decodeApName].
String? decodeApNameFromElements(Iterable<InformationElement> elements) {
  final List<InformationElement> list = elements.toList(growable: false);

  // 1. Cisco Aironet Extensions IE (Tag 133) — the pinned offset. Also covers
  //    Meraki CCX-Naming (same tag, same layout).
  for (final InformationElement ie in list) {
    if (ie.id == _kAironetIeId) {
      final String? name = _decodeAironetName(ie.bytes);
      if (name != null) return name;
    }
  }

  // 2. Vendor-specific (Tag 221), dispatched on OUI. A recognized vendor with an
  //    UNVERIFIED offset yields null (honest "not yet decodable"), NOT a guess.
  for (final InformationElement ie in list) {
    if (ie.id == kEidVendorSpecific) {
      final String? name = _decodeTag221Name(ie.bytes);
      if (name != null) return name;
    }
  }

  // 3. No name IE, unknown vendor, or vendor advertises none (MikroTik) → null.
  return null;
}

/// Returns the [ApNameVendor] a Tag-221 value dispatches to by its 3-byte OUI,
/// or null when the OUI is not in the table (or the value is too short to hold
/// one). Exposed for tests / logging: dispatch (which vendor) is meaningful even
/// when the name itself is not yet decodable.
ApNameVendor? tag221VendorForOui(List<int> tag221Value) {
  if (tag221Value.length < 3) return null;
  return _tag221Specs[_ouiKey(
    tag221Value[0] & 0xff,
    tag221Value[1] & 0xff,
    tag221Value[2] & 0xff,
  )]?.vendor;
}

/// Whether this build can currently decode a name for [vendor]'s Tag-221 form
/// (i.e. its name offset is verified). False for every vendor whose offset is
/// still `null` in [_tag221Specs]. Exposed so a test can assert the honest-null
/// posture is intentional, and so a "needs capture" report can enumerate gaps.
bool tag221OffsetVerified(ApNameVendor vendor) {
  for (final _Tag221Spec spec in _tag221Specs.values) {
    if (spec.vendor == vendor) return spec.nameOffset != null;
  }
  return false;
}

// ── Internals ────────────────────────────────────────────────────────────────

/// Decodes the Tag-133 (Cisco Aironet / Meraki) name at the pinned value-offset.
/// Returns null when the value is too short to hold the field, or the field is
/// not clean printable ASCII.
String? _decodeAironetName(Uint8List value) {
  const int end = _kAironetNameOffset + _kAironetNameLen;
  if (value.length < end) return null; // truncated field — honest null, no throw
  return _decodeAsciiName(
    value.sublist(_kAironetNameOffset, end),
    maxChars: _kAironetNameLen,
  );
}

/// Decodes a Tag-221 vendor-specific name by dispatching on its OUI. Returns
/// null for an unknown OUI, a recognized-but-unverified offset, or a payload too
/// short / not printable ASCII.
String? _decodeTag221Name(Uint8List value) {
  // Need at least the 3-byte OUI + 1 vendor type/subtype byte to dispatch.
  if (value.length < 4) return null;
  final _Tag221Spec? spec = _tag221Specs[_ouiKey(value[0], value[1], value[2])];
  if (spec == null) return null; // unknown vendor OUI
  // A vendor can carry several elements under one OUI; only the AP-name subtype
  // decodes. A different type byte → different element → null (not a name).
  if (spec.requiredVendorType != null && value[3] != spec.requiredVendorType) {
    return null;
  }
  final int? offset = spec.nameOffset;
  if (offset == null) return null; // recognized, but offset UNVERIFIED → honest null
  if (value.length <= offset) return null; // payload too short for the name
  return _decodeAsciiName(value.sublist(offset), maxChars: spec.maxNameChars);
}

/// Turns a raw name field into a clean string, or null.
///
/// Zero-padded / C-string semantics: content ends at the first NUL. The result
/// is then capped to [maxChars] (the vendor field width), trimmed of leading /
/// trailing whitespace, and REJECTED (→ null) if any remaining byte is outside
/// printable ASCII (0x20–0x7E) or the result is empty. Rejecting non-printable
/// bytes is deliberate: a garbage / mojibake decode is worse than an honest null
/// (Pax §4), and it is also what makes a WRONG offset fail safe.
String? _decodeAsciiName(List<int> raw, {int? maxChars}) {
  int end = raw.indexOf(0x00);
  if (end < 0) end = raw.length;
  List<int> slice = raw.sublist(0, end);
  if (maxChars != null && slice.length > maxChars) {
    slice = slice.sublist(0, maxChars);
  }
  for (final int b in slice) {
    if (b < 0x20 || b > 0x7e) return null; // non-printable → reject, never mojibake
  }
  final String name = String.fromCharCodes(slice).trim();
  return name.isEmpty ? null : name;
}
