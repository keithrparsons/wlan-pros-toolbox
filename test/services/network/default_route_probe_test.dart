// Default-route probe - parsed against real captured OS output, not invented.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/default_route_probe.dart';

/// Verbatim from `route -n get default` on Keith's M5, 2026-08-30, with the
/// wired link up. Deliverables/2026-08-30-ethernet-phase0/
/// ethernet-spike-switch-linked.txt
const String kMacRouteWired = '''
   route to: default
destination: default
       mask: default
    gateway: 192.168.8.1
  interface: en5
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
 recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
       0         0         0         0         0         0      1500         0
''';

/// Verbatim `ifconfig en5` from the same capture. The netmask is HEX, which is
/// the detail a dotted-quad parser gets wrong silently.
const String kMacIfconfigEn5 = '''
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	options=404<VLAN_MTU,CHANNEL_IO>
	ether 00:e0:4c:99:a3:4e
	inet6 fe80::10a4:9ef6:d926:33db%en5 prefixlen 64 secured scopeid 0x17
	inet 192.168.8.233 netmask 0xffffff00 broadcast 192.168.8.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect (2500Base-T <full-duplex>)
	status: active
''';

const String kLinuxRoute =
    'default via 192.168.8.1 dev eth0 proto dhcp src 192.168.8.176 metric 100 \n';
const String kLinuxAddr =
    '2: eth0    inet 192.168.8.176/24 brd 192.168.8.255 scope global dynamic eth0\n';

ShellRunner canned(Map<String, String> byFirstArg) =>
    (String exe, List<String> args) async {
      for (final MapEntry<String, String> e in byFirstArg.entries) {
        if ('$exe ${args.join(" ")}'.contains(e.key)) return e.value;
      }
      return null;
    };

void main() {
  group('parseNetmask', () {
    test('macOS hex form', () {
      expect(parseNetmask('0xffffff00'), 24);
      expect(parseNetmask('0xffff0000'), 16);
      expect(parseNetmask('0xffffffff'), 32);
      expect(parseNetmask('0x00000000'), 0);
    });

    test('dotted-quad form', () {
      expect(parseNetmask('255.255.255.0'), 24);
      expect(parseNetmask('255.255.254.0'), 23);
    });

    test('bare prefix form', () {
      expect(parseNetmask('24'), 24);
      expect(parseNetmask('0'), 0);
      expect(parseNetmask('33'), isNull);
    });

    test('a NON-CONTIGUOUS mask is null, never a popcount', () {
      // 0xff00ff00 has holes. Counting its bits gives 16, a plausible number
      // describing a network that does not exist.
      expect(parseNetmask('0xff00ff00'), isNull);
      expect(parseNetmask('255.0.255.0'), isNull);
    });

    test('garbage is null', () {
      expect(parseNetmask('nonsense'), isNull);
      expect(parseNetmask(''), isNull);
      expect(parseNetmask('999.1.1.1'), isNull);
    });
  });

  group('DefaultRoute.netmask', () {
    test('renders the dotted quad back', () {
      const DefaultRoute r = DefaultRoute(interfaceName: 'en5', prefixLength: 24);
      expect(r.netmask, '255.255.255.0');
      expect(const DefaultRoute(interfaceName: 'x', prefixLength: 16).netmask,
          '255.255.0.0');
      expect(const DefaultRoute(interfaceName: 'x').netmask, isNull);
    });
  });

  group('macOS', () {
    test('THE DEFECT: the wired link is found, not the one named en0', () async {
      // On 2026-08-30 Keith's Mac held BOTH links. The default route went out
      // en5 at 192.168.8.233; network_info_plus would have answered with en0 at
      // 192.168.8.134, because it matches on the NAME. This is the fix.
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: true,
        isLinux: false,
        isWindows: false,
        runner: canned(<String, String>{
          'route -n get default': kMacRouteWired,
          'ifconfig en5': kMacIfconfigEn5,
        }),
      );
      final DefaultRoute? r = await p.readV4();
      expect(r, isNotNull);
      expect(r!.interfaceName, 'en5');
      expect(r.gateway, '192.168.8.1');
      expect(r.address, '192.168.8.233');
      expect(r.prefixLength, 24, reason: 'parsed from the HEX netmask');
      expect(r.netmask, '255.255.255.0');
    });

    test('a route we cannot read yields null, never a fabricated interface',
        () async {
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: true,
        isLinux: false,
        isWindows: false,
        runner: (String e, List<String> a) async => null,
      );
      expect(await p.readV4(), isNull);
    });

    test('a route with no readable address still names the interface', () async {
      // Knowing WHICH link carries traffic is useful even when its address
      // could not be read. Returning null for the whole thing would throw away
      // the more important half.
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: true,
        isLinux: false,
        isWindows: false,
        runner: canned(<String, String>{'route -n get default': kMacRouteWired}),
      );
      final DefaultRoute? r = await p.readV4();
      expect(r!.interfaceName, 'en5');
      expect(r.address, isNull);
      expect(r.prefixLength, isNull);
    });
  });

  group('Linux', () {
    test('parses the ip-route and ip-addr pair', () async {
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: false,
        isLinux: true,
        isWindows: false,
        runner: canned(<String, String>{
          'route show default': kLinuxRoute,
          'addr show dev eth0': kLinuxAddr,
        }),
      );
      final DefaultRoute? r = await p.readV4();
      expect(r!.interfaceName, 'eth0');
      expect(r.gateway, '192.168.8.1');
      expect(r.address, '192.168.8.176');
      expect(r.prefixLength, 24);
    });
  });

  group('platforms that cannot be asked', () {
    test('iOS, Android and web return null, and null means "cannot tell"',
        () async {
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: false,
        isLinux: false,
        isWindows: false,
        runner: (String e, List<String> a) async => 'should never be called',
      );
      expect(await p.readV4(), isNull);
    });
  });

  group('Windows', () {
    test('UNVERIFIED path fails CLOSED on unparseable output', () async {
      // No Windows evidence exists yet. The requirement is that a surprise
      // never invents an interface name.
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: false,
        isLinux: false,
        isWindows: true,
        runner: (String e, List<String> a) async => 'unexpected shape',
      );
      expect(await p.readV4(), isNull);
    });

    test('parses the tab-separated shape it asks PowerShell for', () async {
      final DefaultRouteProbe p = DefaultRouteProbe(
        isMacOS: false,
        isLinux: false,
        isWindows: true,
        runner: (String e, List<String> a) async =>
            'Ethernet\t192.168.8.1\t192.168.8.50\t24\n',
      );
      final DefaultRoute? r = await p.readV4();
      expect(r!.interfaceName, 'Ethernet');
      expect(r.address, '192.168.8.50');
      expect(r.prefixLength, 24);
    });
  });
}
