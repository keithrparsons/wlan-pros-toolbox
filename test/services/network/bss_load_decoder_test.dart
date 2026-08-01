// BSS Load decoder — pure-function tests (bss_load_decoder.dart). No I/O, no
// platform symbols: every case is a plain Dart byte buffer, so they run on any
// CI.
//
// What these lock, in the order the bugs actually happen:
//   1. LITTLE-ENDIAN on both 2-octet fields. Every multi-octet vector here uses
//      two DIFFERENT octets, so a big-endian mistake fails rather than passing
//      on a palindrome.
//   2. Human units at the boundary. The raw octet is kept, and the percentage is
//      converted (raw/255 and raw/31250) — a screen showing "utilization: 128"
//      would be wrong AND plausible, which is the dangerous kind.
//   3. The states stay apart: ABSENT (this AP does not advertise it), NOTHING
//      PROVIDED (this device handed us no information elements), UNAVAILABLE
//      (bad length / Cisco variant / the capture was cut), and a genuine
//      ALL-ZERO reading are DIFFERENT answers, named rather than counted here
//      because the count has already changed once. Only ABSENT says anything
//      about the AP, and every test that asserts it also asserts what it is not.
//   4. Nothing throws, ever, on any byte sequence — including a null blob.
//
// Layout and constants are pinned in the decoder's header to Wireshark's
// dissector at commit b1f51ff4 — read that before changing a number here.
//
// Build: Felix 2026-08-01.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/bss_load_decoder.dart';
import 'package:wlan_pros_toolbox/services/network/ie_parser.dart';

/// Builds one non-extended IE element: `[id][len][...data]`.
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// Builds a standard 5-octet BSS Load element (ID 11) from its three fields,
/// laying the two 16-bit fields down LITTLE-ENDIAN, low octet first — i.e. this
/// helper encodes the wire format independently of the decoder's own reader, so
/// the round trip is a real check and not a tautology.
List<int> _bssLoadIe({
  required int stationCount,
  required int channelUtilization,
  required int admissionCapacity,
}) =>
    _ie(11, <int>[
      stationCount & 0xff,
      (stationCount >> 8) & 0xff,
      channelUtilization & 0xff,
      admissionCapacity & 0xff,
      (admissionCapacity >> 8) & 0xff,
    ]);

/// An SSID element (ID 0), used as realistic surrounding traffic in a blob.
List<int> _ssidIe(String ssid) => _ie(0, ssid.codeUnits);

/// Unwraps a reading that must have decoded, failing the test with a readable
/// message when it did not.
BssLoad _decoded(BssLoadReading reading) {
  expect(reading, isA<BssLoadDecoded>(), reason: 'expected a decoded reading');
  return (reading as BssLoadDecoded).load;
}

void main() {
  group('known-good vectors', () {
    test('decodes a busy-AP element in the middle of a realistic blob', () {
      // 23 stations, utilization 120/255 (~47%), 8000 raw admission capacity.
      final List<int> blob = <int>[
        ..._ssidIe('WLANPros'),
        ..._bssLoadIe(
          stationCount: 23,
          channelUtilization: 120,
          admissionCapacity: 8000,
        ),
        ..._ie(3, <int>[36]), // DS Parameter Set, channel 36 — trailing traffic
      ];

      final BssLoad load = _decoded(decodeBssLoad(blob));
      expect(load.stationCount, 23);
      expect(load.rawChannelUtilization, 120);
      expect(load.rawAdmissionCapacity, 8000);
      expect(load.channelUtilizationPercent, closeTo(47.0588, 0.0001));
      expect(load.admissionCapacityMicrosecondsPerSecond, 256000);
      expect(load.admissionCapacityPercent, closeTo(25.6, 0.0001));
      expect(load.admissionCapacityExceedsFullScale, isFalse);
    });

    test('decodes when BSS Load is the only element in the blob', () {
      final BssLoad load = _decoded(
        decodeBssLoad(
          _bssLoadIe(
            stationCount: 1,
            channelUtilization: 3,
            admissionCapacity: 31000,
          ),
        ),
      );
      expect(load.stationCount, 1);
      expect(load.rawChannelUtilization, 3);
      expect(load.rawAdmissionCapacity, 31000);
    });

    test('decodeBssLoadValue decodes bare value octets (header stripped)', () {
      // 0x012A = 298 stations, cu 0x40 = 64, 0x2710 = 10000 raw capacity.
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x2A, 0x01, 0x40, 0x10, 0x27]),
      );
      expect(load.stationCount, 298);
      expect(load.rawChannelUtilization, 64);
      expect(load.rawAdmissionCapacity, 10000);
    });

    test('decodeBssLoadOrNull returns the numbers for a good element', () {
      final BssLoad? load = decodeBssLoadOrNull(
        _bssLoadIe(
          stationCount: 5,
          channelUtilization: 10,
          admissionCapacity: 20,
        ),
      );
      expect(load?.stationCount, 5);
    });
  });

  group('byte order is LITTLE-ENDIAN (both 16-bit fields)', () {
    // Every vector here uses two DIFFERENT octets, so reading big-endian
    // produces a different number and the test fails. A vector like [0x05,0x05]
    // would pass either way and prove nothing.

    test('station count reads low octet first', () {
      // Wire 0x2A 0x01 → 0x012A = 298 little-endian; 0x2A01 = 10753 big-endian.
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x2A, 0x01, 0x00, 0x00, 0x00]),
      );
      expect(load.stationCount, 298);
      expect(load.stationCount, isNot(10753), reason: 'big-endian mistake');
    });

    test('admission capacity reads low octet first', () {
      // Wire 0x10 0x27 → 0x2710 = 10000 little-endian; 0x1027 = 4135 big-endian.
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 0x00, 0x10, 0x27]),
      );
      expect(load.rawAdmissionCapacity, 10000);
      expect(load.rawAdmissionCapacity, isNot(4135), reason: 'big-endian mistake');
    });

    test('an asymmetric vector distinguishes both fields at once', () {
      // Station count 0x0102 = 258, capacity 0x0403 = 1027. Swapping either
      // field to big-endian moves it to 513 / 772 respectively.
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x02, 0x01, 0x7F, 0x03, 0x04]),
      );
      expect(load.stationCount, 258);
      expect(load.rawAdmissionCapacity, 1027);
    });
  });

  group('human units at the decoder boundary', () {
    test('a mid-scale utilization octet is a percentage, not the raw octet', () {
      // The dangerous bug: 128 rendered as "128%" or "utilization: 128".
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 128, 0x00, 0x00]),
      );
      expect(load.rawChannelUtilization, 128, reason: 'raw octet kept');
      expect(load.channelUtilizationPercent, closeTo(50.196, 0.001));
      expect(load.channelUtilizationPercent, lessThan(100));
    });

    test('admission capacity converts to microseconds per second (x32)', () {
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 0x00, 0x10, 0x27]), // 10000
      );
      expect(load.admissionCapacityMicrosecondsPerSecond, 320000);
      expect(load.admissionCapacityPercent, closeTo(32.0, 0.0001));
    });
  });

  group('boundary values', () {
    test('utilization 0 is 0% and utilization 255 is exactly 100%', () {
      final BssLoad idle = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 0, 0x00, 0x00]),
      );
      expect(idle.channelUtilizationPercent, 0.0);

      final BssLoad saturated = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 255, 0x00, 0x00]),
      );
      expect(saturated.rawChannelUtilization, 255);
      expect(saturated.channelUtilizationPercent, 100.0);
    });

    test('admission capacity 0 is 0% and 31250 is exactly 100%', () {
      final BssLoad none = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 0x00, 0x00, 0x00]),
      );
      expect(none.admissionCapacityPercent, 0.0);
      expect(none.admissionCapacityMicrosecondsPerSecond, 0);

      // 31250 = 0x7A12 → little-endian on the wire as 0x12 0x7A.
      final BssLoad full = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 0x00, 0x12, 0x7A]),
      );
      expect(full.rawAdmissionCapacity, 31250);
      expect(full.admissionCapacityPercent, 100.0);
      // A full second of medium time.
      expect(full.admissionCapacityMicrosecondsPerSecond, 1000000);
      expect(full.admissionCapacityExceedsFullScale, isFalse);
    });

    test('station count saturates the 16-bit field without overflow', () {
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0xFF, 0xFF, 0x00, 0x00, 0x00]),
      );
      expect(load.stationCount, 65535);
    });

    test('a capacity above 31250 is reported out of range, never clamped', () {
      // 0xFFFF = 65535 raw — more than a full second of medium time.
      final BssLoad load = _decoded(
        decodeBssLoadValue(<int>[0x00, 0x00, 0x00, 0xFF, 0xFF]),
      );
      expect(load.rawAdmissionCapacity, 65535);
      expect(load.admissionCapacityExceedsFullScale, isTrue);
      expect(load.admissionCapacityPercent, greaterThan(100));
    });
  });

  group('absent, nothing-provided, malformed and zero are DIFFERENT answers',
      () {
    test('an all-zero element is a REAL reading, not an absence', () {
      final BssLoadReading reading = decodeBssLoad(
        _bssLoadIe(
          stationCount: 0,
          channelUtilization: 0,
          admissionCapacity: 0,
        ),
      );
      expect(reading.isDecoded, isTrue);
      final BssLoad load = _decoded(reading);
      expect(load.stationCount, 0);
      expect(load.channelUtilizationPercent, 0.0);
      expect(load.admissionCapacityPercent, 0.0);
    });

    test('a blob with no element 11 is absent, with no length to report', () {
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        ..._ie(3, <int>[36]),
        ..._ie(48, <int>[0x01, 0x00]), // RSN
      ]);
      expect(reading, isA<BssLoadUnavailable>());
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.absent);
      expect(out.valueLength, isNull);
      expect(reading.valueOrNull, isNull);
    });

    test('an empty blob is NOT absent — nothing was read, so nothing is known',
        () {
      final BssLoadReading reading = decodeBssLoad(<int>[]);
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.noInformationElementsProvided,
      );
      expect(
        reading.reason,
        isNot(BssLoadUnavailableReason.absent),
        reason: 'absent would claim this AP does not advertise BSS Load',
      );
    });

    test('a short element is malformed, and NOT absent and NOT zero', () {
      // Element 11 declaring 3 value octets — too short to hold the fields.
      final BssLoadReading reading =
          decodeBssLoad(_ie(11, <int>[0x05, 0x00, 0x40]));
      expect(reading, isA<BssLoadUnavailable>());
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.reason, isNot(BssLoadUnavailableReason.absent));
      expect(out.valueLength, 3);
      expect(reading.valueOrNull, isNull);
    });

    test('a zero-length element 11 is malformed, not a zero reading', () {
      final BssLoadReading reading = decodeBssLoad(_ie(11, <int>[]));
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.malformedLength,
      );
      expect(reading.valueOrNull, isNull);
    });

    test('an over-length element is refused, not decoded from its prefix', () {
      // Element 11 with 7 value octets. The first five look like a valid
      // element; Wireshark refuses any tag_len outside 4..5
      // (packet-ieee80211.c:32228) and so do we — decoding a prefix of an
      // element we do not recognize is a guess.
      final BssLoadReading reading = decodeBssLoad(
        _ie(11, <int>[0x17, 0x00, 0x78, 0x40, 0x1F, 0xAA, 0xBB]),
      );
      expect(reading, isA<BssLoadUnavailable>());
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.valueLength, 7);
      expect(reading.valueOrNull, isNull);
    });

    test('decodeBssLoadOrNull returns null for every not-a-reading case', () {
      expect(decodeBssLoadOrNull(_ssidIe('WLANPros')), isNull, reason: 'absent');
      expect(decodeBssLoadOrNull(_ie(11, <int>[0x01, 0x02, 0x03])), isNull,
          reason: 'malformedLength');
      expect(decodeBssLoadOrNull(<int>[]), isNull, reason: 'empty blob');
      expect(decodeBssLoadOrNull(null), isNull, reason: 'null blob');
    });
  });

  group('Cisco QBSS Version 1 (the 4-octet variant) is recognized, not decoded', () {
    test('a 4-octet element 11 reports the vendor variant, not a number', () {
      // Wireshark: tag_len 4 -> "Cisco QBSS Version 1 - non CCA", whose
      // admission-capacity field is ONE octet with different semantics.
      final BssLoadReading reading =
          decodeBssLoad(_ie(11, <int>[0x17, 0x00, 0x78, 0x20]));
      expect(reading, isA<BssLoadUnavailable>());
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.ciscoQbssVersion1);
      expect(out.valueLength, 4);
      expect(reading.valueOrNull, isNull);
    });

    test('the vendor variant is distinct from a generic length error', () {
      final BssLoadUnavailable vendor =
          decodeBssLoad(_ie(11, <int>[1, 2, 3, 4])) as BssLoadUnavailable;
      final BssLoadUnavailable bad =
          decodeBssLoad(_ie(11, <int>[1, 2, 3])) as BssLoadUnavailable;
      expect(vendor.reason, isNot(bad.reason));
    });

    test('a standard element later in the blob wins over the vendor variant',
        () {
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ie(11, <int>[0x17, 0x00, 0x78, 0x20]), // Cisco v1, refused
        ..._bssLoadIe(
          stationCount: 9,
          channelUtilization: 200,
          admissionCapacity: 1234,
        ),
      ]);
      expect(_decoded(reading).stationCount, 9);
    });
  });

  group('a clipped element 11 is NOT absent', () {
    // The failure this group exists to prevent: our capture is cut through the
    // middle of element 11, and the app tells the engineer "this AP does not
    // advertise BSS Load" about an AP that plainly does. That is the app blaming
    // the Wi-Fi for a defect in our own byte handling. The element's ID and
    // length octets are physically in the buffer; only the value is short.

    test('a clipped element 11 reports truncated, with declared AND available',
        () {
      // 11, 5 -> element 11 declaring five value octets. Two follow.
      final BssLoadReading reading = decodeBssLoad(<int>[11, 5, 0x01, 0x00]);
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.truncated);
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.absent),
        reason: 'the header IS in the blob; absent would be a false statement',
      );
      expect(out.valueLength, 5, reason: 'what the element declared');
      expect(out.availableLength, 2, reason: 'what actually arrived');
      expect(reading.valueOrNull, isNull, reason: 'still never a padded zero');
      expect(reading.isDecoded, isFalse);
    });

    test('a clipped element 11 is found after preceding elements', () {
      // The SSID consumes 10 octets first, so the tail offset is not zero.
      final List<int> blob = <int>[
        ..._ssidIe('WLANPros'),
        11, 5, 0x2A, 0x01, // declares 5, only 2 follow
      ];
      final BssLoadUnavailable out = decodeBssLoad(blob) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.truncated);
      expect(out.valueLength, 5);
      expect(out.availableLength, 2);
    });

    test('an element 11 header with NO value octets is truncated, not absent',
        () {
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[11, 5]) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.truncated);
      expect(out.valueLength, 5);
      expect(
        out.availableLength,
        0,
        reason: 'zero octets arrived, which is not the same as no element',
      );
    });

    test('a clipped element that is NOT element 11 is not a truncated 11', () {
      // DS Parameter Set declaring 4 octets with 1 present. Something was cut
      // off, but it was not element 11, and claiming otherwise would be the
      // mirror-image over-claim. It is not `absent` either — see the
      // 'a clip landing BEFORE element 11' group for why.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        3, 4, 0x24,
      ]);
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, isNot(BssLoadUnavailableReason.truncated));
      expect(out.valueLength, isNull, reason: 'no element 11 was seen');
    });

    test('a 0x0B byte inside another element does not invent an element 11',
        () {
      // The SSID's VALUE contains 0x0B at index 3, and the blob ends with a
      // clipped DS Parameter Set. A decoder that searched the bytes for 0x0B
      // instead of using the walker's own stopping point would report a
      // truncated element 11 that does not exist.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ie(0, <int>[0x57, 0x0B, 0x69]),
        3, 4, 0x24, // clipped, and not element 11
      ]);
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.truncated),
        reason: '0x0B here is a value octet, not an element ID',
      );
      expect(out.valueLength, isNull);
      expect(out.availableLength, isNull);
    });

    test('a good element 11 wins over a clipped one later in the blob', () {
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._bssLoadIe(
          stationCount: 9,
          channelUtilization: 200,
          admissionCapacity: 1234,
        ),
        11, 5, 0x01, 0x00, // clipped element 11 at the tail
      ]);
      expect(_decoded(reading).stationCount, 9);
    });

    test('a complete-but-bad element 11 outranks a clipped one at the tail', () {
      // Precedence: the first element 11 SEEN is the diagnosis, and a complete
      // element always precedes the clipped tail.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ie(11, <int>[0x01, 0x02, 0x03]), // complete, malformed length 3
        11, 5, 0x01, 0x00, // clipped element 11 at the tail
      ]);
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.valueLength, 3);
      expect(out.availableLength, isNull, reason: 'that element was complete');
    });

    test('truncated readings differ by declared and by available length', () {
      const BssLoadUnavailable a = BssLoadUnavailable(
        BssLoadUnavailableReason.truncated,
        valueLength: 5,
        availableLength: 2,
      );
      expect(
        a,
        const BssLoadUnavailable(
          BssLoadUnavailableReason.truncated,
          valueLength: 5,
          availableLength: 2,
        ),
      );
      expect(
        a,
        isNot(const BssLoadUnavailable(
          BssLoadUnavailableReason.truncated,
          valueLength: 5,
          availableLength: 3,
        )),
        reason: 'available length is part of the value',
      );
      expect(
        a,
        isNot(const BssLoadUnavailable(
          BssLoadUnavailableReason.truncated,
          valueLength: 5,
        )),
      );
      expect(
        a,
        isNot(const BssLoadUnavailable(BssLoadUnavailableReason.absent)),
      );
    });

    test('readings differ by DECLARED length alone, with no available length',
        () {
      // The field that is in `==` but that nothing else here separates: two
      // complete elements failing for the same reason with different declared
      // lengths are different readings. Without this, dropping `valueLength`
      // from `==` passes the whole file.
      const BssLoadUnavailable three = BssLoadUnavailable(
        BssLoadUnavailableReason.malformedLength,
        valueLength: 3,
      );
      const BssLoadUnavailable seven = BssLoadUnavailable(
        BssLoadUnavailableReason.malformedLength,
        valueLength: 7,
      );
      expect(
        three,
        isNot(seven),
        reason: 'declared length is part of the value',
      );
      expect(three, const BssLoadUnavailable(
        BssLoadUnavailableReason.malformedLength,
        valueLength: 3,
      ));
      // And through the decoder, not only through the constructor.
      expect(
        decodeBssLoad(_ie(11, <int>[1, 2, 3])),
        isNot(decodeBssLoad(_ie(11, <int>[1, 2, 3, 4, 5, 6, 7]))),
      );
    });
  });

  group('a clip landing BEFORE element 11 is not an absence', () {
    // HIGH-1 from the 2026-08-01 re-gate. The fix before this one closed the
    // case where the clipped element IS element 11. Element 11 sits well down a
    // beacon — after the SSID, the rates and the DS parameter set — so a capture
    // cut at a random offset is FAR likelier to be cut before element 11 than
    // exactly on it. Those clips were reporting `absent`, whose first documented
    // meaning is "this AP does not advertise BSS Load".

    /// The same 26-octet advertisement in real beacon order, from an AP that
    /// plainly DOES advertise BSS Load: SSID, Supported Rates, DS Parameter Set,
    /// then element 11 carrying 23 stations, utilization 120, capacity 8000.
    List<int> advertisement() => <int>[
          ..._ssidIe('WLANPros'), // 10 octets
          ..._ie(1, <int>[0x82, 0x84, 0x8B, 0x96]), // 6 octets
          ..._ie(3, <int>[36]), // 3 octets
          ..._bssLoadIe(
            stationCount: 23,
            channelUtilization: 120,
            admissionCapacity: 8000,
          ), // 7 octets
        ];

    test('the intact advertisement decodes, so the clips below are the variable',
        () {
      expect(advertisement(), hasLength(26));
      final BssLoad load = _decoded(decodeBssLoad(advertisement()));
      expect(load.stationCount, 23);
      expect(load.rawChannelUtilization, 120);
      expect(load.rawAdmissionCapacity, 8000);
    });

    test('a clip on an element BOUNDARY is the one absence we cannot detect',
        () {
      // The honest limit, pinned rather than left in a doc comment. Cut at 16 of
      // 26 — the SSID (10) plus Supported Rates (6) — and every octet still
      // belongs to a well-formed element. The buffer is byte-for-byte identical
      // to a complete blob from an AP that advertises neither a DS Parameter Set
      // nor BSS Load. No decoder can tell them apart, because the difference is
      // not in the bytes.
      //
      // This reads `absent`, and that is the limit's shape: the platform layer
      // that capped the buffer is the only thing that knows, and it owes the
      // decoder that fact. Do not "fix" this by weakening `absent` everywhere —
      // that would make the reading useless for the APs that genuinely do not
      // advertise BSS Load, which is most of them.
      final List<int> onBoundary = advertisement().sublist(0, 16);
      expect(informationElementWalkTail(onBoundary).isComplete, isTrue);
      expect(
        (decodeBssLoad(onBoundary) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
      );
    });

    test('ONE advertisement, three clip offsets, and not one says absent', () {
      // The worked example. Only the first offset was covered by the previous
      // fix; the other two are the ones a real clip is likelier to produce,
      // because element 11 is the LAST of the four elements here.
      for (final int cut in <int>[23, 17, 15]) {
        final BssLoadUnavailable out =
            decodeBssLoad(advertisement().sublist(0, cut))
                as BssLoadUnavailable;
        expect(
          out.reason,
          isNot(BssLoadUnavailableReason.absent),
          reason: 'clipped to $cut of 26 — the AP advertises BSS Load, and '
              'absent would say it does not',
        );
      }
    });

    test('a clip inside element 11 still reports truncated with both counts',
        () {
      // The case the previous fix closed. It must stay closed.
      final BssLoadUnavailable out =
          decodeBssLoad(advertisement().sublist(0, 23)) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.truncated);
      expect(out.valueLength, 5);
      expect(out.availableLength, 2);
    });

    test('a clip inside an EARLIER element reports the clip, not an absence',
        () {
      // Cut at 15 of 26: inside the Supported Rates value, so the walk stops
      // there and element 11 is beyond the cut entirely.
      final BssLoadUnavailable out =
          decodeBssLoad(advertisement().sublist(0, 15)) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.clippedWithoutSeeingElement11);
      expect(out.valueLength, isNull, reason: 'no element 11 was seen');
      expect(out.availableLength, isNull);
    });

    test('a clip landing exactly on a header octet reports the clip', () {
      // Cut at 17 of 26: the DS Parameter Set's id octet arrived and its length
      // octet did not. One dangling octet declares nothing, but it is still
      // evidence the buffer was cut.
      final BssLoadUnavailable out =
          decodeBssLoad(advertisement().sublist(0, 17)) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.clippedWithoutSeeingElement11);
      expect(out.valueLength, isNull);
    });

    test('a lone trailing 0x0B reports the clip, and never a truncated 11', () {
      // The documented edge, re-derived rather than re-asserted. A TLV header is
      // two octets, so with one octet left nothing was DECLARED and `truncated`
      // — which owes a declared length — cannot be populated. But the buffer did
      // end mid-header, so `absent` is a claim the bytes do not support either.
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[..._ssidIe('WLANPros'), 11])
              as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.clippedWithoutSeeingElement11);
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.truncated),
        reason: 'one octet declared no length; truncated could not be filled in',
      );
      expect(out.valueLength, isNull);
      expect(out.availableLength, isNull);
    });

    test('a clipped capture and a clean blob are DIFFERENT objects', () {
      // The part a caller cannot recover from. Two readings that compare equal
      // cannot be told apart downstream however much the caller wants to.
      final BssLoadReading clipped = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        3, 4, 0x24, // clipped DS Parameter Set, no element 11 anywhere
      ]);
      final BssLoadReading clean = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        ..._ie(3, <int>[36]), // complete, and genuinely no element 11
      ]);

      expect((clean as BssLoadUnavailable).reason,
          BssLoadUnavailableReason.absent);
      expect((clipped as BssLoadUnavailable).reason,
          BssLoadUnavailableReason.clippedWithoutSeeingElement11);
      expect(clipped, isNot(clean));
      expect(clipped.hashCode, isNot(clean.hashCode));
    });

    test('absent is earned only by a blob walked to its END', () {
      // The narrowed meaning. Every octet accounted for, no element 11 in any of
      // them: now, and only now, is "this AP does not advertise BSS Load" a
      // statement about the AP.
      final List<int> blob = <int>[
        ..._ssidIe('WLANPros'),
        ..._ie(3, <int>[36]),
        ..._ie(48, <int>[0x01, 0x00]),
      ];
      expect(informationElementWalkTail(blob).isComplete, isTrue);
      expect(
        (decodeBssLoad(blob) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
      );
    });

    test('an empty blob is not a clip either — nothing was cut, and nothing read',
        () {
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[]) as BssLoadUnavailable;
      expect(
        out.reason,
        BssLoadUnavailableReason.noInformationElementsProvided,
      );
      expect(out.reason,
          isNot(BssLoadUnavailableReason.clippedWithoutSeeingElement11));
      expect(out.reason, isNot(BssLoadUnavailableReason.absent));
    });

    test('a decoded element 11 wins even when the blob is clipped after it', () {
      // Precedence is unchanged: a reading we actually have beats any diagnosis.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._bssLoadIe(
          stationCount: 9,
          channelUtilization: 200,
          admissionCapacity: 1234,
        ),
        3, 9, 0x24, // clipped DS Parameter Set at the tail
      ]);
      expect(_decoded(reading).stationCount, 9);
    });

    test('a complete BAD element 11 outranks a clip elsewhere in the blob', () {
      // The "first element 11 seen is the diagnosis" contract, against the new
      // reason: a real element 11 we examined beats "we could not tell".
      final BssLoadUnavailable out = decodeBssLoad(<int>[
        ..._ie(11, <int>[0x01, 0x02, 0x03]),
        3, 9, 0x24, // clipped, not element 11
      ]) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.valueLength, 3);
    });

    test('a complete element 11 outranks a CLIPPED ELEMENT 11 at the tail', () {
      // The EXAMINED rule, on the one blob that can tell it apart from
      // CLIPPED-11 (both named in decodeBssLoad's precedence list):
      // both candidates are element 11, so a decoder that let the tail win would
      // report the clipped one and every other test in this file would still
      // pass. The complete element precedes the clipped tail by construction, so
      // "the FIRST element 11 seen is the diagnosis" picks it.
      final BssLoadUnavailable out = decodeBssLoad(<int>[
        ..._ie(11, <int>[1, 2, 3]), // complete, malformedLength, declared 3
        11, 5, 0x01, // clipped element 11, declares 5, one octet arrives
      ]) as BssLoadUnavailable;

      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.valueLength, 3, reason: 'the COMPLETE element 11 declared 3');
      expect(out.availableLength, isNull, reason: 'that element was whole');
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.truncated),
        reason: 'truncated would be the tail winning',
      );
    });
  });

  group('a platform that handed us nothing is not an AP that advertised nothing',
      () {
    // HIGH-1 from the 2026-08-01 round-3 re-gate. `absent` was documented in one
    // place as a statement about the AP and in two others as the right answer
    // when the platform gave us no bytes at all, and the enum had no member for
    // the second. It is much wider than the iOS note suggested: `ApIeBlob.
    // ieBytes` is a `Uint8List?` that is null on every non-macOS platform (no
    // channel is wired) and on macOS whenever Location is unauthorized, Wi-Fi is
    // off, or no scanned BSS matches the connected BSSID.
    //
    // The fix is not a doc: it is that BOTH spellings a caller would naturally
    // write — passing the null through, or `?? const []` — now produce the
    // honest answer. There is no way to reach `absent` from an empty hand.

    test('a NULL blob reports the platform, never the AP', () {
      final BssLoadUnavailable out =
          decodeBssLoad(null) as BssLoadUnavailable;
      expect(
        out.reason,
        BssLoadUnavailableReason.noInformationElementsProvided,
      );
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.absent),
        reason: 'a device that cannot see IEs knows nothing about this AP',
      );
      expect(out.valueLength, isNull);
      expect(out.availableLength, isNull);
    });

    test('the `?? const []` spelling of the same call agrees with it', () {
      // The trap this member exists to close. A caller with a nullable blob and
      // a non-nullable parameter writes exactly this, and it used to read
      // `absent`.
      const List<int>? fromPlatform = null;
      expect(
        decodeBssLoad(fromPlatform ?? const <int>[]),
        decodeBssLoad(fromPlatform),
        reason: 'both spellings of "we got nothing" must say the same thing',
      );
    });

    test('nothing-provided and absent are DIFFERENT readings, not two names',
        () {
      // Value equality, so a caller cannot collapse them downstream even by
      // accident — the same property `BssLoadUnavailable`'s `==` earned last
      // round.
      final BssLoadReading nothing = decodeBssLoad(null);
      final BssLoadReading absent = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        ..._ie(3, <int>[36]),
      ]);
      expect((absent as BssLoadUnavailable).reason,
          BssLoadUnavailableReason.absent);
      expect(nothing, isNot(absent));
      expect(nothing.hashCode, isNot(absent.hashCode));
    });

    test('a blob that DID carry elements still earns absent', () {
      // The other direction, and the one that stops the fix over-reaching: a
      // decoder that answered `noInformationElementsProvided` for every
      // no-element-11 blob would pass every test above and destroy the only
      // reading that says anything about the AP.
      final List<int> blob = <int>[
        ..._ssidIe('WLANPros'),
        ..._ie(1, <int>[0x82, 0x84]),
        ..._ie(48, <int>[0x01, 0x00]),
      ];
      expect(informationElementWalkTail(blob).isComplete, isTrue);
      expect(
        (decodeBssLoad(blob) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
      );
    });

    test('a single zero-length element is enough to earn absent', () {
      // The boundary between "we were handed no elements" and "we were handed
      // elements, none of them element 11". One legal zero-length element 0 is
      // two octets of real advertisement, so the walk yields something and the
      // AP-facing reading is earned.
      final List<int> blob = _ie(0, <int>[]);
      expect(blob, hasLength(2));
      expect(walkInformationElements(blob).length, 1);
      expect(
        (decodeBssLoad(blob) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
      );
    });

    test('a clip still outranks nothing-provided, because a clip saw octets',
        () {
      // A blob that is nothing BUT a clipped element yields no elements at all,
      // so the "saw no elements" test alone would call it nothing-provided. It
      // is not: octets arrived and were cut. Order matters, and this pins it.
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[3, 9, 0x24]) as BssLoadUnavailable;
      expect(walkInformationElements(<int>[3, 9, 0x24]), isEmpty,
          reason: 'no element survives the bounds check');
      expect(
        out.reason,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
      );
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.noInformationElementsProvided),
        reason: 'bytes did arrive; they were cut',
      );
    });

    test('a lone dangling octet is a clip, not nothing-provided', () {
      // The one-octet residue: no element yielded, nothing declared, but a byte
      // arrived. Same ordering question as above, reached a different way.
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[11]) as BssLoadUnavailable;
      expect(
        out.reason,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
      );
      expect(out.reason,
          isNot(BssLoadUnavailableReason.noInformationElementsProvided));
    });

    test('decodeBssLoadFromElements decides it the same way, in one place', () {
      // Both entry points route through the same decision, so they cannot drift.
      expect(
        (decodeBssLoadFromElements(
          const <InformationElement>[],
          blobWalkedToEnd: true,
        ) as BssLoadUnavailable)
            .reason,
        BssLoadUnavailableReason.noInformationElementsProvided,
      );
      expect(
        (decodeBssLoadFromElements(
          const <InformationElement>[],
          blobWalkedToEnd: false,
        ) as BssLoadUnavailable)
            .reason,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
        reason: 'a caller that does not know must not get an AP-facing answer',
      );
    });

    test('null never throws, and is not decoded', () {
      expect(() => decodeBssLoad(null), returnsNormally);
      expect(() => decodeBssLoadOrNull(null), returnsNormally);
      expect(decodeBssLoad(null).isDecoded, isFalse);
      expect(decodeBssLoad(null).valueOrNull, isNull);
    });
  });

  group('the 4..5 length rule holds on the CLIPPED path too', () {
    // A clipped header declaring a length element 11 cannot have is disqualified
    // by its header alone. `truncated` says "the capture was clipped; the AP's
    // advertisement was not", which for a declared 255 would assert a
    // well-formed 255-octet element 11 that the cited rule says cannot exist
    // (packet-ieee80211.c:32228).

    test('a clipped header declaring an impossible length is malformed', () {
      // One value octet arrives, so any declared length above 1 overruns.
      for (final int declared in <int>[2, 3, 6, 7, 200, 255]) {
        final BssLoadUnavailable out =
            decodeBssLoad(<int>[..._ssidIe('X'), 11, declared, 0x01])
                as BssLoadUnavailable;
        expect(
          out.reason,
          BssLoadUnavailableReason.malformedLength,
          reason: 'declared $declared is outside 4..5',
        );
        expect(out.valueLength, declared, reason: 'what the header claimed');
        expect(out.availableLength, 1, reason: 'what arrived');
      }
    });

    test('declared 1 with nothing following is a clipped malformed header', () {
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[11, 1]) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.valueLength, 1);
      expect(out.availableLength, 0);
    });

    test('declared 0 can never be clipped — zero octets always fit', () {
      // The boundary of the clipped path itself: `[11, 0]` is a COMPLETE
      // element 11 with an empty value, so it is diagnosed on the ordinary path
      // and carries no available count.
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[11, 0]) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(out.valueLength, 0);
      expect(out.availableLength, isNull, reason: 'nothing was cut');
    });

    test('on the clipped path, availableLength is always BELOW valueLength', () {
      // The invariant that makes the two fields readable together: a clipped
      // element by definition did not receive everything it declared.
      for (final int declared in <int>[2, 4, 5, 9, 255]) {
        for (final int available in <int>[0, 1]) {
          if (available >= declared) continue;
          final BssLoadUnavailable out = decodeBssLoad(<int>[
            11,
            declared,
            ...List<int>.filled(available, 0x01),
          ]) as BssLoadUnavailable;
          expect(out.availableLength, available);
          expect(out.availableLength!, lessThan(out.valueLength!));
        }
      }
    });

    test('a clipped header declaring 4 or 5 is truncated, not malformed', () {
      for (final int declared in <int>[4, 5]) {
        final BssLoadUnavailable out =
            decodeBssLoad(<int>[..._ssidIe('X'), 11, declared, 0x01])
                as BssLoadUnavailable;
        expect(
          out.reason,
          BssLoadUnavailableReason.truncated,
          reason: 'declared $declared is a length element 11 may have',
        );
        expect(out.valueLength, declared);
        expect(out.availableLength, 1);
      }
    });

    test('a clipped 4-octet header keeps its declared length for the caller', () {
      // It is NOT reported as ciscoQbssVersion1: those four value octets never
      // arrived, so naming the vendor variant would assert an element we did not
      // see. The declared 4 is preserved so a readout can still say it.
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[11, 4, 0x17]) as BssLoadUnavailable;
      expect(out.reason, isNot(BssLoadUnavailableReason.ciscoQbssVersion1));
      expect(out.reason, BssLoadUnavailableReason.truncated);
      expect(out.valueLength, kBssLoadCiscoV1ValueLength);
    });

    test('the same declared length reads differently complete versus clipped',
        () {
      // Both are malformedLength with valueLength 7; availableLength is what
      // separates "the AP advertised a 7-octet element 11" from "a header
      // claiming 7 octets was cut short".
      final BssLoadUnavailable complete = decodeBssLoad(
        _ie(11, <int>[1, 2, 3, 4, 5, 6, 7]),
      ) as BssLoadUnavailable;
      final BssLoadUnavailable clipped =
          decodeBssLoad(<int>[11, 7, 1, 2, 3]) as BssLoadUnavailable;

      expect(complete.reason, BssLoadUnavailableReason.malformedLength);
      expect(clipped.reason, BssLoadUnavailableReason.malformedLength);
      expect(complete.valueLength, 7);
      expect(clipped.valueLength, 7);
      expect(complete.availableLength, isNull, reason: 'all 7 octets arrived');
      expect(clipped.availableLength, 3, reason: 'only 3 arrived');
      expect(complete, isNot(clipped));
    });

    test('an element 11 header with NO value octets keeps its declared length',
        () {
      // Declared 5, nothing after: truncated with availableLength 0. Zero octets
      // arrived, which is not the same as no element.
      final BssLoadUnavailable out =
          decodeBssLoad(<int>[11, 5]) as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.truncated);
      expect(out.valueLength, 5);
      expect(out.availableLength, 0);

      // Declared 255, nothing after: malformed, and it still reports 0 arrived.
      final BssLoadUnavailable bad =
          decodeBssLoad(<int>[11, 255]) as BssLoadUnavailable;
      expect(bad.reason, BssLoadUnavailableReason.malformedLength);
      expect(bad.valueLength, 255);
      expect(bad.availableLength, 0);
    });
  });

  group('decodeBssLoadFromElements must be TOLD whether the blob was whole', () {
    // The "callers holding the raw bytes must prefer decodeBssLoad" rule used to
    // be a doc comment with no mechanism, and this entry point structurally
    // cannot see a clip: the walker drops the clipped element before it sees
    // anything. The question is now a required argument, so the first caller
    // cannot inherit a false `absent` by omission — the compiler asks.

    test('told the blob was whole, no element 11 is absent', () {
      final BssLoadReading reading = decodeBssLoadFromElements(
        walkInformationElements(<int>[..._ssidIe('WLANPros')]),
        blobWalkedToEnd: true,
      );
      expect((reading as BssLoadUnavailable).reason,
          BssLoadUnavailableReason.absent);
    });

    test('told the blob was cut, no element 11 is a clip, never an absence', () {
      final BssLoadReading reading = decodeBssLoadFromElements(
        walkInformationElements(<int>[11, 5, 0x01, 0x00]),
        blobWalkedToEnd: false,
      );
      expect((reading as BssLoadUnavailable).reason,
          BssLoadUnavailableReason.clippedWithoutSeeingElement11);
    });

    test('it still cannot report truncated, and does not pretend to', () {
      // The honest limit, unchanged: pre-parsed elements are the elements that
      // SURVIVED a bounds check, so the clipped one is already gone. The best
      // this entry point can say is "something was cut".
      final BssLoadReading reading = decodeBssLoadFromElements(
        walkInformationElements(<int>[11, 5, 0x01, 0x00]),
        blobWalkedToEnd: false,
      );
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, isNot(BssLoadUnavailableReason.truncated));
      expect(out.valueLength, isNull);
    });

    test('a real element 11 outranks the flag in both directions', () {
      // The flag only decides the no-element-11 case; it must not colour a
      // diagnosis we actually made.
      for (final bool whole in <bool>[true, false]) {
        final BssLoadReading bad = decodeBssLoadFromElements(
          walkInformationElements(_ie(11, <int>[1, 2, 3])),
          blobWalkedToEnd: whole,
        );
        expect((bad as BssLoadUnavailable).reason,
            BssLoadUnavailableReason.malformedLength);

        final BssLoadReading good = decodeBssLoadFromElements(
          walkInformationElements(_bssLoadIe(
            stationCount: 6,
            channelUtilization: 7,
            admissionCapacity: 8,
          )),
          blobWalkedToEnd: whole,
        );
        expect(_decoded(good).stationCount, 6);
      }
    });
  });

  group('isDecoded separates a reading from a non-reading, BOTH directions',
      () {
    // The predicate the whole sealed design is queried through. Every other
    // assertion on it in this file runs in the TRUE direction, which means a
    // body of `=> true` would satisfy all of them. Both directions are asserted
    // here so neither constant survives.

    test('isDecoded is TRUE only for a decoded reading', () {
      expect(
        decodeBssLoad(
          _bssLoadIe(
            stationCount: 4,
            channelUtilization: 7,
            admissionCapacity: 11,
          ),
        ).isDecoded,
        isTrue,
      );
      expect(
        decodeBssLoad(
          _bssLoadIe(
            stationCount: 0,
            channelUtilization: 0,
            admissionCapacity: 0,
          ),
        ).isDecoded,
        isTrue,
        reason: 'an all-zero reading is still a reading',
      );
    });

    test('isDecoded is FALSE for every not-a-reading case', () {
      expect(
        decodeBssLoad(_ssidIe('WLANPros')).isDecoded,
        isFalse,
        reason: 'absent',
      );
      expect(decodeBssLoad(<int>[]).isDecoded, isFalse, reason: 'empty blob');
      expect(
        decodeBssLoad(_ie(11, <int>[0x01, 0x02, 0x03])).isDecoded,
        isFalse,
        reason: 'malformedLength',
      );
      expect(
        decodeBssLoad(_ie(11, <int>[0x01, 0x02, 0x03, 0x04])).isDecoded,
        isFalse,
        reason: 'ciscoQbssVersion1',
      );
      expect(
        decodeBssLoad(<int>[11, 5, 0x01, 0x00]).isDecoded,
        isFalse,
        reason: 'truncated',
      );
      expect(
        const BssLoadUnavailable(BssLoadUnavailableReason.absent).isDecoded,
        isFalse,
        reason: 'constructed directly, not via the decoder',
      );
    });
  });

  group('when no element 11 decodes, the FIRST one seen is the diagnosis', () {
    test('the first failing element 11 is reported, not a later one', () {
      // Three failing element 11s. The reported reason and length must be the
      // FIRST one's — a decoder that kept overwriting would report the Cisco
      // variant with length 4 instead.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ie(11, <int>[0x01, 0x02, 0x03]), // 1st: malformedLength, 3 octets
        ..._ie(11, <int>[]), // 2nd: malformedLength, 0 octets
        ..._ie(11, <int>[0x01, 0x02, 0x03, 0x04]), // 3rd: Cisco v1, 4 octets
      ]);
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.malformedLength);
      expect(
        out.reason,
        isNot(BssLoadUnavailableReason.ciscoQbssVersion1),
        reason: 'that is the LAST element 11, not the first',
      );
      expect(out.valueLength, 3, reason: 'the first element 11 declared 3');
    });

    test('the walk continues past a failure, so a later good element still wins',
        () {
      // The other half of the contract: "first failure remembered" must not mean
      // "stop looking". Two bad element 11s precede a good one.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ie(11, <int>[0x01, 0x02, 0x03]),
        ..._ie(11, <int>[0x01, 0x02, 0x03, 0x04]),
        ..._bssLoadIe(
          stationCount: 77,
          channelUtilization: 12,
          admissionCapacity: 3456,
        ),
      ]);
      expect(_decoded(reading).stationCount, 77);
      expect(_decoded(reading).rawAdmissionCapacity, 3456);
    });
  });

  group('never throws, on any bytes', () {
    test('a truncated tail stops the walk cleanly rather than overrunning', () {
      // Element 11 declares 5 octets but only 2 follow. The shared walker
      // refuses to yield it — correctly, that is what makes it total — and the
      // decoder must NOT therefore call it absent. Not padding with zeros and
      // not claiming the AP sent nothing are two separate obligations; see the
      // 'a clipped element 11 is NOT absent' group for the full contract.
      final BssLoadReading reading = decodeBssLoad(<int>[11, 5, 0x01, 0x00]);
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.truncated,
      );
      expect(reading.valueOrNull, isNull);
    });

    test('a single trailing byte is a clip — one octet is not a header', () {
      // Three names, three different bit patterns. `[11, 5]` IS a header with no
      // value and is TRUNCATED. A lone octet cannot be a two-octet header, so
      // nothing was declared and truncated cannot be filled in — but the buffer
      // still ended mid-header, so it is not ABSENT either.
      expect(
        (decodeBssLoad(<int>[11]) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
      );
      expect(
        (decodeBssLoad(<int>[0xFF]) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
        reason: 'the dangling octet need not be 0x0B',
      );
      expect(decodeBssLoadOrNull(<int>[0xFF]), isNull);
    });

    test('garbage, out-of-range and negative ints do not throw', () {
      final List<List<int>> garbage = <List<int>>[
        <int>[0xFF, 0xFF, 0xFF],
        <int>[11, 255],
        List<int>.filled(64, 0xAB),
        List<int>.generate(255, (int i) => i),
        <int>[11, 5, 300, -1, 128, 0x12, 0x7A], // outside byte range
      ];
      for (final List<int> bytes in garbage) {
        expect(() => decodeBssLoad(bytes), returnsNormally);
        expect(() => decodeBssLoadOrNull(bytes), returnsNormally);
      }
      expect(() => decodeBssLoadValue(<int>[]), returnsNormally);
      expect(() => decodeBssLoadValue(<int>[300, -1, 999, 0x12, 0x7A]),
          returnsNormally);
    });

    test('out-of-range ints in a value are masked to bytes, not propagated', () {
      // 300 & 0xff == 44; -1 & 0xff == 255 -> 0xFF2C = 65324.
      final BssLoad load =
          _decoded(decodeBssLoadValue(<int>[300, -1, 999, 0x12, 0x7A]));
      expect(load.stationCount, 65324);
      // The literal, not `999 & 0xff` — computing the expectation with the
      // implementation's own operation makes the test agree with a broken mask
      // by construction.
      expect(load.rawChannelUtilization, 231);
      expect(load.rawAdmissionCapacity, 31250);
    });
  });

  group('pinned constants', () {
    test('element id, lengths and scales match the documented pins', () {
      expect(kEidBssLoad, 11);
      expect(kBssLoadStandardValueLength, 5);
      expect(kBssLoadCiscoV1ValueLength, 4);
      expect(kChannelUtilizationFullScale, 255);
      expect(kAdmissionCapacityUnitMicrosecondsPerSecond, 32);
      expect(kAdmissionCapacityFullScale, 31250);
      // The derivation the header states: 31250 units x 32 us = one second.
      expect(
        kAdmissionCapacityFullScale *
            kAdmissionCapacityUnitMicrosecondsPerSecond,
        1000000,
      );
    });

    test('value equality is by field, so readings compare cleanly', () {
      const BssLoad a = BssLoad(
        stationCount: 7,
        rawChannelUtilization: 8,
        rawAdmissionCapacity: 9,
      );
      const BssLoad b = BssLoad(
        stationCount: 7,
        rawChannelUtilization: 8,
        rawAdmissionCapacity: 9,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(const BssLoadDecoded(a), const BssLoadDecoded(b));
      expect(
        const BssLoadUnavailable(BssLoadUnavailableReason.absent),
        const BssLoadUnavailable(BssLoadUnavailableReason.absent),
      );
      expect(
        const BssLoadUnavailable(BssLoadUnavailableReason.absent),
        isNot(const BssLoadUnavailable(
          BssLoadUnavailableReason.malformedLength,
        )),
      );
    });
  });
}
