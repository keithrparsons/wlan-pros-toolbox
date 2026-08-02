// The rendered contract for `bss_load_decoder.dart`, pinned.
//
// THE EXPECTED VALUES IN THIS FILE WERE WRITTEN BEFORE THE CODE THEY CHECK
// ([[feedback_state_the_expected_value_first]]). The table in `_kExpected` is
// the specification; the presentation layer was written to satisfy it. Reading
// it the other way round is how a test stops being able to fail.
//
// WHAT EACH GROUP IS FOR, because "we have tests" is not coverage
// ([[feedback_red_green_is_not_coverage]]):
//
//   * COVERAGE FLOOR — the table is walked against
//     `BssLoadUnavailableReason.values`, so ADDING a member to the decoder fails
//     this file until somebody decides what it says. A hand-written table that
//     nothing forces to stay complete quietly becomes a claim about a smaller
//     set, which is the failure mode `bss_load_ordinal_reference_guard_test`
//     was rewritten three times to close.
//   * THE PIN — every attribution and every headline is a literal here. Any copy
//     edit turns this red on purpose. That is not friction; the whole value of
//     this screen is which sentence lands on which reading.
//   * THE DIRECTION RULE — the one invariant worth stating as a property rather
//     than a table: only `thisAccessPoint` copy may say an access point FAILED
//     to do something.
//
// HONEST LIMIT, so nobody overreads this file. The direction rule is a phrase
// check over a closed list of deficiency verbs. It cannot catch an arbitrary
// paraphrase of "this access point is at fault"; nothing short of a human
// reading the copy can. It catches the phrasings that are actually in the file
// and the obvious next ones. When a gate finds one it missed, add the phrase.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/bss_load_presentation.dart';
import 'package:wlan_pros_toolbox/services/network/bss_load_decoder.dart';
import 'package:wlan_pros_toolbox/services/network/ie_parser.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';

/// A rendered outcome: the reading that produces it and what it must say.
class _Expected {
  const _Expected({
    required this.name,
    required this.reading,
    required this.attribution,
    required this.headline,
    required this.octetDiagnostic,
    required this.context,
    required this.remedy,
  });

  final String name;
  final BssLoadUnavailable reading;
  final BssLoadAttribution attribution;
  final String headline;

  /// Null where no element 11 was seen and there is nothing to count.
  final String? octetDiagnostic;
  final BssLoadReadContext context;
  final BssLoadRemedy remedy;
}

const BssLoadReadContext _kNoIeContextMacosAuthorized = BssLoadReadContext(
  platformExposesInformationElements: true,
  locationAuth: LocationAuthStatus.authorized,
);

/// EIGHT rendered outcomes over SEVEN enum members. `malformedLength` renders
/// two ways because the decoder hands over the field that tells them apart:
/// `availableLength` is null when every declared octet arrived and a count when
/// the buffer ended early. A complete element with a bad length is a whole read
/// of somebody's beacon; a clipped header with a bad length is a whole read of
/// our own truncated buffer. Different attributions, so different sentences.
final List<_Expected> _kExpected = <_Expected>[
  const _Expected(
    name: 'absent',
    reading: BssLoadUnavailable(BssLoadUnavailableReason.absent),
    attribution: BssLoadAttribution.thisAccessPoint,
    headline: 'This access point does not advertise BSS Load.',
    octetDiagnostic: null,
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'noInformationElementsProvided',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.noInformationElementsProvided,
    ),
    attribution: BssLoadAttribution.thisRead,
    headline: 'This device gave us no information elements.',
    octetDiagnostic: null,
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'clippedWithoutSeeingElement11',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.clippedWithoutSeeingElement11,
    ),
    attribution: BssLoadAttribution.thisRead,
    headline:
        'Our capture was cut short before we reached a BSS Load element.',
    octetDiagnostic: null,
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'blobCompletenessNotStated',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.blobCompletenessNotStated,
    ),
    attribution: BssLoadAttribution.whatWeWereTold,
    headline: 'We were not told whether the capture was whole.',
    octetDiagnostic: null,
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'truncated',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.truncated,
      valueLength: 5,
      availableLength: 2,
    ),
    attribution: BssLoadAttribution.thisRead,
    headline: 'Our capture cut a BSS Load element short.',
    octetDiagnostic:
        'Element 11 declared 5 value octets, and 2 octets arrived before the '
        'buffer ended.',
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'ciscoQbssVersion1',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.ciscoQbssVersion1,
      valueLength: 4,
    ),
    attribution: BssLoadAttribution.thisRead,
    headline: 'This build does not decode the Cisco QBSS variant.',
    octetDiagnostic:
        'Element 11 declared 4 value octets, and all of them arrived.',
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'malformedLength, complete element',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.malformedLength,
      valueLength: 7,
    ),
    attribution: BssLoadAttribution.thisAccessPoint,
    headline:
        'This access point sent a BSS Load element with a length it cannot '
        'have.',
    octetDiagnostic:
        'Element 11 declared 7 value octets, and all of them arrived.',
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
  const _Expected(
    name: 'malformedLength, clipped header',
    reading: BssLoadUnavailable(
      BssLoadUnavailableReason.malformedLength,
      valueLength: 200,
      availableLength: 3,
    ),
    attribution: BssLoadAttribution.thisRead,
    headline: 'Our capture cut short an element we would have refused.',
    octetDiagnostic:
        'Element 11 declared 200 value octets, and 3 octets arrived before the '
        'buffer ended.',
    context: _kNoIeContextMacosAuthorized,
    remedy: BssLoadRemedy.none,
  ),
];

/// Phrasings that assert an access point FAILED to do something.
///
/// A positive credit is deliberately absent from this list: `truncated` says
/// "This access point did advertise element 11" under `thisRead` and must keep
/// saying it. Being wrong in that direction costs nobody their reputation.
const List<String> _kDeficiencyPhrases = <String>[
  'does not advertise',
  'did not advertise',
  'advertised nothing',
  'sent no',
  'stayed silent',
  'a length it cannot have',
];

void main() {
  group('coverage floor', () {
    test('every BssLoadUnavailableReason has a rendered outcome', () {
      // WALKED AGAINST THE ENUM, not against the table, so a member added to the
      // decoder fails here instead of silently inheriting somebody else's
      // sentence.
      final Set<BssLoadUnavailableReason> covered = _kExpected
          .map((_Expected e) => e.reading.reason)
          .toSet();
      expect(
        covered,
        BssLoadUnavailableReason.values.toSet(),
        reason:
            'a decoder reason has no rendered outcome. Decide what the screen '
            'says about it; do not let it fall into another headline.',
      );
    });

    test('the table renders more outcomes than there are reasons', () {
      // The floor that makes the split real. If somebody collapses
      // malformedLength back into one sentence, this fails rather than quietly
      // becoming a claim about a shorter list.
      expect(
        _kExpected.length,
        greaterThan(BssLoadUnavailableReason.values.length),
        reason:
            'malformedLength must render two ways, split on availableLength',
      );
    });
  });

  group('the pinned table', () {
    for (final _Expected e in _kExpected) {
      test('${e.name}: attribution, headline, octet diagnostic', () {
        final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
          e.reading,
          context: e.context,
        );
        expect(copy.attribution, e.attribution, reason: e.name);
        expect(copy.headline, e.headline, reason: e.name);
        expect(copy.octetDiagnostic, e.octetDiagnostic, reason: e.name);
        expect(copy.remedy, e.remedy, reason: e.name);
        expect(copy.body, isNotEmpty, reason: e.name);
      });
    }

    test('every headline is distinct', () {
      final List<String> headlines = _kExpected
          .map(
            (_Expected e) =>
                bssLoadUnavailableCopy(e.reading, context: e.context).headline,
          )
          .toList();
      expect(
        headlines.toSet().length,
        headlines.length,
        reason:
            'two readings render the same sentence, which is the collapse this '
            'screen exists to refuse',
      );
    });

    test('all three attributions are in live use', () {
      final Set<BssLoadAttribution> used = _kExpected
          .map(
            (_Expected e) => bssLoadUnavailableCopy(
              e.reading,
              context: e.context,
            ).attribution,
          )
          .toSet();
      expect(used, BssLoadAttribution.values.toSet());
    });

    test('every attribution label is a distinct, non-empty word', () {
      final List<String> labels = BssLoadAttribution.values
          .map((BssLoadAttribution a) => a.label)
          .toList();
      expect(labels.toSet().length, labels.length);
      for (final String l in labels) {
        expect(l.trim(), isNotEmpty);
      }
    });
  });

  group('the direction rule', () {
    // The single invariant stated as a property rather than a table: a
    // deficiency claim about somebody's access point is earned only by a read
    // that was whole ([[feedback_app_blames_the_wifi]]).
    for (final _Expected e in _kExpected) {
      test('${e.name}: no deficiency claim outside thisAccessPoint', () {
        final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
          e.reading,
          context: e.context,
        );
        if (copy.attribution == BssLoadAttribution.thisAccessPoint) return;
        final String prose = '${copy.headline} ${copy.body}'.toLowerCase();
        for (final String phrase in _kDeficiencyPhrases) {
          expect(
            prose.contains(phrase),
            isFalse,
            reason:
                '${e.name} is attributed to ${copy.attribution.name} and blames '
                'the access point with "$phrase". Our own blind spot is never '
                'evidence about somebody else\'s network.',
          );
        }
      });
    }

    test('the phrase list can actually fire', () {
      // A guard nothing has ever demonstrated firing is a guard that might be
      // scanning nothing. `absent` is the live site: it carries a deficiency
      // phrase legitimately, under the one attribution allowed to.
      final BssLoadUnavailableCopy absent = bssLoadUnavailableCopy(
        const BssLoadUnavailable(BssLoadUnavailableReason.absent),
        context: _kNoIeContextMacosAuthorized,
      );
      expect(absent.attribution, BssLoadAttribution.thisAccessPoint);
      expect(
        _kDeficiencyPhrases.any(
          (String p) => absent.headline.toLowerCase().contains(p),
        ),
        isTrue,
        reason:
            'no live copy matches any deficiency phrase, so the loop above '
            'proves nothing',
      );
    });
  });

  group('noInformationElementsProvided reads four ways', () {
    // ONE decoder reason, FOUR true sentences, because the screen holds bits the
    // decoder never sees. Rendering one flat wall while holding them is
    // [[feedback_ui_rendered_a_decision_it_lacked]].
    const BssLoadUnavailable reading = BssLoadUnavailable(
      BssLoadUnavailableReason.noInformationElementsProvided,
    );

    BssLoadUnavailableCopy render(BssLoadReadContext c) =>
        bssLoadUnavailableCopy(reading, context: c);

    test('a platform that exposes no information elements names the platform',
        () {
      final BssLoadUnavailableCopy copy = render(
        const BssLoadReadContext(
          platformExposesInformationElements: false,
          locationAuth: null,
        ),
      );
      expect(copy.body, contains('macOS is the only platform'));
      expect(copy.body, contains('iOS exposes none'));
      expect(copy.remedy, BssLoadRemedy.none);
      // It must NOT reach for Location on a platform where Location gates
      // nothing.
      expect(copy.body.toLowerCase(), isNot(contains('location')));
    });

    test('macOS with the grant unread names no cause and offers no remedy', () {
      final BssLoadUnavailableCopy copy = render(
        const BssLoadReadContext(
          platformExposesInformationElements: true,
          locationAuth: null,
        ),
      );
      expect(copy.body, contains('did not read the Location authorization'));
      expect(copy.body, contains('names no cause'));
      expect(
        copy.remedy,
        BssLoadRemedy.none,
        reason:
            'a screen that did not read the grant may not tell the user the '
            'grant is the problem',
      );
    });

    test('macOS notDetermined is promptable', () {
      final BssLoadUnavailableCopy copy = render(
        const BssLoadReadContext(
          platformExposesInformationElements: true,
          locationAuth: LocationAuthStatus.notDetermined,
        ),
      );
      expect(copy.body, contains('withholds beacon information elements'));
      expect(copy.remedy, BssLoadRemedy.requestLocationPermission);
    });

    for (final LocationAuthStatus blocked in <LocationAuthStatus>[
      LocationAuthStatus.denied,
      LocationAuthStatus.restricted,
    ]) {
      test('macOS ${blocked.name} deep-links settings, never a dead prompt', () {
        // THE STATE NOBODY NAMES. Cited by NAME rather than by position:
        // [[feedback_ui_rendered_a_decision_it_lacked]] carries a numbered
        // family whose own header records that the numbering already drifted
        // once and had to be reconciled against the commits, so an ordinal into
        // it is a citation that can go stale in silence. The case here is the
        // AP SCAN GRANT-LOCATION one, where the screen read a boolean while the
        // platform exposes a tri-state: macOS raises no prompt after a denial,
        // so a Grant button in that state is a control guaranteed to do
        // nothing.
        final BssLoadUnavailableCopy copy = render(
          BssLoadReadContext(
            platformExposesInformationElements: true,
            locationAuth: blocked,
          ),
        );
        expect(copy.remedy, BssLoadRemedy.openLocationSettings);
        expect(copy.remedy, isNot(BssLoadRemedy.requestLocationPermission));
      });
    }

    test('macOS authorized still says nothing about the access point', () {
      final BssLoadUnavailableCopy copy = render(
        _kNoIeContextMacosAuthorized,
      );
      expect(copy.body, contains('Location is authorized'));
      expect(copy.remedy, BssLoadRemedy.none);
      expect(
        copy.body,
        contains('Nothing here is a finding about the access point'),
      );
    });

    test('all four bodies are distinct', () {
      final List<String> bodies = <BssLoadReadContext>[
        const BssLoadReadContext(
          platformExposesInformationElements: false,
          locationAuth: null,
        ),
        const BssLoadReadContext(
          platformExposesInformationElements: true,
          locationAuth: null,
        ),
        const BssLoadReadContext(
          platformExposesInformationElements: true,
          locationAuth: LocationAuthStatus.notDetermined,
        ),
        _kNoIeContextMacosAuthorized,
      ].map((BssLoadReadContext c) => render(c).body).toList();
      expect(bodies.toSet().length, 4);
    });

    test('every branch keeps the same headline and attribution', () {
      // The platform context changes the explanation, never the finding.
      for (final BssLoadReadContext c in <BssLoadReadContext>[
        const BssLoadReadContext(
          platformExposesInformationElements: false,
          locationAuth: null,
        ),
        const BssLoadReadContext(
          platformExposesInformationElements: true,
          locationAuth: LocationAuthStatus.denied,
        ),
        _kNoIeContextMacosAuthorized,
      ]) {
        final BssLoadUnavailableCopy copy = render(c);
        expect(copy.headline, 'This device gave us no information elements.');
        expect(copy.attribution, BssLoadAttribution.thisRead);
      }
    });
  });

  group('the numbers', () {
    test('a real reading formats to the expected strings', () {
      // Station count 10, channel utilization octet 120, admission capacity
      // 8000 raw. Written before the formatter existed:
      //   120 * 100 / 255 = 47.0588... -> 47.1%
      //   8000 * 100 / 31250 = 25.6    -> 25.6%
      //   8000 * 32 = 256000 us/s
      final BssLoadNumbers n = BssLoadNumbers.of(
        const BssLoad(
          stationCount: 10,
          rawChannelUtilization: 120,
          rawAdmissionCapacity: 8000,
        ),
      );
      expect(n.stationCount, '10');
      expect(n.channelUtilization, '47.1%');
      expect(n.channelUtilizationRaw, '120 of 255');
      expect(n.admissionCapacity, '25.6%');
      expect(n.admissionCapacityMicroseconds, '256000 µs/s');
      expect(n.admissionCapacityRaw, '8000');
      expect(n.admissionCapacityExceedsFullScale, isFalse);
    });

    test('ZERO is a reading, not an absence', () {
      // An idle access point on a quiet channel advertises zeros, and they are a
      // real measurement. Nothing here may render as a blank or a dash.
      final BssLoadNumbers n = BssLoadNumbers.of(
        const BssLoad(
          stationCount: 0,
          rawChannelUtilization: 0,
          rawAdmissionCapacity: 0,
        ),
      );
      expect(n.stationCount, '0');
      expect(n.channelUtilization, '0.0%');
      expect(n.channelUtilizationRaw, '0 of 255');
      expect(n.admissionCapacity, '0.0%');
      expect(n.admissionCapacityMicroseconds, '0 µs/s');
      expect(n.admissionCapacityRaw, '0');
      expect(n.admissionCapacityExceedsFullScale, isFalse);
    });

    test('an out-of-range admission capacity is flagged and never capped', () {
      // 31251 is one raw unit past a full second of medium time. The flag is the
      // DECODER's; this only checks it survives to the display layer, and that
      // the figure is not silently clamped to 100.0%.
      final BssLoadNumbers n = BssLoadNumbers.of(
        const BssLoad(
          stationCount: 1,
          rawChannelUtilization: 0,
          rawAdmissionCapacity: 31251,
        ),
      );
      expect(n.admissionCapacityExceedsFullScale, isTrue);
      expect(n.admissionCapacityRaw, '31251');
      expect(
        n.admissionCapacityMicroseconds,
        '1000032 µs/s',
        reason: '31251 * 32, never clamped to 1000000',
      );
    });

    test('at exactly full scale the flag is off', () {
      // The boundary, because a `>` written as `>=` would be invisible without
      // it. 31250 raw IS a full second and is not out of range.
      final BssLoadNumbers n = BssLoadNumbers.of(
        const BssLoad(
          stationCount: 0,
          rawChannelUtilization: 255,
          rawAdmissionCapacity: 31250,
        ),
      );
      expect(n.admissionCapacityExceedsFullScale, isFalse);
      expect(n.admissionCapacity, '100.0%');
      expect(n.channelUtilization, '100.0%');
      expect(n.channelUtilizationRaw, '255 of 255');
    });

    test('the wire value is always shown beside the conversion', () {
      // [[feedback_a_derived_value_in_quotation_position]]: a reader cannot tell
      // a quotation from a silent conversion. Every percentage on this screen
      // ships with the octet it came from, so the conversion stays checkable.
      final BssLoadNumbers n = BssLoadNumbers.of(
        const BssLoad(
          stationCount: 3,
          rawChannelUtilization: 1,
          rawAdmissionCapacity: 1,
        ),
      );
      expect(n.channelUtilizationRaw, isNotEmpty);
      expect(n.admissionCapacityRaw, isNotEmpty);
      // 1/255 rounds to 0.4%, and the raw 1 is what makes that legible.
      expect(n.channelUtilization, '0.4%');
      expect(n.channelUtilizationRaw, '1 of 255');
    });
  });

  group('octet diagnostics', () {
    test('a zero-length element 11 still prints, because it was seen', () {
      // `valueLength` null means NO ELEMENT 11 WAS SEEN, never "length zero".
      // [11, 0] is a complete element 11 with an empty value.
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        const BssLoadUnavailable(
          BssLoadUnavailableReason.malformedLength,
          valueLength: 0,
        ),
        context: _kNoIeContextMacosAuthorized,
      );
      expect(
        copy.octetDiagnostic,
        'Element 11 declared 0 value octets, and all of them arrived.',
      );
    });

    test('a one-octet element takes the singular', () {
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        const BssLoadUnavailable(
          BssLoadUnavailableReason.malformedLength,
          valueLength: 1,
        ),
        context: _kNoIeContextMacosAuthorized,
      );
      expect(copy.octetDiagnostic, contains('1 value octet,'));
      expect(copy.octetDiagnostic, isNot(contains('1 value octets')));
    });

    test('readings that saw no element 11 carry no octet count', () {
      for (final BssLoadUnavailableReason r in <BssLoadUnavailableReason>[
        BssLoadUnavailableReason.absent,
        BssLoadUnavailableReason.noInformationElementsProvided,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
        BssLoadUnavailableReason.blobCompletenessNotStated,
      ]) {
        final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
          BssLoadUnavailable(r),
          context: _kNoIeContextMacosAuthorized,
        );
        expect(
          copy.octetDiagnostic,
          isNull,
          reason: '${r.name} saw no element 11, so there is nothing to count',
        );
      }
    });
  });

  group('end to end from real bytes', () {
    // The table above builds readings by hand. These drive the decoder itself,
    // so the screen is pinned to what a live blob actually produces rather than
    // to what this test file believes it produces.

    test('a real 5-octet element 11 decodes and renders numbers', () {
      // [id=11][len=5][scount lo][scount hi][cu][adc lo][adc hi], little-endian.
      final BssLoadReading reading = decodeBssLoad(
        <int>[11, 5, 0x0A, 0x00, 0x78, 0x40, 0x1F],
      );
      expect(reading, isA<BssLoadDecoded>());
      final BssLoadNumbers n = BssLoadNumbers.of(reading.valueOrNull!);
      expect(n.stationCount, '10');
      expect(n.channelUtilization, '47.1%');
      expect(n.admissionCapacityRaw, '8000');
    });

    test('a null blob renders the platform sentence, never an AP claim', () {
      final BssLoadReading reading = decodeBssLoad(null);
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        reading as BssLoadUnavailable,
        context: const BssLoadReadContext(
          platformExposesInformationElements: false,
          locationAuth: null,
        ),
      );
      expect(copy.attribution, BssLoadAttribution.thisRead);
      expect(copy.headline, 'This device gave us no information elements.');
      expect(copy.headline.toLowerCase(), isNot(contains('access point')));
    });

    test('a whole beacon with no element 11 is the one AP claim', () {
      // An SSID element and a rates element, both complete, no element 11.
      final BssLoadReading reading = decodeBssLoad(
        <int>[0, 2, 0x41, 0x42, 1, 1, 0x82],
      );
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        reading as BssLoadUnavailable,
        context: _kNoIeContextMacosAuthorized,
      );
      expect(reading.reason, BssLoadUnavailableReason.absent);
      expect(copy.attribution, BssLoadAttribution.thisAccessPoint);
    });

    test('a clipped element 11 credits the AP and blames the capture', () {
      // Element 11 declares 5 value octets and only 2 arrive.
      final BssLoadReading reading = decodeBssLoad(<int>[11, 5, 0x01, 0x00]);
      final BssLoadUnavailable unavailable = reading as BssLoadUnavailable;
      expect(unavailable.reason, BssLoadUnavailableReason.truncated);
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        unavailable,
        context: _kNoIeContextMacosAuthorized,
      );
      expect(copy.attribution, BssLoadAttribution.thisRead);
      expect(copy.body, contains('did advertise element 11'));
      expect(
        copy.octetDiagnostic,
        'Element 11 declared 5 value octets, and 2 octets arrived before the '
        'buffer ended.',
      );
    });

    test('a clip that never reached element 11 claims nothing either way', () {
      // An SSID element whose declared length overruns the buffer: the walk
      // stops, and element 11 may or may not have been past it.
      final BssLoadReading reading = decodeBssLoad(<int>[0, 40, 0x41, 0x42]);
      final BssLoadUnavailable unavailable = reading as BssLoadUnavailable;
      expect(
        unavailable.reason,
        BssLoadUnavailableReason.clippedWithoutSeeingElement11,
      );
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        unavailable,
        context: _kNoIeContextMacosAuthorized,
      );
      expect(copy.attribution, BssLoadAttribution.thisRead);
      expect(copy.octetDiagnostic, isNull);
    });

    test('blobCompletenessNotStated comes only from the elements entry point',
        () {
      // decodeBssLoad reads the raw bytes and always knows where the walk
      // stopped, so it can never report this. Only a caller that hands over
      // pre-split elements and says it was not told can. Pinned here so the
      // screen's fourth attribution is not mistaken for something the live
      // macOS path renders.
      final BssLoadReading fromElements = decodeBssLoadFromElements(
        const <InformationElement>[],
        blobCompleteness: IeBlobCompleteness.notStated,
      );
      expect(
        (fromElements as BssLoadUnavailable).reason,
        BssLoadUnavailableReason.blobCompletenessNotStated,
      );
      final BssLoadUnavailableCopy copy = bssLoadUnavailableCopy(
        fromElements,
        context: _kNoIeContextMacosAuthorized,
      );
      expect(copy.attribution, BssLoadAttribution.whatWeWereTold);
    });
  });
}
