import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';

void main() {
  final ToolCategory networking = kToolCategories.firstWhere(
    (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == 'port-scan'),
  );

  test('the tile sits in Networking Tools, Discovery & Scanning', () {
    final ToolEntry tile = networking.tools.firstWhere(
      (ToolEntry t) => t.id == 'egress-check',
    );
    expect(tile.title, 'What This Network Lets Out');
    expect(tile.isLive, isTrue);
    expect(tile.subgroup, 'Discovery & Scanning');
    expect(tile.routeName, '/tools/egress-check');
  });

  test('the tile follows Port Scan', () {
    final List<String> ids = networking.tools
        .map((ToolEntry t) => t.id)
        .toList();
    expect(ids.indexOf('egress-check'), ids.indexOf('port-scan') + 1);
  });

  test('the route is registered', () {
    expect(AppRouter.routes, contains('/tools/egress-check'));
  });

  test('a browser has no raw sockets, so the web build hides it', () {
    expect(kWebUnavailableToolIds, contains('egress-check'));
  });
}
