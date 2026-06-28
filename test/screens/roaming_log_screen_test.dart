// RoamingLogScreen — widget tests (Feature 2, Felix 2026-06-13). The honest
// empty / unavailable branches run hermetically with no platform channel
// (enableSampling: false or an unsupported source). The §8.16 copy-export
// serialization (2026-06-28) is exercised through the pure, sampler-free
// [buildRoamLogCopyText] with synthetic [RoamEvent]s — deterministic, no live
// stream, no timers.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/roaming_log_screen.dart';
import 'package:wlan_pros_toolbox/services/network/roam_detector.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

RoamEvent _roam({
  required DateTime at,
  String? ssid = 'KeithNet',
  required String from,
  required String to,
  int? rssi = -60,
  int? snr,
}) =>
    RoamEvent(
      at: at,
      ssid: ssid,
      fromBssid: from,
      toBssid: to,
      rssiDbm: rssi,
      snrDb: snr,
    );

void main() {
  setUpAll(() async {
    await ToolHelpLoader.ensureLoaded();
  });

  // §8.16 copy text is intercepted at the Clipboard platform-channel boundary
  // so the disabled-state tap can assert nothing is written.
  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(560, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: screen));
    await tester.pump();
  }

  testWidgets('unsupported platform shows the honest unavailable view',
      (t) async {
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.unsupported,
        enableSampling: false,
      ),
    );
    expect(find.text('Roaming Log'), findsOneWidget);
    // No live card and no help footer on the unavailable branch.
    expect(find.text('Roams this session'), findsNothing);
  });

  testWidgets('web shows the unavailable view', (t) async {
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.web,
        enableSampling: false,
      ),
    );
    expect(find.text('Roaming Log'), findsOneWidget);
    expect(find.text('Roams this session'), findsNothing);
  });

  testWidgets(
      'iOS source renders the intro + footer (sampling disabled in test)',
      (t) async {
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.iosShortcuts,
        enableSampling: false,
      ),
    );
    expect(find.text('Roaming Log'), findsOneWidget);
    // The iOS intro names the foreground-only limit honestly.
    expect(
      find.textContaining('There is no'),
      findsOneWidget,
    );
    // The §8.16.1 help footer is wired to roaming-log.
    expect(find.byType(ToolHelpFooter), findsOneWidget);
    expect(find.text('About this tool'), findsOneWidget);
  });

  testWidgets(
      'copy action is DISABLED on the honest empty state (no roams recorded)',
      (t) async {
    // No sampler is wired (enableSampling: false), so there are no roam events
    // and the §8.16 affordance must render disabled and copy nothing on tap.
    await pump(
      t,
      const RoamingLogScreen(
        sourceOverride: WifiInfoSource.iosShortcuts,
        enableSampling: false,
      ),
    );

    final Finder copy = find.bySemanticsLabel('Copy results');
    expect(copy, findsOneWidget);
    await t.tap(copy);
    await t.pump();
    // Disabled affordance writes nothing.
    expect(clipboardWrites, isEmpty);
  });

  group('buildRoamLogCopyText (§8.16 pure serializer)', () {
    test('returns null on the empty session — never copies a fake/empty log',
        () {
      expect(
        buildRoamLogCopyText(events: const <RoamEvent>[], network: 'KeithNet'),
        isNull,
      );
    });

    test('builds the header + one block per roam, in chronological order', () {
      final DateTime start = DateTime(2026, 6, 28, 14, 14, 0);
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 14, 14, 7),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: -67,
          snr: 30,
        ),
        _roam(
          at: DateTime(2026, 6, 28, 14, 15, 2),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          rssi: -72,
        ),
      ];

      final String? text = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        sessionStart: start,
      );

      expect(text, isNotNull);
      // Header.
      expect(text, startsWith('Roaming Log'));
      expect(text, contains('Network: KeithNet'));
      expect(text, contains('Session started: 2:14:00 PM'));
      expect(text, contains('2 roams recorded'));
      // Per-roam blocks with the from→to BSSID pairs.
      expect(text, contains('1. 2:14:07 PM · KeithNet'));
      expect(text, contains('aa:bb:cc:dd:ee:01 -> aa:bb:cc:dd:ee:02'));
      expect(text, contains('Signal at roam: -67 dBm · SNR 30 dB'));
      expect(text, contains('2. 2:15:02 PM · KeithNet'));
      expect(text, contains('aa:bb:cc:dd:ee:02 -> aa:bb:cc:dd:ee:03'));
      // Dwell on the prior AP is derived from consecutive roam timestamps
      // (55s between 14:14:07 and 14:15:02) and only on the 2nd+ roam.
      expect(text, contains('Time on previous AP: 55s'));
    });

    test('honest "unavailable" wording when the platform omitted the signal',
        () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: null,
        ),
      ];

      final String? text = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
      );

      expect(text, contains('Signal at roam: unavailable'));
      // Singular count word on a one-roam session.
      expect(text, contains('1 roam recorded'));
    });

    test('falls back to "Wi-Fi" when a roam carried no SSID', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 9, 0, 0),
          ssid: null,
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
        ),
      ];

      final String? text = buildRoamLogCopyText(
        events: events,
        network: 'Wi-Fi',
      );

      expect(text, contains('· Wi-Fi'));
    });
  });
}
