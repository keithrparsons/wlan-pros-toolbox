// Platform-neutral 802.11 information-element (IE) TLV walker.
//
// A beacon / probe-response IE blob is a run of `[id][len][value…]` triples.
// This module is the ONE bounds-checked walker every platform (macOS / Android
// / Windows / WLAN Pi) and every decoder plugs into — it takes raw bytes off
// the air, so it must NEVER throw on a truncated or malformed blob: a length
// field that overruns the buffer stops the walk cleanly and yields nothing
// further, rather than crashing (cf. the recurring Wireshark 802.11-dissector
// CVEs — attacker-adjacent bytes must fail safe).
//
// Extracted from `windows_wifi_ffi.dart` (where [findInformationElement] began
// life Windows-scoped) so the Windows channel-width/country decoders AND the
// shared AP-name decoder share a single, tested implementation.
// `windows_wifi_ffi.dart` re-exports [findInformationElement] for source
// compatibility with its existing callers and tests.
//
// WHO DEPENDS ON THE WALK'S EXACT STOPPING BEHAVIOUR. [walkInformationElements]
// dropping a truncated tail SILENTLY is what makes it total, and one dependent
// needs to know that it happened: `bss_load_decoder.dart` must tell "the AP does
// not advertise BSS Load" apart from "our capture was cut before we could tell",
// and reporting the first as the second is a false statement about someone's
// network. That question is answered by [informationElementWalkTail] below —
// an OPT-IN sibling, not a change to the walk: existing callers are unaffected,
// the walker's return type is untouched, and nothing here can throw. Its
// contract is pinned by `test/services/network/ie_parser_test.dart`, which
// exists because this walk is load-bearing for four modules.

import 'dart:typed_data';

/// Element ID 255 — the Element ID Extension marker. A `255` element carries its
/// real extension id as the FIRST value byte (e.g. HE / EHT Operation).
const int kEidExtended = 255;

/// Element ID 221 (0xDD) — the vendor-specific IE. Its value begins with a
/// 3-byte OUI + a vendor type/subtype byte; the same tag can appear MULTIPLE
/// times in one blob (one per vendor), so a name decoder must walk them all.
const int kEidVendorSpecific = 221;

/// One parsed information element: its [id] and its VALUE bytes (the id/len
/// header excluded). For an extended element ([id] == [kEidExtended]) the first
/// byte of [bytes] is the extension id.
class InformationElement {
  const InformationElement(this.id, this.bytes);

  /// Element ID (0–255).
  final int id;

  /// Value bytes with the `[id][len]` header stripped. Never null; may be empty
  /// (a zero-length element is legal).
  final Uint8List bytes;
}

/// Lazily walks the TLV blob [ies] and yields every well-formed element in order.
///
/// Bounds-checked and total: it stops at the FIRST element whose declared length
/// overruns the buffer (a truncated tail), and yields nothing for an empty or
/// sub-header input. Never throws. Accepts any `List<int>` (a `Uint8List`, or a
/// plain byte list handed up from a platform channel).
Iterable<InformationElement> walkInformationElements(List<int> ies) sync* {
  final int n = ies.length;
  int i = 0;
  while (i + 2 <= n) {
    final int id = ies[i] & 0xff;
    final int len = ies[i + 1] & 0xff;
    final int dataStart = i + 2;
    final int dataEnd = dataStart + len;
    if (dataEnd > n) break; // truncated element — stop cleanly, never throw.
    yield InformationElement(
      id,
      Uint8List.fromList(ies.sublist(dataStart, dataEnd)),
    );
    i = dataEnd;
  }
}

/// Octets in a non-extended IE header: `[id][len]`.
const int _kIeHeaderOctets = 2;

/// The header of the element [walkInformationElements] stopped at: it declared
/// more value octets than the buffer holds, so the walk yielded it not at all.
///
/// Nothing here is decoded from the clipped element — its value octets are
/// COUNTED, never read as fields. Padding a partial element out to its declared
/// length is a guess wearing a measurement's clothes.
class TruncatedInformationElement {
  const TruncatedInformationElement({
    required this.id,
    required this.declaredLength,
    required this.availableLength,
  });

  /// Element ID from the header octet actually present in the buffer.
  final int id;

  /// The value length the element's length octet CLAIMED. What the AP said it
  /// sent, not what arrived.
  final int declaredLength;

  /// The number of value octets that actually arrived. Always strictly less than
  /// [declaredLength] — that is what made the walk stop.
  final int availableLength;

  /// Value equality on all three fields.
  ///
  /// A tail is a diagnosis, and a diagnosis a caller cannot compare is a
  /// diagnosis a caller cannot test, cache or de-duplicate. The sibling
  /// `BssLoadUnavailable` learned this the expensive way: its equality turned
  /// out to be load-bearing only after a gate found a field missing from it.
  @override
  bool operator ==(Object other) =>
      other is TruncatedInformationElement &&
      other.id == id &&
      other.declaredLength == declaredLength &&
      other.availableLength == availableLength;

  @override
  int get hashCode => Object.hash(id, declaredLength, availableLength);

  @override
  String toString() => 'TruncatedInformationElement(id: $id, '
      'declaredLength: $declaredLength, availableLength: $availableLength)';
}

/// What [walkInformationElements] left behind when it stopped.
class InformationElementWalkTail {
  const InformationElementWalkTail({
    required this.unconsumedOctets,
    required this.truncatedElement,
  });

  /// Octets at the end of the blob that no well-formed element accounted for.
  ///
  /// 0 means the walk reached the end of the buffer and EVERY octet belonged to
  /// a well-formed element — the only condition under which "element X was not
  /// in this blob" is a statement about the AP rather than about the capture.
  final int unconsumedOctets;

  /// The clipped element header at the stop offset, or null when
  /// [unconsumedOctets] is 0 or 1.
  ///
  /// One dangling octet is NOT a header: a TLV header is two octets, so with a
  /// residue of 1 no length was ever declared and there is nothing to report a
  /// declared-versus-available count about. The octet is still evidence the
  /// buffer ended mid-header — see [isComplete], which is false there.
  final TruncatedInformationElement? truncatedElement;

  /// True when the walk consumed the whole buffer.
  ///
  /// FALSE IS THE LOAD-BEARING DIRECTION: it means the buffer ended in the
  /// middle of something, so any element not seen in the walked region may
  /// simply have been cut off. A decoder must not report such an element as
  /// "not advertised".
  bool get isComplete => unconsumedOctets == 0;

  /// Value equality on the residue AND on the clipped element, which is why
  /// [TruncatedInformationElement] needed one too — without it, two tails
  /// carrying different clipped elements would compare equal whenever their
  /// residues matched.
  @override
  bool operator ==(Object other) =>
      other is InformationElementWalkTail &&
      other.unconsumedOctets == unconsumedOctets &&
      other.truncatedElement == truncatedElement;

  @override
  int get hashCode => Object.hash(unconsumedOctets, truncatedElement);

  @override
  String toString() => 'InformationElementWalkTail('
      'unconsumedOctets: $unconsumedOctets, '
      'truncatedElement: $truncatedElement)';
}

/// Reports where [walkInformationElements] stopped on [ies], for the decoders
/// that must tell "this AP did not advertise element X" apart from "our capture
/// was cut before we could tell". Total; never throws; decodes nothing.
///
/// OPT-IN. The walk itself is unchanged and no existing caller inherits this.
///
/// HOW THE STOP OFFSET IS DERIVED, and why this is not a second parser. Every
/// element the walk yields consumed exactly `2 + bytes.length` contiguous octets
/// starting at 0, so summing that over the yielded elements gives the offset
/// where the walk stopped. The offset comes FROM the walk's own output, so this
/// function cannot drift out of agreement with the loop above the way a
/// re-implemented walk could — there is exactly one walk in this file.
///
/// WHY THE RESIDUE IS UNAMBIGUOUS. The loop runs while `i + 2 <= n` and breaks
/// only when a declared length overruns. So after it returns, the residue is
/// exactly one of:
///   * 0 octets — the walk consumed the buffer; nothing was cut;
///   * 1 octet  — the loop ran out of room for a header. The buffer ended one
///                octet into an element header, so something WAS cut, but no
///                length was declared and the element is unidentifiable beyond
///                its id octet;
///   * ≥2 octets — the loop broke, and the octets at the stop offset ARE an
///                element header whose declared length overruns the buffer.
/// No scanning and no guessing: a caller must never search a blob for an element
/// id, because an id-valued byte inside an SSID or a rates element is a VALUE
/// octet, and searching for it invents elements that were never sent.
InformationElementWalkTail informationElementWalkTail(List<int> ies) {
  int consumed = 0;
  for (final InformationElement ie in walkInformationElements(ies)) {
    consumed += _kIeHeaderOctets + ie.bytes.length;
  }
  final int residue = ies.length - consumed;
  if (residue < _kIeHeaderOctets) {
    return InformationElementWalkTail(
      unconsumedOctets: residue,
      truncatedElement: null,
    );
  }
  return InformationElementWalkTail(
    unconsumedOctets: residue,
    truncatedElement: TruncatedInformationElement(
      id: ies[consumed] & 0xff,
      declaredLength: ies[consumed + 1] & 0xff,
      availableLength: residue - _kIeHeaderOctets,
    ),
  );
}

/// Walks an IE TLV blob (`[id][len][data…]` repeated) and returns the `data`
/// bytes of the FIRST element matching [elementId]. For an extended element
/// ([elementId] == 255) the match also requires the first data byte to equal
/// [extId], and the returned bytes EXCLUDE that extension-id byte. Returns null
/// when absent; stops cleanly on a truncated/malformed blob (never throws).
Uint8List? findInformationElement(Uint8List ies, int elementId, {int? extId}) {
  int i = 0;
  while (i + 2 <= ies.length) {
    final int id = ies[i];
    final int len = ies[i + 1];
    final int dataStart = i + 2;
    final int dataEnd = dataStart + len;
    if (dataEnd > ies.length) break; // truncated element — stop
    if (id == elementId) {
      if (id == kEidExtended) {
        if (len >= 1 && extId != null && ies[dataStart] == extId) {
          return Uint8List.sublistView(ies, dataStart + 1, dataEnd);
        }
        // A 255 element with a different extension id — skip and keep walking.
      } else {
        return Uint8List.sublistView(ies, dataStart, dataEnd);
      }
    }
    i = dataEnd;
  }
  return null;
}
