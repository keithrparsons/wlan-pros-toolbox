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
//   3. The three states stay apart: ABSENT, UNAVAILABLE (bad length / Cisco
//      variant), and a genuine ALL-ZERO reading are three different answers.
//   4. Nothing throws, ever, on any byte sequence.
//
// Layout and constants are pinned in the decoder's header to Wireshark's
// dissector at commit b1f51ff4 — read that before changing a number here.
//
// Build: Felix 2026-07-31.

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

  group('absent, malformed and zero are three different answers', () {
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

    test('an empty blob is absent', () {
      final BssLoadReading reading = decodeBssLoad(<int>[]);
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
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

    test('decodeBssLoadOrNull returns null for absent AND for malformed', () {
      expect(decodeBssLoadOrNull(_ssidIe('WLANPros')), isNull);
      expect(decodeBssLoadOrNull(_ie(11, <int>[0x01, 0x02, 0x03])), isNull);
      expect(decodeBssLoadOrNull(<int>[]), isNull);
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

    test('a clipped element that is NOT element 11 stays absent', () {
      // DS Parameter Set declaring 4 octets with 1 present. Something was cut
      // off, but it was not element 11, and claiming otherwise would be the
      // mirror-image over-claim.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        3, 4, 0x24,
      ]);
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
      );
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
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
        reason: '0x0B here is a value octet, not an element ID',
      );
    });

    test('a lone trailing 0x0B is absent — one octet is not a header', () {
      // Documented edge: a TLV header is two octets, so a single trailing byte
      // is indistinguishable from tail garbage. Asserting a truncated element 11
      // here would claim an element we cannot see.
      final BssLoadReading reading = decodeBssLoad(<int>[
        ..._ssidIe('WLANPros'),
        11,
      ]);
      final BssLoadUnavailable out = reading as BssLoadUnavailable;
      expect(out.reason, BssLoadUnavailableReason.absent);
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

    test('decodeBssLoadFromElements cannot see the clip, and says absent', () {
      // Honest limit, asserted rather than left to a doc comment: the walker
      // drops the clipped element before this entry point sees anything.
      final BssLoadReading reading = decodeBssLoadFromElements(
        walkInformationElements(<int>[11, 5, 0x01, 0x00]),
      );
      expect(
        (reading as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
      );
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
  });

  group('isDecoded answers the three-state question in BOTH directions', () {
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

    test('a single trailing byte is absent — one octet is not a header', () {
      // The name matters: `[11, 5]` IS a header with no value and is TRUNCATED,
      // not absent. Only a lone octet, which cannot be a two-octet header, is
      // absent. See the 'a clipped element 11 is NOT absent' group.
      expect(
        (decodeBssLoad(<int>[11]) as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.absent,
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
