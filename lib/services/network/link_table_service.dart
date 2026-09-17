// One link table, from whichever source on this platform can actually tell us.
//
// PHASE 0's CONCLUSION, IMPLEMENTED: the platform layer is a CAPABILITY
// boundary, not a parsing one. Linux hands over carrier, speed_mbps, duplex and
// is_default_route_v4 as typed fields; macOS makes us reconstruct all four from
// three commands. So the Linux path is the SHORTEST here, not the longest, and
// nothing forces Linux down to the weaker macOS shape.
//
// EVERY PLATFORM THAT CANNOT ANSWER SAYS WHY, in words a user can act on. An
// empty screen with no explanation is the defect this app has already paid for
// twice: once when a cellular iPhone showed a silent live-Wi-Fi surface, and
// again on the wired path, which is still open today.

import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'default_route_probe.dart';
import 'link_info.dart';
import 'macos_link_table.dart';
import 'pi_backend.dart';
import 'pi_backend_client.dart';

/// What came back, or why nothing did.
class LinkTableResult {
  const LinkTableResult.ok(this.table)
    : unavailableReason = null,
      source = null;

  const LinkTableResult.unavailable(this.unavailableReason, {this.source})
    : table = null;

  final LinkTable? table;

  /// Plain words. NEVER null when [table] is null, and never a bare
  /// "unavailable": the reason has to tell the user what would change it.
  final String? unavailableReason;

  final String? source;

  bool get hasTable => table != null;
}

typedef ProcessRunner = Future<String?> Function(String exe, List<String> args);

Future<String?> _runProcess(String exe, List<String> args) async {
  // Same guard as DefaultRouteProbe: a real process launch inside a widget
  // test's FakeAsync leaves a timer the test cannot drain, and this now runs
  // on the Wi-Fi Information load path. Parsing coverage is unaffected, since
  // macos_link_table_test.dart feeds the parser Keith's real captures directly.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  try {
    final r = await Process.run(exe, args);
    return r.exitCode == 0 ? r.stdout as String : null;
  } on Object {
    return null;
  }
}

class LinkTableService {
  LinkTableService({
    PiBackendClient? pi,
    DefaultRouteProbe? routeProbe,
    ProcessRunner? runner,
    bool? piAvailable,
    bool? isMacOS,
    bool? isWeb,
  }) : _pi = pi,
       _routeProbe = routeProbe,
       _run = runner ?? _runProcess,
       _piAvailable = piAvailable ?? PiBackend.available,
       _isMacOS = isMacOS ?? (!kIsWeb && Platform.isMacOS),
       _isWeb = isWeb ?? kIsWeb;

  final PiBackendClient? _pi;
  final DefaultRouteProbe? _routeProbe;
  final ProcessRunner _run;
  final bool _piAvailable;
  final bool _isMacOS;
  final bool _isWeb;

  Future<LinkTableResult> read() async {
    // 1. The Pi answers best, and it answers about ITSELF, which is the point
    //    of the Pi edition.
    if (_piAvailable) {
      try {
        final LinkTable t = await (_pi ?? PiBackendClient()).links();
        return LinkTableResult.ok(t);
      } on Object catch (e) {
        return LinkTableResult.unavailable(
          'The Pi did not answer its link table. It is serving this page, so '
          'the service may have restarted. Try again, and if it persists check '
          'the Pi with: sudo systemctl status toolbox-api ($e)',
          source: 'pi',
        );
      }
    }

    // 2. A browser that is NOT on a Pi cannot see interfaces at all, and no
    //    amount of retrying changes that.
    if (_isWeb) {
      return const LinkTableResult.unavailable(
        'A browser is not allowed to see network interfaces. Open this in the '
        'Toolbox app, or reach it from a WLAN Pi, which reports its own links '
        'in full.',
        source: 'web',
      );
    }

    // 3. macOS: reconstruct it.
    if (_isMacOS) {
      final String? ports = await _run('networksetup', <String>[
        '-listallhardwareports',
      ]);
      final String? ifc = await _run('ifconfig', <String>['-a']);
      if (ifc == null) {
        return const LinkTableResult.unavailable(
          'Could not read the interface list from the system. If the Toolbox '
          'is running sandboxed it may not be allowed to run ifconfig.',
          source: 'macos',
        );
      }
      final DefaultRoute? route = await (_routeProbe ?? DefaultRouteProbe())
          .readV4();
      return LinkTableResult.ok(
        parseMacosLinkTable(
          hardwarePorts: ports ?? '',
          ifconfigAll: ifc,
          defaultRouteInterface: route?.interfaceName,
          defaultGateway: route?.gateway,
        ),
      );
    }

    // 4. Everything else, named rather than lumped together.
    return const LinkTableResult.unavailable(
      'This platform does not yet report a full link table here. macOS and the '
      'WLAN Pi do. Windows has not been measured at all yet, and iOS and '
      'Android need a platform channel that has not been built.',
      source: 'other',
    );
  }
}
