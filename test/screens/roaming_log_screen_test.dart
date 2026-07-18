// RoamingLogScreen — widget tests (Feature 2, Felix 2026-06-13). The honest
// empty / unavailable branches run hermetically with no platform channel
// (enableSampling: false or an unsupported source). The §8.16 copy-export
// serialization (2026-06-28) is exercised through the pure, sampler-free
// [buildRoamLogCopyText] with synthetic [RoamEvent]s — deterministic, no live
// stream, no timers.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/pdf_download.dart' show ShareOrigin;
import 'package:wlan_pros_toolbox/screens/tools/network/roaming_log_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/roam_detector.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart'
    show LocationAuthStatus;
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

/// A no-network snapshot adapter standing in for the Windows Native Wifi reader,
/// so the Windows sampler path runs hermetically (no FFI, no wlanapi.dll).
class _FakeSnapshotAdapter implements WifiInfoAdapter {
  const _FakeSnapshotAdapter();

  @override
  Future<ConnectedAp> fetch() async => const ConnectedAp(
        ssid: 'KeithNet',
        bssid: 'a4:83:e7:00:11:22',
        rssiDbm: -55,
      );

  @override
  bool get gatesNameBehindPermission => false;

  @override
  Future<bool> requestNamePermission() async => true;

  @override
  Future<bool> currentNameAuthorization() async => true;

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;

  @override
  Future<bool> openNamePermissionSettings() async => false;

  @override
  String get platformLabel => 'Windows';
}

/// A snapshot adapter that returns a FIRST AP on its first read and a SECOND AP
/// on every read after — so a live sampler observes a real BSSID change and
/// records a roam. Drives the Task-1 dead-Copy-button regression.
class _RoamingAdapter implements WifiInfoAdapter {
  _RoamingAdapter(this.first, this.second);

  final ConnectedAp first;
  final ConnectedAp second;
  int calls = 0;

  @override
  Future<ConnectedAp> fetch() async {
    calls++;
    return calls <= 1 ? first : second;
  }

  @override
  bool get gatesNameBehindPermission => false;

  @override
  Future<bool> requestNamePermission() async => true;

  @override
  Future<bool> currentNameAuthorization() async => true;

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;

  @override
  Future<bool> openNamePermissionSettings() async => false;

  @override
  String get platformLabel => 'Windows';
}

RoamEvent _roam({
  required DateTime at,
  String? ssid = 'KeithNet',
  required String from,
  required String to,
  int? rssi = -60,
  int? snr,
  int? fromChannel,
  int? toChannel,
  String? fromBand,
  String? toBand,
  bool fromBandDerived = false,
  bool toBandDerived = false,
  String? fromApName,
  String? toApName,
}) =>
    RoamEvent(
      at: at,
      ssid: ssid,
      fromBssid: from,
      toBssid: to,
      rssiDbm: rssi,
      snrDb: snr,
      fromChannel: fromChannel,
      toChannel: toChannel,
      fromBand: fromBand,
      toBand: toBand,
      fromBandDerived: fromBandDerived,
      toBandDerived: toBandDerived,
      fromApName: fromApName,
      toApName: toApName,
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
      'Windows source wires the live sampler — monitoring is AVAILABLE, never '
      'the false "off on this device" (C3 fix)', (t) async {
    // Windows Native Wifi polls exactly like macOS/Android; the roam log must
    // treat it as an auto-monitoring platform, not darken it. A fake-adapter
    // sampler runs the path with no FFI.
    final WifiSignalSampler sampler = WifiSignalSampler(
      source: WifiInfoSource.windowsNativeWifi,
      macAdapter: const _FakeSnapshotAdapter(),
    );

    await pump(
      t,
      RoamingLogScreen(
        sourceOverride: WifiInfoSource.windowsNativeWifi,
        sampler: sampler,
      ),
    );

    // The live card renders (monitoring available) — NOT the disabled card.
    expect(find.text('Roams this session'), findsOneWidget);
    expect(
      find.text('Live Wi-Fi monitoring is off on this device.'),
      findsNothing,
    );
    // The intro copy is platform-neutral, not the old macOS-only wording.
    expect(find.textContaining('Your device reads the link'), findsOneWidget);

    // Unmount the screen (detaches the card's listener), then dispose the
    // injected sampler within the test body so its 2 s auto-poll timer is
    // cancelled before the pending-timer invariant check (the screen never
    // disposes an INJECTED sampler).
    await t.pumpWidget(const SizedBox());
    sampler.dispose();
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

  // A capture of what the injected share seam was handed, so a Share tap can be
  // asserted without touching the platform share channel.
  late List<Map<String, Object?>> sharedDocs;

  RoamShareFn fakeShare() => ({
        required List<int> bytes,
        required String filename,
        required String mimeType,
        String? title,
        ShareOrigin? shareOrigin,
      }) async {
        sharedDocs.add(<String, Object?>{
          'html': utf8.decode(bytes),
          'filename': filename,
          'mimeType': mimeType,
        });
      };

  setUp(() => sharedDocs = <Map<String, Object?>>[]);

  // A sampler wired to the FIRST->SECOND roaming adapter, plus a helper that
  // pumps the screen and drives exactly one real roam through it.
  WifiSignalSampler roamingSampler({bool toBandDerived = false}) =>
      WifiSignalSampler(
        source: WifiInfoSource.windowsNativeWifi,
        macAdapter: _RoamingAdapter(
          const ConnectedAp(
            ssid: 'KeithNet',
            bssid: '94:2a:6f:5c:3a:10',
            rssiDbm: -58,
            channel: 44,
            band: '5 GHz',
          ),
          ConnectedAp(
            ssid: 'KeithNet',
            bssid: '94:2a:6f:5c:3e:20',
            rssiDbm: -63,
            channel: 37,
            band: '6 GHz',
            bandDerived: toBandDerived,
          ),
        ),
        macPollInterval: const Duration(milliseconds: 50),
      );

  Future<void> driveOneRoam(WidgetTester t, WifiSignalSampler sampler,
      {RoamShareFn? shareFn, Size surface = const Size(560, 1200)}) async {
    await t.binding.setSurfaceSize(surface);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: RoamingLogScreen(
        sourceOverride: WifiInfoSource.windowsNativeWifi,
        sampler: sampler,
        shareFn: shareFn ?? fakeShare(),
      ),
    ));
    await t.pump(); // build
    await t.pump(); // resolve the seed fetch() -> anchor set, still zero roams
  }

  Future<void> advanceToRoam(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 60)); // fire the poll timer
    await t.pump(); // resolve fetch() -> roam recorded, notifyListeners
    await t.pump(); // rebuild the AppBar AnimatedBuilder
  }

  // ===================================================================
  // TASK 1 — the dead Copy button (AppBar action never re-resolved enabled).
  // ===================================================================
  testWidgets(
      'TASK 1: Copy button goes from disabled to enabled as roams land and '
      'copies the report (dead-Copy-button regression)', (t) async {
    final WifiSignalSampler sampler = roamingSampler();
    await driveOneRoam(t, sampler);

    // Zero roams: the copy affordance is disabled and a tap writes nothing.
    final Finder copy = find.bySemanticsLabel('Copy results');
    expect(copy, findsOneWidget);
    await t.tap(copy);
    await t.pump();
    expect(clipboardWrites, isEmpty,
        reason: 'Copy must be disabled while no roam is recorded.');

    // A roam lands -> the AppBar action must re-resolve to ENABLED (the bug was
    // that it latched disabled for the whole session).
    await advanceToRoam(t);
    expect(sampler.roamEvents, isNotEmpty);

    await t.tap(find.bySemanticsLabel('Copy results'));
    await t.pump();
    expect(clipboardWrites, isNotEmpty,
        reason: 'Copy must become enabled once a roam exists.');
    expect(clipboardWrites.single, startsWith('Roaming Log'));
    expect(clipboardWrites.single, contains('Network: KeithNet'));
    // The identifying last octets of the joined AP are in the copied report.
    expect(clipboardWrites.single, contains(':3e:20'));

    // Drain AppCopyAction's 1.5s confirm-revert timer before teardown.
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpWidget(const SizedBox());
    sampler.dispose();
  });

  // ===================================================================
  // TASK 2 — the row shows the identifying tail, not the shared OUI.
  // ===================================================================
  testWidgets(
      'TASK 2: a roam row shows the last two octets, never the OUI-leading '
      'truncation', (t) async {
    final WifiSignalSampler sampler = roamingSampler();
    await driveOneRoam(t, sampler);
    await advanceToRoam(t);

    // The identifying tails are visible.
    expect(find.textContaining(':3a:10'), findsOneWidget); // left AP
    expect(find.textContaining(':3e:20'), findsOneWidget); // joined AP
    // The shared OUI is NOT rendered as visible text (it lives only in the
    // full-BSSID a11y label, a separate semantics node).
    expect(find.textContaining('94:2a:6f'), findsNothing);

    await t.pumpWidget(const SizedBox());
    sampler.dispose();
  });

  // ===================================================================
  // TASK 3 — band + channel render, and a derived band is marked, on-screen.
  // ===================================================================
  testWidgets(
      'TASK 3: a roam row renders channel + band for both APs and marks a '
      'derived band', (t) async {
    // The joined AP carries a DERIVED band (iOS-style) so the row must flag it.
    final WifiSignalSampler sampler = roamingSampler(toBandDerived: true);
    await driveOneRoam(t, sampler);
    await advanceToRoam(t);

    // Channel leads, band follows, for the left AP (directly reported).
    expect(find.textContaining('ch 44 · 5 GHz'), findsOneWidget);
    // The joined AP's band is derived -> it carries the honest caption.
    expect(find.textContaining('ch 37 · 6 GHz (derived)'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    sampler.dispose();
  });

  testWidgets(
      'TASK 2/3: the roam row renders without overflow on a 360px phone',
      (t) async {
    final WifiSignalSampler sampler = roamingSampler(toBandDerived: true);
    await driveOneRoam(t, sampler, surface: const Size(360, 900));
    await advanceToRoam(t);
    // A RenderFlex overflow would throw and fail this test; reaching the
    // assertions means the two-block row fits the narrow viewport.
    expect(find.textContaining(':3e:20'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.pumpWidget(const SizedBox());
    sampler.dispose();
  });

  // ===================================================================
  // TASK 5 — the Share document action: disabled at zero roams, enabled after.
  // ===================================================================
  testWidgets(
      'TASK 5: Share action is disabled at zero roams and shares an HTML '
      'document once a roam exists', (t) async {
    final WifiSignalSampler sampler = roamingSampler();
    await driveOneRoam(t, sampler);

    final Finder share = find.bySemanticsLabel('Share roaming log');
    expect(share, findsOneWidget);
    // Zero roams: tapping shares nothing.
    await t.tap(share);
    await t.pump();
    expect(sharedDocs, isEmpty,
        reason: 'Share must be disabled while no roam is recorded.');

    await advanceToRoam(t);
    await t.tap(find.bySemanticsLabel('Share roaming log'));
    await t.pump();
    expect(sharedDocs, hasLength(1));
    expect(sharedDocs.single['filename'], 'roaming-log.html');
    expect(sharedDocs.single['mimeType'], 'text/html');
    final String html = sharedDocs.single['html']! as String;
    expect(html, contains('<h1>Roaming Log</h1>'));
    expect(html, contains('KeithNet'));
    // A document has room for the COMPLETE BSSID.
    expect(html, contains('94:2a:6f:5c:3e:20'));

    await t.pumpWidget(const SizedBox());
    sampler.dispose();
  });

  group('buildRoamLogCopyText (§8.16 pure serializer)', () {
    // iOS-style events: band derived from channel, so the 6 GHz caveat applies.
    List<RoamEvent> sampleEvents() => <RoamEvent>[
          _roam(
            at: DateTime(2026, 6, 28, 14, 14, 7),
            from: 'aa:bb:cc:dd:ee:01',
            to: 'aa:bb:cc:dd:ee:02',
            rssi: -67,
            snr: 30,
            fromChannel: 44,
            toChannel: 37,
            fromBand: '5 GHz',
            toBand: '6 GHz',
            fromBandDerived: true,
            toBandDerived: true,
          ),
          _roam(
            at: DateTime(2026, 6, 28, 14, 15, 2),
            from: 'aa:bb:cc:dd:ee:02',
            to: 'aa:bb:cc:dd:ee:03',
            rssi: -72,
            fromChannel: 37,
            toChannel: 44,
            fromBand: '6 GHz',
            toBand: '5 GHz',
            fromBandDerived: true,
            toBandDerived: true,
          ),
        ];

    test('returns null on the empty session — never copies a fake/empty log',
        () {
      expect(
        buildRoamLogCopyText(events: const <RoamEvent>[], network: 'KeithNet'),
        isNull,
      );
    });

    test(
        'TASK 4: report carries platform stamp, last-octets, channel-first '
        'band, summary, and aligns; no em dash', () {
      final String? text = buildRoamLogCopyText(
        events: sampleEvents(),
        network: 'KeithNet',
        capturePlatform: 'iOS',
        sessionStart: DateTime(2026, 6, 28, 14, 14, 0),
      );

      expect(text, isNotNull);
      final String out = text!;
      // Header, platform stamp, session window, count, signal summary.
      expect(out, startsWith('Roaming Log'));
      expect(out, contains('Network: KeithNet'));
      expect(out, contains('Captured on: iOS'));
      expect(out, contains('Session: 2:14:00 PM to 2:15:02 PM'));
      expect(out, contains('2 roams recorded'));
      expect(out,
          contains('Signal: avg -70 dBm, strongest -67 dBm, weakest -72 dBm'));

      // Last-octets identifier, NOT the shared OUI leading each cell.
      expect(out, contains(':ee:01'));
      expect(out, isNot(contains('aa:bb:cc:dd:ee:01')));
      // Channel LEADS the band; a derived band carries the footnote marker.
      expect(out, contains('ch 44 · 5 GHz*'));
      expect(out, contains('ch 37 · 6 GHz*'));
      // Dwell on the previous AP (55s) shows on the 2nd roam; the 1st is n/a.
      expect(out, contains('55s'));
      expect(out, contains('n/a'));

      // Honesty footnotes.
      expect(out, contains('Band derived from the channel number on iOS'));
      expect(out, contains('There is no'));
      expect(out, contains('background Wi-Fi monitoring on iOS'));

      // Alignment: the From column content lines up under the "From" header.
      final List<String> lines = out.split('\n');
      final String header =
          lines.firstWhere((String l) => l.contains('From') && l.contains('To'));
      final String row1 =
          lines.firstWhere((String l) => l.contains(':ee:01'));
      expect(row1.indexOf(':ee:01'), header.indexOf('From'));

      // Voice guard floor: no em dash, no prose en dash, ASCII only for arrows.
      expect(out.contains('—'), isFalse);
    });

    test('honest "signal n/a" wording when the platform omitted RSSI, and a '
        'derived-band-free session has no derived footnote', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: null,
          fromChannel: 36,
          toChannel: 40,
          fromBand: '5 GHz',
          toBand: '5 GHz',
        ),
      ];

      final String? text = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      );

      expect(text, contains('signal n/a'));
      expect(text, contains('Signal: not reported'));
      expect(text, contains('1 roam recorded'));
      expect(text, contains('Captured on: macOS'));
      // Band was reported directly (not derived) -> no derived footnote.
      expect(text, isNot(contains('Band derived from the channel')));
    });
  });

  group('buildRoamLogShareHtml (§8.16 Share document)', () {
    test('returns null on the empty session', () {
      expect(
        buildRoamLogShareHtml(events: const <RoamEvent>[], network: 'KeithNet'),
        isNull,
      );
    });

    test(
        'TASK 5: HTML document carries network, platform, count, full BSSIDs, '
        'channel+band, AP name, and the honesty notes', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 14, 14, 7),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: -67,
          snr: 30,
          fromChannel: 44,
          toChannel: 37,
          fromBand: '5 GHz',
          toBand: '6 GHz',
          fromBandDerived: true,
          toBandDerived: true,
          fromApName: 'Lobby-AP-1',
          toApName: 'Hall-AP-2',
        ),
      ];

      final String? html = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
        sessionStart: DateTime(2026, 6, 28, 14, 14, 0),
      );

      expect(html, isNotNull);
      final String doc = html!;
      expect(doc, contains('<h1>Roaming Log</h1>'));
      expect(doc, contains('KeithNet'));
      expect(doc, contains('Captured on'));
      expect(doc, contains('iOS'));
      expect(doc, contains('1 roam recorded'));
      // Full BSSIDs (there is room in a document), channel + band.
      expect(doc, contains('aa:bb:cc:dd:ee:01'));
      expect(doc, contains('aa:bb:cc:dd:ee:02'));
      expect(doc, contains('ch 44'));
      expect(doc, contains('6 GHz'));
      // AP names carried into the export (macOS advertises them).
      expect(doc, contains('Lobby-AP-1'));
      expect(doc, contains('Hall-AP-2'));
      // Honesty callout (bordered box, same content as the old bare notes).
      expect(doc, contains('class="callout"'));
      expect(doc, contains('Honesty notes on this capture'));
      expect(doc, contains('Band derived from the channel number on iOS'));
      expect(doc, contains('background Wi-Fi monitoring on iOS'));
      // No em dash in the exported document.
      expect(doc.contains('—'), isFalse);
    });

    test(
        'TASK: the upgraded document has stat tiles, computed facts, a ping-pong '
        'line, and no fabricated verdicts', () {
      // A 4-roam session with a precise A->B->A ping-pong (rows 2 and 3) inside
      // the 30s window, plus varied RSSI/SNR/dwell to exercise the stat tiles.
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 14, 0, 0),
          from: '94:2a:6f:5c:aa:01',
          to: '94:2a:6f:5c:aa:02',
          rssi: -59,
          snr: 36,
        ),
        _roam(
          at: DateTime(2026, 6, 28, 14, 0, 40),
          from: '94:2a:6f:5c:aa:02',
          to: '94:2a:6f:5c:aa:03',
          rssi: -62,
          snr: 33,
        ),
        // Ping-pong: back to :02 within 12s of the prior roam.
        _roam(
          at: DateTime(2026, 6, 28, 14, 0, 52),
          from: '94:2a:6f:5c:aa:03',
          to: '94:2a:6f:5c:aa:02',
          rssi: -68,
          snr: 28,
        ),
        _roam(
          at: DateTime(2026, 6, 28, 14, 1, 25),
          from: '94:2a:6f:5c:aa:02',
          to: '94:2a:6f:5c:aa:04',
          rssi: -64,
          snr: 30,
        ),
      ];

      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'Summit-WiFi',
        capturePlatform: 'iOS',
      )!;

      // Stat tiles present with computed values.
      expect(doc, contains('class="stat"'));
      expect(doc, contains('dBm avg at roam'));
      expect(doc, contains('dBm strongest / weakest'));
      expect(doc, contains('dB SNR range'));
      expect(doc, contains('avg dwell per AP'));
      expect(doc, contains('28-36')); // SNR range lo-hi

      // Session-at-a-glance computed facts.
      expect(doc, contains('Session at a glance'));
      expect(doc, contains('Roams fired between -59 dBm'));
      expect(doc, contains('Dwell on the previous AP'));
      // The ping-pong is precisely detected and named with its tails + window.
      expect(doc, contains('Ping-pong at'));
      expect(doc, contains(':aa:02'));
      expect(doc, contains('class="flap"'));

      // No interpretive health verdicts the app cannot prove.
      expect(doc.toLowerCase().contains('healthy'), isFalse);
      expect(doc.contains('—'), isFalse);
    });

    test('no ping-pong line and no flap rows when none is present', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 14, 0, 0),
          from: '94:2a:6f:5c:aa:01',
          to: '94:2a:6f:5c:aa:02',
          rssi: -60,
          snr: 30,
        ),
        _roam(
          at: DateTime(2026, 6, 28, 14, 0, 40),
          from: '94:2a:6f:5c:aa:02',
          to: '94:2a:6f:5c:aa:03',
          rssi: -62,
          snr: 31,
        ),
      ];
      final String doc = buildRoamLogShareHtml(
        events: events, network: 'Summit-WiFi')!;
      expect(doc.contains('Ping-pong at'), isFalse);
      expect(doc.contains('class="flap"'), isFalse);
    });
  });

  group('lastOctets (Task 2 pure helper)', () {
    test('returns the last two octets with a leading colon', () {
      expect(lastOctets('94:2a:6f:5c:3a:10'), ':3a:10');
    });
    test('falls back to the whole value for a malformed/short BSSID', () {
      expect(lastOctets('single'), 'single');
      expect(lastOctets(''), '');
    });
  });

  group('bandChannelLabel (channel-first, honest-null)', () {
    test('leads with channel, then band', () {
      expect(bandChannelLabel(44, '5 GHz'), 'ch 44 · 5 GHz');
    });
    test('marks a derived band with the footnote asterisk', () {
      expect(bandChannelLabel(37, '6 GHz', derived: true), 'ch 37 · 6 GHz*');
    });
    test('omits null parts and returns empty when neither is known', () {
      expect(bandChannelLabel(44, null), 'ch 44');
      expect(bandChannelLabel(null, '5 GHz'), '5 GHz');
      expect(bandChannelLabel(null, null), '');
    });
  });

  group('capturePlatformLabel', () {
    test('maps each source to its platform stamp', () {
      expect(capturePlatformLabel(WifiInfoSource.iosShortcuts), 'iOS');
      expect(capturePlatformLabel(WifiInfoSource.macosCoreWlan), 'macOS');
      expect(capturePlatformLabel(WifiInfoSource.androidWifiManager), 'Android');
    });
  });
}
