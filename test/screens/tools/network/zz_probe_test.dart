import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

class _Cell implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _B implements WiFiDetailsBridge {
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool a) async {}
  @override
  Future<void> resetMonitoringColdStart() async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String n) async => true;
  @override
  Future<bool> runShortcutOneShot(String n) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

class _Sec extends WifiSecurityService {
  @override
  Future<WifiSecurityInfo> fetch() async =>
      const WifiSecurityInfo.unavailable('cellular: no Wi-Fi');
}

void main() {
  testWidgets('probe: what is on the PRE-RUN screen on cellular?', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LiveOnboardingService.prefsKey: true,
    });
    final b = _B();
    final s = WifiSignalSampler(
      source: WifiInfoSource.iosShortcuts,
      iosBridge: b,
      connectionService: WifiConnectionService(
        networkInfo: _Cell(),
        platformOverride: TargetPlatform.iOS,
      ),
    );
    addTearDown(s.dispose);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: TestMyConnectionScreen(
        sourceOverride: WifiInfoSource.iosShortcuts,
        iosBridge: b,
        sampler: s,
        enableCloudApps: false,
        securityService: _Sec(),
        onboardingService:
            LiveOnboardingService(getStore: SharedPreferences.getInstance),
        qualityClient: MockQualityClient(),
      ),
    ));
    await t.pumpAndSettle();
    final buf = StringBuffer();
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      if (w.data != null) buf.writeln('  | ${w.data}');
    }
    // ignore: avoid_print
    print('sampler.notOnWifi = ${s.notOnWifi}\nPRE-RUN TEXT:\n$buf');
  });
}
