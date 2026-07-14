// THE CONSENT LATCH, AND THE RESULT SCREEN THAT OFFERED NO WAY IN.
// (Round-4b cold review, MEDIUM + the opt-in defect, 2026-07-14.)
//
// TWO DEFECTS, ONE ROOT: the result screen REPLACES the pre-run card
// (`if (verdict == null) _actionCard(...)` — test_my_connection_screen.dart), so
// every affordance that carried the cellular-data cost — the warning, the
// cost-labelled button, the decline path — VANISHES the moment a result exists.
// What is left behind tells the user nothing true about what their next tap costs.
//
//   DEFECT 1 — WARNED ONCE, CHARGED N TIMES. `_throughputConsented` latches for the
//   MOUNT and is never reset. Consent once on cellular, and the only remaining
//   control is a bare "Run again" with NO COST LABEL, sitting above a warning the
//   user can no longer see. Every subsequent tap silently spent ANOTHER 50-500 MB.
//
//   DEFECT 2 — NO WAY TO OPT IN. Decline the speed test, and the result renders
//   "Not measured: the speed test was skipped to save cellular data" — a sentence
//   that invites "but I want it" and offers NO BUTTON. The identical cost-labelled
//   tap is deemed sufficient consent on the PRE-RUN screen; there is no principled
//   reason it becomes unsafe AFTER a run. It bites hardest on 5G fixed-wireless home
//   users, who read as "cellular" and are UNLIMITED — permanently denied the
//   headline feature for the life of the mount.
//
// THE SCOPE OF CONSENT, DECIDED: PER-MOUNT for the FLAG (a user who said yes is not
// re-interrogated on every re-run — that is nagging), but EVERY BUTTON THAT CAN
// SPEND CELLULAR DATA CARRIES THE COST IN ITS OWN LABEL. Every spend is therefore
// still preceded by a cost-labelled tap. That is per-run consent in substance, and
// it is exactly the standard the pre-run button already meets.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_transport_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

class _CellularTransport implements NetworkTransportProbe {
  const _CellularTransport();
  @override
  Future<NetworkTransportFacts?> read() async => const NetworkTransportFacts(
        cellular: true,
        wifi: false,
        ethernet: false,
        vpn: false,
      );
}

/// A transport that CHANGES under the mounted screen — the user walking out of
/// Wi-Fi range with Test My Connection open, and the phone dropping to cellular.
/// This is the shape that reaches the `spendData` chokepoint with a caller asking
/// for throughput and NO consent on file.
class _FlippingTransport implements NetworkTransportProbe {
  _FlippingTransport({this.onWifi = true});
  bool onWifi;
  @override
  Future<NetworkTransportFacts?> read() async => NetworkTransportFacts(
        cellular: !onWifi,
        wifi: onWifi,
        ethernet: false,
        vpn: false,
      );
}

class _NativeSilent implements WifiPathProbe {
  const _NativeSilent();
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

class _NoWifiAdapter implements WifiInfoAdapter {
  @override
  Future<ConnectedAp> fetch() async => throw const WifiInfoUnavailable(
      WifiInfoUnavailableReason.channelError, 'no Wi-Fi link');
  @override
  String get platformLabel => 'Android WifiManager';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDns implements DnsProbeService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeNetDetails implements NetworkDetailsService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeIpGeo implements IpGeoService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

String _visibleText(WidgetTester tester) {
  final StringBuffer buf = StringBuffer();
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    if (t.data != null) buf.writeln(t.data);
  }
  return buf.toString();
}

/// Mounts Test My Connection on a CELLULAR Android phone, NOT auto-started, so the
/// test drives the taps itself.
Future<({MockQualityClient quality, WifiSignalSampler sampler})> _pump(
  WidgetTester tester, {
  NetworkTransportProbe transport = const _CellularTransport(),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final MockQualityClient quality = MockQualityClient();
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.androidWifiManager,
    macAdapter: _NoWifiAdapter(),
    connectionService: WifiConnectionService(
      networkInfo: _NoWifiAddress(),
      platformOverride: TargetPlatform.android,
      pathProbe: const _NativeSilent(),
      transportProbe: transport,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: TestMyConnectionScreen(
        autoStart: false,
        sourceOverride: WifiInfoSource.androidWifiManager,
        sampler: sampler,
        macAdapter: _NoWifiAdapter(),
        dnsProbeService: _FakeDns(),
        networkDetailsService: _FakeNetDetails(),
        ipGeoService: _FakeIpGeo(),
        enableCloudApps: false,
        onboardingService:
            LiveOnboardingService(getStore: SharedPreferences.getInstance),
        qualityClient: quality,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (quality: quality, sampler: sampler);
}

Future<void> _teardown(WidgetTester tester, WifiSignalSampler sampler) async {
  await tester.pumpWidget(const SizedBox.shrink());
  sampler.dispose();
  await tester.pump();
}

void main() {
  testWidgets(
      'DEFECT 1 — after consenting once, "Run again" must SAY it spends the data',
      (WidgetTester tester) async {
    final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
        await _pump(tester);

    // Consent, once, on the cost-labelled pre-run button.
    await tester.tap(find.text('Check My Connection (uses data)'));
    await tester.pumpAndSettle();
    expect(r.quality.lastIncludeThroughput, isTrue);

    // The pre-run card is GONE now — the result replaced it. The ONLY re-run
    // control is "Run again", and it used to be a bare, unlabelled button that
    // spent another 50-500 MB per tap.
    expect(find.text('Check My Connection (uses data)'), findsNothing,
        reason: 'the result screen replaces the pre-run card — that is the '
            'precondition for this whole defect');

    expect(find.text('Run again (uses data)'), findsOneWidget,
        reason: 'THE FIX: the button that spends the money must say so. A bare '
            '"Run again" here is the "warned once, charged N times" bug.');
    expect(find.text('Run again'), findsNothing,
        reason: 'the unlabelled variant must NOT render when the tap will spend '
            'cellular data');

    // And it must actually still work — the latch means no re-interrogation.
    await tester.tap(find.text('Run again (uses data)'));
    await tester.pumpAndSettle();
    expect(r.quality.measureCalls, 2);
    expect(r.quality.lastIncludeThroughput, isTrue,
        reason: 'consent is per-mount: a user who said yes is not nagged again, '
            'but the button they tap tells them the truth');

    await _teardown(tester, r.sampler);
  });

  testWidgets(
      'DEFECT 2 — a DECLINED result must offer a way IN, and "Run again" must '
      'NOT claim a cost it will not incur', (WidgetTester tester) async {
    final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
        await _pump(tester);

    // Decline. Everything cheap still runs; the speed test is withheld.
    await tester.tap(find.text('Check without the speed test'));
    await tester.pumpAndSettle();
    expect(r.quality.lastIncludeThroughput, isFalse);

    // The result says the speed test was skipped...
    expect(_visibleText(tester), contains('Not measured'),
        reason: 'the declined stages report honestly');

    // ...and NOW it must offer the way back in. This button did not exist.
    expect(find.text('Run the speed test anyway (uses data)'), findsOneWidget,
        reason: 'THE FIX: "Not measured: the speed test was skipped to save '
            'cellular data" invites "but I want it" and offered NO BUTTON. A 5G '
            'fixed-wireless home user — cellular, and UNLIMITED — was permanently '
            'denied the headline feature.');

    // "Run again" must NOT say "(uses data)" here: consent was never given, so the
    // chokepoint will DOWNGRADE that run and it will spend nothing. A cost claim
    // must never outrun the spend it describes — in either direction.
    expect(find.text('Run again'), findsOneWidget,
        reason: 'un-consented, "Run again" spends NOTHING and must not claim to');
    expect(find.text('Run again (uses data)'), findsNothing);

    // The opt-in is the SAME cost-labelled tap as the pre-run button: one tap,
    // consent recorded, data spent.
    await tester.tap(find.text('Run the speed test anyway (uses data)'));
    await tester.pumpAndSettle();

    expect(r.quality.measureCalls, 2);
    expect(r.quality.lastIncludeThroughput, isTrue,
        reason: 'the opt-in tap IS the consent, exactly as it is pre-run');

    // And having opted in, the re-run control now tells the truth about ITS cost.
    expect(find.text('Run again (uses data)'), findsOneWidget);
    expect(find.text('Run the speed test anyway (uses data)'), findsNothing,
        reason: 'the opt-in is spent; the speed test is no longer skipped');

    await _teardown(tester, r.sampler);
  });

  // ==========================================================================
  // THE CHOKEPOINT ITSELF. Found by a SURVIVING MUTANT, not by reading the code.
  //
  // Mutating `spendData = includeThroughput && (!_notOnWifi || _throughputConsented)`
  // down to a bare `spendData = includeThroughput` left the ENTIRE suite GREEN —
  // mine and the pre-existing TMC consent suite both. That line is the LAST line of
  // defense: it is what makes a caller that asks for throughput without consent
  // SAFE. Nothing tested it, on any platform.
  //
  // Two shapes reach it with `includeThroughput: true` and NO consent on file. Both
  // are real, both spend 50-500 MB if the chokepoint stops working, and neither was
  // covered.
  // ==========================================================================
  group('the spendData chokepoint downgrades an UN-CONSENTED throughput request',
      () {
    testWidgets(
        'SHAPE 1 — "Run again" on a DECLINED cellular result must spend NOTHING',
        (WidgetTester tester) async {
      final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
          await _pump(tester);

      // Decline. No consent is ever recorded for this mount.
      await tester.tap(find.text('Check without the speed test'));
      await tester.pumpAndSettle();
      expect(r.quality.lastIncludeThroughput, isFalse);

      // "Run again" calls _run(includeThroughput: TRUE) — a tear-off that ASKS for
      // the data-hungry stages. Only the chokepoint stops it, because the user has
      // said no and never said yes.
      await tester.tap(find.text('Run again'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 2, reason: 'the re-run did happen');
      expect(r.quality.lastIncludeThroughput, isFalse,
          reason: 'THE CHOKEPOINT: "Run again" asks for throughput, but the user '
              'declined and never consented. It must be DOWNGRADED, not honored. '
              'Without this line it spends another 50-500 MB.');

      await _teardown(tester, r.sampler);
    });

    testWidgets(
        'SHAPE 2 — WALK OUT OF WI-FI RANGE with the screen open: the check must '
        'not spend cellular data the user was never asked about',
        (WidgetTester tester) async {
      // Mount ON WI-FI. The button carries NO cost label, so the tap that sets
      // _throughputConsented never fires — there is nothing to consent to yet.
      final _FlippingTransport transport = _FlippingTransport(onWifi: true);
      final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
          await _pump(tester, transport: transport);

      expect(find.text('Check My Connection'), findsOneWidget,
          reason: 'on Wi-Fi, the plain label — no cost, no warning');

      // The user walks out of range. The phone drops to cellular. Nothing has
      // re-probed yet, so the screen still shows the on-Wi-Fi button.
      transport.onWifi = false;

      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 1);
      expect(r.quality.lastIncludeThroughput, isFalse,
          reason: 'the run must SETTLE the probe before the consent decision reads '
              'it. The user tapped a button that promised no cost, on a link that '
              'is now metered. Spending here is spending money they never agreed '
              'to — and the tap cannot be retroactive consent for a cost it never '
              'displayed.');

      await _teardown(tester, r.sampler);
    });
  });
}
