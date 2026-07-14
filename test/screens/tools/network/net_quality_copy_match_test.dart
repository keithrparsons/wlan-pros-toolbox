// MEDIUM-1: THE SCREEN AND THE PASTED REPORT MUST SAY THE SAME THING.
//
// [[feedback_screenshot_text_match]]. The Network Quality screen renders an
// unavailable metric as its NOTE (`note ?? 'Unavailable'`), so a deliberately
// skipped Responsiveness reads:
//
//     Responsiveness   Not measured, on purpose: it needs a second full-speed
//                      download...
//
// The COPY REPORT wrote the same result as:
//
//     Responsiveness: Unavailable — <grade> (Not measured, on purpose: ...)
//
// It LED WITH "UNAVAILABLE" — the forbidden word, the false claim of incapacity —
// and demoted the actual truth to a parenthetical. Two surfaces, one result, and
// the one the user PASTES INTO A TICKET was the one that lied.
//
// This is the same two-kinds-of-null error the chips were fixed for, surviving in
// the clipboard because nobody read the clipboard.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/services/network/network_transport_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// A MEASURED cellular Android phone: the consent gate fires, the user declines,
/// and Responsiveness carries its deliberate-skip note.
class _Cellular implements NetworkTransportProbe {
  const _Cellular();
  @override
  Future<NetworkTransportFacts?> read() async => const NetworkTransportFacts(
        cellular: true,
        wifi: false,
        ethernet: false,
        vpn: false,
      );
}

class _PathSilent implements WifiPathProbe {
  const _PathSilent();
  @override
  Future<WifiPathFacts?> read() async => null;
}

class _NoWifiAddress implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoSites extends ReachabilityProbe {
  @override
  Future<List<SiteReachability>> measure() async => <SiteReachability>[];
}

LiveQualityMonitor _fakeMonitor() => LiveQualityMonitor(
      sampler: () async => const LatencyStats(
        avgMs: 20,
        minMs: 18,
        maxMs: 24,
        jitterMs: 2,
        lossPct: 0,
        sent: 5,
        received: 5,
      ),
    );

void main() {
  testWidgets(
    'the pasted report never LEADS with "Unavailable" for a DELIBERATE skip',
    (WidgetTester tester) async {
      final MockQualityClient quality = MockQualityClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetQualityScreen(
            client: quality,
            reachabilityProbe: _NoSites(),
            monitor: _fakeMonitor(),
            connectionService: WifiConnectionService(
              networkInfo: _NoWifiAddress(),
              platformOverride: TargetPlatform.android,
              pathProbe: const _PathSilent(),
              transportProbe: const _Cellular(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // DECLINE the speed test. Download / upload / responsiveness are now all
      // deliberately unmeasured, each carrying its own honest note.
      await tester.tap(find.text('Run without the speed test'));
      await tester.pumpAndSettle();

      final AppCopyAction action = tester.widget<AppCopyAction>(
        find.byType(AppCopyAction),
      );
      final String? report = action.textBuilder();
      expect(report, isNotNull, reason: 'a completed run must be copyable');

      // THE ASSERTION. The note IS the value. It must not be demoted behind a word
      // that claims we failed at something we deliberately chose not to do.
      for (final String line in report!.split('\n')) {
        if (line.contains(':') && line.trimLeft().startsWith(RegExp(r'\w'))) {
          final int i = line.indexOf(':');
          final String value = line.substring(i + 1).trim();
          expect(
            value.startsWith('Unavailable'),
            isFalse,
            reason: 'the pasted report LEADS with the forbidden word on: "$line". '
                'The screen says the note; the clipboard must say the same thing '
                '([[feedback_screenshot_text_match]]).',
          );
        }
      }

      // ...and it positively carries the honest reason instead.
      expect(
        report,
        contains('the speed test was skipped'),
        reason: 'the pasted report must carry the same truth the screen shows',
      );
    },
  );
}
