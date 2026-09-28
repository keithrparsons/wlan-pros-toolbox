// The teaching claims of the Wi-Fi Privacy Myths Guided Lesson, one test each.
// The numbered claims are listed in lib/services/wifi_lab/wifi_privacy_model.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wifi_privacy_model.dart';

void main() {
  test('1. Off: the hardware address everywhere, every visit', () {
    for (final PmNetwork n in PmNetwork.values) {
      for (final int day in <int>[0, kVisitGapDays]) {
        expect(pmRecorded(PmAddressMode.off, n, day), kHardwareAddress);
      }
    }
    expect(pmLinkedAcrossNetworks(PmAddressMode.off), isTrue);
    expect(pmLinkedAcrossVisits(PmAddressMode.off), isTrue);
  });

  test('2. Fixed: different per network, kept for that network', () {
    expect(pmLinkedAcrossNetworks(PmAddressMode.fixed), isFalse);
    expect(pmLinkedAcrossVisits(PmAddressMode.fixed), isTrue);
  });

  test('3. Rotating: different per network, changed a month later', () {
    expect(kPublishedRotationDays, 14);
    expect(kVisitGapDays, greaterThanOrEqualTo(2 * kPublishedRotationDays),
        reason: 'the visits must straddle a rotation whatever its phase');
    expect(pmLinkedAcrossNetworks(PmAddressMode.rotating), isFalse);
    expect(pmLinkedAcrossVisits(PmAddressMode.rotating), isFalse);
  });

  test('4. private addresses are locally administered, never group', () {
    expect(pmIsLocal(kHardwareAddress), isFalse);
    expect(pmIsGroup(kHardwareAddress), isFalse);
    for (final PmNetwork n in PmNetwork.values) {
      for (int p = 0; p < 50; p++) {
        final List<int> a = pmPrivateAddress(n, p);
        expect(a, hasLength(6));
        expect(pmIsLocal(a), isTrue, reason: pmFormat(a));
        expect(pmIsGroup(a), isFalse, reason: pmFormat(a));
        expect(a.every((int b) => b >= 0 && b <= 0xFF), isTrue);
      }
    }
    // Second hex digit of a private address is 2, 6, A or E.
    expect('26AE'.contains(pmFormat(pmPrivateAddress(PmNetwork.home, 0))[1]),
        isTrue);
  });

  test('5. a MAC filter from visit 1 admits Off and Fixed, not Rotating', () {
    expect(pmFilterAdmitsSecondVisit(PmAddressMode.off), isTrue);
    expect(pmFilterAdmitsSecondVisit(PmAddressMode.fixed), isTrue);
    expect(pmFilterAdmitsSecondVisit(PmAddressMode.rotating), isFalse);
  });

  test('6. shown: the beacon names it, the probes do not', () {
    expect(pmBeaconName(false), kHomeNetworkName);
    expect(pmProbeName(false), isNull);
    expect(pmPlacesNamed(false), isEmpty);
  });

  test('7. hidden: blank beacon, and the phone names it everywhere', () {
    expect(pmBeaconName(true), isEmpty);
    expect(pmProbeName(true), kHomeNetworkName);
    expect(pmPlacesNamed(true), kPmPlaces);
    expect(kPmPlaces, contains('Airport'));
  });

  test('8. the name crosses the air when a device joins, hidden or not', () {
    expect(pmNameSentWhenJoining(false), isTrue);
    expect(pmNameSentWhenJoining(true), isTrue);
  });

  test('the formatter and the documentation-range hardware address', () {
    expect(pmFormat(kHardwareAddress), '00:00:5E:00:53:1A');
  });
}
