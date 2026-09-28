// Wi-Fi privacy myths. The deterministic model behind the Guided Lesson
// (lib/screens/tools/reference/wifi_privacy_*.dart). Two parts, one control
// each.
//
// PART 1, the private Wi-Fi address. Control: Off / Fixed / Rotating. What
// two routers on the same day, and one router on two visits a month apart,
// record for the same phone.
//  1. Off: the hardware address, the same everywhere and every time
//     (Apple Platform Security: "allowing tracking by networks and nearby
//     Wi-Fi devices").
//  2. Fixed: a different private address for each network, kept for that
//     network ("doesn't rotate, regardless of the network's security or
//     length of time since you last joined", Apple 102509).
//  3. Rotating: different for each network AND changed over time. Apple
//     102509 (published 2025-12-05) says it "rotates to a different private
//     address every 2 weeks"; [kPublishedRotationDays]. The lesson's two
//     visits are a month apart, so a rotating address has changed by the
//     second one under that schedule.
//  4. A private address is locally administered: the second-lowest bit of
//     the first octet set, the lowest (group) bit clear (IEEE 802). A
//     hardware address has the local bit clear.
//  5. A MAC filter set on the first visit lets Off and Fixed back in on the
//     second, and turns Rotating away. It keeps out no one who copies an
//     allowed address, because the address travels unencrypted in every frame
//     header (CWNA-109 5.1.4; Apple 102766: "MAC addresses can easily be
//     copied, spoofed (impersonated), or changed").
//
// PART 2, the hidden network name. Control: shown / hidden.
//  6. Shown: the AP's beacons carry the name; the phone's probe requests do
//     not name it.
//  7. Hidden: the beacons carry a blank name, and the phone names the network
//     in its probe requests, in every place it goes (Apple Platform Security:
//     "If a network is hidden, the device sends a probe with the SSID included
//     in the request—not otherwise"; Apple 102766).
//  8. Either way, the name travels in the clear whenever a device joins, so
//     hiding it is not security (CWNA-109 5.1.3).
//
// All addresses and the network name are illustrative. The hardware address is
// in the IANA documentation range (RFC 7042: 00-00-5E-00-53-00 to -FF), so it
// belongs to no real device.
//
// Pure Dart. No Flutter import, no I/O, no randomness.

/// The three private-address settings.
enum PmAddressMode { off, fixed, rotating }

/// The rotation interval one phone maker publishes (Apple 102509, "every 2
/// weeks"). The only published figure; other makers are unsourced here.
const int kPublishedRotationDays = 14;

/// Days between the lesson's two visits to the same cafe.
const int kVisitGapDays = 30;

/// The networks the phone meets in part 1.
enum PmNetwork { home, cafe }

/// The phone's hardware address: IANA documentation range (RFC 7042).
const List<int> kHardwareAddress = <int>[0x00, 0x00, 0x5E, 0x00, 0x53, 0x1A];

/// Formats six octets as AA:BB:CC:DD:EE:FF.
String pmFormat(List<int> octets) => octets
    .map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// True when the address is locally administered (a private address).
bool pmIsLocal(List<int> octets) => (octets[0] & 0x02) != 0;

/// True when the address is a group (multicast) address. A device's own
/// address never is.
bool pmIsGroup(List<int> octets) => (octets[0] & 0x01) != 0;

/// A private address for [network] in rotation [period]: a fixed mix of the
/// two, locally administered, never a group address. Deterministic, so the
/// lesson draws the same values every time.
List<int> pmPrivateAddress(PmNetwork network, int period) {
  int x = 0x9E3779B1 ^ ((network.index + 1) * 0x85EBCA77) ^ (period * 0xC2B2AE3D);
  final List<int> out = <int>[];
  for (int i = 0; i < 6; i++) {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
    out.add((x >> 16) & 0xFF);
  }
  out[0] = (out[0] | 0x02) & 0xFE;
  return out;
}

/// The rotation period a visit on [day] falls in.
int pmPeriod(int day) => day ~/ kPublishedRotationDays;

/// The address [network]'s router records for the phone on [day].
List<int> pmRecorded(PmAddressMode mode, PmNetwork network, int day) =>
    switch (mode) {
      PmAddressMode.off => kHardwareAddress,
      PmAddressMode.fixed => pmPrivateAddress(network, 0),
      PmAddressMode.rotating => pmPrivateAddress(network, pmPeriod(day)),
    };

bool _same(List<int> a, List<int> b) {
  for (int i = 0; i < 6; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Scene A: can the home router and the cafe router, on the same day, match
/// the phone by its address?
bool pmLinkedAcrossNetworks(PmAddressMode mode) => _same(
  pmRecorded(mode, PmNetwork.home, 0),
  pmRecorded(mode, PmNetwork.cafe, 0),
);

/// Scene B: can the cafe match its two visits, [kVisitGapDays] apart?
bool pmLinkedAcrossVisits(PmAddressMode mode) => _same(
  pmRecorded(mode, PmNetwork.cafe, 0),
  pmRecorded(mode, PmNetwork.cafe, kVisitGapDays),
);

/// A MAC filter at the cafe, set to the address seen on the first visit:
/// does it let the phone in on the second?
bool pmFilterAdmitsSecondVisit(PmAddressMode mode) => pmLinkedAcrossVisits(mode);

// ── Part 2 ──────────────────────────────────────────────────────────────────

/// The illustrative name of the phone's home network.
const String kHomeNetworkName = 'HomeNet';

/// The places the phone goes in part 2, in order.
const List<String> kPmPlaces = <String>['Home', 'Airport', 'Cafe'];

/// The network name the AP's beacons carry. Blank when hidden.
String pmBeaconName(bool hidden) => hidden ? '' : kHomeNetworkName;

/// The network name the phone puts in its probe requests. Null when it asks
/// without naming anything.
String? pmProbeName(bool hidden) => hidden ? kHomeNetworkName : null;

/// The places where the phone says the home network's name out loud.
List<String> pmPlacesNamed(bool hidden) =>
    hidden ? kPmPlaces : const <String>[];

/// True whenever any device joins: the name crosses the air in the clear,
/// hidden or not.
bool pmNameSentWhenJoining(bool hidden) => true;
