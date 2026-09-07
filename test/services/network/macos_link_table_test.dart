// The macOS link table, parsed from the five REAL captures Keith took on
// 2026-08-30. Nothing here is a synthesised fixture.
//
// Deliverables/2026-08-30-ethernet-phase0/ in myPKA; copied into
// test/fixtures/ethernet_phase0/ so the evidence travels with the code.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/macos_link_table.dart';

String fixture(String state) =>
    File('test/fixtures/ethernet_phase0/ethernet-spike-$state.txt')
        .readAsStringSync();

/// Pull one numbered section out of a capture file.
String section(String text, String header) {
  final List<String> lines = text.split('\n');
  final int start = lines.indexWhere((String l) => l.contains(header));
  if (start < 0) return '';
  final int end = lines.indexWhere(
      (String l) => l.startsWith('===== ') && !l.contains(header), start + 1);
  return lines.sublist(start + 1, end < 0 ? lines.length : end).join('\n');
}

LinkTable tableFor(String state, {String? defaultIface}) {
  final String raw = fixture(state);
  return parseMacosLinkTable(
    hardwarePorts: section(raw, 'networksetup -listallhardwareports'),
    ifconfigAll: section(raw, 'ifconfig (all interfaces'),
    defaultRouteInterface: defaultIface,
    defaultGateway: defaultIface == null ? null : '192.168.8.1',
  );
}

LinkInfo? byName(LinkTable t, String name) {
  for (final LinkInfo l in t.links) {
    if (l.name == name) return l;
  }
  return null;
}

void main() {
  group('parseMediaString', () {
    test('the one live format we have actually observed', () {
      final MediaReading m = parseMediaString('autoselect (2500Base-T <full-duplex>)');
      expect(m.speedMbps, 2500);
      expect(m.duplex, 'full');
      expect(m.hasLink, isTrue);
    });

    test('tolerates the case and spacing variance macOS shows across drivers', () {
      expect(parseMediaString('1000baseT <full-duplex>').speedMbps, 1000);
      expect(parseMediaString('100baseTX <half-duplex>').speedMbps, 100);
      expect(parseMediaString('100baseTX <half-duplex>').duplex, 'half');
      expect(parseMediaString('autoselect (1000BASE-T <FULL-DUPLEX>)').speedMbps, 1000);
      expect(parseMediaString('10Gbase-T <full-duplex>').speedMbps, 10000);
    });

    test('no link is recognised in both forms', () {
      expect(parseMediaString('none').hasLink, isFalse);
      expect(parseMediaString('autoselect (none)').hasLink, isFalse);
    });

    test('an UNRECOGNISED string is not treated as no-link', () {
      // Failing toward the honest half: we have seen exactly one live format,
      // so a surprise must mean "speed unknown", never "the cable is out".
      final MediaReading m = parseMediaString('autoselect (SomeFutureThing)');
      expect(m.speedMbps, isNull);
      expect(m.hasLink, isNull, reason: 'says nothing, so status: decides');
    });

    test('a bare autoselect says nothing about link', () {
      // This is what an associated Wi-Fi radio reports.
      expect(parseMediaString('autoselect').hasLink, isNull);
      expect(parseMediaString('autoselect').speedMbps, isNull);
    });
  });

  group('THE TWO TRAPS PHASE 0 MEASURED', () {
    test('IFF_RUNNING lies: en2 is UP and RUNNING with no cable ever in it', () {
      // en2 is named "Ethernet Adapter", is always present, and is permanently
      // inactive. Anything reaching for the conventional BSD carrier flag gets
      // a live-looking interface here.
      final LinkTable t = tableFor('switch-linked', defaultIface: 'en5');
      final LinkInfo en2 = byName(t, 'en2')!;
      expect(en2.operState, 'UP', reason: 'the UP flag IS set');
      expect(en2.carrier, isFalse, reason: 'and it has no carrier at all');
      expect(en2.speedMbps, isNull, reason: 'no speed beside a dead port');
      expect(en2.addresses, isEmpty);
    });

    test('a cable into a DEAD SWITCH is byte-identical to no cable', () {
      // 'switch-dead' is a cable into an unpowered switch; 'nocable' is the
      // adapter with nothing in it. Both read autoselect (none) / inactive.
      final LinkInfo dead = byName(tableFor('switch-dead'), 'en5')!;
      final LinkInfo out = byName(tableFor('nocable'), 'en5')!;
      expect(dead.carrier, isFalse);
      expect(out.carrier, isFalse);
      expect(dead.speedMbps, out.speedMbps);
      expect(dead.duplex, out.duplex);
      // Not a fourth state to model. A genuine limit, and the UI must say
      // "no link" and let the user check both ends.
      expect(dead.addresses.where((LinkAddress a) => !a.isLinkLocal), isEmpty);
    });
  });

  group('the three states, all measured', () {
    test('NO ADAPTER: en5 is absent from the enumeration entirely', () {
      // 'unplugged' is the USB adapter itself removed, not the cable.
      expect(byName(tableFor('unplugged'), 'en5'), isNull,
          reason: 'absent is different from present-and-down');
      // And with the adapter back but no cable, it IS enumerated, down.
      final LinkInfo present = byName(tableFor('nocable'), 'en5')!;
      expect(present.carrier, isFalse);
      expect(present.addresses.where((LinkAddress a) => !a.isLinkLocal), isEmpty);
    });

    test('LINK UP: en5 reports 2500Base-T full duplex and holds the route', () {
      final LinkTable t = tableFor('switch-linked', defaultIface: 'en5');
      final LinkInfo en5 = byName(t, 'en5')!;
      expect(en5.kind, LinkKind.wired);
      expect(en5.carrier, isTrue);
      expect(en5.speedMbps, 2500);
      expect(en5.duplex, 'full');
      expect(en5.isDefaultRouteV4, isTrue);
      expect(
        en5.addresses.any((LinkAddress a) => a.address == '192.168.8.233'),
        isTrue,
      );
    });

    test('Wi-Fi is classified from the hardware port, not from being en0', () {
      final LinkInfo en0 = byName(tableFor('switch-linked'), 'en0')!;
      expect(en0.kind, LinkKind.wifi);
      expect(en0.carrier, isTrue, reason: 'Wi-Fi was up at the same time');
      expect(en0.speedMbps, isNull,
          reason: 'a bare autoselect gives no rate, and none is invented');
    });

    test('the Thunderbolt bridge is virtual, not a wired port', () {
      final LinkInfo? b = byName(tableFor('switch-linked'), 'bridge0');
      expect(b, isNotNull);
      expect(b!.kind, LinkKind.virtual);
    });

    test('awdl0 and utun* have no hardware port and are never wired', () {
      final LinkTable t = tableFor('switch-linked');
      for (final String n in <String>['awdl0', 'llw0', 'utun0']) {
        final LinkInfo? l = byName(t, n);
        if (l == null) continue;
        expect(l.kind, isNot(LinkKind.wired), reason: '$n must not read as wired');
      }
    });
  });

  group('the default route is never guessed', () {
    test('with no route reading, NO interface claims the default route', () {
      final LinkTable t = tableFor('switch-linked');
      expect(t.links.any((LinkInfo l) => l.isDefaultRouteV4), isFalse);
      expect(t.defaultRouteInterfaceV4, isNull);
    });
  });
}
