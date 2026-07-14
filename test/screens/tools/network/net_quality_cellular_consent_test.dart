// NETWORK QUALITY HAD NO CONSENT GATE AT ALL (round-4 cold review, F-1).
//
// Test My Connection got a careful cellular-data gate on 2026-07-13. Network
// Quality — shipped, routed, and iOS-live — spends the SAME bytes through the
// SAME engine, and had nothing. It called `_client.measure()` bare, riding an
// `includeThroughput = true` default on the QualityClient interface.
//
// On a cellular iPhone: open the tool, tap Run, and it began a full-rate ~30 s
// download plus the RPM load generator — roughly 50 MB on a slow link, 500 MB or
// more on fast 5G — with no warning, no decline path, and nothing to consent to.
//
// The gate was never the whole gate. It was ONE CALLER being careful while the
// door stood open. The default is now gone from the interface, so the compiler
// asks the question at every call site, and this screen answers it.
//
// CONTRACT (identical to Test My Connection — same cost, same words, same rules):
//   1. On CELLULAR: warn, and require an explicit cost-labelled tap before a
//      single throughput byte moves.
//   2. On WI-FI: nothing changes. No warning, no extra tap.
//   3. On an AMBIGUOUS probe: nothing changes either. An ambiguous read is never
//      proof of cellular, and must never nag a wired desktop (GL-005).
//   4. Declining still runs everything cheap — latency, jitter, loss,
//      reachability. Only the data-hungry stages are withheld.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_data_cost.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The native NWPathMonitor stays silent so the verdict is driven through the
/// address probe, which is the seam these tests can actually set.
class _NativeSilent implements WifiPathProbe {
  const _NativeSilent();
  @override
  Future<WifiPathFacts?> read() async => null;
}

/// Cellular-only: the Wi-Fi interface carries no address of either family — the
/// only shape permitted to assert `notOnWifi`.
class _CellularOnly implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _OnWifi implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '192.168.1.20';
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The read THROWS -> `unknown`. The user may well be on Wi-Fi.
class _Ambiguous implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => throw Exception('denied');
  @override
  Future<String?> getWifiIPv6() async => throw Exception('denied');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A link that CHANGES under the mounted screen — the user walking out of Wi-Fi
/// range with the tool open. The same F-2 shape, on the tool that had no gate.
class _Flipping implements NetworkInfo {
  _Flipping({this.onWifi = true});
  bool onWifi;
  @override
  Future<String?> getWifiIP() async => onWifi ? '192.168.1.20' : null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// No sites, no network: the reachability pass is irrelevant to the consent gate.
class _NoSites extends ReachabilityProbe {
  @override
  Future<List<SiteReachability>> measure() async => <SiteReachability>[];
}

/// A monitor with a fake sampler, so the screen's live-trend timer never touches
/// the network (and never outlives the test).
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

Future<MockQualityClient> _pump(
  WidgetTester tester,
  NetworkInfo net, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  final MockQualityClient quality = MockQualityClient();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: NetQualityScreen(
        client: quality,
        reachabilityProbe: _NoSites(),
        monitor: _fakeMonitor(),
        connectionService: WifiConnectionService(
          networkInfo: net,
          platformOverride: platform,
          pathProbe: const _NativeSilent(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return quality;
}

String _visibleText(WidgetTester tester) {
  final StringBuffer buf = StringBuffer();
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    if (t.data != null) buf.writeln(t.data);
  }
  return buf.toString();
}

void main() {
  group('cellular: Network Quality must warn before it spends the data', () {
    testWidgets('the pre-run screen states the cost and offers a way out', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _CellularOnly());
      final String screen = _visibleText(tester);

      expect(screen, contains("You're on cellular."));
      // Assert against the SSOT constant, not a hand-copied literal. The literal
      // is how this drifted in the first place: the copy said "about 30 seconds"
      // (two 15 s download windows) long after the RPM window stopped running on
      // cellular, and the test happily confirmed the stale sentence.
      expect(screen, contains(kCellularDataWarning));
      expect(screen, contains('15 seconds'));
      expect(screen, contains('30 MB at 10 Mbps'));
      // The hedged range is GONE — a consent dialog states a sourced number.
      expect(screen, isNot(contains('roughly')));
      expect(screen, isNot(contains('or more')));

      expect(find.text('Run test (uses data)'), findsOneWidget);
      expect(find.text('Run without the speed test'), findsOneWidget);
    });

    testWidgets('NO throughput byte moves until the user consents', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await _pump(tester, _CellularOnly());

      await tester.tap(find.text('Run without the speed test'));
      await tester.pumpAndSettle();

      expect(
        quality.measureCalls,
        1,
        reason: 'the cheap probes still run — declining is not a dead end',
      );
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason:
            'THE BYPASS: this tool called measure() bare and rode the '
            'interface default, spending up to 500 MB of cellular data with no '
            'warning and no way to say no.',
      );
    });

    testWidgets(
      'the cost-labelled tap IS the consent, and it spends the data',
      (WidgetTester tester) async {
        final MockQualityClient quality = await _pump(tester, _CellularOnly());

        await tester.tap(find.text('Run test (uses data)'));
        await tester.pumpAndSettle();

        expect(quality.measureCalls, 1);
        expect(
          quality.lastIncludeThroughput,
          isTrue,
          reason: 'an explicit, cost-labelled tap is consent and must work',
        );
      },
    );
  });

  group('on Wi-Fi and on an ambiguous probe: nothing changes', () {
    testWidgets('ON WI-FI there is no warning and no extra tap', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await _pump(tester, _OnWifi());
      final String screen = _visibleText(tester);

      expect(screen, isNot(contains("You're on cellular.")));
      expect(find.text('Run without the speed test'), findsNothing);
      expect(find.text('Run test'), findsOneWidget);

      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();

      expect(
        quality.lastIncludeThroughput,
        isTrue,
        reason: 'on Wi-Fi the full test runs exactly as before, one tap',
      );
    });

    // ========================================================================
    // READ THIS TEST'S NAME, AND THEN READ ITS SCOPE. (Round-4b, 2026-07-14.)
    //
    // THIS TEST IS CORRECT, AND IT WAS ALSO THE COVER FOR A LIVE DATA LEAK. Both
    // things are true, and the second one is not the first one's fault.
    //
    // What it asserts is right, ON iOS, and must not be "fixed": a read that
    // THREW (`_Ambiguous` = getWifiIP() throws) is a FAILED read, not a cellular
    // one. Nagging there would nag a wired desktop and a Location-denied user, and
    // withholding the speed test would silently delete the headline feature for
    // everyone whose read failed. `unknown` means CARRY ON. That is GL-005, and it
    // still holds.
    //
    // THE DEFECT WAS ITS SCOPE, NOT ITS ASSERTION. Every test in this file drives
    // `TargetPlatform.iOS` (the `_pump` default) — the `platform:` parameter existed
    // and NOT ONE caller ever passed it. So "ambiguous ⇒ spend" was the only rule
    // in force on ANDROID... where, before round 4b, EVERY probe was ambiguous BY
    // CONSTRUCTION (`notOnWifi` was structurally unreachable off iOS). A rule
    // written for "we genuinely cannot tell" silently came to govern a platform
    // that CAN tell and was simply never asked. 4,238 tests passed over a zero-tap,
    // 50-500 MB cellular data leak on a store-live platform.
    //
    // THE CORRECTION IS NOT TO INVERT THIS ASSERTION — that would ship a real bug.
    // It is to (a) NAME THE PLATFORM this invariant is scoped to, so its silence
    // about the others is visible, and (b) DECOMPOSE "ambiguous" on Android, where
    // it is no longer one thing: an unreadable transport is still ambiguous and
    // still must not nag, but a MEASURED `TRANSPORT_CELLULAR` is not ambiguous at
    // all. Both axes now live in android_cellular_consent_test.dart.
    //
    // [[feedback_tests_that_enshrine_the_bug]] — third occurrence. The lesson is
    // sharper than "read the test names": a green test can be RIGHT and still be
    // the reason nobody looked, because a passing invariant reads as coverage of
    // every platform it never ran on.
    // ========================================================================
    testWidgets(
      'ON iOS an AMBIGUOUS (failed) probe must NOT nag — it is not proof of '
      'cellular, and Android is NOT covered by this rule',
      (WidgetTester tester) async {
        final MockQualityClient quality = await _pump(
          tester,
          _Ambiguous(),
          // Stated, not defaulted. This invariant is iOS-scoped and the platform is
          // now part of the test's claim rather than an invisible default.
          platform: TargetPlatform.iOS,
        );
        final String screen = _visibleText(tester);

        expect(
          screen,
          isNot(contains("You're on cellular.")),
          reason: 'a failed read is not a positive cellular signal (GL-005)',
        );
        expect(find.text('Run test'), findsOneWidget);

        await tester.tap(find.text('Run test'));
        await tester.pumpAndSettle();
        expect(
          quality.lastIncludeThroughput,
          isTrue,
          reason:
              'on iOS a FAILED read must not withhold the feature. This is '
              'NOT a licence to spend on Android, where the transport is '
              'MEASURED — see android_cellular_consent_test.dart',
        );
      },
    );
  });

  testWidgets(
    'WALK OUT OF WI-FI RANGE with Network Quality open: the run must not spend '
    'cellular data the user was never asked about',
    (WidgetTester tester) async {
      // Mount on Wi-Fi: no warning, plain "Run test", and the consent tap that
      // sets _throughputConsented therefore never fires.
      final _Flipping net = _Flipping(onWifi: true);
      final MockQualityClient quality = MockQualityClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: NetQualityScreen(
            client: quality,
            reachabilityProbe: _NoSites(),
            monitor: _fakeMonitor(),
            connectionService: WifiConnectionService(
              networkInfo: net,
              platformOverride: TargetPlatform.iOS,
              pathProbe: const _NativeSilent(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Run test'), findsOneWidget);

      // The user walks out of range. Nothing re-probes; the screen still shows
      // the on-Wi-Fi button.
      net.onWifi = false;

      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();

      expect(quality.measureCalls, 1);
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason:
            'the run must settle the probe BEFORE the consent decision '
            'reads it — otherwise it spends up to 500 MB on a link the user '
            'never agreed to pay for',
      );
    },
  );
}
