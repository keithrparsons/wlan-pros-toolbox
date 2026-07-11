@Tags(['capture'])
library;

// Book 3 figure-capture harness — "Fix Your Own Wi-Fi" (the consumer book +
// in-app help guide). Renders the 15 capturable app screenshots S1–S15 from the
// chapter drafts with FIXED, prose-matching fixtures and writes 3× PNGs to
// `book3_screenshots/raw/`.
//
// (S16 is NOT an app screen — it is a pasted result living inside an OS Messages
// or email compose view. The headless app harness cannot render that faithfully;
// it is flagged in the deliverable for a Charta mockup, not captured here.)
//
// This reuses the established Book-1/Play capture pattern (RepaintBoundary
// .toImage(pixelRatio: 3.0) inside tester.runAsync — never matchesGoldenFile —
// so a normal `flutter test` / the golden suite is unaffected; these tests assert
// nothing about a committed baseline). The only structural difference from the
// Book-1 content-widget harness is that these consumer screens are mounted as
// MaterialApp.home (so the real AppBar — and its §8.16 Copy action, the S15
// subject — renders exactly as in the running app), framed at iPhone-class width
// (393 logical px), brand AppTheme.dark().
//
// Honesty gate (GL-005 / GL-008): every fixture is realistic and internally
// coherent — a real macOS CoreWLAN snapshot, a real net_quality result. The on-
// screen verdict words / grades are the app's OWN computed output (asserted via
// _expectText before the PNG is written), never painted-on strings. The
// "Couldn't check" shot (S5) uses a genuinely non-resolving Wi-Fi read — the app
// states "Couldn't check" honestly rather than a fabricated zero.
//
// Run:
//   flutter test --tags capture test/book3_screenshots/capture_book3_figures_test.dart
// or via tool/capture_book3_screenshots.sh.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';

import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_glossary_screen.dart';
import 'package:wlan_pros_toolbox/services/glossary/glossary_service.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

// ── Capture constants ───────────────────────────────────────────────────────

/// iPhone-class logical width for every Book 3 figure (the book is iPhone-first).
const double kPhoneWidth = 393;

/// 3× DPI — print / e-book quality.
const double kPixelRatio = 3.0;

/// Output directory for the raw (un-annotated) Book 3 PNGs.
const String kOutDir = 'book3_screenshots/raw';

final GlobalKey _captureKey = GlobalKey();

// ── Live-fixture fakes (constructor-injection seams) ────────────────────────

/// A deterministic DNS resolution-time probe so the S06 capture never touches a
/// live resolver (and never leaks a timeout Timer under FakeAsync).
class _FakeDnsProbe extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async =>
      DnsProbeResult.success(host: 'cloudflare.com', millis: 12);
}

/// A deterministic local-addressing reader for the S06 capture.
class _FakeNetworkDetails extends NetworkDetailsService {
  @override
  Future<NetworkDetails> read() async => const NetworkDetails(
        localIp: '192.168.1.42',
        subnetMask: '255.255.255.0',
        gateway: '192.168.1.1',
      );
}

/// A macOS adapter that returns one fixed [ConnectedAp] — drives the Wi-Fi
/// Information screen to exact, prose-matching RF values (S7 / S8 / S11 / S12).
class _FixedMacAdapter implements WifiInfoAdapter {
  _FixedMacAdapter(this.ap);
  final ConnectedAp ap;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ap;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A macOS adapter at a fixed Tx rate, so usable Wi-Fi = 0.55 × Tx lands the
/// Test My Connection chips on a chosen absolute tier (Strong >250 / Moderate
/// 100–250 / Weak <100). RSSI/SNR set the live-signal grade for the shots that
/// show the sparkline (S6).
class _TxLinkMacAdapter implements WifiInfoAdapter {
  _TxLinkMacAdapter(this.txRateMbps, {this.rssi = -55, this.snr = 37});
  final double txRateMbps;
  final int rssi;
  final int snr;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ConnectedAp.fromWifiInfo(
        WifiInfo(
          interfaceName: 'en0',
          ssid: 'WLANPros-5G',
          bssid: 'a4:83:e7:00:11:22',
          rssiDbm: rssi,
          noiseDbm: rssi - snr,
          snrDb: snr,
          txRateMbps: txRateMbps,
          phyMode: '802.11ax',
          channel: 36,
          channelWidthMhz: 80,
          band: '5 GHz',
          countryCode: 'US',
          hardwareAddress: 'a4:83:e7:aa:bb:cc',
          poweredOn: true,
          locationAuthorized: true,
        ),
      );
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A macOS adapter whose snapshot read never resolves — models the honest
/// "Couldn't check" Wi-Fi axis for S5. The internet side still measures.
class _HangingMacAdapter implements WifiInfoAdapter {
  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() => Completer<ConnectedAp>().future;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => false;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.notDetermined;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A net_quality result builder for the comparison / quality screens.
QualityResult _internetResult({
  required double down,
  required double up,
  required double latencyMs,
  required double jitterMs,
  required double lossPct,
  QualityGrade downUpGrade = QualityGrade.good,
  QualityGrade latencyGrade = QualityGrade.good,
  QualityGrade lossGrade = QualityGrade.good,
  QualityGrade jitterGrade = QualityGrade.good,
  QualityGrade respGrade = QualityGrade.good,
  double respRpm = 1200,
}) {
  return QualityResult(
    source: QualitySource.mock,
    measuredAt: DateTime.utc(2026, 1, 1),
    metrics: <QualityMetric>[
      QualityMetric(
        id: MetricIds.latency,
        label: 'Latency',
        value: latencyMs,
        unit: 'ms',
        grade: latencyGrade,
      ),
      QualityMetric(
        id: MetricIds.jitter,
        label: 'Jitter',
        value: jitterMs,
        unit: 'ms',
        grade: jitterGrade,
      ),
      QualityMetric(
        id: MetricIds.loss,
        label: 'Loss',
        value: lossPct,
        unit: '%',
        grade: lossGrade,
      ),
      QualityMetric(
        id: MetricIds.download,
        label: 'Download',
        value: down,
        unit: 'Mbps',
        grade: downUpGrade,
      ),
      QualityMetric(
        id: MetricIds.upload,
        label: 'Upload',
        value: up,
        unit: 'Mbps',
        grade: downUpGrade,
      ),
      QualityMetric(
        id: MetricIds.responsiveness,
        label: 'Responsiveness',
        value: respRpm,
        unit: 'RPM',
        grade: respGrade,
      ),
    ],
  );
}

// ── Capture plumbing ─────────────────────────────────────────────────────────

/// Mounts [child] as the home of a full MaterialApp under AppTheme.dark(), framed
/// at iPhone width × [height], wrapped in a RepaintBoundary so we snapshot the
/// WHOLE screen (AppBar + body) at 3×. MaterialApp.home (not a bare MediaQuery)
/// is required so the screens' Scaffold / Navigator / AppBar — and the §8.16 Copy
/// action in the AppBar (S15) — render exactly as in the running app.
Widget _host(Widget child, double height) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(kPhoneWidth, height),
      devicePixelRatio: kPixelRatio,
      textScaler: const TextScaler.linear(1.0),
    ),
    child: RepaintBoundary(
      key: _captureKey,
      child: SizedBox(
        width: kPhoneWidth,
        height: height,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: child,
        ),
      ),
    ),
  );
}

/// Sizes the surface, pumps [build], settles it, runs [drive] to preset the
/// fixture, asserts the honesty gate via [verify], then writes `<figId>.png` at
/// 3×. [settle] false lets a screen with a live poll timer (S6) pump a bounded
/// number of frames instead of settling forever.
Future<void> _capture(
  WidgetTester tester, {
  required String figId,
  required double height,
  required Widget Function() build,
  Future<void> Function(WidgetTester tester)? drive,
  void Function(WidgetTester tester)? verify,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(Size(kPhoneWidth, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(kPhoneWidth * kPixelRatio, height * kPixelRatio);
  tester.view.devicePixelRatio = kPixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(build(), height));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
  if (drive != null) {
    await drive(tester);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
  }
  if (verify != null) verify(tester);

  await _writePng(tester, figId);

  // Unmount so any live poll timer started by the screen (S6's WifiSignalSampler
  // macOS poll) is cancelled before the test ends — otherwise the leaked periodic
  // timer trips the framework's pending-timer guard at teardown. The screen's
  // dispose() calls the sampler's async stop(); draining it inside runAsync lets
  // that future complete and the periodic timer cancel. The PNG is already
  // written, so this affects nothing visual.
  if (!settle) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }
}

/// Snapshots the captured RepaintBoundary at [kPixelRatio] and writes the PNG.
Future<void> _writePng(WidgetTester tester, String figId) async {
  final RenderRepaintBoundary boundary = _captureKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: kPixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final Directory dir = Directory(kOutDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('$kOutDir/$figId.png').writeAsBytesSync(byteData!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE $figId.png  ${image.width}x${image.height}px');
    image.dispose();
  });
}

/// Asserts a Text widget with [exact] is on screen — the honesty gate that the
/// rendered value is the app's own output, not a painted-on string.
void _expectText(String exact) {
  expect(find.text(exact), findsWidgets,
      reason: 'expected on-screen value "$exact" not found');
}

void main() {
  // A reusable internet "Strong/healthy" result for the chip-only shots.
  QualityResult strongInternet() => _internetResult(
        down: 400, up: 360, latencyMs: 12, jitterMs: 2, lossPct: 0,
        downUpGrade: QualityGrade.excellent,
        latencyGrade: QualityGrade.excellent,
        lossGrade: QualityGrade.excellent,
        jitterGrade: QualityGrade.excellent,
        respGrade: QualityGrade.excellent,
      );

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 1 — Test My Connection (the consumer front door).
  // ════════════════════════════════════════════════════════════════════════

  // S1 — idle: the near-empty front door, the one plain line + the one button.
  testWidgets('S01 Test My Connection — idle (one button, one line)',
      (tester) async {
    await _capture(
      tester,
      figId: 'S01-test-my-connection-idle',
      height: 1000,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(scriptedResult: strongInternet()),
      ),
      verify: (t) => _expectText('Check My Connection'),
    );
  });

  // S2 — Wi-Fi the weaker road. Tx 60 → usable 33 Mbps (Wi-Fi chip "Weak");
  // internet download 440 (Internet chip "Strong") but graded FAIR so the
  // verdict honestly lands on the Wi-Fi link → hero "Your Wi-Fi is the slow
  // part." (The app's middle tier word is "Moderate"; ch1's "Fair" is prose
  // shorthand — captured honestly as the app states it.)
  testWidgets('S02 Test My Connection — Wi-Fi weaker', (tester) async {
    await _capture(
      tester,
      figId: 'S02-test-my-connection-wifi-weaker',
      height: 1760,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(60, rssi: -68, snr: 18),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 440, up: 360, latencyMs: 22, jitterMs: 4, lossPct: 0,
            downUpGrade: QualityGrade.fair,
            latencyGrade: QualityGrade.fair,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Your Wi-Fi is the slow part.');
        _expectText('Weak'); // Wi-Fi chip
        _expectText('Strong'); // Internet chip
      },
    );
  });

  // S3 — Internet the weaker road. Tx 720 → usable 396 (Wi-Fi chip "Strong");
  // internet download 40 (Internet chip "Weak") graded fair → upstream verdict
  // → hero "Your internet is the slow part." Headline points at the provider.
  testWidgets('S03 Test My Connection — Internet weaker', (tester) async {
    await _capture(
      tester,
      figId: 'S03-test-my-connection-internet-weaker',
      height: 1760,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 40, up: 20, latencyMs: 40, jitterMs: 8, lossPct: 1,
            downUpGrade: QualityGrade.fair,
            latencyGrade: QualityGrade.fair,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Your internet is the slow part.');
        _expectText('Strong'); // Wi-Fi chip
        _expectText('Weak'); // Internet chip
      },
    );
  });

  // S4 — both roads strong → hero "Your Wi-Fi and internet both look fine."
  // Tx 720 → usable 396 (Strong); internet download 400 (Strong), graded
  // excellent → bothHealthy. The headline sends you downstream to the app/site.
  testWidgets('S04 Test My Connection — both strong', (tester) async {
    await _capture(
      tester,
      figId: 'S04-test-my-connection-both-strong',
      height: 1760,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(scriptedResult: strongInternet()),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pumpAndSettle();
      },
      // Both axes land on the SAME real tier (Strong / Strong), so the screen's
      // own same-tier hero fires: "Both sides are strong. They're about the same
      // speed." — the honest "both roads healthy, look downstream" message ch1
      // frames as "both strong." Both chips read Strong.
      verify: (t) {
        _expectText('Both sides are strong. They’re about the same speed.');
        _expectText('Strong');
      },
    );
  });

  // S5 — one road honestly "Couldn't check." The Wi-Fi read never resolves; the
  // internet side measures. The app states the honest non-measurement, never a
  // fake zero → hero "We checked your internet, but not your Wi-Fi."
  testWidgets('S05 Test My Connection — Couldn\'t check', (tester) async {
    await _capture(
      tester,
      figId: 'S05-test-my-connection-couldnt-check',
      height: 1760,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _HangingMacAdapter(),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 200, up: 100, latencyMs: 22, jitterMs: 4, lossPct: 0,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pump(const Duration(seconds: 9));
        await t.pumpAndSettle();
      },
      verify: (t) => _expectText("Couldn't check"),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 2 — Wi-Fi vs Internet verdict (the merged Test My Connection screen
  // with the live-signal walk-around tip showing).
  // ════════════════════════════════════════════════════════════════════════

  // S6 — the verdict line + the walk-around tip. Run close to the box: Tx 720 →
  // usable 396 Mbps; internet download 150. deltaPct = 100×(396−150)/150
  // = +164% → the app's OWN comparison line "Your Wi-Fi link is 164% faster than
  // your internet connection." enableLiveSampling true so the live-signal card —
  // which carries the walk-around tip — renders; the macOS sampler polls the
  // injected fixed adapter (a real, flat sample, not fabricated). settle:false to
  // pump a bounded number of frames rather than wait on the live poll timer.
  testWidgets('S06 Wi-Fi vs Internet — verdict + walk-around tip',
      (tester) async {
    await _capture(
      tester,
      figId: 'S06-wifi-vs-internet-verdict',
      height: 2400,
      settle: false,
      // Let the SCREEN build its own sampler from the injected macOS adapter
      // (do NOT inject the sampler): the screen owns that sampler's lifecycle and
      // disposes it on unmount, cancelling the macOS poll timer — an injected
      // sampler is treated as the test's and is never disposed, leaking the timer.
      build: () => TestMyConnectionScreen(
        enableLiveSampling: true,
        // This figure captures the live walk-around card, not the bottom Cloud
        // Apps panel; disable the panel so its real reachability socket does not
        // leak a pending timer in this settle:false manual-pump capture.
        enableCloudApps: false,
        // Inject deterministic DNS-probe + addressing fakes so the real
        // resolver / interface reads (and their timeout Timers) do not leak into
        // this settle:false manual-pump capture — the figure shows the live card,
        // not the Network/DNS report sections.
        dnsProbeService: _FakeDnsProbe(),
        networkDetailsService: _FakeNetworkDetails(),
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720, rssi: -52, snr: 38),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 150, up: 100, latencyMs: 18, jitterMs: 3, lossPct: 0,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 150));
        }
      },
      verify: (t) {
        _expectText('Your Wi-Fi link is 164% faster than your internet '
            'connection.');
        _expectText('Walk around while this runs to see how your Wi-Fi signal '
            'changes from spot to spot.');
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 3 + 5 — Wi-Fi Information (the five facts).
  // ════════════════════════════════════════════════════════════════════════

  // S7 — a GOOD connection: WLANPros-6E, band 6 GHz, ch 37 (a real PSC),
  // 160 MHz, RSSI -52 (Strong), SNR 38, Tx 1441 / Rx 1200. Every fact lines up.
  testWidgets('S07 Wi-Fi Information — good connection', (tester) async {
    await _capture(
      tester,
      figId: 'S07-wifi-information-good',
      height: 2420,
      build: () => WifiInfoScreen(
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _FixedMacAdapter(
          ConnectedAp.fromWifiInfo(
            WifiInfo(
              interfaceName: 'en0',
              ssid: 'WLANPros-6E',
              bssid: 'a4:83:e7:00:11:22',
              rssiDbm: -52,
              noiseDbm: -90, // SNR 38
              snrDb: 38,
              txRateMbps: 1441,
              rxRateMbps: 1200,
              phyMode: '802.11ax',
              channel: 37, // a real 6 GHz PSC: (37-5) % 16 == 0
              channelWidthMhz: 160,
              band: '6 GHz',
              countryCode: 'US',
              hardwareAddress: 'a4:83:e7:aa:bb:cc',
              poweredOn: true,
              locationAuthorized: true,
            ),
          ),
        ),
      ),
      verify: (t) {
        _expectText('WLANPros-6E');
        _expectText('-52');
        _expectText('6 GHz');
        _expectText('1441');
      },
    );
  });

  // S8 — a BAD connection: Linksys-Home, 2.4 GHz only, ch 6 (crowded band),
  // RSSI -68 (Fair), SNR 18, Tx 72 (low link speed). The bad shape, telling on
  // itself.
  testWidgets('S08 Wi-Fi Information — bad connection', (tester) async {
    await _capture(
      tester,
      figId: 'S08-wifi-information-bad',
      height: 2200,
      build: () => WifiInfoScreen(
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _FixedMacAdapter(
          ConnectedAp.fromWifiInfo(
            WifiInfo(
              interfaceName: 'en0',
              ssid: 'Linksys-Home',
              bssid: 'c0:56:27:aa:bb:cc',
              rssiDbm: -68,
              noiseDbm: -86, // SNR 18
              snrDb: 18,
              txRateMbps: 72,
              rxRateMbps: 72,
              phyMode: '802.11n',
              channel: 6,
              channelWidthMhz: 20,
              band: '2.4 GHz',
              countryCode: 'US',
              hardwareAddress: 'c0:56:27:dd:ee:ff',
              poweredOn: true,
              locationAuthorized: true,
            ),
          ),
        ),
      ),
      verify: (t) {
        _expectText('Linksys-Home');
        _expectText('-68');
        _expectText('2.4 GHz');
        _expectText('72');
      },
    );
  });

  // S11 — BEFORE the fix: the far-corner reading. WLANPros-5G but on 2.4 GHz,
  // RSSI -72 (Fair), SNR 16, Tx 58 (low link speed). The "before" starting line.
  testWidgets('S11 Wi-Fi Information — before the fix', (tester) async {
    await _capture(
      tester,
      figId: 'S11-wifi-information-before-fix',
      height: 2200,
      build: () => WifiInfoScreen(
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _FixedMacAdapter(
          ConnectedAp.fromWifiInfo(
            WifiInfo(
              interfaceName: 'en0',
              ssid: 'WLANPros-Home',
              bssid: 'c0:56:27:00:24:06',
              rssiDbm: -72, // Fair
              noiseDbm: -88, // SNR 16
              snrDb: 16,
              txRateMbps: 58, // low link speed
              rxRateMbps: 58,
              phyMode: '802.11n',
              channel: 6,
              channelWidthMhz: 20,
              band: '2.4 GHz',
              countryCode: 'US',
              hardwareAddress: 'c0:56:27:dd:ee:ff',
              poweredOn: true,
              locationAuthorized: true,
            ),
          ),
        ),
      ),
      verify: (t) {
        _expectText('WLANPros-Home');
        _expectText('-72');
        _expectText('2.4 GHz');
      },
    );
  });

  // S12 — AFTER the fix: same network, same screen, now from closer to the box
  // and moved onto the fast lane. WLANPros-Home but 5 GHz ch 44, RSSI -49
  // (Strong), SNR 41, Tx 866 (link speed recovered). Proof the fix worked.
  testWidgets('S12 Wi-Fi Information — after the fix', (tester) async {
    await _capture(
      tester,
      figId: 'S12-wifi-information-after-fix',
      height: 2200,
      build: () => WifiInfoScreen(
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _FixedMacAdapter(
          ConnectedAp.fromWifiInfo(
            WifiInfo(
              interfaceName: 'en0',
              ssid: 'WLANPros-Home',
              bssid: 'c0:56:27:00:24:48',
              rssiDbm: -49, // Strong
              noiseDbm: -90, // SNR 41
              snrDb: 41,
              txRateMbps: 866, // recovered link speed
              rxRateMbps: 866,
              phyMode: '802.11ac',
              channel: 44,
              channelWidthMhz: 80,
              band: '5 GHz',
              countryCode: 'US',
              hardwareAddress: 'c0:56:27:dd:ee:ff',
              poweredOn: true,
              locationAuthorized: true,
            ),
          ),
        ),
      ),
      verify: (t) {
        _expectText('WLANPros-Home');
        _expectText('-49');
        _expectText('5 GHz');
        _expectText('866');
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 4 — Network Quality (six graded rows).
  // ════════════════════════════════════════════════════════════════════════

  LatencyStats goodStats() => const LatencyStats(
        avgMs: 24, minMs: 18, maxMs: 34, jitterMs: 6, lossPct: 0,
        sent: 5, received: 5,
      );

  Future<Duration?> fakeProber(String host, int port, Duration timeout) async {
    if (host == 'one.one.one.one') return const Duration(milliseconds: 12);
    if (host == 'www.google.com') return const Duration(milliseconds: 24);
    return null;
  }

  const List<PopularSite> sites = <PopularSite>[
    PopularSite(name: 'Cloudflare', host: 'one.one.one.one'),
    PopularSite(name: 'Google', host: 'www.google.com'),
  ];

  // S9 — six graded rows, NO single score: latency, jitter, loss, download,
  // upload, responsiveness, each graded on its own.
  testWidgets('S09 Network Quality — six graded rows', (tester) async {
    await _capture(
      tester,
      figId: 'S09-network-quality-six-rows',
      height: 2000,
      build: () => NetQualityScreen(
        client: MockQualityClient(
          scriptedResult: _internetResult(
            down: 180, up: 12, latencyMs: 24, jitterMs: 6, lossPct: 0,
            downUpGrade: QualityGrade.good,
          ),
        ),
        reachabilityProbe: ReachabilityProbe(prober: fakeProber, sites: sites),
        monitor: LiveQualityMonitor(sampler: () async => goodStats()),
      ),
      drive: (t) async {
        await t.tap(find.text('Run test'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Latency');
        _expectText('Jitter');
        _expectText('Loss');
        _expectText('Download');
        _expectText('Upload');
        _expectText('Responsiveness');
      },
    );
  });

  // S10 — the call-killer profile: a gorgeous DOWNLOAD grade (Excellent) sitting
  // next to WEAK jitter and FAIR loss. A speed test would call this great; the
  // call still freezes. download/upload Excellent; jitter Poor; loss Fair.
  //
  // Loss is set to 2.0 % — genuinely FAIR by the engine (scoring.dart grades
  // loss < 2.5 % as Fair, >= 2.5 % as Poor), so the rendered loss chip honestly
  // reads Fair, matching the "shaky Fair loss" caption. NOTE: the loss row is
  // part of the live-sampled trio (latency/jitter/loss), so its on-screen value
  // AND grade come from the live MONITOR sample below, which grades via
  // QualityScoring.gradeLossPct — NOT from the one-shot lossGrade override. The
  // monitor sampler's lossPct is therefore the source of truth for this figure
  // and is set to 2.0 % here. (A prior fixture used 3 %, which the engine grades
  // Poor, contradicting the "Fair" caption — Book 3 technical-edit item C2.)
  // sent/received (72/71 ≈ 1.4 %) only gate the latency-success path and stay
  // realistic; the explicit lossPct field drives the displayed loss.
  testWidgets('S10 Network Quality — call-killer profile', (tester) async {
    await _capture(
      tester,
      figId: 'S10-network-quality-call-killer',
      height: 2000,
      build: () => NetQualityScreen(
        client: MockQualityClient(
          scriptedResult: _internetResult(
            down: 480, up: 240, latencyMs: 60, jitterMs: 45, lossPct: 2,
            downUpGrade: QualityGrade.excellent,
            latencyGrade: QualityGrade.fair,
            jitterGrade: QualityGrade.poor,
            lossGrade: QualityGrade.fair,
            respGrade: QualityGrade.fair,
          ),
        ),
        reachabilityProbe: ReachabilityProbe(prober: fakeProber, sites: sites),
        monitor: LiveQualityMonitor(
          sampler: () async => const LatencyStats(
            avgMs: 60, minMs: 22, maxMs: 140, jitterMs: 45, lossPct: 2,
            sent: 72, received: 71,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Run test'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Download');
        _expectText('Jitter');
        _expectText('Loss');
        // C2 honesty gate: the loss row must render the engine's OWN computed
        // grade. 2 % loss grades Fair (scoring.dart: < 2.5 % → Fair), matching
        // the "shaky Fair loss" caption. "2%" is the rendered loss value (the
        // monitor sample, rounded to an integer percent). Jitter 45 ms stays
        // Poor, and Download Excellent — the call-killer trap intact.
        _expectText('2%'); // loss value, displayed
        _expectText('Fair'); // loss grade chip (engine-computed)
        _expectText('Poor'); // jitter grade chip
        _expectText('Excellent'); // download grade chip
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 6 — Test My Connection read as a HANDOFF + the Glossary.
  // ════════════════════════════════════════════════════════════════════════

  // S13 — Internet weaker, read as the "call the provider" handoff. Same coherent
  // fixture as S3 (Wi-Fi Strong, Internet Weak, "Your internet is the slow part."),
  // framed in ch6 as the stop-here / hand-off signal.
  testWidgets('S13 Test My Connection — Internet weaker handoff',
      (tester) async {
    await _capture(
      tester,
      figId: 'S13-test-my-connection-handoff',
      height: 1760,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 40, up: 20, latencyMs: 40, jitterMs: 8, lossPct: 1,
            downUpGrade: QualityGrade.fair,
            latencyGrade: QualityGrade.fair,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Your internet is the slow part.');
        _expectText('Strong'); // Wi-Fi
        _expectText('Weak'); // Internet
      },
    );
  });

  // S14 — Glossary: a term lookup. The real bundled glossary asset loads (offline
  // asset read resolved inside runAsync), then "channel" is typed into the search
  // field so the plain-English "Channel" definition leads the frame. ("Channel"
  // is a standalone glossary term, the cleaner of the ch6 "band/channel" pair —
  // "band" only exists as "2.4 GHz Band" / "5 GHz Band" / "6 GHz Band".)
  testWidgets('S14 Glossary — term lookup ("channel")', (tester) async {
    await _capture(
      tester,
      figId: 'S14-glossary-channel-lookup',
      height: 1500,
      // Inject the service built from the REAL bundled asset (read from disk),
      // so the capture uses the real data without depending on the async
      // rootBundle load settling — the larger multilingual asset no longer
      // resolves inside a bare pumpAndSettle. English is the default render.
      build: () => WifiGlossaryScreen(
        service: GlossaryService.fromJson(
          File('assets/data/glossary.json').readAsStringSync(),
        ),
      ),
      drive: (t) async {
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, 'channel');
        await t.pumpAndSettle();
      },
      verify: (t) => _expectText('Channel'),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 7 — the Copy-results affordance.
  // ════════════════════════════════════════════════════════════════════════

  // S15 — the §8.16 Copy action on a result screen. Test My Connection after a
  // run (the same coherent internet-weaker fixture as S13), framed so the AppBar
  // Copy-results action is in view. Mounted as MaterialApp.home so the real
  // AppBar — and its trailing AppCopyAction — renders exactly as in the app.
  // (S16 — the copied reading pasted into a Messages/email draft — is NOT an app
  // screen and is NOT captured here; see the deliverable note.)
  testWidgets('S15 Copy results affordance — result screen', (tester) async {
    await _capture(
      tester,
      figId: 'S15-copy-results-affordance',
      height: 900, // short frame: keep the AppBar + Copy action + hero in view
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 40, up: 20, latencyMs: 40, jitterMs: 8, lossPct: 1,
            downUpGrade: QualityGrade.fair,
            latencyGrade: QualityGrade.fair,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pumpAndSettle();
      },
      // Honesty gate: the Copy action must be present (enabled) once results
      // exist — its idle semantics label is "Copy results".
      verify: (t) => expect(
        find.bySemanticsLabel('Copy results'),
        findsOneWidget,
        reason: 'the §8.16 Copy-results AppBar action must be present and '
            'enabled on a result screen',
      ),
    );
  });
}
