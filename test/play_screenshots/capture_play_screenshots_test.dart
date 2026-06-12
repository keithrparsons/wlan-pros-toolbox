@Tags(['capture'])
library;

// Google Play Store phone-screenshot capture harness.
//
// Produces FULL-SCREEN app views (the whole Scaffold, AppBar included) at
// EXACTLY 1080×1920 logical-px × pixelRatio → device pixels, the Play phone
// requirement (portrait, 9:16). Unlike the book-figure harness
// (test/book_screenshots/capture_book_figures_test.dart) — which captures
// single content-sized tool WIDGETS at iPhone width — this harness mounts each
// real screen as MaterialApp.home (so AppBar + Navigator work), pins the
// surface to 360×640 logical px, and snapshots at pixelRatio 3.0 →
// 1080×1920 device px.
//
// Tagged `capture` (NOT `golden`) so a normal `flutter test` / the CI golden
// suite is unaffected: these tests assert nothing about a committed baseline.
// They mount the screen, settle it (driving in realistic sample data where the
// screen needs it), assert the representative value is on-screen (the honesty
// gate — the rendered value is the app's own output, not a painted-on string),
// then write the PNG.
//
// Theme: AppTheme.dark() (the brand #1A1A1A canvas), textScaler 1.0, fonts
// pinned by test/flutter_test_config.dart.
//
// Sample-data honesty (GL-005 / GL-008):
//  * Live-data screens (Wi-Fi Information, Test My Connection, Network Quality)
//    are driven through the SAME constructor-injection seams the book harness
//    uses — a fixed macOS ConnectedAp adapter and a MockQualityClient with a
//    scripted result. The values shown are realistic and internally coherent
//    (a real 6 GHz 6E link; a real internet result). They are SAMPLE data, not
//    a live device read — flagged in the deliverable as representative.
//  * Pure calculators (EIRP) and read-only references (Channel Map, Glossary)
//    and the data-driven Home / Category screens render fully offline with no
//    fabrication — the calculator output is computed live from the typed input.
//
// Run:
//   flutter test --tags capture test/play_screenshots/capture_play_screenshots_test.dart
// or via tool/capture_play_screenshots.sh (which also strips alpha → 24-bit RGB
// and verifies every PNG is exactly 1080×1920).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';

import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eirp_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_glossary_screen.dart';
import 'package:wlan_pros_toolbox/services/glossary/glossary_service.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

// ── Capture constants ───────────────────────────────────────────────────────

/// Logical px of the phone frame. 360 × 3.0 = 1080, 640 × 3.0 = 1920 → the Play
/// phone requirement (portrait 9:16, 1080×1920) lands EXACTLY.
const double kPhoneLogicalWidth = 360;
const double kPhoneLogicalHeight = 640;
const double kPixelRatio = 3.0;

const String kOutDir = 'play_screenshots/raw';

/// 10" tablet frame: 800 × 1280 logical × pixelRatio 2.0 → 1600 × 2560 device
/// px (9:16 portrait). Width ≥ 720 trips the app's tablet layout.
const double kTabletLogicalWidth = 800;
const double kTabletLogicalHeight = 1280;
const double kTabletPixelRatio = 2.0;

const String kTabletOutDir = 'play_screenshots/raw-tablet';

final GlobalKey _captureKey = GlobalKey();

// ── Live-fixture fakes (constructor-injection seams) ────────────────────────

/// An Android adapter that returns one fixed [ConnectedAp] built through the
/// Android mapping ([ConnectedAp.fromAndroidWifiInfo]). Reports the Android
/// platform label and the Android capability flags (rxRateAvailable +
/// securityAvailable true), so the Wi-Fi Information screen renders the FULL
/// live-data set Android actually exposes — Rx rate AND Tx rate, a real
/// security type, SSID/BSSID/RSSI/noise/SNR/channel/width/band/standard — with
/// NO "not available on this platform" lines. Sample values are realistic and
/// internally coherent (a real 6 GHz Wi-Fi 6E link), injected via the same
/// constructor seam the macOS fixture uses.
class _FixedAndroidAdapter implements WifiInfoAdapter {
  _FixedAndroidAdapter(this.ap);
  final ConnectedAp ap;

  @override
  String get platformLabel => 'Android';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ap;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A macOS adapter at a fixed Tx rate → usable Wi-Fi = 0.55 × Tx, used to land
/// the Test My Connection chips on a chosen tier.
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
          ssid: 'WLANPros-6E',
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
  Future<bool> openNamePermissionSettings() async => true;
}

/// A net_quality result builder for the comparison/quality screens.
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
          grade: latencyGrade),
      QualityMetric(
          id: MetricIds.jitter,
          label: 'Jitter',
          value: jitterMs,
          unit: 'ms',
          grade: jitterGrade),
      QualityMetric(
          id: MetricIds.loss,
          label: 'Loss',
          value: lossPct,
          unit: '%',
          grade: lossGrade),
      QualityMetric(
          id: MetricIds.download,
          label: 'Download',
          value: down,
          unit: 'Mbps',
          grade: downUpGrade),
      QualityMetric(
          id: MetricIds.upload,
          label: 'Upload',
          value: up,
          unit: 'Mbps',
          grade: downUpGrade),
      QualityMetric(
          id: MetricIds.responsiveness,
          label: 'Responsiveness',
          value: respRpm,
          unit: 'RPM',
          grade: respGrade),
    ],
  );
}

// ── Capture plumbing ─────────────────────────────────────────────────────────

/// Mounts [child] as the home of a full MaterialApp under AppTheme.dark(), sized
/// to the phone frame and wrapped in a RepaintBoundary so we snapshot the WHOLE
/// screen (AppBar + body) at [kPixelRatio]. A MaterialApp (not a bare
/// MediaQuery) is required so the screens' Scaffold / Navigator / AppBar all
/// render exactly as they do in the running app.
Widget _host(Widget child, double w, double h, double ratio) {
  return MediaQuery(
    data: MediaQueryData(
      size: Size(w, h),
      devicePixelRatio: ratio,
      textScaler: const TextScaler.linear(1.0),
    ),
    child: RepaintBoundary(
      key: _captureKey,
      child: SizedBox(
        width: w,
        height: h,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: child,
        ),
      ),
    ),
  );
}

/// Sizes the surface to the phone frame, pumps [build], settles it, optionally
/// drives sample data via [drive], asserts the honesty gate via [verify], then
/// writes `<id>.png` at exactly 1080×1920 device px.
Future<void> _capture(
  WidgetTester tester, {
  required String id,
  required Widget Function() build,
  Future<void> Function(WidgetTester tester)? drive,
  void Function(WidgetTester tester)? verify,
}) =>
    _captureAt(
      tester,
      id: id,
      build: build,
      drive: drive,
      verify: verify,
      logicalWidth: kPhoneLogicalWidth,
      logicalHeight: kPhoneLogicalHeight,
      ratio: kPixelRatio,
      outDir: kOutDir,
    );

Future<void> _captureTablet(
  WidgetTester tester, {
  required String id,
  required Widget Function() build,
  Future<void> Function(WidgetTester tester)? drive,
  void Function(WidgetTester tester)? verify,
}) =>
    _captureAt(
      tester,
      id: id,
      build: build,
      drive: drive,
      verify: verify,
      logicalWidth: kTabletLogicalWidth,
      logicalHeight: kTabletLogicalHeight,
      ratio: kTabletPixelRatio,
      outDir: kTabletOutDir,
    );

Future<void> _captureAt(
  WidgetTester tester, {
  required String id,
  required Widget Function() build,
  required double logicalWidth,
  required double logicalHeight,
  required double ratio,
  required String outDir,
  Future<void> Function(WidgetTester tester)? drive,
  void Function(WidgetTester tester)? verify,
}) async {
  await tester.binding.setSurfaceSize(Size(logicalWidth, logicalHeight));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(logicalWidth * ratio, logicalHeight * ratio);
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(build(), logicalWidth, logicalHeight, ratio));
  await tester.pumpAndSettle();
  if (drive != null) {
    await drive(tester);
    await tester.pumpAndSettle();
  }
  if (verify != null) verify(tester);

  await _writePng(tester, id, ratio, outDir);
}

Future<void> _writePng(
    WidgetTester tester, String id, double ratio, String outDir) async {
  final RenderRepaintBoundary boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: ratio);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Directory dir = Directory(outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('$outDir/$id.png').writeAsBytesSync(byteData!.buffer.asUint8List());
    // ignore: avoid_print
    print('WROTE $id.png  ${image.width}x${image.height}px');
    image.dispose();
  });
}

void _expectText(String exact) {
  expect(find.text(exact), findsWidgets,
      reason: 'expected on-screen value "$exact" not found');
}

void main() {
  // ── 1. Home / "Check My Connection" consumer front door (the hero) ──────────
  testWidgets('play-1 Home — Check My Connection front door', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-1-check-my-connection',
      build: () => const HomeScreen(),
      verify: (t) {
        _expectText('Is it your Wi-Fi or your Internet?');
        _expectText('Check My Connection');
      },
    );
  });

  // ── 2. Test My Connection — the verdict (Wi-Fi is the slow part) ────────────
  // Tx 60 → usable 33 Mbps (Wi-Fi "Weak"); internet avg 400 (Strong) but graded
  // FAIR so the verdict honestly lands on the Wi-Fi link. The hero sentence is
  // the engine's OWN output. Same coherent fixture as book fig-8-1.
  testWidgets('play-2 Test My Connection — verdict', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-2-test-my-connection',
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(60, rssi: -68, snr: 18),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 440,
            up: 360,
            latencyMs: 22,
            jitterMs: 4,
            lossPct: 0,
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

  // ── 3. Wi-Fi Information — the Android live-data set (full RF + Rx + security) ─
  // This is the GOOGLE PLAY (Android) listing, so the shot must show the data
  // ANDROID actually exposes — not the macOS subset. Driven through the ANDROID
  // source ([WifiInfoSource.androidWifiManager]) + the Android mapping
  // ([ConnectedAp.fromAndroidWifiInfo]), so the screen renders the full live set
  // with NO "not available on this platform" lines: Rx rate AND Tx rate, a real
  // WPA3-Personal security type, SSID/BSSID/RSSI/noise/SNR/channel/width/band/
  // standard. A coherent 6 GHz Wi-Fi 6E link: WLANPros-6E, ch 37 (a real PSC),
  // 160 MHz, RSSI -52 (Excellent), noise -90 → SNR 38, Tx 1441 / Rx 1200,
  // 802.11ax (Wi-Fi 6E), WPA3 Personal. SAMPLE injected via the fixed Android
  // adapter (the Android WifiManager bridge supplies the same fields live).
  testWidgets('play-3 Wi-Fi Information — Android live-data set', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-3-wifi-information',
      build: () => WifiInfoScreen(
        sourceOverride: WifiInfoSource.androidWifiManager,
        macAdapter: _FixedAndroidAdapter(
          ConnectedAp.fromAndroidWifiInfo(
            WifiInfo(
              interfaceName: 'wlan0',
              ssid: 'WLANPros-6E',
              bssid: 'a4:83:e7:00:11:22',
              rssiDbm: -52,
              noiseDbm: -90, // SNR 38 (supplied → no Android noise-floor note)
              snrDb: 38,
              txRateMbps: 1441,
              rxRateMbps: 1200, // Android exposes Rx via getRxLinkSpeedMbps()
              // fromAndroidWifiInfo passes phyMode straight through to
              // `standard`, so carry the full formatted label here.
              phyMode: '802.11ax (Wi-Fi 6E)',
              channel: 37, // a real 6 GHz PSC: (37-5) % 16 == 0
              channelWidthMhz: 160,
              band: '6 GHz',
              countryCode: 'US',
              // Android does not expose the device Wi-Fi MAC to apps; the native
              // side returns null rather than the 02:00:00:00:00:00 sentinel.
              hardwareAddress: null,
              // Maps to WifiSecurity.wpa3Personal → "WPA3 Personal" on screen.
              securityToken: 'wpa3Personal',
              poweredOn: true,
              locationAuthorized: true,
            ),
          ),
        ),
      ),
      // The screen opens on the "Live trend" sparkline block; a single-snapshot
      // fixture makes that a flat line. Scroll down so the network IDENTITY
      // cards (SSID / BSSID / Security / Signal / Rate / Channel-Band-PHY) — the
      // full Android live-data set — lead the frame.
      drive: (t) async {
        // Let the real async OUI table load (rootBundle.loadString) resolve so
        // the AP-vendor row shows the resolved manufacturer (Apple, Inc. for the
        // a4:83:e7 prefix) instead of the transient "Loading…" state — an honest
        // resolved value, the app's own offline OUI lookup.
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await t.pumpAndSettle();
        // Scroll far enough that the WHOLE Channel card lands inside the frame
        // with a comfortable bottom margin — Channel (with its "* Preferred
        // Scanning Channel (PSC)" footnote, which is what the "37 *" asterisk
        // refers to), Width, and Band all fully visible, the way Tx/Rx sit
        // cleanly in the Rate card. The earlier -1620 clipped the Channel row's
        // bottom third AND scrolled the PSC footnote off-screen, leaving the
        // asterisk dangling; this larger offset brings both the row and its
        // explanatory footnote on-screen so the asterisk reads as a real,
        // resolved footnote rather than an orphan.
        await t.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -1860),
        );
        await t.pumpAndSettle();
      },
      // Honesty gate: assert each headline live-data value is the screen's OWN
      // rendered output before writing the PNG. The Rx rate and the WPA3 security
      // type are the Android-advantage values that the macOS fixture could not
      // show — their presence proves no platform-unavailable line replaced them.
      verify: (t) {
        _expectText('-52'); // RSSI
        _expectText('6 GHz'); // Band — channel/band card in frame
        _expectText('1441'); // Tx Rate (Mbps)
        _expectText('1200'); // Rx Rate (Mbps) — Android exposes it
        _expectText('WPA3 Personal'); // real security type — Android exposes it
        // No "Not exposed by Android" line for Rx rate or security must exist.
        expect(find.text('Not exposed by Android'), findsNothing,
            reason: 'Android exposes Rx rate and security — no '
                'platform-unavailable line should appear for shot 3');
      },
    );
  });

  // ── 4. Network Quality — six graded rows ────────────────────────────────────
  testWidgets('play-4 Network Quality — graded result', (tester) async {
    Future<Duration?> fakeProber(String host, int port, Duration timeout) async {
      if (host == 'one.one.one.one') return const Duration(milliseconds: 12);
      if (host == 'www.google.com') return const Duration(milliseconds: 24);
      return null;
    }

    const List<PopularSite> sites = <PopularSite>[
      PopularSite(name: 'Cloudflare', host: 'one.one.one.one'),
      PopularSite(name: 'Google', host: 'www.google.com'),
    ];

    await _capture(
      tester,
      id: 'play-phone-4-network-quality',
      build: () => NetQualityScreen(
        client: MockQualityClient(
          scriptedResult: _internetResult(
            down: 480,
            up: 240,
            latencyMs: 14,
            jitterMs: 3,
            lossPct: 0,
            downUpGrade: QualityGrade.excellent,
            latencyGrade: QualityGrade.excellent,
          ),
        ),
        reachabilityProbe: ReachabilityProbe(prober: fakeProber, sites: sites),
        monitor: LiveQualityMonitor(
          sampler: () async => const LatencyStats(
            avgMs: 14,
            minMs: 10,
            maxMs: 22,
            jitterMs: 3,
            lossPct: 0,
            sent: 5,
            received: 5,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Run test'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Latency');
        _expectText('Download');
        _expectText('Responsiveness');
      },
    );
  });

  // ── 5. EIRP calculator — the pro RF tools ───────────────────────────────────
  // TX 23 dBm, cable loss 2 dB, antenna gain 6 dBi → EIRP 27.0 dBm. Output is
  // computed live from the typed input (no fabrication).
  testWidgets('play-5 EIRP calculator', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-5-eirp-calculator',
      build: () => const EirpScreen(),
      drive: (t) async {
        final Finder fields = find.byType(TextField);
        await t.enterText(fields.at(0), '23'); // TX power (dBm)
        await t.pump();
        await t.enterText(fields.at(1), '2'); // Cable loss (dB)
        await t.pump();
        await t.enterText(fields.at(2), '6'); // Antenna gain (dBi)
        await t.pump();
      },
      verify: (t) => _expectText('27.0'), // EIRP dBm — the app's own computation
    );
  });

  // ── 6. Tool catalog — the home category grid (breadth: 5 categories) ────────
  // The home screen scrolled past the hero so the category grid — every category
  // with its live tool-count badge — fills the frame and tells the breadth story
  // ("128 tools across 5 categories"). Data-driven from kToolCategories; counts
  // are the app's own live counts, not painted on.
  testWidgets('play-6 Home grid — category breadth', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-6-tool-catalog',
      build: () => const HomeScreen(),
      drive: (t) async {
        await t.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -360),
        );
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Test Network');
        _expectText('Networking Tools');
      },
    );
  });

  // ── 7. Channel Map — a visual reference screen (2.4 GHz 1/6/11) ─────────────
  testWidgets('play-7 Channel Map — visual reference', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-7-channel-map',
      build: () => const ChannelMapScreen(),
      verify: (t) => _expectText('2.4 GHz'),
    );
  });

  // ── 8. Wi-Fi Glossary — the educational depth ───────────────────────────────
  testWidgets('play-8 Wi-Fi Glossary', (tester) async {
    await _capture(
      tester,
      id: 'play-phone-8-glossary',
      // Inject the service from the real bundled asset (read from disk) so the
      // capture does not depend on the async rootBundle load settling. English
      // is the default render. See the S14 note in the book3 capture harness.
      build: () => WifiGlossaryScreen(
        service: GlossaryService.fromJson(
          File('assets/data/glossary.json').readAsStringSync(),
        ),
      ),
    );
  });

  // ── Bonus: 10" tablet shots (1600×2560, 9:16 portrait) ──────────────────────
  // 800 × 1280 logical × pixelRatio 2.0 → 1600 × 2560 device px, the Play 10"
  // tablet slot. Width ≥ 720 trips the app's tablet layout (desktop-edge padding,
  // multi-column home grid). Two shots only — phone is the requirement.

  testWidgets('tablet-1 Home grid — tablet layout', (tester) async {
    await _captureTablet(
      tester,
      id: 'play-tablet-1-home-grid',
      build: () => const HomeScreen(),
      verify: (t) => _expectText('Check My Connection'),
    );
  });

  testWidgets('tablet-2 Channel Map — tablet layout', (tester) async {
    await _captureTablet(
      tester,
      id: 'play-tablet-2-channel-map',
      build: () => const ChannelMapScreen(),
      verify: (t) => _expectText('2.4 GHz'),
    );
  });
}
