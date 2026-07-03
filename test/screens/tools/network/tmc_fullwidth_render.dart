// Render-proof capture for the FULL-WIDTH verdict-sentence fix (NOT a golden
// test). Verifies the iPhone bug Keith reported 2026-06-15: the verdict sentence
// ("Both sides are weak. Your Wi-Fi is slightly ahead.") was wrapping down a
// narrow LEFT column because a trailing "Run again" button shared its row. The
// fix moves "Run again" to its own row beneath the sentence, so the verdict now
// spans the full card width and "Run again" stays clearly visible.
//
// Captures the real TestMyConnectionScreen at the four required widths
// (375 / 393 / 430 / 768) in BOTH themes, for the exact "slightly ahead"
// wording Keith cited, to the myPKA Deliverables folder for Vera's gate.
//
// Drives the production screen through its injection seams (a macOS adapter
// whose Tx rate sets the Wi-Fi usable-capacity tier, and a MockQualityClient
// whose scripted down/up sets the internet tier). No real platform channel,
// socket, or poll timer is touched.
//
// Capture utility, not a regression gate. Run explicitly:
//   flutter test test/screens/tools/network/tmc_fullwidth_render.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:net_quality/net_quality.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/Documents/myPKA/Deliverables/2026-06-15-tmc-fullwidth-verdict-renders';

// The four widths to verify: three iPhone logical widths + a tablet width.
const List<double> _widths = <double>[375, 393, 430, 768];

/// macOS adapter at a chosen Tx rate → usable Wi-Fi = 0.55 × Tx.
class _MacLinkAdapter implements WifiInfoAdapter {
  _MacLinkAdapter(this.txRateMbps);
  final double txRateMbps;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ConnectedAp.fromWifiInfo(
        WifiInfo(
          interfaceName: 'en0',
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          rssiDbm: -55,
          noiseDbm: -92,
          snrDb: 37,
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
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

QualityResult _internet({required double down, required double up}) =>
    QualityResult(
      source: QualitySource.mock,
      measuredAt: DateTime.utc(2026, 1, 1),
      metrics: <QualityMetric>[
        const QualityMetric(
          id: MetricIds.latency,
          label: 'Latency',
          value: 18,
          unit: 'ms',
          grade: QualityGrade.good,
        ),
        const QualityMetric(
          id: MetricIds.loss,
          label: 'Loss',
          value: 0,
          unit: '%',
          grade: QualityGrade.good,
        ),
        QualityMetric(
          id: MetricIds.download,
          label: 'Download',
          value: down,
          unit: 'Mbps',
          grade: QualityGrade.fair,
        ),
        QualityMetric(
          id: MetricIds.upload,
          label: 'Upload',
          value: up,
          unit: 'Mbps',
          grade: QualityGrade.fair,
        ),
      ],
    );

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary = boundaryKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('$_outDir/$filename');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _renderAtWidth(
  WidgetTester tester,
  double width,
  ThemeData theme,
  String themeName,
) async {
  const double height = 900;
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GlobalKey boundaryKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: const TextScaler.linear(1.0),
          ),
          // "Both sides are weak. Your Wi-Fi is slightly ahead." — the exact
          // wording Keith cited. Tx 120 → usable 66 (weak); internet download 40
          // (weak); Wi-Fi ahead by margin (+65%).
          child: TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _MacLinkAdapter(120),
            qualityClient: MockQualityClient(
              scriptedResult: _internet(down: 40, up: 20),
            ),
            nowOverride: () => DateTime.utc(2026, 6, 15, 14, 30),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
  await tester.tap(find.text('Check My Connection'));
  await tester.pumpAndSettle();

  await _capture(
    tester,
    boundaryKey,
    'tmc-fullwidth_${width.toInt()}_$themeName.png',
  );
}

void main() {
  for (final double w in _widths) {
    testWidgets('render dark @ ${w.toInt()}', (tester) async {
      await _renderAtWidth(tester, w, AppTheme.dark(), 'dark');
    });
    testWidgets('render light @ ${w.toInt()}', (tester) async {
      await _renderAtWidth(tester, w, AppTheme.light(), 'light');
    });
  }
}
