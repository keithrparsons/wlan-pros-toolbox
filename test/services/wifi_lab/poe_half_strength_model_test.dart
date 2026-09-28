// Teaching claims of "PoE: Why the New AP Runs at Half Strength"
// (poe-half-strength), pinned against the model.
//
// Claims (research brief candidate 10; Juniper Mist Wi-Fi 7 AP guide; Cisco
// Meraki Wi-Fi 7 Technical Guide; IEEE 802.3):
//   1. 802.3bt meets the about 29 W full-function need: 12 of 12 streams.
//   2. 802.3at falls short: three radios at 2x2 (6 of 12, half) or two
//      radios at 4x4 (8 of 12), the two choices in the guide.
//   3. The power light is on in every case.
//   4. 802.3af boots with a reduced set (Keith, 2026-09-27); the set is
//      illustrative, and flagged so.
//   5. Port watts equal the PoE Reference tool's (one set of numbers).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/poe_half_strength_model.dart';

void main() {
  test('the generic AP: three radios, 4x4 each, about 29 W', () {
    expect(PhRadio.values, hasLength(3));
    expect(PhAp.fullStreams, 4);
    expect(PhAp.maxStreams, 12);
    expect(PhAp.fullFunctionWatts, 29);
  });

  test('802.3bt: full function, every radio 4x4:4, 12 of 12', () {
    const PhConfig c = PhConfig(port: PhPort.bt);
    expect(c.fullFunction, isTrue);
    expect(c.streamsLive, 12);
    expect(c.radiosLive, 3);
    for (final PhRadio r in PhRadio.values) {
      expect(c.radioState(r), '4x4:4');
    }
    expect(c.shortfallWatts, 0);
    expect(c.illustrative, isFalse);
  });

  test('802.3at, three radios at 2x2: half strength, 6 of 12', () {
    const PhConfig c = PhConfig(port: PhPort.at);
    expect(c.atMode, PhAtMode.allAt2x2, reason: 'the default');
    expect(c.fullFunction, isFalse);
    expect(c.streamsLive, 6);
    expect(c.streamShare, 0.5);
    expect(c.radiosLive, 3);
    for (final PhRadio r in PhRadio.values) {
      expect(c.radioState(r), '2x2:2');
    }
    expect(c.shortfallWatts, closeTo(3.5, 1e-9));
  });

  test('802.3at, two radios at 4x4: 8 of 12, 2.4 GHz off', () {
    const PhConfig c = PhConfig(port: PhPort.at, atMode: PhAtMode.twoAt4x4);
    expect(c.streamsLive, 8);
    expect(c.radiosLive, 2);
    expect(c.radioState(PhRadio.g24), 'Off');
    expect(c.radioState(PhRadio.g5), '4x4:4');
    expect(c.radioState(PhRadio.g6), '4x4:4');
  });

  test('the 802.3at choice changes nothing on the other ports', () {
    for (final PhPort p in <PhPort>[PhPort.af, PhPort.bt]) {
      expect(
        PhConfig(port: p).streamsLive,
        PhConfig(port: p, atMode: PhAtMode.twoAt4x4).streamsLive,
      );
    }
  });

  // Keith, 2026-09-27: on 802.3af the AP "boots but with less Wi-Fi
  // capabilities, like fewer spatial streams, or other reductions in
  // capabilities". The set below is one illustrative example.
  test('802.3af: illustrative, flagged, a reduced set that still runs '
      'Wi-Fi', () {
    const PhConfig c = PhConfig(port: PhPort.af);
    expect(c.illustrative, isTrue);
    expect(c.radioState(PhRadio.g24), '1x1:1');
    expect(c.radioState(PhRadio.g5), '2x2:2');
    expect(c.radioState(PhRadio.g6), 'Off');
    expect(c.streamsLive, 3);
    expect(c.radiosLive, 2);
    expect(c.otherReductions, <String>[
      'Lower transmit power',
      'USB port off',
      'Second Ethernet port off',
    ]);
    expect(PhLabels.afIllustrative, startsWith('Illustrative'));
    expect(PhLabels.afIllustrative, contains('802.3af'));
    expect(PhLabels.afIllustrative, contains('vendors differ'));
    expect(PhLabels.afIllustrative, contains('this is one example'));
    expect(PhLabels.afIllustrative, contains('12.95 W'));
  });

  test('802.3af runs fewer streams than either 802.3at choice, and the '
      'other ports cut nothing else', () {
    for (final PhAtMode m in PhAtMode.values) {
      expect(
        const PhConfig(port: PhPort.af).streamsLive,
        lessThan(PhConfig(port: PhPort.at, atMode: m).streamsLive),
      );
      expect(PhConfig(port: PhPort.at, atMode: m).otherReductions, isEmpty);
    }
    expect(const PhConfig(port: PhPort.bt).otherReductions, isEmpty);
  });

  test('the power light is on in every case', () {
    for (final PhPort p in PhPort.values) {
      for (final PhAtMode m in PhAtMode.values) {
        expect(PhConfig(port: p, atMode: m).powerLightOn, isTrue);
      }
    }
  });

  test('more power never means fewer streams', () {
    for (final PhAtMode m in PhAtMode.values) {
      final List<int> s = <int>[
        for (final PhPort p in PhPort.values)
          PhConfig(port: p, atMode: m).streamsLive,
      ];
      expect(s, orderedEquals(<int>[...s]..sort()));
    }
    // Only a port that meets the need gives full function.
    for (final PhPort p in PhPort.values) {
      expect(
        PhConfig(port: p).fullFunction,
        p.pdWatts >= PhAp.fullFunctionWatts,
      );
    }
  });

  test('port watts are the PoE Reference tool\'s, one set of numbers', () {
    for (final PhPort p in PhPort.values) {
      final String key = p == PhPort.bt ? '802.3bt Type 3' : p.standard;
      final PoeStandard ref = PoeReferenceScreen.standards.firstWhere(
        (PoeStandard s) => s.standard == key,
      );
      expect(p.pseWatts, ref.pseWatts, reason: key);
      expect(p.pdWatts, ref.pdWatts, reason: key);
      expect(ref.name, startsWith(p.commonName), reason: key);
    }
  });

  test('watts format', () {
    expect(PhFormat.watts(12.95), '12.95 W');
    expect(PhFormat.watts(25.5), '25.5 W');
    expect(PhFormat.watts(51), '51.0 W');
    expect(PhFormat.watts(3.5), '3.5 W');
    expect(PhFormat.percent(0.5), '50%');
  });
}
