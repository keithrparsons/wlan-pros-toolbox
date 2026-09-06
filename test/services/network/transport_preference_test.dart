// The app-wide transport choice: storage, resolution, and what CurrentNetwork
// does with it.
//
// Keith ruled the shape on 2026-09-01: "I agree the transport chooser should be
// app-wide." One choice, every tool honours it, one place it is applied.
//
// THE TESTS THAT MATTER MOST ARE THE ONES WHERE THE CHOICE CANNOT BE HONOURED.
// Falling back to the routing table is correct; falling back SILENTLY is the
// defect, because a screen would then show numbers for a link the user did not
// pick and say nothing about it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/macos_link_table.dart';
import 'package:wlan_pros_toolbox/services/network/transport_chooser.dart';
import 'package:wlan_pros_toolbox/services/network/transport_preference.dart';

/// The live multi-homed capture Keith took on 2026-09-01 in the cabin: Wi-Fi on
/// en0 at .134, a wired link on en5 at .234, and THE DEFAULT ROUTE ON en5.
/// This is the `en0` defect in the flesh and it is the only fixture that has
/// both links up at once.
String get multihomed => File(
        'test/fixtures/ethernet_phase0/multihomed-2026-09-01-en5-default.txt')
    .readAsStringSync();

String block(String text, String header) {
  final List<String> lines = text.split('\n');
  final int start = lines.indexWhere((String l) => l.contains(header));
  if (start < 0) return '';
  final int end = lines.indexWhere(
      (String l) => l.startsWith('=== ') && !l.contains(header), start + 1);
  return lines.sublist(start + 1, end < 0 ? lines.length : end).join('\n');
}

LinkTable get liveTable => parseMacosLinkTable(
      hardwarePorts: block(multihomed, 'networksetup -listnetworkserviceorder'),
      ifconfigAll: block(multihomed, 'ifconfig'),
      defaultRouteInterface: 'en5',
      defaultGateway: '192.168.8.1',
    );

TransportOption opt(TransportKind k, TransportState s,
        {LinkInfo? link, String reason = ''}) =>
    TransportOption(
        kind: k,
        state: s,
        reason: reason,
        // The helper's callers care about resolution, not copy. A fixed
        // non-empty stand-in keeps them honest against the never-empty
        // guarantee without making every case restate a string it does not
        // exercise.
        shortReason: reason.isEmpty ? 'No detail.' : reason,
        link: link,
      );

void main() {
  group('TransportPreference storage', () {
    test('nothing stored reads as null, which is "let the OS decide"', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await TransportPreference().read(), isNull);
    });

    test('a written kind round-trips', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final TransportPreference p = TransportPreference();
      expect(await p.write(TransportKind.ethernet), isTrue);
      expect(await p.read(), TransportKind.ethernet);
    });

    test('writing null clears it', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{TransportPreference.prefsKey: 'ethernet'});
      final TransportPreference p = TransportPreference();
      await p.write(null);
      expect(await p.read(), isNull);
    });

    test('an unrecognised stored value reads as null rather than guessing',
        () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{TransportPreference.prefsKey: 'quantum'});
      expect(await TransportPreference().read(), isNull);
    });
  });

  group('resolveTransport', () {
    final LinkInfo eth = liveTable.links.firstWhere((LinkInfo l) => l.name == 'en5');
    final LinkInfo wifi = liveTable.links.firstWhere((LinkInfo l) => l.name == 'en0');

    test('no choice means followingSystem, and that is not a degraded state', () {
      final ResolvedTransport r = resolveTransport(
          chosen: null, options: const <TransportOption>[], activeLink: wifi);
      expect(r.resolution, TransportResolution.followingSystem);
      expect(r.isStale, isFalse);
      expect(r.link, wifi);
    });

    test('a choosable choice is honoured and returns ITS link', () {
      final ResolvedTransport r = resolveTransport(
        chosen: TransportKind.ethernet,
        options: <TransportOption>[
          opt(TransportKind.ethernet, TransportState.active, link: eth),
        ],
        activeLink: wifi,
      );
      expect(r.isHonoured, isTrue);
      expect(r.link, eth);
      expect(r.isStale, isFalse);
    });

    test('a kind absent from the options is unavailable, NOT silently ignored',
        () {
      final ResolvedTransport r = resolveTransport(
        chosen: TransportKind.cellular,
        options: <TransportOption>[
          opt(TransportKind.ethernet, TransportState.active, link: eth),
        ],
        activeLink: wifi,
      );
      expect(r.resolution, TransportResolution.chosenUnavailable);
      expect(r.isStale, isTrue);
      expect(r.link, wifi, reason: 'still usable: the fallback is never nothing');
    });

    test('a refusal and an unanswered question are DIFFERENT resolutions', () {
      final ResolvedTransport refused = resolveTransport(
        chosen: TransportKind.ethernet,
        options: <TransportOption>[
          opt(TransportKind.ethernet, TransportState.presentNotSelectable,
              link: eth, reason: 'iOS will not let an app pin traffic.'),
        ],
        activeLink: wifi,
      );
      final ResolvedTransport untested = resolveTransport(
        chosen: TransportKind.ethernet,
        options: <TransportOption>[
          opt(TransportKind.ethernet, TransportState.presentUntested,
              link: eth, reason: 'Not established on this machine.'),
        ],
        activeLink: wifi,
      );
      expect(refused.resolution, TransportResolution.chosenNotSelectable);
      expect(untested.resolution, TransportResolution.chosenUntested);
      expect(refused.resolution, isNot(untested.resolution),
          reason: 'showing them identically is the two-kinds-of-null error');
    });

    test("the chooser's own reason is carried through, never rewritten", () {
      const String words = 'The cable is out.';
      final ResolvedTransport r = resolveTransport(
        chosen: TransportKind.ethernet,
        options: <TransportOption>[
          opt(TransportKind.ethernet, TransportState.presentNoLink,
              link: eth, reason: words),
        ],
        activeLink: wifi,
      );
      expect(r.reason, words);
    });
  });

  group('CurrentNetwork honours the choice, on Keith\'s live capture', () {
    test('the fixture really is multi-homed with the route on the WIRED link',
        () {
      final LinkTable t = liveTable;
      final LinkInfo en0 = t.links.firstWhere((LinkInfo l) => l.name == 'en0');
      final LinkInfo en5 = t.links.firstWhere((LinkInfo l) => l.name == 'en5');
      expect(en0.addresses.any((LinkAddress a) => a.address == '192.168.8.134'),
          isTrue);
      expect(en5.addresses.any((LinkAddress a) => a.address == '192.168.8.234'),
          isTrue);
      expect(t.primary?.name, 'en5',
          reason: 'the default route is on the cable, not on Wi-Fi');
    });

    test('no preference supplied leaves transport null and behaviour unchanged',
        () async {
      final NetworkSuggestion s = await CurrentNetwork(
        reader: () async =>
            (ip: '192.168.8.234', mask: '255.255.255.0', gateway: '192.168.8.1'),
      ).suggest();
      expect(s.transport, isNull,
          reason: 'null means this path never consulted a preference');
      expect(s.transportIgnored, isFalse);
      expect(s.transportWarning, isNull);
      expect(s.cidr, '192.168.8.0/24');
    });
  });

  group('the warning is never empty when the choice is not honoured', () {
    for (final TransportState state in <TransportState>[
      TransportState.presentNoLink,
      TransportState.presentNotSelectable,
      TransportState.presentUntested,
      TransportState.absent,
    ]) {
      test('$state produces a non-empty warning', () {
        final ResolvedTransport r = resolveTransport(
          chosen: TransportKind.ethernet,
          options: <TransportOption>[
            opt(TransportKind.ethernet, state, reason: 'because.'),
          ],
          activeLink: null,
        );
        final NetworkSuggestion s = NetworkSuggestion(
          cidr: '10.0.0.0/24',
          gatewayIp: null,
          deviceIp: '10.0.0.5',
          maskWasReal: true,
          transport: r,
        );
        expect(s.transportIgnored, isTrue);
        expect(s.transportWarning, isNotNull);
        expect(s.transportWarning, isNotEmpty);
      });
    }
  });

  group('measurementAttribution (Keith 2026-09-06: name the transport)', () {
    // "Nothing names which transport a result used. Now that a user can choose
    // one, this matters." A number with no named subject is a number the reader
    // cannot act on.

    test('on Wi-Fi names the network AND the interface when both are known', () {
      expect(
        measurementAttribution(
          notOnWifi: false,
          interfaceName: 'en0',
          ssid: 'KeithNet',
        ),
        'Measured over Wi-Fi: KeithNet (en0).',
      );
    });

    test('degrades one field at a time rather than inventing either', () {
      expect(
        measurementAttribution(notOnWifi: false, ssid: 'KeithNet'),
        'Measured over Wi-Fi: KeithNet.',
      );
      expect(
        measurementAttribution(notOnWifi: false, interfaceName: 'en0'),
        'Measured over Wi-Fi (en0).',
      );
      expect(measurementAttribution(notOnWifi: false), 'Measured over Wi-Fi.');
    });

    test('off Wi-Fi never claims a Wi-Fi measurement', () {
      expect(
        measurementAttribution(notOnWifi: true, interfaceName: 'en5'),
        'Measured over en5, not Wi-Fi.',
      );
      expect(
        measurementAttribution(notOnWifi: true),
        'Measured over your wired or cellular connection, not Wi-Fi.',
      );
      // And it must not leak an SSID that belongs to a link the test did not use.
      expect(
        measurementAttribution(
          notOnWifi: true,
          interfaceName: 'en5',
          ssid: 'KeithNet',
        ),
        isNot(contains('KeithNet')),
      );
    });

    test('blank and whitespace-only fields are treated as absent', () {
      expect(
        measurementAttribution(notOnWifi: false, ssid: '   ', interfaceName: ''),
        'Measured over Wi-Fi.',
      );
    });

    test('no em dash, per GL-004: this is user-facing product copy', () {
      final List<String> all = <String>[
        measurementAttribution(
            notOnWifi: false, ssid: 'KeithNet', interfaceName: 'en0'),
        measurementAttribution(notOnWifi: false),
        measurementAttribution(notOnWifi: true, interfaceName: 'en5'),
        measurementAttribution(notOnWifi: true),
      ];
      for (final String s in all) {
        expect(s.contains('\u2014'), isFalse, reason: 'em dash in: $s');
        expect(s.contains('\u2013'), isFalse, reason: 'en dash in: $s');
      }
    });
  });
}
