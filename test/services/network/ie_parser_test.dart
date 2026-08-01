// The shared 802.11 information-element walker (ie_parser.dart) — its FIRST
// direct tests. No platform symbols, no I/O: plain Dart byte buffers, so these
// run on any CI.
//
// WHY THIS FILE EXISTS. `walkInformationElements` takes bytes straight off the
// air on macOS, Windows, Android and the WLAN Pi, and four modules decode from
// its output (`bss_load_decoder.dart`, `ap_name_decoder.dart`,
// `windows_wifi_ffi.dart`'s width/country decoders, and the MAC/AP-name
// enrichment above them). Until now nothing asserted its contract DIRECTLY —
// the guarantees were only ever exercised sideways, through a consumer's own
// tests. That is coupling by accident: a maintainer editing the loop finds out
// what it promised by breaking a BSS Load test, in a different module, for a
// reason the failure message does not explain.
//
// So this file pins the walk itself, including the guarantees nobody had written
// down. Four edits a maintainer might plausibly make are each covered by a named
// test below, because each is silent in most of the suite:
//
//   1. yielding a best-effort PARTIAL element instead of dropping it;
//   2. SKIPPING a bad element and resuming the walk after it;
//   3. relaxing the loop guard from `i + 2 <= n` to `i < n`;
//   4. dropping ZERO-LENGTH elements as uninteresting.
//
// Edit 3 does not just change an answer — it makes the walk THROW on a one-octet
// tail, and this function's whole reason for existing is that attacker-adjacent
// bytes must fail safe (cf. the recurring Wireshark 802.11-dissector CVEs).
//
// Build: Felix 2026-08-01.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ie_parser.dart';

/// Builds one non-extended IE element: `[id][len][...data]`.
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// An SSID element (ID 0) — realistic surrounding traffic in a blob.
List<int> _ssid(String ssid) => _ie(0, ssid.codeUnits);

/// Byte sequences that must never throw, whatever a function does with them.
/// Includes values outside byte range, which a platform channel handing up a
/// plain `List<int>` (rather than a `Uint8List`) really can produce.
const List<List<int>> _neverThrows = <List<int>>[
  <int>[],
  <int>[0],
  <int>[11],
  <int>[255],
  <int>[11, 255],
  <int>[255, 255, 255],
  <int>[0, 200, 1, 2, 3],
  <int>[300, -1, 999, 0, 0],
  <int>[-1],
];

void main() {
  group('walkInformationElements — the shape of the walk', () {
    test('yields every element in blob order, with the header stripped', () {
      final List<InformationElement> out = walkInformationElements(<int>[
        ..._ssid('WLANPros'),
        ..._ie(1, <int>[0x82, 0x84]),
        ..._ie(3, <int>[36]),
      ]).toList();

      expect(out.map((InformationElement e) => e.id), <int>[0, 1, 3]);
      expect(out[0].bytes, 'WLANPros'.codeUnits);
      expect(out[1].bytes, <int>[0x82, 0x84]);
      expect(out[2].bytes, <int>[36]);
    });

    test('a ZERO-LENGTH element is yielded, with empty bytes', () {
      // Mutant 4: dropping these as uninteresting. A zero-length element is
      // legal, and `bss_load_decoder.dart` reports `[11][0]` as a malformed
      // element 11 — a diagnosis it can only make if the element arrives.
      final List<InformationElement> out = walkInformationElements(<int>[
        ..._ssid('WLANPros'),
        ..._ie(11, <int>[]),
        ..._ie(3, <int>[36]),
      ]).toList();

      expect(out.map((InformationElement e) => e.id), <int>[0, 11, 3]);
      expect(out[1].bytes, isEmpty);
      expect(out[1].bytes, isA<Uint8List>());
    });

    test('a blob that is exactly one empty element yields that element', () {
      final List<InformationElement> out =
          walkInformationElements(<int>[11, 0]).toList();
      expect(out, hasLength(1));
      expect(out.single.id, 11);
      expect(out.single.bytes, isEmpty);
    });

    test('an empty blob and a sub-header blob yield nothing', () {
      expect(walkInformationElements(<int>[]), isEmpty);
      expect(walkInformationElements(<int>[11]), isEmpty);
    });

    test('a Uint8List and a plain List<int> walk identically', () {
      // Platform channels hand up whichever they please.
      final List<int> plain = <int>[..._ssid('WLANPros'), ..._ie(3, <int>[36])];
      final List<InformationElement> a = walkInformationElements(plain).toList();
      final List<InformationElement> b =
          walkInformationElements(Uint8List.fromList(plain)).toList();

      expect(a.map((InformationElement e) => e.id),
          b.map((InformationElement e) => e.id));
      expect(a[0].bytes, b[0].bytes);
      expect(a[1].bytes, b[1].bytes);
    });
  });

  group('walkInformationElements — the truncation contract', () {
    test('the overrunning element is NOT yielded, not even partially', () {
      // Mutant 1: a "best-effort" partial yield. Element 11 declares 5 octets
      // and 2 arrive. Handing up those 2 as if they were the element invites the
      // decoder above to pad them out to 5, which is a fabricated reading.
      final List<InformationElement> out = walkInformationElements(<int>[
        ..._ssid('WLANPros'),
        11, 5, 0x01, 0x00,
      ]).toList();

      expect(out, hasLength(1), reason: 'only the SSID is well-formed');
      expect(out.single.id, 0);
      expect(
        out.map((InformationElement e) => e.id),
        isNot(contains(11)),
        reason: 'a clipped element must not appear in the walk at all',
      );
    });

    test('the walk does NOT resume after an overrunning element', () {
      // Mutant 2: skip the bad element and carry on. The octets INSIDE the
      // overrunning element's declared span here look exactly like a well-formed
      // SSID; a resuming walk would yield an element the AP never sent.
      final List<InformationElement> out = walkInformationElements(<int>[
        ..._ssid('WLANPros'),
        11, 99, // declares 99 octets — overruns
        0, 3, 0x41, 0x42, 0x43, // would parse as SSID 'ABC' if the walk resumed
      ]).toList();

      expect(out, hasLength(1));
      expect(out.single.id, 0);
      expect(out.single.bytes, 'WLANPros'.codeUnits);
    });

    test('a single dangling octet stops the walk cleanly and never throws', () {
      // Mutant 3: `i < n` instead of `i + 2 <= n`. That reads the length octet
      // one past the end of the buffer and THROWS on bytes that came off the
      // air. The walk must end quietly instead.
      late final List<InformationElement> out;
      expect(
        () => out = walkInformationElements(<int>[..._ssid('WLANPros'), 11])
            .toList(),
        returnsNormally,
      );
      expect(out, hasLength(1));
      expect(out.single.id, 0);
    });

    test('a header declaring 255 with nothing following stops the walk', () {
      expect(walkInformationElements(<int>[11, 255]), isEmpty);
      expect(
        walkInformationElements(<int>[..._ssid('X'), 11, 255]).map(
          (InformationElement e) => e.id,
        ),
        <int>[0],
      );
    });

    test('never throws, on any bytes', () {
      for (final List<int> bytes in _neverThrows) {
        expect(() => walkInformationElements(bytes).toList(), returnsNormally,
            reason: 'walk threw on $bytes');
      }
      expect(
        () => walkInformationElements(List<int>.generate(255, (int i) => i))
            .toList(),
        returnsNormally,
      );
    });
  });

  group('walkInformationElements — guarantees nobody had written down', () {
    test('the returned Iterable is RE-iterable, not a spent iterator', () {
      // `sync*` gives a fresh walk per iteration. A consumer that walks once to
      // count and again to decode must get the same answer both times; a Stream
      // or a cached iterator would hand back nothing the second time.
      final Iterable<InformationElement> walk = walkInformationElements(<int>[
        ..._ssid('WLANPros'),
        ..._ie(3, <int>[36]),
      ]);
      expect(walk.length, 2);
      expect(walk.length, 2, reason: 'second walk must see the same elements');
      expect(walk.map((InformationElement e) => e.id), <int>[0, 3]);
    });

    test('the walk is LAZY — later octets are read only when asked for', () {
      // Load-bearing in two directions. It is why walking a 255-octet blob for
      // one element is cheap, and it is why a caller must NOT mutate the buffer
      // mid-walk: the elements it has not reached yet still come from the live
      // list.
      final List<int> blob = <int>[0, 1, 0xAA, 1, 1, 0xBB];
      final Iterator<InformationElement> it =
          walkInformationElements(blob).iterator;

      expect(it.moveNext(), isTrue);
      expect(it.current.bytes, <int>[0xAA]);

      blob[5] = 0x99; // the second element's value — not read yet
      expect(it.moveNext(), isTrue);
      expect(
        it.current.bytes,
        <int>[0x99],
        reason: 'proves the second element had not been read at first yield',
      );
    });

    test('yielded bytes are a COPY — the source can change afterwards', () {
      // The asymmetry with `findInformationElement` below is deliberate and this
      // is the half decoders rely on: a decoder may hold yielded bytes past the
      // lifetime of the platform buffer they came from.
      final List<int> blob = <int>[0, 1, 0xAA];
      final List<InformationElement> out = walkInformationElements(blob).toList();
      blob[2] = 0x99;
      expect(out.single.bytes, <int>[0xAA]);
    });

    test('ids, lengths and value octets are masked to bytes', () {
      // A platform channel handing up a `List<int>` can carry values outside
      // byte range; the walk must behave as though the wire octet arrived.
      // 267 & 0xff == 11, 300 & 0xff == 44, -1 & 0xff == 255.
      final List<InformationElement> out =
          walkInformationElements(<int>[267, 2, 300, -1]).toList();

      expect(out, hasLength(1));
      expect(out.single.id, 11, reason: 'id octet masked');
      expect(out.single.bytes, <int>[44, 255], reason: 'value octets masked');
    });

    test('a length octet outside byte range is masked, not taken literally', () {
      // 258 & 0xff == 2, so this is a two-octet element and the walk continues.
      final List<InformationElement> out =
          walkInformationElements(<int>[0, 258, 0x41, 0x42, ..._ie(3, <int>[36])])
              .toList();
      expect(out.map((InformationElement e) => e.id), <int>[0, 3]);
      expect(out.first.bytes, <int>[0x41, 0x42]);
    });
  });

  group('findInformationElement agrees with the walk', () {
    test('both find the same first element for an id', () {
      final Uint8List blob = Uint8List.fromList(<int>[
        ..._ssid('WLANPros'),
        ..._ie(3, <int>[36]),
        ..._ie(3, <int>[44]), // a second element 3 — FIRST must win in both
      ]);

      expect(findInformationElement(blob, 3), <int>[36]);
      expect(
        walkInformationElements(blob)
            .firstWhere((InformationElement e) => e.id == 3)
            .bytes,
        <int>[36],
      );
    });

    test('both stop at the same place on a clipped blob', () {
      // Element 3 lies inside the clipped span. Neither may report it.
      final Uint8List blob = Uint8List.fromList(<int>[
        ..._ssid('WLANPros'),
        11, 99, // overruns
        ..._ie(3, <int>[36]),
      ]);

      expect(findInformationElement(blob, 3), isNull);
      expect(walkInformationElements(blob).map((InformationElement e) => e.id),
          <int>[0]);
    });

    test('ASYMMETRY, deliberate: find returns a VIEW, the walk returns a COPY',
        () {
      // `findInformationElement` uses `Uint8List.sublistView`, so its result
      // ALIASES the caller's buffer — zero-copy on the Windows width/country
      // path. Anyone holding those bytes past the buffer's lifetime must copy
      // them; anyone holding the walk's bytes need not.
      final Uint8List blob = Uint8List.fromList(<int>[0, 1, 0xAA]);
      final Uint8List? found = findInformationElement(blob, 0);
      final InformationElement walked = walkInformationElements(blob).single;

      blob[2] = 0x99;

      expect(found, <int>[0x99], reason: 'a view, aliasing the source');
      expect(walked.bytes, <int>[0xAA], reason: 'a copy, independent');
    });

    test('never throws, on any bytes', () {
      for (final List<int> bytes in _neverThrows) {
        expect(
          () => findInformationElement(
              Uint8List.fromList(bytes.map((int b) => b & 0xff).toList()), 11),
          returnsNormally,
          reason: 'find threw on $bytes',
        );
      }
    });
  });

  group('informationElementWalkTail — did the walk reach the end?', () {
    test('a blob walked to its end is COMPLETE, with no truncated element', () {
      final InformationElementWalkTail tail =
          informationElementWalkTail(<int>[
        ..._ssid('WLANPros'),
        ..._ie(3, <int>[36]),
      ]);

      expect(tail.unconsumedOctets, 0);
      expect(tail.truncatedElement, isNull);
      expect(tail.isComplete, isTrue);
    });

    test('an empty blob is complete — there was nothing to cut', () {
      final InformationElementWalkTail tail = informationElementWalkTail(<int>[]);
      expect(tail.unconsumedOctets, 0);
      expect(tail.isComplete, isTrue);
      expect(tail.truncatedElement, isNull);
    });

    test('a clipped element reports its id, what it DECLARED, and what arrived',
        () {
      final InformationElementWalkTail tail = informationElementWalkTail(<int>[
        ..._ssid('WLANPros'), // 10 octets consumed first, so the offset is not 0
        11, 5, 0x01, 0x00,
      ]);

      expect(tail.isComplete, isFalse);
      expect(tail.unconsumedOctets, 4);
      final TruncatedInformationElement clipped = tail.truncatedElement!;
      expect(clipped.id, 11);
      expect(clipped.declaredLength, 5, reason: 'what the AP claimed it sent');
      expect(clipped.availableLength, 2, reason: 'what actually arrived');
    });

    test('declaredLength is what was CLAIMED, however impossible', () {
      final TruncatedInformationElement clipped =
          informationElementWalkTail(<int>[11, 255]).truncatedElement!;
      expect(clipped.declaredLength, 255);
      expect(clipped.availableLength, 0,
          reason: 'the header arrived and nothing else');
    });

    test('a ONE-octet residue is not complete, and declares nothing', () {
      // The distinction the lone-trailing-byte edge turns on: the buffer ended
      // one octet into a header, so something was cut — but no length was ever
      // declared, and reporting a declared-versus-available count would be
      // inventing a claim the bytes do not make.
      final InformationElementWalkTail tail =
          informationElementWalkTail(<int>[..._ssid('WLANPros'), 11]);

      expect(tail.unconsumedOctets, 1);
      expect(tail.truncatedElement, isNull);
      expect(tail.isComplete, isFalse,
          reason: 'a dangling octet is still evidence the buffer was cut');
    });

    test('the stop offset comes from the walk, so a value octet is not a tail',
        () {
      // The SSID's VALUE contains 0x0B. A function that SEARCHED for an element
      // id would report a truncated element 11 that was never sent.
      final InformationElementWalkTail tail = informationElementWalkTail(<int>[
        ..._ie(0, <int>[0x57, 0x0B, 0x69]),
        3, 4, 0x24, // the real clipped element, and it is not element 11
      ]);

      expect(tail.truncatedElement!.id, 3);
      expect(tail.truncatedElement!.declaredLength, 4);
      expect(tail.truncatedElement!.availableLength, 1);
    });

    test('the tail is measured after ALL complete elements, not just the first',
        () {
      final InformationElementWalkTail tail = informationElementWalkTail(<int>[
        ..._ssid('WLANPros'), // 10
        ..._ie(1, <int>[0x82, 0x84]), // 4
        ..._ie(3, <int>[36]), // 3
        3, 9, 0x24, 0x25, // 4 octets, declares 9
      ]);
      expect(tail.unconsumedOctets, 4);
      expect(tail.truncatedElement!.availableLength, 2);
    });

    test('unconsumedOctets equals the blob length minus what the walk consumed',
        () {
      // The invariant the derivation rests on, checked against an independently
      // computed sum rather than against the implementation's own arithmetic.
      for (final List<int> blob in <List<int>>[
        <int>[],
        <int>[11],
        <int>[..._ssid('WLANPros')],
        <int>[..._ssid('WLANPros'), 11, 5, 0x01],
        <int>[..._ssid('A'), ..._ie(3, <int>[36]), 7, 200],
        List<int>.generate(255, (int i) => i),
      ]) {
        int consumed = 0;
        for (final InformationElement e in walkInformationElements(blob)) {
          consumed += 2 + e.bytes.length;
        }
        expect(
          informationElementWalkTail(blob).unconsumedOctets,
          blob.length - consumed,
          reason: 'residue disagrees with the walk on $blob',
        );
      }
    });

    test('id and declared length are masked to bytes', () {
      // 267 & 0xff == 11, 300 & 0xff == 44.
      final TruncatedInformationElement clipped =
          informationElementWalkTail(<int>[267, 300, 0x01]).truncatedElement!;
      expect(clipped.id, 11);
      expect(clipped.declaredLength, 44);
      expect(clipped.availableLength, 1);
    });

    test('never throws, on any bytes', () {
      for (final List<int> bytes in _neverThrows) {
        expect(() => informationElementWalkTail(bytes), returnsNormally,
            reason: 'tail threw on $bytes');
      }
    });

    test('toString names the fields, so a failure message is readable', () {
      expect(
        informationElementWalkTail(<int>[11, 5, 0x01]).toString(),
        allOf(contains('unconsumedOctets: 3'), contains('declaredLength: 5')),
      );
    });
  });
}
