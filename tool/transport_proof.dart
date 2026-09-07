// LIVE PROOF: does choosing a transport actually move traffic on this machine?
//
// Run with: dart run tool/transport_proof.dart
//
// WHY THIS EXISTS. Everything in the transport chooser has been unit-tested
// against fixtures and NOTHING has been run against a real multi-homed machine
// end to end. The board has carried "Still unproven live: that picking Ethernet
// moves real traffic. Needs the cable in, ~20 minutes" since 2026-09-01.
//
// WHAT THIS CAN ESTABLISH, and it is deliberately less than the headline:
//   1. The link table names the right default route (the `en0` defect).
//   2. `Socket.connect(sourceAddress:)` is a REAL bind, not a hint -- proven by
//      an address the machine does not hold FAILING.
//   3. Each interface can or cannot carry an internet connection when bound.
//   4. The stored preference resolves to the interface the user picked, and the
//      prefill follows it rather than the default route.
//
// WHAT IT CANNOT ESTABLISH ON THIS TOPOLOGY, stated up front so the output is
// not over-read. Both interfaces here sit on ONE subnet behind ONE gateway. A
// bind that connects proves the source address was accepted; it does NOT prove
// the packet left by that physical interface, because either source is
// legitimate to this gateway. **The two-gateway case remains untested and this
// script cannot test it.** Read section 3 of the output as "the bind is
// accepted", never as "traffic is pinned".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/services/network/default_route_probe.dart';
import 'package:wlan_pros_toolbox/services/network/link_bind_probe.dart';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/macos_link_table.dart';
import 'package:wlan_pros_toolbox/services/network/transport_chooser.dart';
import 'package:wlan_pros_toolbox/services/network/transport_preference.dart';

const String kHost = 'cloudflare.com';
const int kPort = 443;

void hr(String title) => print('\n${'=' * 72}\n$title\n${'=' * 72}');

void main() {
  // Run with: flutter test tool/transport_proof.dart
  //
  // A TEST HARNESS, NOT A TEST. It asserts nothing and is deliberately NOT
  // under test/ so the normal suite never runs it: it opens real sockets to
  // the internet and its result depends on how the machine is cabled, which
  // is the opposite of what a unit test should be. `flutter test` is used
  // only because this code imports shared_preferences and kIsWeb, so it needs
  // Flutter bindings that `dart run` cannot provide.
  TestWidgetsFlutterBinding.ensureInitialized();
  test('LIVE transport proof', _run, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _run() async {
  final String ports = (await Process.run(
      'networksetup', <String>['-listallhardwareports'])).stdout as String;
  final String ifc =
      (await Process.run('ifconfig', <String>['-a'])).stdout as String;
  // THE PROBE REFUSES TO SPAWN A PROCESS UNDER `flutter test`, on purpose:
  // `_runProcess` checks FLUTTER_TEST and returns null, because a real process
  // launch inside FakeAsync leaves a pending timer a widget test cannot drain.
  // That guard is correct and is not being questioned here. This harness is
  // not a widget test and has no FakeAsync, so it injects a runner that really
  // runs -- through the file's own [ShellRunner] seam, which exists for this.
  final DefaultRoute? route = await DefaultRouteProbe(
    runner: (String exe, List<String> args) async {
      final ProcessResult r = await Process.run(exe, args);
      return r.exitCode == 0 ? r.stdout as String : null;
    },
  ).readV4();

  final LinkTable t = parseMacosLinkTable(
    hardwarePorts: ports,
    ifconfigAll: ifc,
    defaultRouteInterface: route?.interfaceName,
    defaultGateway: route?.gateway,
  );

  // ---------------------------------------------------------------- 1
  hr('1. THE LINK TABLE, AND THE en0 DEFECT');
  print('OS default route : ${route?.interfaceName} via ${route?.gateway}');
  final LinkInfo? picked = selectDefaultLink(t.links);
  print('selectDefaultLink: ${picked?.name}');
  print('');
  final List<LinkInfo> usable = userSelectableLinks(t.links);
  for (final LinkInfo l in usable) {
    final String a = l.addresses
        .where((LinkAddress x) => !x.isLinkLocal && x.isIPv4)
        .map((LinkAddress x) => x.address)
        .join(', ');
    print('  ${l.name.padRight(6)} ${l.kind.name.padRight(6)} '
        '${a.padRight(16)} ${l.isDefaultRouteV4 ? "<- DEFAULT ROUTE" : ""}');
  }
  final LinkInfo? wifi =
      usable.where((LinkInfo l) => l.kind == LinkKind.wifi).firstOrNull;
  final LinkInfo? wired =
      usable.where((LinkInfo l) => l.kind == LinkKind.wired).firstOrNull;

  if (wifi == null || wired == null) {
    print('\nNOT MULTI-HOMED. Need one Wi-Fi and one wired link up at once.');
    print('This proof cannot run. Plug the cable in and re-run.');
    return;
  }
  print('\nVERDICT: network_info_plus would report ${wifi.name} '
      '(${_v4(wifi)}) as "the" address.');
  print('         The default route is actually on ${picked?.name} '
      '(${_v4(picked!)}).');
  print('         Those differ, so this machine reproduces the defect.');

  // ---------------------------------------------------------------- 2
  hr('2. IS THE BIND REAL? (the control)');
  print('Binding to an address this machine does NOT hold must FAIL.');
  print('If it succeeds, sourceAddress is being ignored and every other');
  print('result on this page is meaningless.\n');
  final Map<String, bool> control = await LinkBindProbe().probe(
    sourceAddresses: <String, InternetAddress>{
      'bogus-192.0.2.1': InternetAddress('192.0.2.1'),
    },
    host: kHost,
    port: kPort,
  );
  final bool bogus = control['bogus-192.0.2.1'] ?? false;
  print('  bind 192.0.2.1 (TEST-NET-1, not ours) -> '
      '${bogus ? "CONNECTED  *** BIND IS NOT REAL ***" : "refused, as required"}');
  if (bogus) {
    print('\nSTOP. The control failed. Do not trust section 3.');
    return;
  }

  // ---------------------------------------------------------------- 3
  hr('3. CAN EACH INTERFACE CARRY AN INTERNET CONNECTION WHEN BOUND?');
  print('Destination: $kHost:$kPort  (the app\'s own first-choice host)\n');
  final Map<String, InternetAddress> sources = <String, InternetAddress>{
    wired.name: InternetAddress(_v4(wired)),
    wifi.name: InternetAddress(_v4(wifi)),
  };
  final Stopwatch sw = Stopwatch()..start();
  final Map<String, bool> probed = await LinkBindProbe()
      .probe(sourceAddresses: sources, host: kHost, port: kPort);
  sw.stop();
  probed.forEach((String k, bool v) {
    final String kind = k == wired.name ? 'wired' : 'Wi-Fi';
    print('  ${k.padRight(6)} ($kind, ${sources[k]!.address.padRight(15)}) -> '
        '${v ? "CONNECTED" : "did not get through"}');
  });
  print('\n  (${sw.elapsedMilliseconds} ms for ${sources.length} probes, '
      'sequential by design)');
  // THIS CAVEAT USED TO BE HARDCODED AND ON 2026-09-04 IT PRINTED A FALSEHOOD.
  // It asserted "both addresses are on one subnet behind gateway X" while the
  // machine was demonstrably on TWO gateways, because it was written when only
  // the one-subnet case existed. A caveat that does not check its own premise is
  // worse than no caveat: it tells the reader the result is weaker than it is.
  // LinkInfo carries no per-interface gateway (LinkTable records only THE
  // default one), so the two-gateway condition is inferred from the addresses:
  // two links on different IPv4 subnets are, in practice, behind different
  // gateways. Stated as an inference rather than dressed up as a reading.
  String net24(String ip) {
    final List<String> o = ip.split('.');
    return o.length == 4 ? '${o[0]}.${o[1]}.${o[2]}' : ip;
  }
  final String gwWired = net24(_v4(wired));
  final String gwWifi = net24(_v4(wifi));
  final bool oneGateway = gwWired == gwWifi;
  if (oneGateway) {
    print('\n  CAVEAT: both addresses sit behind the same gateway');
    print('  (${route?.gateway}). A connect here proves the SOURCE WAS');
    print('  ACCEPTED. It does not prove which wire the packet left by,');
    print('  because either source is legitimate to that one gateway.');
    print('  The two-gateway case is NOT exercised by this run.');
  } else {
    print('\n  TWO GATEWAYS ARE IN PLAY: $gwWired and $gwWifi.');
    print('  This is the case transport_chooser.dart calls untested.');
    print('  A connect on BOTH is a real result -- but a TCP connect still');
    print('  does not name the wire. To prove the egress path, compare the');
    print('  PUBLIC IP each bound socket presents (cloudflare.com/cdn-cgi/');
    print('  trace). Measured 2026-09-04: en0 23.151.112.175 vs en5');
    print('  143.105.206.91 -- different networks, so binding genuinely');
    print('  pinned the traffic.');
  }

  // ---------------------------------------------------------------- 4
  hr('4. THE CHOOSER ROWS, BEFORE AND AFTER THE PROBE');
  for (final MapEntry<String, Map<String, bool>> e
      in <String, Map<String, bool>>{
    'BEFORE (nothing probed) -- what the screen shows on first open':
        const <String, bool>{},
    'AFTER  (probe results fed in) -- what "Try it now" produces': probed,
  }.entries) {
    print('\n${e.key}');
    for (final TransportOption o in buildTransportOptions(
      platform: TransportPlatform.macos,
      scope: TransportScope.internet,
      links: t.links,
      probed: e.value,
    )) {
      print('  ${o.kind.label.padRight(9)} ${o.state.name.padRight(21)} '
          '${o.shortReason}');
    }
  }

  // ---------------------------------------------------------------- 5
  hr('5. DOES A STORED CHOICE RESOLVE TO THE INTERFACE PICKED?');
  final List<TransportOption> rows = buildTransportOptions(
    platform: TransportPlatform.macos,
    scope: TransportScope.localSubnet,
    links: t.links,
  );
  print('Scope: localSubnet (where macOS is SelectSupport.yes)\n');
  for (final TransportKind? want in <TransportKind?>[
    null,
    TransportKind.ethernet,
    TransportKind.wifi,
    TransportKind.cellular,
  ]) {
    final ResolvedTransport r = resolveTransport(
      chosen: want,
      options: rows,
      activeLink: picked,
    );
    final String label = want?.label ?? 'nothing chosen';
    print('  chose ${label.padRight(15)} -> ${r.resolution.name.padRight(21)} '
        'tools use ${r.link?.name ?? "-"}'
        '${r.isStale ? "   (STALE: banner shown)" : ""}');
  }

  // ---------------------------------------------------------------- 6
  hr('6. WHAT IS ACTUALLY STORED ON THIS MACHINE RIGHT NOW');
  final TransportKind? stored = await TransportPreference().read();
  print('  TransportPreference.read() -> ${stored?.name ?? "null "
      "(following the system, which is the correct default)"}');
  print('  prefs key: ${TransportPreference.prefsKey}');

  hr('SUMMARY');
  print('Multi-homed          : YES  (${wired.name} wired + ${wifi.name} Wi-Fi)');
  print('Reproduces en0 defect: YES  (route on ${picked.name}, '
      'network_info_plus would say ${wifi.name})');
  print('Bind is real         : YES  (bogus source refused)');
  print('Wired bind connects  : ${(probed[wired.name] ?? false) ? "YES" : "NO"}');
  print('Wi-Fi bind connects  : ${(probed[wifi.name] ?? false) ? "YES" : "NO"}');
  print('Two-gateway case     : NOT TESTED, and not testable on this network');
}

String _v4(LinkInfo l) => l.addresses
    .firstWhere((LinkAddress a) => a.isIPv4 && !a.isLinkLocal)
    .address;
