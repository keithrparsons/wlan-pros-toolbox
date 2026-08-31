// Live check: parse THIS machine's link table and print it.
// Run with: dart run tool/link_table_check.dart
import 'dart:io';
import 'package:wlan_pros_toolbox/services/network/link_info.dart';
import 'package:wlan_pros_toolbox/services/network/macos_link_table.dart';
import 'package:wlan_pros_toolbox/services/network/default_route_probe.dart';
import 'package:wlan_pros_toolbox/services/network/transport_chooser.dart';

Future<void> main() async {
  final String ports =
      (await Process.run('networksetup', <String>['-listallhardwareports'])).stdout as String;
  final String ifc = (await Process.run('ifconfig', <String>['-a'])).stdout as String;
  final DefaultRoute? route = await DefaultRouteProbe().readV4();

  final LinkTable t = parseMacosLinkTable(
    hardwarePorts: ports,
    ifconfigAll: ifc,
    defaultRouteInterface: route?.interfaceName,
    defaultGateway: route?.gateway,
  );

  print('default route: ${route?.interfaceName} via ${route?.gateway} '
      '(${route?.address}/${route?.prefixLength})\n');
  print('name      kind      carrier  speed  duplex  route  addresses');
  print('-' * 76);
  for (final LinkInfo l in t.links) {
    if (l.kind == LinkKind.virtual && l.addresses.isEmpty) continue;
    final String a = l.addresses
        .where((LinkAddress x) => !x.isLinkLocal)
        .map((LinkAddress x) => x.address)
        .join(', ');
    print('${l.name.padRight(9)} ${l.kind.name.padRight(9)} '
        '${(l.carrier?.toString() ?? "?").padRight(8)} '
        '${(l.speedMbps?.toString() ?? "-").padRight(6)} '
        '${(l.duplex ?? "-").padRight(7)} '
        '${(l.isDefaultRouteV4 ? "YES" : "").padRight(6)} $a');
  }

  print('\nselectDefaultLink -> ${selectDefaultLink(t.links)?.name}');
  print('\nchooser rows (macOS, internet scope, nothing probed yet):');
  for (final TransportOption o in buildTransportOptions(
      platform: TransportPlatform.macos,
      scope: TransportScope.internet,
      links: t.links)) {
    print('  ${o.kind.label.padRight(9)} ${o.state.name.padRight(22)} ${o.reason}');
  }
}
