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
