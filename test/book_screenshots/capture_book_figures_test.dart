@Tags(['capture'])
library;

// Book-figure capture harness — "Learn Wi-Fi by Doing It" (Ch 1–8).
// Tagged `capture` (not `golden`) so it is excluded from CI: this is a figure
// GENERATOR (writes book_screenshots/raw/), not a regression guard. The real
// golden suites now run in CI. Run this generator deliberately with:
// flutter test --tags capture
//
// NOT a golden/regression suite. This renders the 16 book figures from the
// SHOT-LIST with FIXED, prose-matching fixtures and writes 3× PNGs to
// `book_screenshots/raw/`. It uses RenderRepaintBoundary.toImage(pixelRatio: 3.0)
// inside tester.runAsync — never matchesGoldenFile — so a normal `flutter test`
// / the existing golden suite is unaffected (these tests assert nothing about a
// committed baseline; they only assert the on-screen computed value equals the
// prose number, then write the file).
//
// Font + theme pinning is inherited from test/flutter_test_config.dart (IBM Plex
// Sans / DM Mono / Roboto Mono loaded, so identifiers/numbers render as real
// glyphs) and AppTheme.dark(), textScaler 1.0.
//
// Run via tool/capture_book_screenshots.sh, or:
//   flutter test test/book_screenshots/capture_book_figures_test.dart
//
// Each figure is sized to 393 logical px wide (iPhone-class) with a height tall
// enough that the named inputs AND outputs/callout targets are in-frame.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import '../support/figure_write_gate.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';

import 'package:wlan_pros_toolbox/screens/tools/dbm_watt_converter.dart';
// Book 2 (Ch 10–13) lab-tool screens. The two downtilt screens each export an
// enum named `HeightUnit`, so they are imported here only for the screen types;
// no enum from either is referenced in this file (the captures drive them via
// TextField input and band/default state only).
import 'package:wlan_pros_toolbox/screens/tools/calculators/downtilt_screen.dart'
    show DowntiltScreen;
import 'package:wlan_pros_toolbox/screens/tools/calculators/downtilt_coverage_screen.dart'
    show DowntiltCoverageScreen;
import 'package:wlan_pros_toolbox/screens/tools/calculators/link_budget_screen.dart'
    show LinkBudgetScreen;
import 'package:wlan_pros_toolbox/screens/tools/calculators/ptp_link_screen.dart'
    show PtpLinkScreen;
import 'package:wlan_pros_toolbox/screens/tools/reference/spectrum_screen.dart'
    show SpectrumScreen;
import 'package:wlan_pros_toolbox/screens/tools/reference/non_wifi_channels_screen.dart'
    show NonWifiChannelsScreen;
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart'
    show ChannelMapScreen;
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/noise_floor_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rf_attenuation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wavelength_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/db_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_typography.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';

// ── Capture constants ───────────────────────────────────────────────────────

/// iPhone-class logical width for every figure (SHOT-LIST hard req 2).
const double kPhoneWidth = 393;

/// 3× DPI — print/e-book quality (SHOT-LIST hard req 1). The existing goldens
/// render at 1.0; book assets must not ship at 1×.
const double kPixelRatio = 3.0;

/// Output directory for the raw (un-annotated) book PNGs.
const String kOutDir = 'book_screenshots/raw';

// ── Live-fixture fakes (constructor-injection seams) ────────────────────────

/// A macOS adapter that returns one fixed [ConnectedAp]. Used to drive the
/// Wi-Fi Information screen to exact, prose-matching RF values.
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

/// A macOS adapter at a fixed Tx rate, so usable Wi-Fi = 0.55 × Tx lands on a
/// chosen absolute tier for the Test My Connection chips.
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
  Future<LocationAuthStatus> nameAuthorizationStatus() async => LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A macOS adapter whose snapshot read never resolves — models the honest
/// "Couldn't check" Wi-Fi axis for Fig 1.3.
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

// A net_quality result builder for the comparison/quality screens.
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

/// Family name of the formula-glyph fallback subset loaded in
/// `test/flutter_test_config.dart`. Kept in sync with `kFormulaFallbackFamily`
/// there. Adding it to the theme's `fontFamilyFallback` makes the render engine
/// consult it PER-GLYPH for codepoints DM Mono / IBM Plex Sans lack — λ (U+03BB),
/// sub/superscript digits and signs — so the formula cards render real glyphs
/// instead of `.notdef` boxes in the headless capture. On a real device the OS
/// font chain supplies these, so this is a test-render concern only.
const String _kFormulaFallbackFamily = 'FormulaFallback';

/// Returns [base] with the formula-glyph fallback family appended to every
/// text style's `fontFamilyFallback`: the whole [TextTheme] (covers prose like
/// `3·10⁸`, `10⁻²³`) and each style on the [AppMonoText] extension (covers the
/// `mono.inlineCode` formula lines `λ(m) = 300 / f` and `dBm = 10·log₁₀(mW)`).
/// The primary face still wins for every glyph it owns — fallback only supplies
/// the missing math glyphs — so there is no visual regression elsewhere.
ThemeData _withFormulaGlyphFallback(ThemeData base) {
  const List<String> fb = <String>[_kFormulaFallbackFamily];

  TextStyle withFb(TextStyle s) => s.copyWith(
        fontFamilyFallback: <String>[...?s.fontFamilyFallback, ...fb],
      );

  final TextTheme tt = base.textTheme.apply(fontFamilyFallback: fb);

  final AppMonoText? mono = base.extension<AppMonoText>();
  final ThemeData themed = base.copyWith(textTheme: tt);
  if (mono == null) return themed;

  final AppMonoText monoFb = mono.copyWith(
    outputXL: withFb(mono.outputXL),
    outputLarge: withFb(mono.outputLarge),
    outputMedium: withFb(mono.outputMedium),
    inlineCode: withFb(mono.inlineCode),
    robotoMono: withFb(mono.robotoMono),
  );
  final List<ThemeExtension<dynamic>> exts = themed.extensions.values
      .where((ThemeExtension<dynamic> e) => e is! AppMonoText)
      .toList();
  exts.add(monoFb);
  return themed.copyWith(extensions: exts);
}

/// Mounts [child] under AppTheme.dark() at [kPhoneWidth] × [height], with the
/// surface inside a RepaintBoundary so we can snapshot it at 3×.
Widget _host(Widget child, double height) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _withFormulaGlyphFallback(AppTheme.dark()),
    home: RepaintBoundary(
      key: _captureKey,
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(kPhoneWidth, height),
          textScaler: const TextScaler.linear(1.0),
        ),
        child: child,
      ),
    ),
  );
}

final GlobalKey _captureKey = GlobalKey();

/// Sizes the test surface, pumps [build]'s widget, runs [drive] to preset the
/// fixture, then writes a 3× PNG named `<figId>.png`. Asserting equality of the
/// prose number is the caller's job (via [verify]).
Future<void> _capture(
  WidgetTester tester, {
  required String figId,
  required double height,
  required Widget Function() build,
  Future<void> Function(WidgetTester tester)? drive,
  void Function(WidgetTester tester)? verify,
}) async {
  await tester.binding.setSurfaceSize(Size(kPhoneWidth, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = Size(kPhoneWidth * kPixelRatio, height * kPixelRatio);
  tester.view.devicePixelRatio = kPixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(build(), height));
  await tester.pumpAndSettle();
  if (drive != null) {
    await drive(tester);
    await tester.pumpAndSettle();
  }
  if (verify != null) verify(tester);

  await _writePng(tester, figId);
}

/// Snapshots the captured RepaintBoundary at [kPixelRatio] and writes the PNG.
Future<void> _writePng(WidgetTester tester, String figId) async {
  final RenderRepaintBoundary boundary = _captureKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: kPixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    // Render always runs; the WRITE is opt-in so a plain `flutter test` never
    // dirties the tree. See test/support/figure_write_gate.dart.
    if (kWriteFigures) {
      final Directory dir = Directory(kOutDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final File file = File('$kOutDir/$figId.png');
      file.writeAsBytesSync(byteData!.buffer.asUint8List());
      // Echo dimensions so the run log records them.
      // ignore: avoid_print
      print('WROTE $figId.png  ${image.width}x${image.height}px');
    }
    image.dispose();
  });
}

/// Asserts a Text widget with [exact] is on screen — the truthfulness gate that
/// the rendered computed output equals the prose number.
void _expectText(String exact) {
  expect(find.text(exact), findsWidgets,
      reason: 'expected on-screen value "$exact" not found');
}

/// The connection-probe seam (F-1). Network Quality now gates its data-hungry
/// stages on an honest not-on-Wi-Fi read; screenshot fixtures must supply it
/// rather than reach an unmocked platform channel. `unknown` changes nothing.
class _SilentPathNQ implements WifiPathProbe {
  const _SilentPathNQ();
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      );
}

class _UnknownNetNQ implements NetworkInfo {
  // ROUND 5: a render/screenshot test models a normal device ON WI-FI (a link the
  // app can PROVE is free), so the fail-closed gate stays silent and the run behaves
  // as it always has. An `unknown` service now raises the cost UI and withholds
  // throughput, which is exactly what a screenshot must not capture.
  @override
  Future<String?> getWifiIP() async => '192.168.1.10';
  @override
  Future<String?> getWifiIPv6() async => throw Exception('no plugin in test');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WifiConnectionService _unknownConnectionNQ() => WifiConnectionService(
      networkInfo: _UnknownNetNQ(),
      platformOverride: TargetPlatform.iOS,
      pathProbe: const _SilentPathNQ(),
    );

void main() {
  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 4 — dBm/Watt Converter (golden-fixture). The PROSE anchors:
  //   0 dBm → 1.0000 mW, 1.0000e-3 W   (Fig 4.1; the 0-state of the 4.2 triptych)
  //   −41 dBm → 7.9433e-8 W            (Fig 4.2 middle)
  //   −67 dBm → ≈2.0e-10 W (1.9953e-10)(Fig 4.2 right)
  // ════════════════════════════════════════════════════════════════════════
  Future<void> driveDbm(WidgetTester tester, String dbm) async {
    final Finder dbmField = find.byType(TextField).first;
    await tester.enterText(dbmField, dbm);
    await tester.pump();
  }

  testWidgets('fig-4-1 dBm/Watt — input 0', (tester) async {
    await _capture(
      tester,
      figId: 'fig-4-1',
      height: 1180,
      build: () => const DbmWattConverterScreen(),
      drive: (t) => driveDbm(t, '0'),
      verify: (t) {
        _expectText('1.0000'); // mW
        _expectText('1.0000e-3'); // W
      },
    );
  });

  testWidgets('fig-4-2a dBm/Watt — 0 dBm (triptych left)', (tester) async {
    await _capture(
      tester,
      figId: 'fig-4-2a',
      height: 1180,
      build: () => const DbmWattConverterScreen(),
      drive: (t) => driveDbm(t, '0'),
      verify: (t) => _expectText('1.0000e-3'),
    );
  });

  testWidgets('fig-4-2b dBm/Watt — -41 dBm (triptych middle)', (tester) async {
    await _capture(
      tester,
      figId: 'fig-4-2b',
      height: 1180,
      build: () => const DbmWattConverterScreen(),
      drive: (t) => driveDbm(t, '-41'),
      verify: (t) => _expectText('7.9433e-8'),
    );
  });

  testWidgets('fig-4-2c dBm/Watt — -67 dBm (triptych right)', (tester) async {
    await _capture(
      tester,
      figId: 'fig-4-2c',
      height: 1180,
      build: () => const DbmWattConverterScreen(),
      drive: (t) => driveDbm(t, '-67'),
      verify: (t) => _expectText('1.9953e-10'),
    );
  });

  // Fig 4.3 — dB Reference (static reference screen, no input).
  testWidgets('fig-4-3 dB Reference table', (tester) async {
    await _capture(
      tester,
      figId: 'fig-4-3',
      height: 1400,
      build: () => const DbReferenceScreen(),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 5 — Noise Floor + Signal Thresholds.
  //   20 MHz / NF 7 dB / 20°C → thermal -100.9, receiver -93.9, rule -101.0
  // ════════════════════════════════════════════════════════════════════════
  testWidgets('fig-5-1 Noise Floor — 20 MHz, NF 7 dB', (tester) async {
    await _capture(
      tester,
      figId: 'fig-5-1',
      height: 1320,
      build: () => const NoiseFloorScreen(),
      // Defaults are already BW 20 MHz, NF 7, temp 20 → no driving needed.
      verify: (t) {
        _expectText('-100.9'); // thermal
        _expectText('-93.9'); // rx floor (the one that matters)
        _expectText('-101.0'); // rule of thumb
      },
    );
  });

  // Fig 5.2 — Signal Thresholds (static).
  testWidgets('fig-5-2 Signal Thresholds', (tester) async {
    await _capture(
      tester,
      figId: 'fig-5-2',
      height: 1500,
      build: () => const SignalThresholdsScreen(),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 6 — FSPL + Wavelength.
  //   5 GHz @ 1 km → 106.4 dB ; @ 2 km → 112.5 dB (prose says ≈112.4; +6 dB)
  //   5 GHz → 6.00 cm
  // ════════════════════════════════════════════════════════════════════════
  Future<void> driveFspl(WidgetTester tester, String freq, String dist) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), freq); // Frequency (GHz default)
    await tester.pump();
    await tester.enterText(fields.at(1), dist); // Distance (km default)
    await tester.pump();
  }

  testWidgets('fig-6-1a FSPL — 5 GHz @ 1 km', (tester) async {
    await _capture(
      tester,
      figId: 'fig-6-1a',
      height: 1320,
      build: () => const FsplScreen(),
      drive: (t) => driveFspl(t, '5', '1'),
      verify: (t) => _expectText('106.4'),
    );
  });

  testWidgets('fig-6-1b FSPL — 5 GHz @ 2 km', (tester) async {
    await _capture(
      tester,
      figId: 'fig-6-1b',
      height: 1320,
      build: () => const FsplScreen(),
      drive: (t) => driveFspl(t, '5', '2'),
      // Prose says ≈112.4; the tool renders 112.5 (exact 112.45 → 1-dp round-up).
      verify: (t) => _expectText('112.5'),
    );
  });

  testWidgets('fig-6-2 Wavelength — 5 GHz', (tester) async {
    await _capture(
      tester,
      figId: 'fig-6-2',
      height: 1280,
      build: () => const WavelengthScreen(),
      drive: (t) async {
        // Frequency field, then flip the unit toggle to GHz.
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.pump();
        await tester.tap(find.text('GHz'));
        await tester.pump();
      },
      verify: (t) {
        _expectText('6.00'); // cm
        _expectText('0.0600'); // m
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 7 — RF Attenuation.
  //   5 GHz, drywall ×1 → 4 dB (Fig 7.1)
  //   2× drywall (8) + 1× concrete block CMU (13) → 21 dB total (Fig 7.2)
  // ════════════════════════════════════════════════════════════════════════
  testWidgets('fig-7-1 RF Attenuation — 5 GHz drywall x1', (tester) async {
    await _capture(
      tester,
      figId: 'fig-7-1',
      height: 1340,
      build: () => const RfAttenuationScreen(),
      drive: (t) async {
        await t.tap(find.text('5 GHz')); // band toggle
        await t.pumpAndSettle();
        // Material defaults to Drywall; qty defaults to 1. Add it.
        await t.tap(find.bySemanticsLabel('Add material'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('4'); // total dB
        _expectText('1× Drywall / Plasterboard: 4 dB');
      },
    );
  });

  testWidgets('fig-7-2 RF Attenuation — worked example 21 dB', (tester) async {
    await _capture(
      tester,
      figId: 'fig-7-2',
      height: 1480,
      build: () => const RfAttenuationScreen(),
      drive: (t) async {
        await t.tap(find.text('5 GHz'));
        await t.pumpAndSettle();
        // 2× drywall (default material).
        await t.enterText(find.byType(TextField).first, '2');
        await t.pump();
        await t.tap(find.bySemanticsLabel('Add material'));
        await t.pumpAndSettle();
        // Switch material to Concrete block / CMU (the 7th item), qty 1. The
        // open DropdownButton menu caps at ~5 visible rows then scrolls, and CMU
        // sits below that fold — so scroll the open menu down before tapping it.
        await t.tap(find.byType(DropdownButton<RfMaterial>).first);
        await t.pumpAndSettle();
        await t.drag(
          find.byType(DropdownMenuItem<RfMaterial>).first,
          const Offset(0, -250),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Concrete block / CMU').last, warnIfMissed: false);
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, '1');
        await t.pump();
        await t.tap(find.bySemanticsLabel('Add material'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('21'); // total dB
        _expectText('2× Drywall / Plasterboard: 8 dB');
        _expectText('1× Concrete block / CMU: 13 dB');
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 1 + 8 — Test My Connection (live-fixture).
  // ════════════════════════════════════════════════════════════════════════

  // Fig 1.1 — pre-run idle: the two chips + Run button.
  testWidgets('fig-1-1 Test My Connection — idle (two roads)', (tester) async {
    await _capture(
      tester,
      figId: 'fig-1-1',
      height: 900,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 440, up: 360, latencyMs: 18, jitterMs: 3, lossPct: 0,
          ),
        ),
      ),
      verify: (t) => _expectText('Check My Connection'),
    );
  });

  // Fig 1.2 — post-run: Wi-Fi Strong, Internet Moderate, headline names slower.
  testWidgets('fig-1-2 Test My Connection — Wi-Fi Strong / Internet Moderate',
      (tester) async {
    await _capture(
      tester,
      figId: 'fig-1-2',
      height: 1700,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        // Tx 720 → usable 396 (Strong). Internet download 140 (Moderate); the
        // consumer internet number is the DOWNLOAD, and 140 < 0.40 × 396 so the
        // verdict names the internet as the slower side (ratio ≈ 0.35 → upstream).
        macAdapter: _TxLinkMacAdapter(720),
        qualityClient: MockQualityClient(
          scriptedResult: _internetResult(
            down: 140, up: 100, latencyMs: 22, jitterMs: 4, lossPct: 0,
            downUpGrade: QualityGrade.fair,
          ),
        ),
      ),
      drive: (t) async {
        await t.tap(find.text('Check My Connection'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Strong'); // Wi-Fi
        _expectText('Moderate'); // Internet
      },
    );
  });

  // Fig 1.3 — one chip "Couldn't check" (honest non-measurement).
  testWidgets('fig-1-3 Test My Connection — Couldn\'t check', (tester) async {
    await _capture(
      tester,
      figId: 'fig-1-3',
      height: 1700,
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

  // Fig 8.1 — the Chapter 8 capstone: the verdict must honestly name Wi-Fi as
  // the limiting/slow side while the internet is healthy.
  //
  // The hero sentence is the app's OWN output, not hand-written: the engine's
  // wifiLimiter verdict (→ ConsumerOutcome.wifi) drives the hero
  // "Your Wi-Fi is the slow part." For that verdict to fire, the engine's grade
  // gate must NOT engage — i.e. internet health must read MARGINAL — and the
  // headroom ratio (internet download / usableWifi) must be ≥ 0.70. (When the internet
  // grades GOOD/EXCELLENT the gate short-circuits to bothHealthy → the wrong,
  // contradictory "both look fine" hero — which is exactly the bug this fixture
  // fixes.) So the internet down/up are graded FAIR here: the grade gate stays
  // open, the ratio diagnoses, and the verdict lands on the Wi-Fi link.
  //
  // The two axis CHIPS are absolute-rate driven (independent of the verdict /
  // grades): usable Wi-Fi 33 Mbps → "Weak", internet download 440 Mbps → "Strong".
  // Wi-Fi Weak ≠ Internet Strong (different tiers), so the same-tier hero
  // override does not fire and the per-outcome "Your Wi-Fi is the slow part."
  // hero stands. Mirrors fig-8-2 (Linksys-Home, 2.4 GHz, -68 Fair, SNR 18).
  //
  //   Tx 60   → usable 0.55×60 = 33 Mbps  → Wi-Fi chip "Weak"
  //   440/360 → internet down  = 440 Mbps → Internet chip "Strong"
  //   ratio   = 440 / 33 = 13.3 ≥ 0.70    → wifiLimiter
  testWidgets('fig-8-1 Test My Connection — Wi-Fi is the slow part',
      (tester) async {
    await _capture(
      tester,
      figId: 'fig-8-1',
      height: 1700,
      build: () => TestMyConnectionScreen(
        enableLiveSampling: false,
        sourceOverride: WifiInfoSource.macosCoreWlan,
        // Tx 60 → usable 33 (Weak), RSSI -68 / SNR 18 (matches fig-8-2).
        macAdapter: _TxLinkMacAdapter(60, rssi: -68, snr: 18),
        qualityClient: MockQualityClient(
          // Internet download 440 (Strong chip) but graded FAIR so the grade gate
          // stays open and the verdict lands on the Wi-Fi link.
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
        _expectText('Your Wi-Fi is the slow part.'); // app's own hero verdict
        _expectText('Weak'); // Wi-Fi chip
        _expectText('Strong'); // Internet chip
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 2 + 8 — Wi-Fi Information (live-fixture, iOS-framed).
  // ════════════════════════════════════════════════════════════════════════

  // Fig 2.1 — SSID WLANPros-6E, a self-consistent 6 GHz AP: band 6 GHz, ch 37
  // (a real 6 GHz PSC), width 160 MHz, RSSI -52, SNR 38, Tx 1441.
  // Driven via the macOS source so all prose fields (SSID/BSSID/band/channel/
  // signal/SNR/PHY) render from one snapshot. macOS CoreWLAN reports the band
  // DIRECTLY (ConnectedAp.fromWifiInfo forwards info.band verbatim with
  // bandDerived:false — it does NOT re-derive band from the channel on this
  // path), so setting band:'6 GHz' renders "6 GHz" honestly. Channel 37 with a
  // 6 GHz band is a Preferred Scanning Channel ((37-5) % 16 == 0), so the
  // Channel row shows the PSC marker. RSSI -52 grades Excellent; SNR 38 grades
  // Excellent — the figure is now internally coherent (a 6E network on 6 GHz).
  testWidgets('fig-2-1 Wi-Fi Information — WLANPros-6E', (tester) async {
    await _capture(
      tester,
      figId: 'fig-2-1',
      // Tall enough to bring the Channel card's Band row ("6 GHz") in-frame.
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
              noiseDbm: -90, // SNR = 38
              snrDb: 38,
              txRateMbps: 1441,
              rxRateMbps: 1200,
              phyMode: '802.11ax',
              channel: 37, // a real 6 GHz PSC: (37-5) % 16 == 0
              channelWidthMhz: 160,
              band: '6 GHz', // macOS reports band directly; rendered verbatim
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
        _expectText('6 GHz'); // Band renders directly from the macOS source
      },
    );
  });

  // Fig 8.2 — SSID Linksys-Home, ch 6 (2.4 GHz), RSSI -68 (Fair), SNR ≈18.
  // Single BSSID = one AP. Driven via the macOS source. RSSI -68 grades Fair
  // (matches prose); SNR 18 grades Fair.
  testWidgets('fig-8-2 Wi-Fi Information — Linksys-Home (2.4 GHz)',
      (tester) async {
    await _capture(
      tester,
      figId: 'fig-8-2',
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
              noiseDbm: -86, // SNR = 18
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
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // CHAPTER 3 + 8 — Network Quality (live-fixture). Six graded rows, no score.
  //   latency 24, jitter 6, loss 0, download 180, upload 12, responsiveness.
  // ════════════════════════════════════════════════════════════════════════
  LatencyStats fig31Stats() => const LatencyStats(
        avgMs: 24,
        minMs: 18,
        maxMs: 34,
        jitterMs: 6,
        lossPct: 0,
        sent: 5,
        received: 5,
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

  testWidgets('fig-3-1 Network Quality — six graded rows', (tester) async {
    await _capture(
      tester,
      figId: 'fig-3-1',
      height: 1900,
      build: () => NetQualityScreen(
        connectionService: _unknownConnectionNQ(),
        client: MockQualityClient(
          scriptedResult: _internetResult(
            down: 180, up: 12, latencyMs: 24, jitterMs: 6, lossPct: 0,
            downUpGrade: QualityGrade.good,
          ),
        ),
        reachabilityProbe: ReachabilityProbe(prober: fakeProber, sites: sites),
        monitor: LiveQualityMonitor(sampler: () async => fig31Stats()),
      ),
      drive: (t) async {
        await t.tap(find.text('Run test'));
        await t.pumpAndSettle();
      },
      verify: (t) {
        _expectText('Latency');
        _expectText('Download');
        _expectText('Upload');
        _expectText('Responsiveness');
      },
    );
  });

  // Fig 8.3 — Network Quality confirming the internet road is healthy.
  testWidgets('fig-8-3 Network Quality — internet road healthy', (tester) async {
    await _capture(
      tester,
      figId: 'fig-8-3',
      height: 1900,
      build: () => NetQualityScreen(
        connectionService: _unknownConnectionNQ(),
        client: MockQualityClient(
          scriptedResult: _internetResult(
            down: 480, up: 360, latencyMs: 12, jitterMs: 2, lossPct: 0,
            downUpGrade: QualityGrade.excellent,
            latencyGrade: QualityGrade.excellent,
            lossGrade: QualityGrade.excellent,
            jitterGrade: QualityGrade.excellent,
            respGrade: QualityGrade.excellent,
          ),
        ),
        reachabilityProbe: ReachabilityProbe(prober: fakeProber, sites: sites),
        monitor: LiveQualityMonitor(sampler: () async => fig31Stats()),
      ),
      drive: (t) async {
        await t.tap(find.text('Run test'));
        await t.pumpAndSettle();
      },
      verify: (t) => _expectText('Excellent'),
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // BOOK 2 — "The Definitive Guide" lab-tool screenshots, Chapters 10–13.
  //
  // Same capture mechanism as Book 1 above: _host() under AppTheme.dark(),
  // RepaintBoundary.toImage(pixelRatio: 3.0) at 393 logical px wide, with
  // representative (NOT empty) input driven in via TextField / default state.
  // Filenames use the ss-<ch>-<n> scheme the book deliverable expects.
  //
  // All four calculators are pure (no network, no platform channel) and all
  // three references are compile-time-const datasets, so every figure renders
  // fully offline in the headless harness — none needs live device data.
  // ════════════════════════════════════════════════════════════════════════

  // ── Chapter 10 — Antenna geometry ──────────────────────────────────────────

  // ss-10-1 Antenna Downtilt — AP at 6 m AGL covering a 30 m radius → 11.31°.
  // Fields are [height, coverage] in DOM order; both default to meters.
  testWidgets('ss-10-1 Antenna Downtilt — 6 m / 30 m', (tester) async {
    await _capture(
      tester,
      figId: 'ss-10-1-antenna-downtilt',
      height: 1180,
      build: () => const DowntiltScreen(),
      drive: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), '6'); // Antenna height (AGL), m
        await t.pump();
        await t.enterText(fields.at(1), '30'); // Target coverage distance, m
        await t.pump();
      },
      verify: (t) => _expectText('11.31'), // downtilt angle, degrees
    );
  });

  // ss-10-2 Downtilt Coverage — 8 m AGL, 8° downtilt, 12° vertical beamwidth
  //   → near 32 m / far 229 m / depth 197 m (0-dp dual m/ft).
  // Fields are [height, tilt, beamwidth] in DOM order; height defaults to m.
  testWidgets('ss-10-2 Downtilt Coverage — 8 m / 8° / 12°', (tester) async {
    await _capture(
      tester,
      figId: 'ss-10-2-downtilt-coverage',
      height: 1480,
      build: () => const DowntiltCoverageScreen(),
      drive: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), '8'); // Antenna height (AGL), m
        await t.pump();
        await t.enterText(fields.at(1), '8'); // Downtilt angle, degrees
        await t.pump();
        await t.enterText(fields.at(2), '12'); // Vertical beamwidth, degrees
        await t.pump();
      },
      verify: (t) {
        _expectText('32 m / 105 ft'); // near edge
        _expectText('229 m / 752 ft'); // far edge
        _expectText('197 m / 646 ft'); // coverage depth
      },
    );
  });

  // ── Chapter 11 — Link budgets ──────────────────────────────────────────────

  // ss-11-1 Link Budget — a worked indoor/outdoor budget:
  //   Tx 23 dBm, TxGain 14 dBi, TxLoss 1.5 dB, FSPL 120 dB, other 0,
  //   RxLoss 1.5 dB, RxGain 14 dBi, RxSens -82 dBm
  //   → received -72.0 dBm, link margin 10.0 dB (healthy, just at threshold).
  // Required-field DOM order: TxPower, TxGain, TxLoss, FSPL, OtherLosses,
  // RxLoss, RxGain, RxSensitivity. TxPower defaults to the dBm unit.
  testWidgets('ss-11-1 Link Budget — 23 dBm / margin 10 dB', (tester) async {
    await _capture(
      tester,
      figId: 'ss-11-1-link-budget',
      height: 2200,
      build: () => const LinkBudgetScreen(),
      drive: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), '23'); // TX Power (dBm)
        await t.pump();
        await t.enterText(fields.at(1), '14'); // TX Antenna Gain (dBi)
        await t.pump();
        await t.enterText(fields.at(2), '1.5'); // TX Cable Loss (dB)
        await t.pump();
        await t.enterText(fields.at(3), '120'); // Free Space Path Loss (dB)
        await t.pump();
        await t.enterText(fields.at(4), '0'); // Other Losses (dB)
        await t.pump();
        await t.enterText(fields.at(5), '1.5'); // RX Cable Loss (dB)
        await t.pump();
        await t.enterText(fields.at(6), '14'); // RX Antenna Gain (dBi)
        await t.pump();
        await t.enterText(fields.at(7), '-82'); // RX Sensitivity (dBm)
        await t.pump();
      },
      verify: (t) {
        _expectText('-72.0'); // received signal, dBm
        _expectText('10.0'); // link margin, dB
      },
    );
  });

  // ss-11-2 PtP Link Check — a clear-air 5.8 GHz backhaul:
  //   f 5.8 GHz, d 5 km, Tx 20 dBm, TxGain 23 dBi, RxGain 23 dBi,
  //   losses 0, rain 0, sensitivity -80 dBm, required margin 10 dB
  //   → EIRP 43.0 dBm, FSPL 121.7 dB, Rx -55.7 dBm, margin 24.3 dB → PASS.
  // Required-field DOM order: Frequency, Distance, Tx power, Tx gain, Rx gain,
  // TxLoss, RxLoss, RainRate, (polarization toggle), RxSensitivity, ReqMargin.
  testWidgets('ss-11-2 PtP Link Check — 5.8 GHz / 5 km / PASS',
      (tester) async {
    await _capture(
      tester,
      figId: 'ss-11-2-ptp-link-check',
      height: 2600,
      build: () => const PtpLinkScreen(),
      drive: (t) async {
        final fields = find.byType(TextField);
        await t.enterText(fields.at(0), '5.8'); // Frequency (GHz)
        await t.pump();
        await t.enterText(fields.at(1), '5'); // Distance (km)
        await t.pump();
        await t.enterText(fields.at(2), '20'); // Tx power (dBm)
        await t.pump();
        await t.enterText(fields.at(3), '23'); // Tx antenna gain (dBi)
        await t.pump();
        await t.enterText(fields.at(4), '23'); // Rx antenna gain (dBi)
        await t.pump();
        await t.enterText(fields.at(5), '0'); // Tx cable + connector loss (dB)
        await t.pump();
        await t.enterText(fields.at(6), '0'); // Rx cable + connector loss (dB)
        await t.pump();
        await t.enterText(fields.at(7), '0'); // Rain rate (mm/hr)
        await t.pump();
        await t.enterText(fields.at(8), '-80'); // Receiver sensitivity (dBm)
        await t.pump();
        await t.enterText(fields.at(9), '10'); // Required fade margin (dB)
        await t.pump();
      },
      verify: (t) {
        _expectText('PASS'); // verdict chip word
        _expectText('24.3'); // link margin, dB
        _expectText('43.0'); // EIRP, dBm
      },
    );
  });

  // ── Chapter 12 — Spectrum references ───────────────────────────────────────

  // ss-12-1 Spectrum Reference — the band fact sheet. Defaults to the 2.4 GHz
  // tab (SpectrumBand.ghz24), the congested band the chapter opens on.
  // Read-only compile-time dataset → renders on its success state with no input.
  testWidgets('ss-12-1 Spectrum Reference — 2.4 GHz fact sheet',
      (tester) async {
    await _capture(
      tester,
      figId: 'ss-12-1-spectrum-reference',
      height: 1900,
      build: () => const SpectrumScreen(),
      verify: (t) => _expectText('2.4 GHz'),
    );
  });

  // ss-12-2 Non-Wi-Fi Wireless Channels — the read-only reference covering the
  // non-Wi-Fi radios (LoRaWAN / 802.15.4 / Bluetooth / BLE / Zigbee) that share
  // the bands. Compile-time dataset → renders fully with no input.
  testWidgets('ss-12-2 Non-Wi-Fi Wireless Channels', (tester) async {
    await _capture(
      tester,
      figId: 'ss-12-2-non-wifi-channels',
      height: 2200,
      build: () => const NonWifiChannelsScreen(),
    );
  });

  // ── Chapter 13 — Channel map ───────────────────────────────────────────────

  // ss-13-1 Channel Map — defaults to the 2.4 GHz bonding map
  // (ChanMapBand.ghz24), which is exactly the 1 / 6 / 11 non-overlapping view
  // the chapter teaches. Read-only compile-time dataset, no input needed.
  testWidgets('ss-13-1 Channel Map — 2.4 GHz (1/6/11)', (tester) async {
    await _capture(
      tester,
      figId: 'ss-13-1-channel-map',
      height: 1700,
      build: () => const ChannelMapScreen(),
      verify: (t) => _expectText('2.4 GHz'),
    );
  });
}
