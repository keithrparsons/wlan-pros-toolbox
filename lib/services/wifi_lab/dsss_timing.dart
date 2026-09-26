// 802.11b (DSSS and CCK) frame timing, shared by the Wi-Fi Classroom tools
// that put an 802.11b frame on the air: Multicast at the Basic Rate
// (multicast_basic_rate_model.dart) and Legacy Protection Cost
// (legacy_protection_model.dart).
//
// EXTRACTED 2026-09-27 from multicast_basic_rate_model.dart, where the long
// preamble, slot, SIFS and CWmin first lived, so the two tools share one copy.
// Airtime Anatomy (airtime_anatomy.dart) is OFDM only and has no path for
// these rates; this file is the 802.11b complement to it.
//
// SOURCE. IEEE 802.11b-1999, as read by Pax for the wave 4 research brief
// (myPKA Deliverables/2026-09-26-wifi-classroom-wave4-research/brief-GKL.md,
// section L):
//   - clause 18.3.4: TXTIME = PreambleLength + PLCPHeaderTime
//       + Ceiling(((LENGTH + PBCC) x 8) / DATARATE)   (PBCC = 0 here)
//   - clause 18.2.2.1, Figure 127: long preamble 144 us + header 48 us
//   - clause 18.2.2.2, Figure 128: short preamble 72 us + header 24 us, with
//     the payload at 2, 5.5 or 11 Mb/s only (no short preamble at 1 Mb/s)
//   - Table 101: slot 20 us, SIFS 10 us
//   - clause 18.2.3.5: the payload time rounds UP to a whole microsecond
// CWmin 31 is the 802.11b value the multicast tool already used.
//
// ARITHMETIC. Whole microseconds, integers only: the rate is carried in
// tenths of a Mb/s so 5.5 stays exact, and the ceiling is taken on integers.
//
// ASCII only, no em dashes (GL-004). No Flutter imports.

/// The 802.11b timing constants.
class DsssTiming {
  DsssTiming._();

  /// Table 101.
  static const int slotUs = 20;

  /// Table 101.
  static const int sifsUs = 10;

  /// The 802.11b minimum contention window.
  static const int cwMin = 31;

  /// Long PLCP preamble (SYNC + SFD), 144 us at 1 Mb/s.
  static const int longSyncUs = 144;

  /// Long PLCP header, 48 us at 1 Mb/s.
  static const int longHeaderUs = 48;

  /// Short PLCP preamble, 72 us at 1 Mb/s.
  static const int shortSyncUs = 72;

  /// Short PLCP header, 24 us at 2 Mb/s.
  static const int shortHeaderUs = 24;

  /// 144 us long preamble + 48 us PLCP header.
  static const int longPreambleUs = longSyncUs + longHeaderUs;

  /// 72 us short preamble + 24 us PLCP header.
  static const int shortPreambleUs = shortSyncUs + shortHeaderUs;
}

/// The 802.11b PLCP preamble format.
enum DsssPreamble {
  long('Long', DsssTiming.longPreambleUs),
  short('Short', DsssTiming.shortPreambleUs);

  const DsssPreamble(this.label, this.us);

  final String label;

  /// Preamble plus PLCP header, microseconds.
  final int us;
}

/// The four 802.11b data rates, slowest first.
enum DsssRate {
  r1(10),
  r2(20),
  r5_5(55),
  r11(110);

  const DsssRate(this.tenthsMbps);

  /// The rate in tenths of a Mb/s, so 5.5 stays exact.
  final int tenthsMbps;

  double get mbps => tenthsMbps / 10;

  /// "5.5 Mb/s".
  String get label =>
      '${tenthsMbps % 10 == 0 ? '${tenthsMbps ~/ 10}' : mbps.toString()} Mb/s';

  /// 802.11b defines the short preamble only for 2, 5.5 and 11 Mb/s.
  bool allows(DsssPreamble p) => p == DsssPreamble.long || this != DsssRate.r1;

  /// The rate for [tenthsMbps], or null when it is not an 802.11b rate.
  static DsssRate? ofTenths(int tenthsMbps) {
    for (final DsssRate r in DsssRate.values) {
      if (r.tenthsMbps == tenthsMbps) return r;
    }
    return null;
  }
}

/// Why [DsssRate.r1] has no short preamble, word for word as the tools show
/// it.
const String kDsssNoShortAt1Reason =
    '802.11b defines short preamble only for 2, 5.5 and 11 Mb/s.';

/// The payload time of [bytes] at [tenthsMbps] (tenths of a Mb/s), rounded up
/// to a whole microsecond as clause 18.2.3.5 requires:
/// ceil(8 x bytes / rate). 14 bytes at 11 Mb/s = 10.18 -> 11 us.
int dsssPayloadUs(int bytes, int tenthsMbps) {
  assert(bytes >= 0);
  assert(tenthsMbps > 0);
  return _ceilDiv(80 * bytes, tenthsMbps);
}

/// TXTIME of one 802.11b frame of [bytes] at [rate] with [preamble],
/// microseconds (clause 18.3.4). Throws when the preamble is not defined for
/// the rate (short at 1 Mb/s).
int dsssTxTimeUs(
  int bytes,
  DsssRate rate, {
  DsssPreamble preamble = DsssPreamble.long,
}) {
  if (!rate.allows(preamble)) {
    throw ArgumentError.value(preamble, 'preamble', kDsssNoShortAt1Reason);
  }
  return preamble.us + dsssPayloadUs(bytes, rate.tenthsMbps);
}

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;
