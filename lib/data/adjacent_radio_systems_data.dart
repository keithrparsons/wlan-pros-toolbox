// Beyond Wi-Fi: The Adjacent Radios - typed const datasets for the read-only
// field/trade reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/
// 12-adjacent-radio-systems.md, SOP-020 PASS): the five 2.4 GHz contenders, the
// ten-system coexistence table, the three corrections, the "which radio when"
// picker, and the framing prose. No copy is rewritten here - the screen only
// lays it out.
//
// GL-005 / truthfulness: the five 2.4 GHz systems, the ten-row coexistence
// table, and the three corrections are the load-bearing facts, so the widget
// test asserts the anchor rows (LoRaWAN sub-GHz / no, Zigbee shares 2.4 GHz,
// CBRS does not interfere) against these consts so a future edit cannot
// silently drift a value away from Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

/// Stable catalog tool id - backs the route, the help entry, the bundled
/// spectrum-matrix plate (assets/reference/adjacent-radio-systems.png), and the
/// tests. Permanent.
const String kAdjacentRadioSystemsToolId = 'adjacent-radio-systems';

/// One row of the coexistence table. [system] is the radio system; [band] is
/// the band it lives in; [range] and [dataRate] are real-world envelopes;
/// [sharesTwoFour] is whether it contends for 2.4 GHz Wi-Fi airtime.
class RadioSystemRow {
  const RadioSystemRow({
    required this.system,
    required this.band,
    required this.range,
    required this.dataRate,
    required this.sharesTwoFour,
  });

  /// The radio system, e.g. `LoRaWAN`.
  final String system;

  /// The band it occupies.
  final String band;

  /// The range envelope.
  final String range;

  /// The data-rate envelope.
  final String dataRate;

  /// Whether it shares 2.4 GHz with Wi-Fi (`Yes` / `No`), verbatim.
  final String sharesTwoFour;
}

/// The ten-system coexistence table, verbatim from the copy.
const List<RadioSystemRow> kRadioSystems = <RadioSystemRow>[
  RadioSystemRow(
    system: 'LoRaWAN',
    band: 'Sub-GHz (US 902-928 / EU 863-870 MHz)',
    range: '2-15 km',
    dataRate: '0.3-50 kbps',
    sharesTwoFour: 'No',
  ),
  RadioSystemRow(
    system: 'Zigbee',
    band: '2.4 GHz (868/915 MHz optional)',
    range: '10-100 m per hop',
    dataRate: '~250 kbps',
    sharesTwoFour: 'Yes',
  ),
  RadioSystemRow(
    system: 'Thread',
    band: '2.4 GHz (802.15.4)',
    range: '10-100 m per hop',
    dataRate: '~250 kbps',
    sharesTwoFour: 'Yes',
  ),
  RadioSystemRow(
    system: 'BLE',
    band: '2.4 GHz',
    range: '10 m to ~1 km (Coded PHY)',
    dataRate: '125 kbps to 2 Mbps',
    sharesTwoFour: 'Yes',
  ),
  RadioSystemRow(
    system: 'Z-Wave',
    band: 'Sub-GHz (US 908.42 / EU 868.42 MHz)',
    range: '30 m to ~400 m (Long Range)',
    dataRate: '9.6-100 kbps',
    sharesTwoFour: 'No',
  ),
  RadioSystemRow(
    system: 'UWB (802.15.4z)',
    band: '3.1-10.6 GHz',
    range: '~50-200 m',
    dataRate: 'ranging, not data',
    sharesTwoFour: 'No',
  ),
  RadioSystemRow(
    system: 'NB-IoT',
    band: 'Licensed cellular',
    range: 'km (deep coverage)',
    dataRate: '20-250 kbps',
    sharesTwoFour: 'No',
  ),
  RadioSystemRow(
    system: 'LTE-M',
    band: 'Licensed cellular',
    range: 'km',
    dataRate: '~1 Mbps',
    sharesTwoFour: 'No',
  ),
  RadioSystemRow(
    system: 'Private 5G / CBRS',
    band: '3.55-3.70 GHz',
    range: 'Campus',
    dataRate: 'Mbps to Gbps',
    sharesTwoFour: 'No',
  ),
  RadioSystemRow(
    system: 'Wi-Fi HaLow (802.11ah)',
    band: 'Sub-GHz (US 902-928 / EU 863-868 MHz)',
    range: '~1 km',
    dataRate: '150 kbps to 78 Mbps',
    sharesTwoFour: 'No',
  ),
];

/// The five systems that share your 2.4 GHz air, verbatim from the copy.
const List<String> kTwoFourContenders = <String>[
  'BLE (2400 to 2483.5 MHz, 40 channels at 2 MHz spacing) and Bluetooth '
      'Classic (same band, 79 channels at 1 MHz spacing), both adaptive '
      'frequency hopping. Wearables, audio, beacons, device onboarding, RTLS, '
      'and BT 5.1 direction finding.',
  'Zigbee (16 channels at 250 kbps, self-healing mesh). Lighting, building '
      'automation, HVAC, sensors.',
  'Thread (the same 802.15.4 PHY, IPv6-native, self-healing mesh). The '
      'transport under most new Matter devices.',
  'ANT+ (an ultra-low-power sensor protocol). Fitness and health telemetry.',
];

/// The three corrections worth carrying, verbatim from the copy.
const List<String> kRadioCorrections = <String>[
  'Matter is not a radio. It is a Connectivity Standards Alliance application '
      'layer that runs over Thread, Wi-Fi, and Ethernet, and is commissioned '
      'over BLE. It has no PHY of its own. When someone asks whether a device '
      'is "Matter or Wi-Fi," the honest answer is that Matter can ride Wi-Fi.',
  '802.15.4 is not 2.4 GHz only. The standard also defines 868 MHz (EU) and '
      '902 to 928 MHz (US) sub-GHz PHYs, and Zigbee has sub-GHz profiles. '
      'Nearly all modern Zigbee, Thread, and Matter gear ships 2.4 GHz, which '
      'is why the coexistence problem is real, but "2.4 only" is wrong.',
  'CBRS and private 5G do not interfere with Wi-Fi. CBRS lives at 3.55 to 3.70 '
      'GHz, which does not overlap any Wi-Fi band. The conflict is over the job '
      'and the budget, not the spectrum: private cellular competes with Wi-Fi '
      'for the enterprise-connectivity use case, and vendors pitch it against '
      'you. It never competes for your air.',
];

/// The "which radio when" picker, verbatim from the copy.
const List<String> kWhichRadioWhen = <String>[
  'Long-range, low-power sensors, no on-site gateway wanted: cellular IoT '
      '(NB-IoT or LTE-M).',
  'Long-range, low-power sensors, and you want to own the network: LoRaWAN.',
  'Wi-Fi-family long range with a higher rate (cameras, IP): Wi-Fi HaLow.',
  'Low-power mesh control (lighting, building automation): Zigbee or Thread '
      '(2.4 GHz, so coordinate) or Z-Wave (sub-GHz, coexistence-clean).',
  'Precise indoor location: UWB (centimeter-level) or BLE angle-of-arrival '
      '(sub-meter); Wi-Fi RSSI and FTM are coarser.',
  'Enterprise-wide deterministic coverage and mobility: private 5G or CBRS, '
      'the one case where you owe the client an honest "Wi-Fi versus cellular" '
      'read.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead.
const String kAdjacentLead =
    'The non-Wi-Fi radios a WLAN pro coexists with, designs around, and gets '
    'asked about. The fact that matters most for your air: five of them (BLE, '
    'Bluetooth Classic, Zigbee, Thread, and ANT+) live in 2.4 GHz and contend '
    'for the exact airtime you are planning. Everything else sits in sub-GHz '
    'or licensed spectrum and does not interfere, which is itself the design '
    'lever.';

/// Lead-in to the five 2.4 GHz contenders, verbatim.
const String kTwoFourIntro =
    'Five systems live in the 2.4 GHz band and steal airtime from your Wi-Fi:';

/// The coordinate-the-plans note under the 2.4 GHz contenders, verbatim.
const String kTwoFourCoordinate =
    'They are low duty cycle, but at scale (hundreds of BLE beacons, a large '
    'Zigbee mesh) they subtract real airtime. 2.4 GHz is a shared commons, not '
    'a Wi-Fi-only band. In a building running a Zigbee lighting mesh, '
    'coordinate the two plans: Zigbee channels 15, 20, 25, and 26 sit in the '
    'gaps around the Wi-Fi 1/6/11 plan. Plan your 2.4 GHz Wi-Fi as if it owns '
    'the band and you have designed half the picture.';

/// Lead-in to the coexistence-clean table, verbatim.
const String kSubGhzIntro =
    'Read the "Shares 2.4 GHz" line first. Zigbee, Thread and BLE sit in the '
    'same 2.4 GHz air as your Wi-Fi and do compete for it. Everything sub-GHz '
    'or licensed is coexistence-clean. That is the design lever: when 2.4 GHz '
    'is congested, the right move is often to push the IoT onto one of the '
    'clean ones rather than fight for airtime.';

/// The envelope caution under the table (rendered as a warning band).
///
/// This used to say "every range, rate, and battery figure". There is no
/// battery figure: [RadioSystemRow] has no battery field and the table renders
/// no battery column. Pointing the reader at a column that does not exist is
/// the same phantom-promise class as a caveat describing a parser the screen
/// does not have. It now names only the columns actually on screen.
const String kEnvelopeWarning =
    'Read every range and rate figure as a real-world envelope, not a hard '
    'spec. They move with power, antenna, spreading factor, channel width, and '
    'environment.';

/// Lead-in to the "which radio when" picker, verbatim.
const String kWhichRadioIntro =
    'A quick read for the "should this be Wi-Fi or something else" question:';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kAdjacentWlanCares =
    'The client increasingly hands you the whole smart-building radio stack, '
    'not just the Wi-Fi. Being the person in the building who knows what '
    'shares the 2.4 GHz air, what runs clean in sub-GHz, and when to talk a '
    'client out of a private-cellular pitch that Wi-Fi already covers, is '
    'authority. It is also self-defense: a Zigbee mesh and a wall of BLE '
    'beacons show up in your 2.4 GHz sweep as non-Wi-Fi energy, and naming '
    'what you are seeing is the difference between a diagnosis and a guess.';

/// The defer footer (rendered as an info band). Verbatim.
const String kAdjacentDeferNote =
    'Reference only. Bands and topologies are stable, but range, data-rate, '
    'and battery figures are real-world envelopes that vary with power, '
    'antenna, spreading factor, channel width, and environment. Confirm '
    'current standards editions and regional band allocations for the specific '
    'deployment.';
