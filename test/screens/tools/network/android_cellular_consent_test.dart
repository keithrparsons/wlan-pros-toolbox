// THE ANDROID CELLULAR-DATA CONSENT GATE. (Round-4b, 2026-07-14.)
//
// THIS FILE IS THE COLD REVIEW'S PROOF-OF-EXPLOIT, INVERTED. Every assertion here
// that now demands the gate FIRE was, three commits ago, an assertion that PASSED
// while proving the app spent the user's money. The exploit is preserved verbatim
// in its comments so the shape of the hole cannot be forgotten.
//
// THE HOLE, AS FOUND. The consent gate was iOS-ONLY, and NOT by design — BY
// STRUCTURE. Two independent copies:
//
//   1. wifi_connection_service.dart — `if (_platform != TargetPlatform.iOS)
//      return WifiConnectionStatus.unknown;` made `notOnWifi` STRUCTURALLY
//      UNREACHABLE off iOS. NetQualityScreen's gate reads `status == notOnWifi`
//      EXACTLY.
//   2. wifi_signal_sampler.dart — `notOnWifi => _controller?.notOnWifi ?? false`,
//      and `_controller` is built ONLY for `WifiInfoSource.iosShortcuts`; its
//      `load()` was a NO-OP off iOS. TestMyConnectionScreen's gate reads EXACTLY
//      that.
//
// So on ANDROID — LIVE on Google Play, and the platform where "on cellular" is the
// DEFAULT assumption — `_notOnWifi` was permanently `false`, therefore
// `spendData = includeThroughput && (!_notOnWifi || _throughputConsented)` was
// UNCONDITIONALLY TRUE. No warning. No cost sentence. No decline path. No consent
// tap. And the home hero pushes Test My Connection with `autoStart: true`, so
// OPENING THE APP on a cellular Android phone auto-ran a full-rate ~30 s download
// plus the RPM load generator — 50 to 500 MB — with ZERO TAPS.
//
// WHY IT WAS "WE NEVER ASKED", NOT "WE CANNOT KNOW". Android reports the transport
// DEFINITIVELY: `ConnectivityManager` + `NetworkCapabilities.TRANSPORT_CELLULAR`.
// That is a MEASURED signal, not an inference from an IP address. The GL-005
// rationale the iOS gate rests on ("an ambiguous read is never proof of cellular;
// never nag a wired desktop") was written for platforms that genuinely cannot tell,
// and IT DOES NOT COVER ANDROID. Treating a knowable fact as unknowable is the
// two-kinds-of-null error pointed the wrong way ([[feedback_unsourced_is_not_invalid]]).
//
// WHAT THIS FILE MUST PROVE, ON BOTH TOOLS AND ON EVERY AXIS:
//   A. CELLULAR Android is gated — warning, cost sentence, decline path, consent
//      tap — in Network Quality AND Test My Connection.
//   B. The ZERO-TAP auto-start path is CLOSED.
//   C. WI-FI and ETHERNET Android are NOT nagged (no over-suppression).
//   D. AMBIGUOUS stays AMBIGUOUS — an unreadable transport, a VPN that hides its
//      underlying network, and both-transports-at-once assert NEITHER cellular NOR
//      Wi-Fi (GL-005: never a definitive verdict from an unverified signal).
//   E. macOS and Windows are UNTOUCHED.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_data_cost.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
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

// ---------------------------------------------------------------------------
// The transport probe — the ONE seam this whole gate hangs on.
// ---------------------------------------------------------------------------

/// The Android transport probe, faked. These are the raw
/// `NetworkCapabilities.hasTransport(...)` bits the OS reports for the ACTIVE
/// network — the MEASURED signal, not an inference.
class _Transport implements NetworkTransportProbe {
  const _Transport({
    this.cellular = false,
    this.wifi = false,
    this.ethernet = false,
    this.vpn = false,
  });

  final bool cellular;
  final bool wifi;
  final bool ethernet;
  final bool vpn;

  /// A phone on 5G. The whole point.
  static const _Transport cellularOnly = _Transport(cellular: true);

  /// A tablet on Wi-Fi. Must never be nagged.
  static const _Transport wifiOnly = _Transport(wifi: true);

  /// A wired Android TV / a docked tablet. NOT cellular. Must never be nagged.
  static const _Transport ethernetOnly = _Transport(ethernet: true);

  /// A VPN that never called `setUnderlyingNetworks`, so the OS reports no
  /// underlying transport. GENUINELY ambiguous.
  static const _Transport vpnOpaque = _Transport(vpn: true);

  /// Wi-Fi AND cellular on one active network (a VPN over both). We cannot know
  /// which link pays. GENUINELY ambiguous.
  static const _Transport both = _Transport(cellular: true, wifi: true);

  /// Airplane mode: a SUCCESSFUL read of "there is no active network". Not a
  /// failure, and not cellular.
  static const _Transport offline = _Transport();

  @override
  Future<NetworkTransportFacts?> read() async => NetworkTransportFacts(
    cellular: cellular,
    wifi: wifi,
    ethernet: ethernet,
    vpn: vpn,
  );
}

/// The channel did not answer at all (absent, threw, timed out). NOT a verdict in
/// either direction.
class _TransportSilent implements NetworkTransportProbe {
  const _TransportSilent();
  @override
  Future<NetworkTransportFacts?> read() async => null;
}

/// The native NWPathMonitor channel does not exist off iOS: a guaranteed
/// MissingPluginException in production, `null` here.
class _NativeSilent implements WifiPathProbe {
  const _NativeSilent();
  @override
  Future<WifiPathFacts?> read() async => null;
}

/// CELLULAR-ONLY at the ADDRESS layer: the Wi-Fi interface carries no address of
/// either family. This is what the exploit used to model a 5G phone — and on
/// Android it is NOT ENOUGH on its own, which is exactly the point: the address
/// probe refuses to assert a negative off iOS, so the verdict must come from the
/// TRANSPORT probe.
class _NoWifiAddress implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A normal Wi-Fi address. Used to prove Ethernet/VPN rows are decided by the
/// TRANSPORT, and to prove the Wi-Fi row is not accidentally driven by addresses.
class _HasWifiAddress implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '192.168.1.20';
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

/// Android, cellular: the Wi-Fi snapshot read fails because there is no Wi-Fi link.
class _NoWifiAdapter implements WifiInfoAdapter {
  @override
  Future<ConnectedAp> fetch() async => throw const WifiInfoUnavailable(
    WifiInfoUnavailableReason.channelError,
    'no Wi-Fi link',
  );
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

WifiConnectionService _android(
  NetworkTransportProbe transport, {
  NetworkInfo? net,
}) => WifiConnectionService(
  networkInfo: net ?? _NoWifiAddress(),
  platformOverride: TargetPlatform.android,
  pathProbe: const _NativeSilent(),
  transportProbe: transport,
);

/// Mounts Network Quality on an Android device with the given transport.
Future<MockQualityClient> _pumpNetQuality(
  WidgetTester tester,
  NetworkTransportProbe transport, {
  NetworkInfo? net,
}) async {
  final MockQualityClient quality = MockQualityClient();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: NetQualityScreen(
        client: quality,
        reachabilityProbe: _NoSites(),
        monitor: _fakeMonitor(),
        connectionService: _android(transport, net: net),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return quality;
}

/// Mounts Test My Connection on an Android device with the given transport,
/// EXACTLY as the home hero mounts it (`autoStart: true`) unless told otherwise.
Future<({MockQualityClient quality, WifiSignalSampler sampler})> _pumpTmc(
  WidgetTester tester,
  NetworkTransportProbe transport, {
  bool autoStart = true,
  NetworkInfo? net,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final MockQualityClient quality = MockQualityClient();
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.androidWifiManager,
    macAdapter: _NoWifiAdapter(),
    connectionService: _android(transport, net: net),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: TestMyConnectionScreen(
        autoStart: autoStart,
        sourceOverride: WifiInfoSource.androidWifiManager,
        sampler: sampler,
        macAdapter: _NoWifiAdapter(),
        dnsProbeService: _FakeDns(),
        networkDetailsService: _FakeNetDetails(),
        ipGeoService: _FakeIpGeo(),
        enableCloudApps: false,
        onboardingService: LiveOnboardingService(
          getStore: SharedPreferences.getInstance,
        ),
        qualityClient: quality,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (quality: quality, sampler: sampler);
}

/// Tears down the Android poll timer the screen starts, so the pending-timer
/// invariant cannot mask a result.
Future<void> _teardown(WidgetTester tester, WifiSignalSampler sampler) async {
  await tester.pumpWidget(const SizedBox.shrink());
  sampler.dispose();
  await tester.pump();
}

void main() {
  // =========================================================================
  // A. THE GATE'S INPUT IS ALIVE ON ANDROID.
  // =========================================================================
  group('WifiConnectionService on Android', () {
    test('a MEASURED cellular transport returns notOnWifi', () async {
      // WAS: `expect(status, isNot(WifiConnectionStatus.notOnWifi))` — and it
      // PASSED. `notOnWifi` was structurally unreachable off iOS, so every screen
      // gate that reads `status == notOnWifi` was dead code on Android.
      expect(
        await _android(_Transport.cellularOnly).status(),
        WifiConnectionStatus.notOnWifi,
        reason:
            'TRANSPORT_CELLULAR on the active network is a MEASUREMENT, not '
            'an inference. This is the ONE negative Android may assert.',
      );
    });

    test('a Wi-Fi transport returns onWifi', () async {
      expect(
        await _android(_Transport.wifiOnly).status(),
        WifiConnectionStatus.onWifi,
      );
    });

    test(
      'ETHERNET is NOT cellular and is NOT nagged — it returns unknown',
      () async {
        // A wired Android TV. `unknown` means "carry on as before": no warning, and
        // no false claim of a Wi-Fi link either. OVER-SUPPRESSION PROOF.
        expect(
          await _android(_Transport.ethernetOnly).status(),
          WifiConnectionStatus.unknown,
          reason: 'a wired Android TV must never see a cellular warning',
        );
      },
    );

    test('a VPN that hides its underlying transport stays AMBIGUOUS', () async {
      // Android usually merges the underlying transports into a VPN network's
      // capabilities. When a VPN app does not call setUnderlyingNetworks, it does
      // not — and we must NOT guess "cellular" (that would nag every VPN-on-Wi-Fi
      // user). Stated as a KNOWN LIMIT, not hidden.
      expect(
        await _android(_Transport.vpnOpaque).status(),
        WifiConnectionStatus.unknown,
      );
    });

    test('BOTH Wi-Fi and cellular on one network stays AMBIGUOUS', () async {
      // We cannot know which link pays. Assert NEITHER.
      expect(
        await _android(_Transport.both).status(),
        WifiConnectionStatus.unknown,
      );
    });

    test('NO ACTIVE NETWORK (airplane mode) is not cellular', () async {
      // A SUCCESSFUL read of "nothing is connected". Claiming "you're on cellular"
      // here would be a fabrication.
      expect(
        await _android(_Transport.offline).status(),
        WifiConnectionStatus.unknown,
      );
    });

    test(
      'an UNREADABLE transport falls back and stays unknown — never a verdict',
      () async {
        // The channel is absent / threw / timed out. The address probe below refuses
        // to assert a negative off iOS, so this resolves to `unknown`. THE F-4
        // INVARIANT HOLDS ON ANDROID: no definitive negative from an unverified
        // signal.
        expect(
          await _android(const _TransportSilent()).status(),
          WifiConnectionStatus.unknown,
        );
      },
    );

    test('a Wi-Fi ADDRESS cannot override a MEASURED cellular transport, and a '
        'missing address cannot manufacture one', () async {
      // The transport probe is the PRIMARY signal on Android and sits ABOVE the
      // address probe. A stale/rogue Wi-Fi address on a cellular phone must not
      // suppress the gate...
      expect(
        await _android(
          _Transport.cellularOnly,
          net: _HasWifiAddress(),
        ).status(),
        WifiConnectionStatus.notOnWifi,
      );
      // ...and an absent Wi-Fi address on a WIRED box must not create a cellular
      // verdict out of nothing. This is the exact shape the old address-only
      // exploit relied on.
      expect(
        await _android(_Transport.ethernetOnly, net: _NoWifiAddress()).status(),
        WifiConnectionStatus.unknown,
      );
    });
  });

  // =========================================================================
  // B. macOS AND WINDOWS ARE UNTOUCHED.
  // =========================================================================
  group('macOS / Windows are out of scope and stay that way', () {
    test('macOS never asserts notOnWifi, even with no Wi-Fi address', () async {
      // "Never nag a wired desktop" genuinely applies here, and a laptop on a phone
      // hotspot reads as Wi-Fi (a known, documented limit). No honest negative
      // exists to assert, so none is asserted.
      final WifiConnectionService macos = WifiConnectionService(
        networkInfo: _NoWifiAddress(),
        platformOverride: TargetPlatform.macOS,
        pathProbe: const _NativeSilent(),
        // Even handed a CELLULAR transport, macOS must ignore it: the probe is
        // never consulted off Android. This proves the platform gate, not just the
        // absence of a channel.
        transportProbe: _Transport.cellularOnly,
      );
      expect(await macos.status(), WifiConnectionStatus.unknown);
    });

    test('Windows never asserts notOnWifi either', () async {
      final WifiConnectionService windows = WifiConnectionService(
        networkInfo: _NoWifiAddress(),
        platformOverride: TargetPlatform.windows,
        pathProbe: const _NativeSilent(),
        transportProbe: _Transport.cellularOnly,
      );
      expect(await windows.status(), WifiConnectionStatus.unknown);
    });
  });

  // =========================================================================
  // C. NETWORK QUALITY on a cellular Android phone.
  // =========================================================================
  group('Network Quality on ANDROID', () {
    testWidgets('CELLULAR: warns, states the cost, and offers a way out', (
      WidgetTester tester,
    ) async {
      // WAS: `expect(screen, isNot(contains("You're on cellular.")))` — PASSED.
      // WAS: `expect(find.text('Run without the speed test'), findsNothing)` —
      // PASSED. WAS: `expect(find.text('Run test'), findsOneWidget)` — PASSED,
      // the ON-WI-FI label on a cellular phone.
      final MockQualityClient quality = await _pumpNetQuality(
        tester,
        _Transport.cellularOnly,
      );
      final String screen = _visibleText(tester);

      expect(
        screen,
        contains("You're on cellular."),
        reason: 'the cellular user MUST be warned',
      );
      expect(
        screen,
        contains(kCellularDataWarning),
        reason: 'the cost must be stated before it is spent',
      );
      expect(
        screen,
        contains('573 MB at 300 Mbps'),
        reason: 'the top-end figure must still be stated plainly — and it is now the '
            'DERIVED one. "570" understated the true 572.5 MB, on the one screen '
            'whose entire job is to say what a tap will cost, and it erred in the '
            'direction that spends the user\'s money under false pretenses.',
      );
      expect(
        find.text('Run without the speed test'),
        findsOneWidget,
        reason: 'there MUST be a decline path',
      );
      expect(
        find.text('Run test (uses data)'),
        findsOneWidget,
        reason: "the button's own label must carry the cost",
      );
      expect(
        find.text('Run test'),
        findsNothing,
        reason: 'the on-Wi-Fi label must NOT appear on a cellular phone',
      );

      expect(quality.measureCalls, 0, reason: 'nothing has run yet');
    });

    testWidgets('CELLULAR: DECLINING spends no throughput bytes', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await _pumpNetQuality(
        tester,
        _Transport.cellularOnly,
      );

      await tester.tap(find.text('Run without the speed test'));
      await tester.pumpAndSettle();

      expect(quality.measureCalls, 1);
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason: 'the decline path must withhold the data-hungry stages',
      );
    });

    testWidgets(
      'CELLULAR: the cost-labelled tap IS the consent, and it works',
      (WidgetTester tester) async {
        final MockQualityClient quality = await _pumpNetQuality(
          tester,
          _Transport.cellularOnly,
        );

        await tester.tap(find.text('Run test (uses data)'));
        await tester.pumpAndSettle();

        expect(quality.measureCalls, 1);
        expect(
          quality.lastIncludeThroughput,
          isTrue,
          reason:
              'an explicit, cost-labelled tap is consent and must be honored',
        );
      },
    );

    testWidgets('WI-FI Android: no warning, no extra tap, nothing changes', (
      WidgetTester tester,
    ) async {
      final MockQualityClient quality = await _pumpNetQuality(
        tester,
        _Transport.wifiOnly,
      );
      final String screen = _visibleText(tester);

      expect(screen, isNot(contains("You're on cellular.")));
      expect(find.text('Run without the speed test'), findsNothing);
      expect(find.text('Run test'), findsOneWidget);

      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();
      expect(
        quality.lastIncludeThroughput,
        isTrue,
        reason: 'a tablet on Wi-Fi must not be nagged or downgraded',
      );
    });

    testWidgets('ETHERNET Android (a wired TV): NOT nagged', (
      WidgetTester tester,
    ) async {
      // OVER-SUPPRESSION PROOF, at the screen.
      final MockQualityClient quality = await _pumpNetQuality(
        tester,
        _Transport.ethernetOnly,
      );
      final String screen = _visibleText(tester);

      expect(
        screen,
        isNot(contains("You're on cellular.")),
        reason: 'a wired Android TV is not on cellular',
      );
      expect(find.text('Run test'), findsOneWidget);

      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();
      expect(quality.lastIncludeThroughput, isTrue);
    });

    testWidgets(
      'AN UNREADABLE transport must ASK — WITHOUT claiming cellular',
      (WidgetTester tester) async {
        // ====================================================================
        // THE SEVENTH ENSHRINED TEST OF THE WEEK. THIS IS WHAT IT USED TO SAY:
        //
        //   testWidgets('AN UNREADABLE transport must NOT nag — ambiguity is
        //                preserved', ...
        //     expect(screen, isNot(contains("You're on cellular.")));
        //     expect(find.text('Run test'), findsOneWidget);
        //     await tester.tap(find.text('Run test'));
        //     expect(quality.lastIncludeThroughput, isTrue);   // <- 573 MB, no tap
        //
        // GREEN. And it was ASSERTING, as correct behavior, that the app spends up
        // to 573 MB of a cellular user's data on an unreadable transport — the exact
        // shape Vera exploited (an Android channel that is absent, threw, or blew its
        // 3 s deadline). It was written in the same commit that closed the Android
        // hole, by an author who had just quoted [[feedback_tests_that_enshrine_the_bug]]
        // in this file's own header.
        //
        // THE TEST'S FIRST ASSERTION WAS ALWAYS RIGHT, AND STILL IS: a read we could
        // not make is NOT proof of cellular, and we must never claim it is. What was
        // wrong was the inference drawn from that — "therefore spend". GL-005 forbids
        // FABRICATING A CLAIM. It never required spending a stranger's money to avoid
        // a prompt.
        //
        // SO BOTH THINGS ARE NOW TRUE AT ONCE, and that is the whole design:
        //   * we do NOT say "You're on cellular"  (we don't know that)
        //   * we DO ask before we spend            (we don't know it's free either)
        // ====================================================================
        final MockQualityClient quality = await _pumpNetQuality(
          tester,
          const _TransportSilent(),
        );
        final String screen = _visibleText(tester);

        expect(
          screen,
          isNot(contains("You're on cellular.")),
          reason: 'a read we could not make is not proof of cellular (GL-005). This '
              'assertion was always correct and is UNCHANGED.',
        );
        expect(
          screen,
          contains("We can't tell whether this device is on Wi-Fi or cellular."),
          reason: 'say the true thing, and ask',
        );
        expect(
          find.text('Run test'),
          findsNothing,
          reason: 'the free-to-spend label must NOT appear on a link we could not read',
        );
        expect(find.text('Run without the speed test'), findsOneWidget);

        await tester.tap(find.text('Run test (may use data)'));
        await tester.pumpAndSettle();
        expect(
          quality.lastIncludeThroughput,
          isTrue,
          reason: 'an explicit, cost-labelled tap is consent and must be honored',
        );
      },
    );
  });

  // =========================================================================
  // D. TEST MY CONNECTION — THE ZERO-TAP PATH. The app's primary entry point.
  // =========================================================================
  group('Test My Connection on ANDROID', () {
    testWidgets(
      'THE ZERO-TAP EXPLOIT IS CLOSED: the home hero auto-start must NOT run '
      'the speed test on a cellular Android phone',
      (WidgetTester tester) async {
        // WAS: `expect(quality.measureCalls, 1)` — PASSED, "the hero auto-run fired
        // with no user tap". WAS: `expect(quality.lastIncludeThroughput, isTrue)` —
        // PASSED: "full throughput + RPM on a cellular Android phone, zero taps, no
        // warning, no consent, no decline path".
        final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
            await _pumpTmc(tester, _Transport.cellularOnly);

        expect(
          r.quality.measureCalls,
          0,
          reason:
              'ZERO BYTES. The auto-start must stop dead on cellular and let '
              'the user decide. Not one measurement may fire without a tap.',
        );

        // And it must not silently do nothing: the user is SHOWN the cost and BOTH
        // choices, so the feature is offered, not withheld.
        final String screen = _visibleText(tester);
        expect(screen, contains("You're on cellular."));
        expect(find.text('Check My Connection (uses data)'), findsOneWidget);
        expect(find.text('Check without the speed test'), findsOneWidget);

        await _teardown(tester, r.sampler);
      },
    );

    testWidgets('CELLULAR: the cost-labelled tap consents and spends', (
      WidgetTester tester,
    ) async {
      final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
          await _pumpTmc(tester, _Transport.cellularOnly);

      await tester.tap(find.text('Check My Connection (uses data)'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 1);
      expect(r.quality.lastIncludeThroughput, isTrue);

      await _teardown(tester, r.sampler);
    });

    testWidgets('CELLULAR: declining spends no throughput bytes', (
      WidgetTester tester,
    ) async {
      final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
          await _pumpTmc(tester, _Transport.cellularOnly);

      await tester.tap(find.text('Check without the speed test'));
      await tester.pumpAndSettle();

      expect(r.quality.measureCalls, 1);
      expect(r.quality.lastIncludeThroughput, isFalse);

      await _teardown(tester, r.sampler);
    });

    testWidgets('WI-FI Android: the hero auto-start still runs, in full', (
      WidgetTester tester,
    ) async {
      // NO OVER-SUPPRESSION. The most-travelled path in the app must be exactly as
      // fast as it always was for the overwhelming majority of users.
      final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
          await _pumpTmc(tester, _Transport.wifiOnly);

      expect(
        r.quality.measureCalls,
        1,
        reason: 'on Wi-Fi the hero auto-run fires immediately, as always',
      );
      expect(r.quality.lastIncludeThroughput, isTrue);

      await _teardown(tester, r.sampler);
    });

    testWidgets('ETHERNET Android: the hero auto-start still runs, in full', (
      WidgetTester tester,
    ) async {
      final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
          await _pumpTmc(tester, _Transport.ethernetOnly);

      expect(
        r.quality.measureCalls,
        1,
        reason: 'a wired Android box is not cellular and must not be stopped',
      );
      expect(r.quality.lastIncludeThroughput, isTrue);

      await _teardown(tester, r.sampler);
    });

    testWidgets(
      'AN UNREADABLE transport: THE ZERO-TAP PATH IS CLOSED HERE TOO',
      (WidgetTester tester) async {
        // ====================================================================
        // THE EIGHTH ENSHRINED TEST. THIS IS WHAT IT USED TO SAY:
        //
        //   testWidgets('AN UNREADABLE transport: the auto-start still runs
        //                (ambiguity)', ...
        //     // Only a POSITIVE not-on-Wi-Fi verdict stops the run. Stopping on
        //     // `unknown` would interrogate every user whose channel hiccuped.
        //     expect(r.quality.measureCalls, 1);
        //     expect(r.quality.lastIncludeThroughput, isTrue);
        //
        // GREEN — and it was asserting that the app's PRIMARY ENTRY POINT (the home
        // hero pushes this screen with `autoStart: true`) spends up to 573 MB of a
        // cellular user's data with ZERO TAPS, on an Android transport channel that
        // failed to answer. That is Vera's exploit #3, written down as a requirement.
        //
        // THE COMMENT'S WORRY WAS REAL AND IS ADDRESSED PROPERLY. "Stopping on
        // `unknown` would interrogate every user whose channel hiccuped" — and, more
        // importantly, every wired desktop. So the fix does not stop on `unknown`
        // BLINDLY: it stops when the link is not PROVEN FREE, and "proven free"
        // includes a MEASURED Ethernet transport and every platform with no cellular
        // radio (see the ETHERNET and macOS/Windows tests above and below, which are
        // unchanged and still green). A phone whose channel hiccuped is asked. A
        // wired Android TV is not.
        // ====================================================================
        final ({MockQualityClient quality, WifiSignalSampler sampler}) r =
            await _pumpTmc(tester, const _TransportSilent());

        expect(
          r.quality.measureCalls,
          0,
          reason: 'ZERO BYTES. An unreadable channel is not permission to spend.',
        );

        // ...and the user is offered the choice, honestly worded.
        final String screen = _visibleText(tester);
        expect(
          screen,
          contains("We can't tell whether this device is on Wi-Fi or cellular."),
        );
        expect(
          screen,
          isNot(contains("You're on cellular.")),
          reason: 'we still do not claim a link we could not read',
        );
        expect(find.text('Check without the speed test'), findsOneWidget);

        await _teardown(tester, r.sampler);
      },
    );
  });

  // =========================================================================
  // E. THE SAMPLER — the SECOND, INDEPENDENT copy of the hole.
  // =========================================================================
  group('WifiSignalSampler.notOnWifi on ANDROID', () {
    test('load() is no longer a no-op: it settles the transport verdict', () async {
      // WAS: `notOnWifi => _controller?.notOnWifi ?? false`, and `_controller` is
      // built ONLY for iosShortcuts — so this was hard-wired `false` on Android and
      // `load()` returned without doing anything. TMC's gate reads EXACTLY this.
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.androidWifiManager,
        macAdapter: _NoWifiAdapter(),
        connectionService: _android(_Transport.cellularOnly),
      );
      addTearDown(sampler.dispose);

      expect(sampler.notOnWifi, isFalse, reason: 'false until load() settles');
      await sampler.load();
      expect(
        sampler.notOnWifi,
        isTrue,
        reason:
            'THE AWAIT MUST SETTLE THE PROBE — _autoStart awaits exactly '
            'this before it decides whether to spend the data',
      );
    });

    test('Wi-Fi and Ethernet leave notOnWifi false', () async {
      for (final _Transport t in <_Transport>[
        _Transport.wifiOnly,
        _Transport.ethernetOnly,
        _Transport.vpnOpaque,
        _Transport.both,
      ]) {
        final WifiSignalSampler sampler = WifiSignalSampler(
          source: WifiInfoSource.androidWifiManager,
          macAdapter: _NoWifiAdapter(),
          connectionService: _android(t),
        );
        addTearDown(sampler.dispose);
        await sampler.load();
        expect(sampler.notOnWifi, isFalse, reason: '$t must not be nagged');
      }
    });

    test('the verdict LOWERS again when the device returns to Wi-Fi', () async {
      // It must not latch: a user who walks back into Wi-Fi range is no longer
      // paying per byte and must stop being warned.
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.androidWifiManager,
        macAdapter: _NoWifiAdapter(),
        connectionService: _android(_Transport.cellularOnly),
      );
      addTearDown(sampler.dispose);
      await sampler.load();
      expect(sampler.notOnWifi, isTrue);

      final WifiSignalSampler back = WifiSignalSampler(
        source: WifiInfoSource.androidWifiManager,
        macAdapter: _NoWifiAdapter(),
        connectionService: _android(_Transport.wifiOnly),
      );
      addTearDown(back.dispose);
      await back.load();
      expect(back.notOnWifi, isFalse);
    });

    test('macOS and Windows samplers build NO probe and stay false', () async {
      for (final WifiInfoSource s in <WifiInfoSource>[
        WifiInfoSource.macosCoreWlan,
        WifiInfoSource.windowsNativeWifi,
      ]) {
        final WifiSignalSampler sampler = WifiSignalSampler(
          source: s,
          macAdapter: _NoWifiAdapter(),
          // Even handed a cellular service, these sources must not consult it:
          // `_connectionService` is null for them BY CONSTRUCTION.
          connectionService: _android(_Transport.cellularOnly),
        );
        addTearDown(sampler.dispose);
        await sampler.load();
        expect(
          sampler.notOnWifi,
          isFalse,
          reason: '$s must remain a no-op — never nag a wired desktop',
        );
      }
    });
  });
}
