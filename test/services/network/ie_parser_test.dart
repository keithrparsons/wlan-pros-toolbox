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
// down. The edits a maintainer might plausibly make are each covered by a named
// test below, because each is silent in most of the suite. They are NAMED and
// not numbered, and that is a repair rather than a style: the list used to be
// numbered and the paragraph below used to say "Edit 3", which is a reference
// with no grep handle — insert an edit at the top and the sentence silently
// points at the wrong one. The BSS Load files next door lost two sentences to
// exactly that.
//
//   PARTIAL-YIELD — yielding a best-effort PARTIAL element instead of dropping
//     it;
//   SKIP-AND-RESUME — skipping a bad element and resuming the walk after it;
//   LOOSE-LOOP-GUARD — relaxing the loop guard from `i + 2 <= n` to `i < n`;
//   DROP-ZERO-LENGTH — dropping zero-length elements as uninteresting.
//
// LOOSE-LOOP-GUARD does not just change an answer — it makes the walk THROW on a
// one-octet tail, and this function's whole reason for existing is that
// attacker-adjacent bytes must fail safe (cf. the recurring Wireshark
// 802.11-dissector CVEs).
//
// Build: Felix 2026-08-01.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ie_parser.dart';

/// Builds one non-extended IE element: `[id][len][...data]`.
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// An SSID element (ID 0) — realistic surrounding traffic in a blob.
List<int> _ssid(String ssid) => _ie(0, ssid.codeUnits);

/// An extended element: `[255][len][extId][...data]`. The extension id is the
/// FIRST value octet and is counted in the declared length.
List<int> _extIe(int extId, List<int> data) =>
    <int>[kEidExtended, data.length + 1, extId, ...data];

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

  group('findInformationElement — the EXTENDED (255) element branch', () {
    // Recorded as a coverage boundary at the 2026-08-01 re-gate: replacing the
    // `extId == null` path with a `throw` left every suite green, so no test
    // reached this branch. Both production callers pass an `extId`
    // (`windows_wifi_ffi.dart`), which makes it unreachable in the app today —
    // but it is reachable through the public API, and an unasserted branch in
    // the one walker four modules share is a gap, not a fact about production.

    test('a matching extension id returns the data WITHOUT the ext-id byte', () {
      // HE Operation is ext-id 36; the returned bytes must start after it, or
      // every field offset in the caller's decoder is out by one.
      final Uint8List blob = Uint8List.fromList(<int>[
        ..._ssid('WLANPros'),
        ..._extIe(36, <int>[0xF0, 0x0D]),
      ]);
      expect(findInformationElement(blob, kEidExtended, extId: 36),
          <int>[0xF0, 0x0D]);
    });

    test('a 255 element with a DIFFERENT extension id is skipped, not returned',
        () {
      // The comment in the source says "skip and keep walking", and the second
      // element proves the walk really does continue rather than returning null
      // at the first 255.
      final Uint8List blob = Uint8List.fromList(<int>[
        ..._extIe(35, <int>[0xAA]), // EHT-era neighbour, not what we asked for
        ..._extIe(36, <int>[0xBB, 0xCC]),
      ]);
      expect(findInformationElement(blob, kEidExtended, extId: 36),
          <int>[0xBB, 0xCC]);
      expect(findInformationElement(blob, kEidExtended, extId: 99), isNull);
    });

    test('asking for 255 with NO extId matches nothing, however many are there',
        () {
      // The branch the re-gate found unasserted. `extId: null` cannot identify
      // an extended element — the id is in the value — so the honest answer is
      // null rather than the first 255 element's bytes.
      final Uint8List blob = Uint8List.fromList(<int>[
        ..._extIe(36, <int>[0xF0]),
        ..._extIe(35, <int>[0x0D]),
      ]);
      expect(findInformationElement(blob, kEidExtended), isNull);
    });

    test('a zero-length 255 element is skipped, and the real one still matches',
        () {
      // With no value octets there is no extension id to compare, so the empty
      // element cannot match and the walk must carry on to the one that can.
      final Uint8List blob = Uint8List.fromList(<int>[
        kEidExtended, 0, // declares nothing
        ..._extIe(36, <int>[0x77]),
      ]);
      expect(findInformationElement(blob, kEidExtended, extId: 36), <int>[0x77],
          reason: 'the empty one is skipped, the real one still matches');
      expect(findInformationElement(blob, kEidExtended, extId: 0), isNull,
          reason: 'no ext id was read from the empty element');
    });

    test('a zero-length 255 element at the END never reads past the buffer', () {
      // `len >= 1` in the source is a BOUNDS CHECK, not a formality, and the
      // test above does not prove it: there, the octet after the empty element
      // exists and merely fails to match, so relaxing the guard to `len >= 0`
      // survives. Here the empty element is the last thing in the buffer, so
      // the same relaxation indexes one past the end and THROWS — on bytes that
      // came off the air, which is the one thing this module may never do.
      final Uint8List trailing =
          Uint8List.fromList(<int>[..._ssid('X'), kEidExtended, 0]);
      expect(
        () => findInformationElement(trailing, kEidExtended, extId: 36),
        returnsNormally,
      );
      expect(findInformationElement(trailing, kEidExtended, extId: 36), isNull);

      final Uint8List alone = Uint8List.fromList(<int>[kEidExtended, 0]);
      expect(
        () => findInformationElement(alone, kEidExtended, extId: 36),
        returnsNormally,
      );
      expect(findInformationElement(alone, kEidExtended, extId: 36), isNull);
    });

    test('never throws on the EXTENDED path either, on any bytes', () {
      // The file's existing never-throws case asks for element 11, so it never
      // enters this branch at all. Same corpus, asked as an extended element.
      for (final List<int> bytes in _neverThrows) {
        final Uint8List blob =
            Uint8List.fromList(bytes.map((int b) => b & 0xff).toList());
        expect(
          () => findInformationElement(blob, kEidExtended, extId: 36),
          returnsNormally,
          reason: 'find threw on $bytes with an extId',
        );
        expect(
          () => findInformationElement(blob, kEidExtended),
          returnsNormally,
          reason: 'find threw on $bytes with no extId',
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

    test('the residue is the tail the blob was BUILT with, across six shapes',
        () {
      // WHY THE ORACLE IS A LITERAL AND NOT A SUM. This test used to compute its
      // expectation as `blob.length - sum(2 + e.bytes.length)` over the walk,
      // under a comment claiming an "independently computed sum". That is
      // `informationElementWalkTail`'s own formula, character for character
      // (`ie_parser.dart`, `consumed += _kIeHeaderOctets + ie.bytes.length`), so
      // both sides moved together and the test was blind to exactly the class of
      // change the invariant exists to catch. Demonstrated at the 2026-08-01
      // re-gate: under a walker that skips a bad element and resumes, four other
      // tests in this file go red and that one passed green.
      //
      // THE ORACLE WAS ONLY HALF OF IT, and fixing only the half that was
      // reported would have left the test just as blind. With the literals in
      // place, the six ORIGINAL blobs still all pass under that same mutant:
      // every one of them resumes into a region that yields nothing further, so
      // the residue lands on the same number either way. The seventh case below
      // exists for that and nothing else — its overrun span contains octets that
      // parse as a well-formed element, so a resuming walk consumes them and the
      // residue moves. A coupled oracle is what made a weak case list
      // invisible: with both sides moving together, no blob could ever have
      // failed, so nobody would have found out the blobs proved nothing.
      //
      // The case list is now total over every walker edit this file's header
      // names — PARTIAL-YIELD, SKIP-AND-RESUME, LOOSE-LOOP-GUARD and
      // DROP-ZERO-LENGTH: run this test alone against each and each goes red.
      //
      // Every expectation below is a CONSTANT. Seven come from the blob's own
      // construction — a well-formed prefix plus a deliberate tail, so the
      // expected residue is the tail's length by definition and cannot be
      // re-derived from the implementation. The last is a hand-derived number,
      // shown with its working, because that blob's structure is emergent.
      const List<int> tail3 = <int>[11, 5, 0x01]; // declares 5, one octet given
      const List<int> tail2 = <int>[7, 200]; // declares 200, none given
      const List<int> tail1 = <int>[11]; // half a header
      // Declares 99 and overruns; the octets INSIDE its declared span parse as
      // a well-formed SSID 'ABC'. A walk that skipped and resumed would consume
      // five of these seven octets and report a residue of 2.
      const List<int> tailResumable = <int>[11, 99, 0, 3, 0x41, 0x42, 0x43];

      final List<(String, List<int>, int)> cases = <(String, List<int>, int)>[
        ('empty blob', <int>[], 0),
        ('whole blob, nothing cut', <int>[..._ssid('WLANPros')], 0),
        ('one dangling octet', <int>[...tail1], tail1.length),
        (
          'a prefix plus a 3-octet clipped element',
          <int>[..._ssid('WLANPros'), ...tail3],
          tail3.length,
        ),
        (
          'two whole elements plus a 2-octet clipped header',
          <int>[..._ssid('A'), ..._ie(3, <int>[36]), ...tail2],
          tail2.length,
        ),
        (
          'a clipped element whose SPAN would parse as another element',
          <int>[..._ssid('WLANPros'), ...tailResumable],
          tailResumable.length,
        ),
        (
          // A dropped zero-length element takes its two header octets out of
          // the consumed count, so the residue moves. Without this case the
          // fourth documented walker edit passes this test.
          'a zero-length element still consumes its header',
          <int>[..._ssid('A'), ..._ie(11, <int>[]), ...tail2],
          tail2.length,
        ),
        // 0,1,2… walks as [0](len 1), [3](len 4), [9](len 10), [21](len 22),
        // [45](len 46), [93](len 94) — ending at offset 189 — then [189] declares
        // 190 with 64 octets left, which overruns. 255 - 189 = 66.
        ('0..254 counting blob', List<int>.generate(255, (int i) => i), 66),
      ];

      for (final (String name, List<int> blob, int expected) in cases) {
        expect(
          informationElementWalkTail(blob).unconsumedOctets,
          expected,
          reason: '$name: residue must be $expected',
        );
      }
    });

    test('the counting blob stops where the hand derivation says it does', () {
      // The working behind the 66 above, asserted rather than trusted, so the
      // literal in the previous test is checkable without re-running the walk in
      // one's head. Also a second, independent grip on the same mutant class:
      // a walk that skipped and resumed would not stop at element 189.
      final List<int> blob = List<int>.generate(255, (int i) => i);
      expect(
        walkInformationElements(blob).map((InformationElement e) => e.id),
        <int>[0, 3, 9, 21, 45, 93],
      );
      final TruncatedInformationElement clipped =
          informationElementWalkTail(blob).truncatedElement!;
      expect(clipped.id, 189, reason: 'the header at offset 189');
      expect(clipped.declaredLength, 190);
      expect(clipped.availableLength, 64, reason: '255 - 189 - 2');
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

  group('the tail types compare BY VALUE, field by field', () {
    // Both types shipped with `toString` and no `==`, so two structurally
    // identical tails compared unequal. No consumer compared them yet, which
    // made this the cheap moment: the sibling `BssLoadUnavailable` needed a
    // gate to discover its own equality was load-bearing and short a field.
    //
    // Every field gets its OWN discriminating pair below. A test that only
    // asserts "equal things are equal" survives dropping any field from `==`.

    test('identical tails are equal, and hash the same', () {
      final InformationElementWalkTail a =
          informationElementWalkTail(<int>[..._ssid('WLANPros'), 11, 5, 0x01]);
      final InformationElementWalkTail b =
          informationElementWalkTail(<int>[..._ssid('WLANPros'), 11, 5, 0x01]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.truncatedElement, b.truncatedElement);
      expect(a.truncatedElement.hashCode, b.truncatedElement.hashCode);
    });

    test('a clipped element differs by ID alone', () {
      expect(
        const TruncatedInformationElement(
            id: 11, declaredLength: 5, availableLength: 2),
        isNot(const TruncatedInformationElement(
            id: 12, declaredLength: 5, availableLength: 2)),
      );
    });

    test('a clipped element differs by DECLARED length alone', () {
      expect(
        const TruncatedInformationElement(
            id: 11, declaredLength: 5, availableLength: 2),
        isNot(const TruncatedInformationElement(
            id: 11, declaredLength: 4, availableLength: 2)),
        reason: 'declared 5 and declared 4 are different diagnoses',
      );
    });

    test('a clipped element differs by AVAILABLE length alone', () {
      expect(
        const TruncatedInformationElement(
            id: 11, declaredLength: 5, availableLength: 2),
        isNot(const TruncatedInformationElement(
            id: 11, declaredLength: 5, availableLength: 3)),
      );
    });

    test('a tail differs by RESIDUE alone, with no clipped element either side',
        () {
      expect(
        const InformationElementWalkTail(
            unconsumedOctets: 0, truncatedElement: null),
        isNot(const InformationElementWalkTail(
            unconsumedOctets: 1, truncatedElement: null)),
        reason: 'complete and one-octet-cut must not compare equal',
      );
    });

    test('a tail differs by its CLIPPED ELEMENT alone, at the same residue', () {
      // The field that would go unnoticed: both tails have a residue of 4, so
      // an `==` that compared only `unconsumedOctets` would call them equal.
      final InformationElementWalkTail eleven =
          informationElementWalkTail(<int>[..._ssid('X'), 11, 5, 0x01, 0x02]);
      final InformationElementWalkTail three =
          informationElementWalkTail(<int>[..._ssid('X'), 3, 5, 0x01, 0x02]);

      expect(eleven.unconsumedOctets, three.unconsumedOctets,
          reason: 'the residues are deliberately identical');
      expect(eleven, isNot(three));
      expect(eleven.hashCode, isNot(three.hashCode));
    });

    test('a null clipped element is not equal to a present one', () {
      expect(
        const InformationElementWalkTail(
            unconsumedOctets: 2, truncatedElement: null),
        isNot(const InformationElementWalkTail(
          unconsumedOctets: 2,
          truncatedElement: TruncatedInformationElement(
              id: 11, declaredLength: 5, availableLength: 0),
        )),
      );
    });

    test('neither type equals a foreign object', () {
      expect(
        const TruncatedInformationElement(
            id: 11, declaredLength: 5, availableLength: 2),
        isNot('not a tail'),
      );
      expect(
        const InformationElementWalkTail(
            unconsumedOctets: 0, truncatedElement: null),
        isNot(42),
      );
    });
  });
}
