// PoE: Why the New AP Runs at Half Strength: the pure model for the Wi-Fi
// Classroom tool (poe-half-strength).
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate
// 10 and the section 5 anti-patterns, approved by Keith.
//
// THE LESSON. A Wi-Fi 7 AP on a switch port that cannot supply its full
// power still boots and still lights its power light, and quietly runs with
// fewer radios or fewer spatial streams. "The light is on, so power is fine"
// is the belief it corrects.
//
// ONE GENERIC AP, NOT A PRODUCT (Keith's no-names rule; brief anti-pattern
// 5: each vendor cuts different things). The AP here is a tri-band Wi-Fi 7
// AP with three radios (2.4, 5 and 6 GHz), each 4x4:4, that needs about 29 W
// at the AP for full function. Its behavior on each port type follows ONE
// published vendor guide, read for this build (fetched 2026-09-27):
//   - Juniper Mist, "Wi-Fi 7 AP guide: choose the right AP" (AP47, listed as
//     "Tri Band 4x4"): "requires approximately 29 Watts of power at the
//     powered device (PD) for full Wi-Fi functionality. When powered by
//     802.3at power, the AP operates with reduced functionality. The three
//     Wi-Fi radios operate at 2x2:2, or 4x4:4 with any two Wi-Fi radios
//     enabled."
//   - Cisco Meraki, "Wi-Fi 7 (802.11be) Technical Guide": "802.3bt (UPOE) is
//     the recommended power input for full operation of Wi-Fi 7 Access
//     Points ... capable of operating at lower power with 802.3at power with
//     reduced functionality."
// Neither guide says what happens on 802.3af. Keith's ruling (2026-09-27):
// the AP "boots but with less Wi-Fi capabilities, like fewer spatial
// streams, or other reductions in capabilities". THE SET IS ILLUSTRATIVE and
// is labeled so on screen and in help ([PhLabels.afIllustrative]): one
// plausible generic set chosen to fit the 12.95 W 802.3af guarantees at the
// AP, 2.4 GHz at 1x1, 5 GHz at 2x2, 6 GHz off, lower transmit power, and the
// USB port and the second Ethernet port off. No per-part wattage is claimed.
// Vendors differ; this is one example.
//
// Which radio goes dark in the "two radios at 4x4" choice: the guide says
// "any two". This model turns off 2.4 GHz and keeps 5 and 6 GHz, a stated
// choice, not a claim about any product.
//
// PORT POWER. IEEE 802.3 figures, the same ones the PoE Reference tool
// shows (a test holds the two equal): the power the switch port sends
// (PSE: power sourcing equipment) and the most the standard guarantees at
// the device after the cable (PD: powered device).
//
// Pure Dart, no Flutter imports. ASCII only, no em dashes (GL-004).

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kPoeHalfStrengthToolId = 'poe-half-strength';

/// The switch port type: the tool's one main control.
enum PhPort {
  af('802.3af', 'PoE', 15.4, 12.95),
  at('802.3at', 'PoE+', 30.0, 25.5),
  bt('802.3bt', 'PoE++', 60.0, 51.0);

  const PhPort(this.standard, this.commonName, this.pseWatts, this.pdWatts);

  /// IEEE designation.
  final String standard;

  /// Common name (PoE, PoE+, PoE++).
  final String commonName;

  /// Power the switch port sends, W.
  final double pseWatts;

  /// Most the standard guarantees at the AP after the cable, W.
  final double pdWatts;

  /// "802.3at (PoE+)"; 802.3bt names its Type 3, the 60 W type.
  String get label => this == PhPort.bt
      ? '$standard Type 3 ($commonName)'
      : '$standard ($commonName)';
}

/// What the AP gives up on an 802.3at port. Both are in the Juniper guide.
enum PhAtMode {
  allAt2x2('All three radios at 2x2', 'three radios at 2x2:2'),
  twoAt4x4('Two radios at 4x4, one off', 'two radios at 4x4:4, 2.4 GHz off');

  const PhAtMode(this.label, this.phrase);
  final String label;
  final String phrase;
}

/// The three radios, in drawing order.
enum PhRadio {
  g24('2.4 GHz'),
  g5('5 GHz'),
  g6('6 GHz');

  const PhRadio(this.label);
  final String label;
}

/// Every UI label that needs a qualifier, in one place; tests hold them.
abstract final class PhLabels {
  static const String afIllustrative =
      'Illustrative: vendors differ; this is one example. The vendor guides '
      'do not say what a Wi-Fi 7 AP does on 802.3af. This model boots with '
      'less: 2.4 GHz at 1x1, 5 GHz at 2x2, 6 GHz off, lower transmit power, '
      'and the USB (Universal Serial Bus) port and second Ethernet port '
      'off, a set chosen to fit '
      'the 12.95 W at the AP. Check your AP\'s data sheet.';
  static const String genericAp =
      'A generic tri-band Wi-Fi 7 AP: three radios, each 4x4, about 29 W for '
      'full function';
  static const String vendorsDiffer =
      'Vendors cut different things at lower power. This AP follows one '
      'published guide; yours may differ.';
}

/// The generic AP and its needs.
abstract final class PhAp {
  /// Streams per radio at full function.
  static const int fullStreams = 4;

  /// Power at the AP for full function, W (Juniper Mist guide, "approximately
  /// 29 Watts").
  static const double fullFunctionWatts = 29;

  static int get maxStreams => fullStreams * PhRadio.values.length;
}

/// One configuration. Immutable.
class PhConfig {
  const PhConfig({this.port = PhPort.at, this.atMode = PhAtMode.allAt2x2});

  /// Default: the case the tool is named for, a new AP on last year's
  /// 802.3at switch.
  final PhPort port;
  final PhAtMode atMode;

  PhConfig withPort(PhPort p) => PhConfig(port: p, atMode: atMode);
  PhConfig withAtMode(PhAtMode m) => PhConfig(port: port, atMode: m);

  /// Streams live on [r] (0 = radio off).
  int streamsOn(PhRadio r) => switch (port) {
    PhPort.bt => PhAp.fullStreams,
    PhPort.at => switch (atMode) {
      PhAtMode.allAt2x2 => 2,
      PhAtMode.twoAt4x4 => r == PhRadio.g24 ? 0 : PhAp.fullStreams,
    },
    // Illustrative (Keith, 2026-09-27): fewer streams, one band off.
    PhPort.af => switch (r) {
      PhRadio.g24 => 1,
      PhRadio.g5 => 2,
      PhRadio.g6 => 0,
    },
  };

  /// What else the AP cuts besides spatial streams. Only the illustrative
  /// 802.3af set cuts anything else; the Juniper guide names only radio
  /// changes on 802.3at.
  List<String> get otherReductions => port == PhPort.af
      ? const <String>[
          'Lower transmit power',
          'USB port off',
          'Second Ethernet port off',
        ]
      : const <String>[];

  int get streamsLive =>
      PhRadio.values.fold<int>(0, (int s, PhRadio r) => s + streamsOn(r));

  int get radiosLive =>
      PhRadio.values.where((PhRadio r) => streamsOn(r) > 0).length;

  /// Share of the AP's spatial streams still live, 0 to 1.
  double get streamShare => streamsLive / PhAp.maxStreams;

  /// Whether the port meets the AP's full-function need.
  bool get fullFunction => port.pdWatts >= PhAp.fullFunctionWatts;

  /// Whether this state rests on an illustrative assumption.
  bool get illustrative => port == PhPort.af;

  /// The power light. On in every case: that is the lesson.
  bool get powerLightOn => true;

  /// "4x4:4", "2x2:2" or "Off".
  String radioState(PhRadio r) {
    final int n = streamsOn(r);
    return n == 0 ? 'Off' : '${n}x$n:$n';
  }

  /// How short of full function the port falls at the AP, W (0 when enough).
  double get shortfallWatts =>
      fullFunction ? 0 : PhAp.fullFunctionWatts - port.pdWatts;

  @override
  bool operator ==(Object other) =>
      other is PhConfig && other.port == port && other.atMode == atMode;

  @override
  int get hashCode => Object.hash(port, atMode);
}

abstract final class PhFormat {
  static String watts(double w) {
    final String s = w.toStringAsFixed(2);
    // 12.95 stays 12.95; 25.50 -> 25.5; 51.00 -> 51.0.
    if (s.endsWith('0')) return '${w.toStringAsFixed(1)} W';
    return '$s W';
  }

  static String percent(double share) => '${(share * 100).round()}%';
}
