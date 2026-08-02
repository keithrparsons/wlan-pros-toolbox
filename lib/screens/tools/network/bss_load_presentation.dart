// The rendered contract for `bss_load_decoder.dart`: turns a [BssLoadReading]
// into the words a screen shows, and nothing else.
//
// Pure Dart. No Flutter import, no widget, no state, deliberately mirroring the
// decoder it renders, so every string below is testable without a widget pump
// and the screen cannot quietly grow a second copy of this vocabulary.
//
// ── WHY THIS FILE IS SEPARATE FROM THE SCREEN ────────────────────────────────
//
// `bss_load_decoder.dart` was rewritten twice to stop one failure: reporting a
// defect in OUR OWN byte handling as a fact about somebody's access point
// ([[feedback_app_blames_the_wifi]]). It ended up with seven distinct
// unavailable reasons where a lesser type would have had one.
//
// A SCREEN THAT RENDERS ALL SEVEN AS ONE GREY "UNAVAILABLE" THROWS AWAY
// EVERYTHING THOSE TWO REWRITES BOUGHT, and it does it silently: the decoder
// stays correct, the tests stay green, and the user reads a shrug. This file is
// the place that refuses, and it is separate so a test can assert the refusal
// directly instead of digging the strings out of a widget tree.
//
// ── THE GROUPING, AND WHAT IS DELIBERATELY NOT GROUPED ───────────────────────
//
// Seven reasons is too many to render as seven walls of text. Collapsing them to
// one is the failure above. The resolution is to group the ATTRIBUTION and keep
// the HEADLINE separate:
//
//   * THREE attributions ([BssLoadAttribution]), which answer "whose side is
//     this reason on". That is the axis a WLAN engineer cares about, because it
//     decides whether the finding is about the network they are standing in or
//     about the tool in their hand.
//   * EIGHT headlines, one per rendered outcome, each one sentence. Nothing is
//     merged. Reading two of them never leaves a reader thinking they read the
//     same thing twice.
//
// EIGHT, NOT SEVEN, AND THE EXTRA ONE IS NOT AN INVENTION.
// [BssLoadUnavailableReason.malformedLength] covers two materially different
// findings, and the decoder hands over the field that tells them apart: its own
// doc says they are "told apart by [BssLoadUnavailable.availableLength]: null
// when every declared octet arrived, and a count when the buffer ended early".
// A COMPLETE element with a bad length is a whole, honest read of somebody's
// beacon. A CLIPPED header with a bad length is a whole, honest read of our own
// truncated buffer. They land in different attributions, so rendering one
// sentence for both would re-introduce the exact collapse this file exists to
// prevent.
//
// ── THE ATTRIBUTION IS WORDED, NEVER COLORED ─────────────────────────────────
//
// No status hue distinguishes these groups, on two independent grounds.
// GL-003 section 8.13 carries a computed-verdict-ONLY hard rule on the status
// tokens, and "whose side is this on" is a category rather than a pass/warn/fail
// assessment. And WCAG 2.2 SC 1.4.1 forbids carrying meaning by hue alone, so a
// color-coded grouping would have needed the words anyway. The words are the
// mechanism; there is no hue to lose.
//
// THAT RULE IS CITED BY ITS NAME AND NOT BY ITS POSITION IN THE LIST, which is
// the same discipline the decoder applies to its own honesty contract: an
// ordinal has no grep handle, so an insertion upstream falsifies the sentence in
// total silence. Measured, not assumed: this file is not among the four
// `bss_load_ordinal_reference_guard_test.dart` scans, but it was run against
// them on 2026-08-02 and the bare "rule 6" phrasing this paragraph used to carry
// was rejected. Naming the rule means the guard can be widened to cover this
// screen without a copy edit falling out of it.
//
// ── WHAT THIS FILE MAY NEVER SAY ─────────────────────────────────────────────
//
// THE RULE IS ABOUT DIRECTION, NOT ABOUT MENTION, and the first draft of this
// paragraph got that wrong. It said only [BssLoadAttribution.thisAccessPoint]
// copy may describe the access point's advertisement, and the copy below breaks
// that on purpose: [BssLoadUnavailableReason.truncated] sits under
// [BssLoadAttribution.thisRead] and opens by saying this access point DID
// advertise element 11. That sentence is the whole point of the reading. A
// comment promising the opposite of the line beneath it is the exact defect
// [[feedback_screen_does_what_copy_says]] is named for, so here is the rule the
// code actually keeps:
//
//   ONLY [BssLoadAttribution.thisAccessPoint] COPY MAY SAY AN ACCESS POINT
//   FAILED TO DO SOMETHING. A positive credit ("it did advertise this") is safe
//   anywhere, because being wrong in that direction costs nobody their
//   reputation. A deficiency claim is earned only by a read that was whole.
//
// `bss_load_presentation_test.dart` pins that mechanically, alongside the full
// attribution-and-headline table, so a future edit that lets an accusation drift
// across the line turns the build red rather than shipping.
//
// Build: Felix 2026-08-02. First non-test consumer of the decoder's contract.

import '../../../services/network/bss_load_decoder.dart';
import '../../../services/network/wifi_info_service.dart' show LocationAuthStatus;

/// Whose side an unavailable reading is on.
///
/// NAMED, NEVER NUMBERED, like the decoder it renders. Cite a member by name.
enum BssLoadAttribution {
  /// The reading describes what the access point put in its beacon, and our own
  /// read of it was whole. The only attribution whose copy may make a claim
  /// about somebody else's network.
  thisAccessPoint,

  /// The reading describes this device, this capture, or this build. The access
  /// point may well advertise BSS Load perfectly; we could not get it, or could
  /// not honestly decode what we got.
  thisRead,

  /// The reading describes a gap in what we were TOLD. Not a clipped capture and
  /// not a silent access point: nobody stated whether the capture was whole.
  whatWeWereTold,
}

/// The human-readable label for an attribution, shown as an eyebrow above the
/// headline.
extension BssLoadAttributionLabel on BssLoadAttribution {
  String get label {
    switch (this) {
      case BssLoadAttribution.thisAccessPoint:
        return 'About this access point';
      case BssLoadAttribution.thisRead:
        return 'About this read';
      case BssLoadAttribution.whatWeWereTold:
        return 'About what we were told';
    }
  }
}

/// What the SCREEN knows and the decoder does not.
///
/// The decoder sees bytes. It cannot know that this platform never exposes
/// information elements in the first place, or that macOS is withholding them
/// for want of a Location grant. Rendering
/// [BssLoadUnavailableReason.noInformationElementsProvided] as one flat sentence
/// while the screen is holding those bits is
/// [[feedback_ui_rendered_a_decision_it_lacked]]: a UI asked to explain
/// something, holding the input, and guessing anyway.
///
/// BOTH FIELDS ARE REQUIRED for the reason that memory gives as the only
/// structural remedy found: an optional with a default lets a call site forget
/// to consult the state, and the forgetting is silent.
class BssLoadReadContext {
  const BssLoadReadContext({
    required this.platformExposesInformationElements,
    required this.locationAuth,
  });

  /// Whether any channel on this platform hands up raw beacon information
  /// elements. macOS only today: `WifiInfoService.connectedApIeBlob` returns an
  /// honest-null blob everywhere else without touching a channel.
  final bool platformExposesInformationElements;

  /// What Location authorization said, or NULL when we did not ask.
  ///
  /// NULL MEANS NOT CONSULTED, AND IT NEVER RENDERS A LOCATION CLAIM. A screen
  /// that did not read the grant may not tell the user their grant is the
  /// problem, and may not tell them it is not. Only consulted when
  /// [platformExposesInformationElements] is true, because Location gates
  /// nothing anywhere else.
  final LocationAuthStatus? locationAuth;
}

/// What a screen may offer the user to do about an unavailable reading.
///
/// Derived from the tri-state, never from a bool. `denied` and `restricted` are
/// both [openLocationSettings] because macOS will never surface a prompt for
/// either: offering a Grant button there is a control that is guaranteed to do
/// nothing (`LocationAuthStatus.isPromptable` is the SSOT for the difference and
/// is consulted rather than re-derived).
enum BssLoadRemedy {
  /// Nothing the user can do from here. The honest default.
  none,

  /// The system permission prompt can still appear. Offer it.
  requestLocationPermission,

  /// Not promptable. Deep-link the Location settings pane instead.
  openLocationSettings,
}

/// Everything a screen renders for one unavailable reading.
class BssLoadUnavailableCopy {
  const BssLoadUnavailableCopy({
    required this.attribution,
    required this.headline,
    required this.body,
    required this.remedy,
    this.octetDiagnostic,
  });

  /// Whose side this reading is on. Rendered as a word, never as a hue.
  final BssLoadAttribution attribution;

  /// One sentence. Distinct across every rendered outcome.
  final String headline;

  /// The paragraph under the headline.
  final String body;

  /// What the user may do about it, which is usually nothing.
  final BssLoadRemedy remedy;

  /// The octet counts of the element we refused, when one was seen.
  ///
  /// A DIAGNOSTIC ABOUT OUR OWN READ, NEVER THE ACCESS POINT'S LOAD. The decoder
  /// is explicit that [BssLoadUnavailable.valueLength] and
  /// [BssLoadUnavailable.availableLength] "are the octet counts of the element we
  /// refused ... they are diagnostics about our own read, never the AP's load".
  /// Null wherever no element 11 was seen, because there is nothing to count.
  final String? octetDiagnostic;
}

/// Renders an unavailable [reading] into the words a screen shows.
///
/// Total: every member of [BssLoadUnavailableReason] is handled, and the switch
/// is exhaustive, so adding a member to the decoder stops this file compiling
/// rather than letting a new outcome fall into somebody else's sentence.
BssLoadUnavailableCopy bssLoadUnavailableCopy(
  BssLoadUnavailable reading, {
  required BssLoadReadContext context,
}) {
  switch (reading.reason) {
    case BssLoadUnavailableReason.absent:
      return const BssLoadUnavailableCopy(
        attribution: BssLoadAttribution.thisAccessPoint,
        headline: 'This access point does not advertise BSS Load.',
        body:
            'The beacon was read end to end and carried no BSS Load element. '
            'The element is optional and plenty of access points leave it off.',
        remedy: BssLoadRemedy.none,
      );

    case BssLoadUnavailableReason.noInformationElementsProvided:
      return _noInformationElements(context);

    case BssLoadUnavailableReason.clippedWithoutSeeingElement11:
      return const BssLoadUnavailableCopy(
        attribution: BssLoadAttribution.thisRead,
        headline:
            'Our capture was cut short before we reached a BSS Load element.',
        body:
            'The walk stopped part way through the beacon, so a BSS Load '
            'element may have been in the part that was cut. BSS Load sits well '
            'down a beacon, after the SSID, the rates and the DS parameter set, '
            'so a clip is likelier to land before it than on it. Nothing here '
            'says whether this access point advertises it.',
        remedy: BssLoadRemedy.none,
      );

    case BssLoadUnavailableReason.blobCompletenessNotStated:
      return const BssLoadUnavailableCopy(
        attribution: BssLoadAttribution.whatWeWereTold,
        headline: 'We were not told whether the capture was whole.',
        body:
            'No BSS Load element was among the elements handed to us, and '
            'whatever handed them over did not say whether it had read the '
            'beacon to its end. That is a gap in what we were told. Nothing '
            'here says the capture was clipped, and nothing here is a finding '
            'about the access point you are connected to.',
        remedy: BssLoadRemedy.none,
      );

    case BssLoadUnavailableReason.truncated:
      return BssLoadUnavailableCopy(
        attribution: BssLoadAttribution.thisRead,
        headline: 'Our capture cut a BSS Load element short.',
        body:
            'This access point did advertise element 11, and the buffer ended '
            'part way through it. Nothing was decoded from the octets that did '
            'arrive: padding a partial element out to full length is the guess '
            'this tool exists to refuse. The advertisement was whole. Our '
            'capture was not.',
        remedy: BssLoadRemedy.none,
        octetDiagnostic: _octetDiagnostic(reading),
      );

    case BssLoadUnavailableReason.ciscoQbssVersion1:
      return BssLoadUnavailableCopy(
        attribution: BssLoadAttribution.thisRead,
        headline: 'This build does not decode the Cisco QBSS variant.',
        body:
            'This access point sent element 11 in the Cisco "QBSS Version 1, '
            'non CCA" form, whose admission-capacity field is one octet and '
            'carries different meaning from the two octets the standard form '
            'uses. Reading it with the standard layout would produce a number '
            'that looks entirely plausible and is wrong, so this build '
            'recognizes the variant and refuses it.',
        remedy: BssLoadRemedy.none,
        octetDiagnostic: _octetDiagnostic(reading),
      );

    case BssLoadUnavailableReason.malformedLength:
      // THE ONE REASON THAT RENDERS TWO WAYS, and the field that splits it is
      // the decoder's own. See the header.
      final bool wasClipped = reading.availableLength != null;
      if (wasClipped) {
        return BssLoadUnavailableCopy(
          attribution: BssLoadAttribution.thisRead,
          headline: 'Our capture cut short an element we would have refused.',
          body:
              'An element 11 header arrived and the buffer ended before its '
              'value did. Its declared length is not one a BSS Load element may '
              'have, which disqualifies it whether or not our capture was '
              'whole, so nothing was read from the octets that arrived. Because '
              'the capture was cut, nothing here is a finding about this access '
              'point.',
          remedy: BssLoadRemedy.none,
          octetDiagnostic: _octetDiagnostic(reading),
        );
      }
      return BssLoadUnavailableCopy(
        attribution: BssLoadAttribution.thisAccessPoint,
        headline:
            'This access point sent a BSS Load element with a length it cannot '
            'have.',
        body:
            'The whole element arrived, and nothing was cut. A BSS Load element '
            'carries 5 value octets in IEEE 802.11-2012, or 4 in the Cisco '
            'variant. Wireshark treats any other length as an error and decodes '
            'nothing, and so does this build: reading a prefix of an element we '
            'do not recognize would be a guess dressed as a measurement.',
        remedy: BssLoadRemedy.none,
        octetDiagnostic: _octetDiagnostic(reading),
      );
  }
}

/// The four ways "no information elements reached us" reads, once the screen
/// contributes what it knows.
///
/// This is ONE decoder reason and FOUR true sentences, because the decoder
/// deliberately says only what the bytes support. Every branch closes on the
/// same scope declaration, because that is the load-bearing claim: an empty hand
/// is never evidence about somebody's access point.
BssLoadUnavailableCopy _noInformationElements(BssLoadReadContext context) {
  const String headline = 'This device gave us no information elements.';
  const BssLoadAttribution attribution = BssLoadAttribution.thisRead;

  if (!context.platformExposesInformationElements) {
    return const BssLoadUnavailableCopy(
      attribution: attribution,
      headline: headline,
      body:
          'macOS is the only platform that hands raw beacon information '
          'elements to this app today, and iOS exposes none to any app at all. '
          'Nothing on this screen is a finding about the access point you are '
          'connected to.',
      remedy: BssLoadRemedy.none,
    );
  }

  final LocationAuthStatus? auth = context.locationAuth;

  if (auth == null) {
    // WE DID NOT ASK, SO WE NAME NO CAUSE. Saying "grant Location" here would
    // be a guess, and saying "Location is fine" would be a different one.
    return const BssLoadUnavailableCopy(
      attribution: attribution,
      headline: headline,
      body:
          'macOS returned no information elements for the connected BSS. We did '
          'not read the Location authorization for this attempt, so this screen '
          'names no cause for it. Nothing here is a finding about the access '
          'point you are connected to.',
      remedy: BssLoadRemedy.none,
    );
  }

  if (!auth.isAuthorized) {
    return BssLoadUnavailableCopy(
      attribution: attribution,
      headline: headline,
      body:
          'macOS withholds beacon information elements from an app that does '
          'not hold Location access, so there were no bytes to walk. Grant it '
          'and read again. Nothing here is a finding about the access point you '
          'are connected to.',
      // The tri-state decides, and `isPromptable` is the SSOT for it. A denied
      // or restricted grant gets the settings pane, because macOS will never
      // raise a prompt for either.
      remedy: auth.isPromptable
          ? BssLoadRemedy.requestLocationPermission
          : BssLoadRemedy.openLocationSettings,
    );
  }

  return const BssLoadUnavailableCopy(
    attribution: attribution,
    headline: headline,
    body:
        'Location is authorized and macOS still returned no information '
        'elements for the connected BSS. Wi-Fi may be off, or the scan may have '
        'found no BSS matching the BSSID you are associated to. Nothing here is '
        'a finding about the access point you are connected to.',
    remedy: BssLoadRemedy.none,
  );
}

/// The octet counts, phrased so a reader can tell a declared number from an
/// arrived one.
///
/// Returns null when no element 11 was seen. [BssLoadUnavailable.valueLength]'s
/// own doc is "NULL MEANS NO ELEMENT 11 WAS SEEN, NOT LENGTH ZERO", so that is
/// the question asked, and a genuine zero-length element 11 still prints.
String? _octetDiagnostic(BssLoadUnavailable reading) {
  final int? declared = reading.valueLength;
  if (declared == null) return null;
  final int? arrived = reading.availableLength;
  if (arrived == null) {
    return 'Element 11 declared $declared value '
        '${_octetWord(declared)}, and all of them arrived.';
  }
  return 'Element 11 declared $declared value ${_octetWord(declared)}, and '
      '$arrived ${_octetWord(arrived)} arrived before the buffer ended.';
}

String _octetWord(int n) => n == 1 ? 'octet' : 'octets';

/// The three numbers a decoded reading carries, formatted for display.
///
/// EVERY CONVERTED FIGURE IS SHOWN BESIDE THE RAW VALUE IT CAME FROM. The
/// percentages here are the decoder's own getters; the rounding to one decimal
/// place is this file's, and a reader who wants to check it has the wire value
/// on the same row ([[feedback_a_derived_value_in_quotation_position]]).
class BssLoadNumbers {
  const BssLoadNumbers._({
    required this.stationCount,
    required this.channelUtilization,
    required this.channelUtilizationRaw,
    required this.admissionCapacity,
    required this.admissionCapacityMicroseconds,
    required this.admissionCapacityRaw,
    required this.admissionCapacityExceedsFullScale,
  });

  /// Formats a decoded [load]. No verdict is computed: the decoder returns three
  /// numbers and one out-of-range flag, and this class adds no fourth judgement
  /// about whether a channel is "busy" or a station count is "high".
  factory BssLoadNumbers.of(BssLoad load) {
    return BssLoadNumbers._(
      stationCount: '${load.stationCount}',
      channelUtilization: _percent(load.channelUtilizationPercent),
      channelUtilizationRaw:
          '${load.rawChannelUtilization} of $kChannelUtilizationFullScale',
      admissionCapacity: _percent(load.admissionCapacityPercent),
      admissionCapacityMicroseconds:
          '${load.admissionCapacityMicrosecondsPerSecond} µs/s',
      admissionCapacityRaw: '${load.rawAdmissionCapacity}',
      admissionCapacityExceedsFullScale: load.admissionCapacityExceedsFullScale,
    );
  }

  /// Associated stations, as the access point counts them. Zero is a reading.
  final String stationCount;

  /// Channel utilization as a percentage, to one decimal place.
  final String channelUtilization;

  /// The wire octet behind [channelUtilization], so the conversion is checkable.
  final String channelUtilizationRaw;

  /// Available admission capacity as a percentage of one second of medium time.
  final String admissionCapacity;

  /// The same figure in microseconds of medium time per second.
  final String admissionCapacityMicroseconds;

  /// The wire value behind both, so both conversions are checkable.
  final String admissionCapacityRaw;

  /// The decoder's own out-of-range flag: the access point advertised more than
  /// a full second of medium time available, which is not physically
  /// meaningful. NEVER capped for display, and the flag is the decoder's
  /// assessment rather than this file's.
  final bool admissionCapacityExceedsFullScale;

  static String _percent(double value) => '${value.toStringAsFixed(1)}%';
}
