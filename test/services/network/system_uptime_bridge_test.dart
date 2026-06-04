// SystemUptimeBridge unit tests — the Dart side of the native uptime channel,
// including the honest null on a missing handler and on invalid native values
// (Batch 6).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/system_uptime_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wlanpros.toolbox/system_info');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void setHandler(Future<Object?>? Function(MethodCall)? handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => setHandler(null));

  test('valid native value passes through', () async {
    setHandler((call) async {
      expect(call.method, 'systemUptime');
      return 273120.5;
    });
    expect(await SystemUptimeBridge().read(), 273120.5);
  });

  test('missing handler → null (off-iOS/macOS, honest unavailable)', () async {
    // No handler registered → MissingPluginException.
    expect(await SystemUptimeBridge().read(), isNull);
  });

  test('negative / non-finite native value → null', () async {
    setHandler((call) async => -1.0);
    expect(await SystemUptimeBridge().read(), isNull);

    setHandler((call) async => double.nan);
    expect(await SystemUptimeBridge().read(), isNull);
  });

  test('platform exception → null, never throws', () async {
    setHandler((call) async => throw PlatformException(code: 'ERR'));
    expect(await SystemUptimeBridge().read(), isNull);
  });
}
