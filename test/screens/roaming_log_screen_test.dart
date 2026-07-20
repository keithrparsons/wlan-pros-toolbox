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
import 'package:wlan_pros_toolbox/services/network/device_info_service.dart';
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

/// A snapshot adapter that always returns the SAME connected AP, so the live
/// sampler seeds a stable current-connection reading without ever recording a
/// roam. [ap] lets a test control exactly which fields are present, to exercise
/// the current-connection card's connected / partial / disconnected states.
class _StaticApAdapter implements WifiInfoAdapter {
  const _StaticApAdapter(this.ap);

  final ConnectedAp ap;

  @override
  Future<ConnectedAp> fetch() async => ap;

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

/// A macOS Location (name-gate) adapter whose status is scriptable, used to
/// drive the Roaming Log's "Location access needed" flow hermetically (no
/// CLLocationManager, no platform channel). Records the prompt + deep-link calls
/// so a test can assert the screen requested the grant / opened Settings, and can
/// flip its status once the prompt is answered to model a grant or a denial.
class _FakeLocationAdapter implements WifiInfoAdapter {
  _FakeLocationAdapter(this._status, {LocationAuthStatus? afterPrompt})
      // ignore: prefer_initializing_formals
      : _afterPrompt = afterPrompt;

  LocationAuthStatus _status;
  final LocationAuthStatus? _afterPrompt;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => _status;

  @override
  Future<bool> requestNamePermission() async {
    requestCalls++;
    if (_afterPrompt != null) _status = _afterPrompt;
    return _status.isAuthorized;
  }

  @override
  Future<bool> currentNameAuthorization() async => _status.isAuthorized;

  @override
  Future<bool> openNamePermissionSettings() async {
    openSettingsCalls++;
    return true;
  }

  // The screen never calls fetch() on the LOCATION adapter (the sampler owns the
  // snapshot read via its own adapter); a benign reading keeps the contract total.
  @override
  Future<ConnectedAp> fetch() async => const ConnectedAp(poweredOn: true);

  @override
  String get platformLabel => 'macOS CoreWLAN';
}

RoamEvent _roam({
  required DateTime at,
  String? ssid = 'KeithNet',
  required String from,
  required String to,
  int? rssi = -60,
  int? fromRssi,
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
      fromRssiDbm: fromRssi,
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

/// The native transport probe channel. Stubbed (honest "unavailable") so the
/// Android-source sampler path settles without leaving a pending probe timer.
const MethodChannel _networkTransportChannel =
    MethodChannel('com.wlanpros.toolbox/network_transport');

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
    // On an Android source the sampler's WifiConnectionService fires the native
    // transport probe. Stub it to the HONEST "could not read" payload so the
    // probe settles in-process (no dangling 3s timer) — the same fidelity stub
    // interface_info_screen_test uses. Inert for the Windows/macOS/iOS sources.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _networkTransportChannel,
      (MethodCall call) async => <String, Object?>{'available': false},
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkTransportChannel, null);
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
    // canceled before the pending-timer invariant check (the screen never
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

  // ===================================================================
  // macOS Location-denied state (Keith on-device: Roaming Log went BLANK with
  // no explanation when Location was not granted). CoreWLAN withholds the
  // SSID/BSSID every roam is built from without a Location grant, so the screen
  // must show an actionable "Location access needed" state, never a perpetual
  // empty "watching for roams".
  // ===================================================================
  group('macOS Location gate', () {
    testWidgets(
        'DENIED on entry renders the honest "Location access needed" state with '
        'a settings deep-link, and no live roam card', (t) async {
      final _FakeLocationAdapter loc =
          _FakeLocationAdapter(LocationAuthStatus.denied);
      await pump(
        t,
        RoamingLogScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: loc,
          enableSampling: false,
        ),
      );
      // Let _initMacLocation resolve the (denied) status and flip the body.
      await t.pump();

      expect(find.text('Location access needed'), findsOneWidget);
      // The perpetual empty state must NOT be what a denied user sees.
      expect(find.text('Roams this session'), findsNothing);

      // A denied status is NOT promptable, so the screen must not fire the
      // system dialog into a wall; the only path forward is the deep link.
      expect(loc.requestCalls, 0);

      final Finder action = find.text('Open Location settings');
      expect(action, findsOneWidget);
      await t.tap(action);
      await t.pump();
      expect(loc.openSettingsCalls, 1,
          reason: 'the action must deep-link the Location Services pane');
    });

    testWidgets(
        'NOT-DETERMINED on entry fires the native prompt ONCE; a grant resolves '
        'straight into the live log with no denied state', (t) async {
      final _FakeLocationAdapter loc = _FakeLocationAdapter(
        LocationAuthStatus.notDetermined,
        afterPrompt: LocationAuthStatus.authorized,
      );
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.macosCoreWlan,
        macAdapter: const _FakeSnapshotAdapter(),
        macPollInterval: const Duration(milliseconds: 50),
      );
      await pump(
        t,
        RoamingLogScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          sampler: sampler,
          macAdapter: loc,
        ),
      );
      await t.pump(); // resolve the prompt + re-read

      expect(loc.requestCalls, 1,
          reason: 'a promptable status fires the system prompt once on entry');
      // Granted after the prompt: the denied state must never appear.
      expect(find.text('Location access needed'), findsNothing);
      // The live monitoring card is what a granted user sees.
      expect(find.text('Roams this session'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets(
        'NOT-DETERMINED then DENIED after the prompt shows the deep-link state',
        (t) async {
      final _FakeLocationAdapter loc = _FakeLocationAdapter(
        LocationAuthStatus.notDetermined,
        afterPrompt: LocationAuthStatus.denied,
      );
      await pump(
        t,
        RoamingLogScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          macAdapter: loc,
          enableSampling: false,
        ),
      );
      await t.pump();

      expect(loc.requestCalls, 1);
      expect(find.text('Location access needed'), findsOneWidget);
      expect(find.text('Open Location settings'), findsOneWidget);
    });

    testWidgets(
        'AUTHORIZED renders the live roam log, never the Location state',
        (t) async {
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.macosCoreWlan,
        macAdapter: const _FakeSnapshotAdapter(),
        macPollInterval: const Duration(milliseconds: 50),
      );
      await pump(
        t,
        RoamingLogScreen(
          sourceOverride: WifiInfoSource.macosCoreWlan,
          sampler: sampler,
          macAdapter: _FakeLocationAdapter(LocationAuthStatus.authorized),
        ),
      );
      await t.pump();

      expect(find.text('Location access needed'), findsNothing);
      expect(find.text('Roams this session'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets('iOS is UNAFFECTED: no macOS Location state on the iOS source',
        (t) async {
      // iOS reads the name through its own Shortcut flow; the macOS Location
      // adapter is never built off the macOS source, so this state never shows.
      await pump(
        t,
        const RoamingLogScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          enableSampling: false,
        ),
      );
      await t.pump();
      expect(find.text('Location access needed'), findsNothing);
    });
  });

  // ===================================================================
  // CURRENT-CONNECTION CARD (top of body) — the live link snapshot shown the
  // instant the tool opens, from the SAME sampler reading the roam watch uses.
  // Honest-null throughout: measured fields only, no fabricated verdict.
  // ===================================================================
  group('current-connection card', () {
    Future<WifiSignalSampler> pumpWithStaticAp(
      WidgetTester t,
      ConnectedAp ap, {
      WifiInfoSource source = WifiInfoSource.windowsNativeWifi,
    }) async {
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: source,
        macAdapter: _StaticApAdapter(ap),
        macPollInterval: const Duration(milliseconds: 50),
      );
      await pump(
        t,
        RoamingLogScreen(
          sourceOverride: source,
          sampler: sampler,
        ),
      );
      await t.pump(); // resolve the seed fetch() -> sampler.latest populated
      return sampler;
    }

    testWidgets(
        'CONNECTED: renders SSID, BSSID tail, band+standard, channel+width, '
        'signal, SNR and Tx rate from the live reading', (t) async {
      final WifiSignalSampler sampler = await pumpWithStaticAp(
        t,
        const ConnectedAp(
          ssid: 'KeithNet',
          bssid: '94:2a:6f:5c:3a:10',
          rssiDbm: -52,
          snrDb: 34,
          txRateMbps: 1201,
          channel: 69,
          channelWidthMhz: 80,
          channelWidthAvailable: true,
          band: '6 GHz',
          standard: '802.11be (Wi-Fi 7)',
        ),
      );

      expect(find.text('Current connection'), findsOneWidget);
      expect(find.text('KeithNet'), findsOneWidget);
      // BSSID tail (the identifying last octets), never the shared OUI.
      expect(find.text(':3a:10'), findsOneWidget);
      expect(find.textContaining('94:2a:6f'), findsNothing);
      // Band + standard, channel + width, signal, SNR, Tx rate — measured values.
      expect(find.text('6 GHz · 802.11be (Wi-Fi 7)'), findsOneWidget);
      expect(find.text('ch 69 · 80 MHz'), findsOneWidget);
      expect(find.text('-52 dBm'), findsOneWidget);
      expect(find.text('34 dB'), findsOneWidget); // not derived -> no caption
      expect(find.text('1201 Mbps'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets(
        'NOT CONNECTED: a powered-on reading with no link data shows the clean '
        '"Not connected to Wi-Fi" state, never fake data', (t) async {
      final WifiSignalSampler sampler =
          await pumpWithStaticAp(t, const ConnectedAp(poweredOn: true));

      expect(find.text('Current connection'), findsOneWidget);
      expect(
        find.textContaining('Not connected to Wi-Fi'),
        findsOneWidget,
      );
      // No fabricated field rows on the disconnected state.
      expect(find.text('Signal'), findsNothing);
      expect(find.text('Band'), findsNothing);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets(
        'PARTIAL: only the fields the reading carried render; a null field is '
        'OMITTED (honest), and a missing AP name/BSSID shows the neutral dash',
        (t) async {
      final WifiSignalSampler sampler = await pumpWithStaticAp(
        t,
        const ConnectedAp(
          ssid: 'PartialNet',
          rssiDbm: -60,
          // No BSSID, no band, no standard, no channel/width, no SNR, no Tx rate.
        ),
      );

      expect(find.text('PartialNet'), findsOneWidget);
      expect(find.text('-60 dBm'), findsOneWidget);
      // The present rows carry their labels...
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Signal'), findsOneWidget);
      // ...and the absent fields are dropped entirely (no blank, no fake value).
      expect(find.text('Band'), findsNothing);
      expect(find.text('Channel'), findsNothing);
      expect(find.text('SNR'), findsNothing);
      expect(find.text('Tx rate'), findsNothing);
      // No name and no BSSID -> the neutral dash, not a guessed identifier.
      expect(find.text('—'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets(
        'DERIVED: an app-derived band and SNR (iOS) carry the honest "(derived)" '
        'caption, never presented as measured', (t) async {
      final WifiSignalSampler sampler = await pumpWithStaticAp(
        t,
        const ConnectedAp(
          ssid: 'KeithNet',
          bssid: '94:2a:6f:5c:3a:10',
          rssiDbm: -55,
          band: '6 GHz',
          bandDerived: true,
          snrDb: 30,
          snrDerived: true,
          channel: 37,
        ),
      );

      expect(find.text('6 GHz (derived)'), findsOneWidget);
      expect(find.text('30 dB (derived)'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets(
        'AP NAME present: the vendor name LEADS the access-point value and the '
        'BSSID tail drops beneath it (name-first, honest identifier)', (t) async {
      final WifiSignalSampler sampler = await pumpWithStaticAp(
        t,
        const ConnectedAp(
          ssid: 'KeithNet',
          bssid: '94:2a:6f:5c:3a:10',
          apName: 'AP-Lobby-3',
          rssiDbm: -52,
        ),
      );

      // The name is prominent...
      expect(find.text('AP-Lobby-3'), findsOneWidget);
      // ...and the identifying BSSID tail is still shown beneath it (never the
      // shared OUI head), so the AP stays precisely identifiable.
      expect(find.text(':3a:10'), findsOneWidget);
      expect(find.textContaining('94:2a:6f'), findsNothing);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });

    testWidgets(
        'ANDROID source: the card renders the live connection cleanly (apName '
        'is null on Android — no name row, the BSSID tail stands alone)',
        (t) async {
      final WifiSignalSampler sampler = await pumpWithStaticAp(
        t,
        const ConnectedAp(
          ssid: 'KeithNet',
          bssid: '94:2a:6f:5c:3a:10',
          rssiDbm: -58,
          band: '5 GHz',
          standard: '802.11ax (Wi-Fi 6)',
          channel: 44,
          channelWidthMhz: 80,
          channelWidthAvailable: true,
          txRateMbps: 866,
          // Android exposes no beacon IEs → apName stays null (honest).
        ),
        source: WifiInfoSource.androidWifiManager,
      );

      expect(find.text('Current connection'), findsOneWidget);
      expect(find.text('KeithNet'), findsOneWidget);
      // No fabricated AP name on Android; the BSSID tail identifies the AP.
      expect(find.text(':3a:10'), findsOneWidget);
      // The fields the Android adapter populates render; the layout is intact.
      expect(find.text('5 GHz · 802.11ax (Wi-Fi 6)'), findsOneWidget);
      expect(find.text('ch 44 · 80 MHz'), findsOneWidget);
      expect(find.text('-58 dBm'), findsOneWidget);
      expect(find.text('866 Mbps'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      sampler.dispose();
    });
  });

  group('current-connection pure formatters', () {
    test('currentBandStandard joins band and standard, captions a derived band',
        () {
      expect(
        currentBandStandard(const ConnectedAp(band: '6 GHz', standard: 'Wi-Fi 7')),
        '6 GHz · Wi-Fi 7',
      );
      expect(
        currentBandStandard(
            const ConnectedAp(band: '6 GHz', bandDerived: true)),
        '6 GHz (derived)',
      );
      expect(currentBandStandard(const ConnectedAp()), isNull);
    });

    test('currentChannelWidth leads with channel and adds width only when '
        'the platform exposes it', () {
      expect(
        currentChannelWidth(const ConnectedAp(
            channel: 69, channelWidthMhz: 80, channelWidthAvailable: true)),
        'ch 69 · 80 MHz',
      );
      // Width present but platform cannot expose it -> channel only, no guess.
      expect(
        currentChannelWidth(const ConnectedAp(channel: 44, channelWidthMhz: 80)),
        'ch 44',
      );
      // The 80+80 MHz sentinel renders its own unit.
      expect(
        currentChannelWidth(const ConnectedAp(
            channel: 44, channelWidthMhz: 8080, channelWidthAvailable: true)),
        'ch 44 · 80+80 MHz',
      );
      expect(currentChannelWidth(const ConnectedAp()), isNull);
    });

    test('currentTxRate formats Mbps without a trailing .0 and null-omits', () {
      expect(currentTxRate(1201), '1201 Mbps');
      expect(currentTxRate(866.7), '866.7 Mbps');
      expect(currentTxRate(null), isNull);
    });
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
    expect(find.textContaining(':3a:10'), findsOneWidget); // left AP (roam row)
    // The joined AP's tail now appears TWICE: once in the roam row's "to" block
    // and once in the top "Current connection" card, which — after this roam —
    // shows the joined AP as the live link. Both use the same lastOctets tail.
    expect(find.textContaining(':3e:20'), findsNWidgets(2));
    // The shared OUI is NOT rendered as visible text anywhere (it lives only in
    // the full-BSSID a11y label, a separate semantics node) — the current-
    // connection card also renders the tail, never the OUI.
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

  // ===================================================================
  // FROM/TO RSSI — the row shows the old AP's last reading and the new AP's.
  // ===================================================================
  testWidgets(
      'a roam row shows BOTH the old AP RSSI and the new AP RSSI, labeled '
      'old vs new', (t) async {
    // The roaming adapter's first AP reads -58 dBm (anchored as the "from"
    // reading), the joined AP reads -63 dBm at the roam.
    final WifiSignalSampler sampler = roamingSampler();
    await driveOneRoam(t, sampler);
    await advanceToRoam(t);

    // Both readings are on-screen, and the label makes old vs new explicit.
    expect(
      find.textContaining('Signal on prev AP -58 dBm → this AP -63 dBm'),
      findsOneWidget,
    );

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
    // assertions means the two-block row fits the narrow viewport. The joined
    // AP's tail shows in both the roam row and the top current-connection card.
    expect(find.textContaining(':3e:20'), findsNWidgets(2));
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
            fromRssi: -60,
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
            fromRssi: -67,
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
      // Two populations, each labeled for what it computes. The pre-roam set
      // is the trigger level (-60, -67); the post-roam set is what the client
      // landed on (-67, -72). Pooling them would describe neither.
      expect(
        out,
        contains('Signal before roam (on the AP being left): avg -64 dBm, '
            'strongest -60 dBm, weakest -67 dBm'),
      );
      expect(
        out,
        contains('Signal after roam (on the AP joined): avg -70 dBm, '
            'strongest -67 dBm, weakest -72 dBm'),
      );

      // From/to RSSI pair per roam: the OLD AP's last reading, an ASCII arrow,
      // and the NEW AP's reading at the roam, so the delta reads left to right.
      expect(out, contains('-60 dBm -> -67 dBm'), reason: 'roam 1 from/to RSSI');
      expect(out, contains('-67 dBm -> -72 dBm'), reason: 'roam 2 from/to RSSI');
      // SNR (the single reading at the roam) still trails the pair.
      expect(out, contains('-60 dBm -> -67 dBm SNR 30 dB'));

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

    test(
        'from/to RSSI honest-null: a null from-reading prints "n/a", never a '
        'fabricated value', () {
      // The first roam has no prior-AP reading (fromRssi null) but a real joined
      // reading; the second has both. The report must show the honest "n/a" for
      // the missing side and never invent a number.
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 6, 28, 10, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: -56,
          fromRssi: null,
        ),
        _roam(
          at: DateTime(2026, 6, 28, 10, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          rssi: -61,
          fromRssi: -56,
        ),
      ];

      final String out = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;

      // Missing from-reading is honest "n/a", real to-reading is shown.
      expect(out, contains('n/a -> -56 dBm'));
      // Both present on the second roam.
      expect(out, contains('-56 dBm -> -61 dBm'));
      // Never a fabricated stand-in for the unknown from-reading.
      expect(out, isNot(contains('0 dBm -> -56 dBm')));
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
          fromRssi: -70,
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
      // From/to RSSI pair: the old AP's last reading, an arrow, the new AP's
      // reading at the roam. The column header names the direction.
      expect(doc, contains('Signal (from &rarr; to)'));
      expect(doc, contains('-70 dBm → -67 dBm'));
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
      // Tiles name their population. This fixture records no pre-roam readings,
      // so the before-roam tiles are absent rather than invented (GL-005).
      expect(doc, contains('dBm avg after roam'));
      expect(doc, isNot(contains('dBm weakest before roam')));
      expect(doc, contains('dB SNR range'));
      expect(doc, contains('avg dwell per AP'));
      expect(doc, contains('28-36')); // SNR range lo-hi

      // Session-at-a-glance computed facts.
      expect(doc, contains('Session at a glance'));
      // These are post-roam readings, so they describe where the client LANDED.
      // "Roams fired between" is trigger language and must not appear when no
      // pre-roam reading was recorded.
      expect(doc, contains('Roams landed between -59 dBm'));
      expect(doc, isNot(contains('Roams fired between')));
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

  group('captureLabel (enriched device stamp, honest fallback chain)', () {
    test('model + version present: "<model>, <platform> <version>"', () {
      expect(
        captureLabel(
          'macOS',
          const DeviceInfoSnapshot(modelName: 'MacBook Air', osVersion: '26.1'),
        ),
        'MacBook Air, macOS 26.1',
      );
      // The iOS example from the brief.
      expect(
        captureLabel(
          'iOS',
          const DeviceInfoSnapshot(modelName: 'iPhone 17', osVersion: '26'),
        ),
        'iPhone 17, iOS 26',
      );
    });

    test('model present, version null: model + platform, no version', () {
      expect(
        captureLabel(
          'macOS',
          const DeviceInfoSnapshot(modelName: 'MacBook Air'),
        ),
        'MacBook Air, macOS',
      );
    });

    test('both null: bare platform floor (null snapshot or empty snapshot)', () {
      expect(captureLabel('macOS', null), 'macOS');
      expect(captureLabel('macOS', const DeviceInfoSnapshot()), 'macOS');
      expect(captureLabel('iOS', const DeviceInfoSnapshot()), 'iOS');
    });

    test('modelName null falls back to the raw modelIdentifier', () {
      expect(
        captureLabel(
          'iOS',
          const DeviceInfoSnapshot(modelIdentifier: 'iPhone17,3', osVersion: '26'),
        ),
        'iPhone17,3, iOS 26',
      );
    });

    test('model null but version present: platform + version, never fabricated',
        () {
      expect(
        captureLabel('macOS', const DeviceInfoSnapshot(osVersion: '26.1')),
        'macOS 26.1',
      );
    });

    test('blank model/version strings are treated as absent (honest floor)', () {
      expect(
        captureLabel(
          'iOS',
          const DeviceInfoSnapshot(modelName: '   ', osVersion: ''),
        ),
        'iOS',
      );
    });
  });

  group('enriched "Captured on" flows through the exports', () {
    List<RoamEvent> oneRoam() => <RoamEvent>[
          _roam(
            at: DateTime(2026, 6, 28, 14, 14, 7),
            from: 'aa:bb:cc:dd:ee:01',
            to: 'aa:bb:cc:dd:ee:02',
            rssi: -67,
            fromChannel: 44,
            toChannel: 37,
            fromBand: '5 GHz',
            toBand: '6 GHz',
            fromBandDerived: true,
            toBandDerived: true,
          ),
        ];

    test(
        'copy text shows the enriched device stamp AND still fires the iOS '
        'honesty note (label enriches display, note keyed to bare platform)',
        () {
      final String out = buildRoamLogCopyText(
        events: oneRoam(),
        network: 'KeithNet',
        capturePlatform: 'iOS',
        capturedOnLabel: 'iPhone 17, iOS 26',
      )!;
      expect(out, contains('Captured on: iPhone 17, iOS 26'));
      // The foreground note must still be the iOS-specific one — proving the
      // enriched label did NOT break the `capturePlatform == 'iOS'` branch.
      expect(out, contains('background Wi-Fi monitoring on iOS'));
    });

    test('copy text without a device label degrades to the bare platform floor',
        () {
      final String out = buildRoamLogCopyText(
        events: oneRoam(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;
      expect(out, contains('Captured on: macOS'));
    });

    test('HTML document carries the enriched stamp in both header spots', () {
      final String doc = buildRoamLogShareHtml(
        events: oneRoam(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
        capturedOnLabel: 'MacBook Air, macOS 26.1',
      )!;
      // The .sub header line and the .meta "Captured on" row both carry it.
      expect(
        'MacBook Air, macOS 26.1'.allMatches(doc).length,
        greaterThanOrEqualTo(2),
      );
      expect(doc, contains('<span class="k">Captured on</span>'));
    });
  });

  // The signal summary must never report the network as stronger than the
  // capture shows. `rssiDbm` is ALWAYS the post-roam reading (the AP joined, so
  // always comparatively strong); `fromRssiDbm` is ALWAYS the pre-roam reading
  // (the AP being left, so always comparatively weak). Summarizing only the
  // former discards exactly the number a designer needs — how weak the client
  // let it get before it roamed — and flatters the network. Regression guard for
  // the 2026-07-20 field capture whose header read "weakest -71 dBm" while the
  // table beneath it carried a -81 dBm reading.
  group('signal summary counts BOTH sides of every roam', () {
    // Every pre-roam reading here is weaker than every post-roam reading. The
    // weakest datum in the fixture is -81 dBm and it lives ONLY in fromRssiDbm,
    // so a summary built from rssiDbm alone can never mention it.
    List<RoamEvent> lopsided() => <RoamEvent>[
          _roam(
            at: DateTime(2026, 7, 20, 9, 0, 0),
            from: 'aa:bb:cc:dd:ee:01',
            to: 'aa:bb:cc:dd:ee:02',
            fromRssi: -78,
            rssi: -55,
          ),
          _roam(
            at: DateTime(2026, 7, 20, 9, 1, 0),
            from: 'aa:bb:cc:dd:ee:02',
            to: 'aa:bb:cc:dd:ee:03',
            fromRssi: -81,
            rssi: -50,
          ),
          _roam(
            at: DateTime(2026, 7, 20, 9, 2, 0),
            from: 'aa:bb:cc:dd:ee:03',
            to: 'aa:bb:cc:dd:ee:04',
            fromRssi: -76,
            rssi: -60,
          ),
        ];

    test('copy report header reports the pre-roam floor, not just the landing',
        () {
      final String out = buildRoamLogCopyText(
        events: lopsided(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;

      final String beforeLine = out
          .split('\n')
          .firstWhere((String l) => l.startsWith('Signal before roam'));
      final String afterLine = out
          .split('\n')
          .firstWhere((String l) => l.startsWith('Signal after roam'));

      // The -81 dBm the client held on down to MUST reach the summary. On the
      // unfixed code the header's weakest is -60 (the weakest LANDING) and -81
      // appears nowhere outside the table.
      expect(beforeLine, contains('weakest -81 dBm'),
          reason: 'weakest pre-roam reading must appear in the summary');
      expect(beforeLine, contains('avg -78 dBm'));

      // -60 dBm is the weakest LANDING. It is a true number, but only under the
      // after-roam label; the unfixed code presented it unqualified as the
      // weakest signal of the session, which the table contradicted.
      expect(afterLine, contains('weakest -60 dBm'));
      expect(out, isNot(contains('Signal: avg')),
          reason: 'the unlabeled single-population header must be gone');

      // Label/computation agreement: the pre-roam and post-roam populations are
      // reported as distinct, each named for what it actually measures.
      expect(out, contains('before roam'));
      expect(out, contains('after roam'));
      // "at roam" was ambiguous — it read as the trigger and computed the
      // destination. It must not survive anywhere in the report.
      expect(out, isNot(contains('avg at roam')));
    });

    test('share HTML stat tiles surface the pre-roam floor', () {
      final String doc = buildRoamLogShareHtml(
        events: lopsided(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;

      // Scoped to the tiles, not the whole document: the table row carries -81
      // even on the unfixed code, so an unscoped `contains` would pass while a
      // tile still showed the post-roam number under a before-roam label.
      final String tiles = doc.substring(
        doc.indexOf('class="stat"'),
        doc.indexOf('<table'),
      );
      expect(tiles, contains('<div class="n">-81</div>'),
          reason: 'the weakest-before tile must carry the pre-roam floor');
      expect(tiles, contains('<div class="n">-78</div>'),
          reason: 'the avg-before tile must carry the pre-roam average');
      expect(tiles, contains('<div class="n">-55</div>'),
          reason: 'the avg-after tile must carry the post-roam average');
      expect(tiles, contains('dBm weakest before roam'));
      expect(tiles, contains('dBm avg before roam'));
      expect(tiles, contains('dBm avg after roam'));
      // The mislabeled tiles are gone.
      expect(doc, isNot(contains('dBm avg at roam')));
      expect(doc, isNot(contains('dBm strongest / weakest')));
    });

    test('narrative facts describe the trigger level, not only the landing', () {
      final String doc = buildRoamLogShareHtml(
        events: lopsided(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;

      // "Roams fired between ..." is trigger language: it must be computed from
      // the pre-roam readings. On the unfixed code it reads "-50 dBm ... -60
      // dBm" — the landing values wearing a trigger label.
      expect(doc, contains('Roams fired between -76 dBm'));

      // Scoped to the narrative region, NOT the whole document. Unscoped, this
      // assertion is dead: the table row supplies '-81 dBm' on defective code
      // too, so it passed under mutation while its siblings did the killing.
      final int glanceAt = doc.indexOf('Session at a glance');
      expect(glanceAt, greaterThanOrEqualTo(0),
          reason: 'the narrative section must exist for this test to mean anything');
      final String glance = doc.substring(glanceAt, doc.indexOf('</ul>', glanceAt));
      expect(glance, contains('-81 dBm'),
          reason: 'the weakest TRIGGER level must reach the narrative, not only '
              'the table row that already carried it before the fix');

      expect(doc, isNot(contains('Roams fired between -50 dBm')));
    });

    test('screen, copy report and share HTML agree on the weakest reading', () {
      final List<RoamEvent> events = lopsided();
      final String out = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;
      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;
      // Scoped to the SUMMARY, not the whole document: the table row already
      // contains -81 on the unfixed code, so an unscoped `contains` would pass
      // before and after and prove nothing.
      final String copyHeader = out
          .split('\n')
          .firstWhere((String l) => l.startsWith('Signal before roam'));
      expect(copyHeader, contains('-81 dBm'),
          reason: 'copy summary line must state the pre-roam floor');

      final String tiles = doc.substring(
        doc.indexOf('class="stat"'),
        doc.indexOf('<table'),
      );
      expect(tiles, contains('-81'),
          reason: 'share HTML stat tiles must state the same floor');

      // And the table row that proves it is still there, unchanged, on both
      // surfaces: summary and table now agree instead of contradicting.
      expect(out, contains('-81 dBm -> -50 dBm'));
      expect(doc, contains('-81 dBm → -50 dBm'));
    });

    // ---- Sample-size disclosure (the `n` carried into every label) ----
    //
    // The before/after lines are typographic peers but not always sample-size
    // peers: iOS omits RSSI far more often than macOS, so "before" can be
    // computed from a handful of roams while "after" is computed from all of
    // them. A -79 avg over 3 roams sitting beside a -53 avg over 40 invites
    // exactly the false comparison the split summary exists to prevent.
    //
    // Each site is asserted INDEPENDENTLY, because each is mutated
    // independently: a single test covering all three would still pass with two
    // of the three disclosures stripped.

    /// Four roams; only ONE carries a pre-roam reading. The post-roam
    /// population is complete. This is the lopsided shape iOS actually
    /// produces, and n=1 is the hard boundary for the wording.
    List<RoamEvent> sparseBefore() => <RoamEvent>[
          _roam(
            at: DateTime(2026, 7, 20, 9, 0, 0),
            from: 'aa:bb:cc:dd:ee:01',
            to: 'aa:bb:cc:dd:ee:02',
            rssi: -55,
          ),
          _roam(
            at: DateTime(2026, 7, 20, 9, 1, 0),
            from: 'aa:bb:cc:dd:ee:02',
            to: 'aa:bb:cc:dd:ee:03',
            rssi: -50,
          ),
          _roam(
            at: DateTime(2026, 7, 20, 9, 2, 0),
            from: 'aa:bb:cc:dd:ee:03',
            to: 'aa:bb:cc:dd:ee:04',
            fromRssi: -79,
            rssi: -53,
          ),
          _roam(
            at: DateTime(2026, 7, 20, 9, 3, 0),
            from: 'aa:bb:cc:dd:ee:04',
            to: 'aa:bb:cc:dd:ee:05',
            rssi: -52,
          ),
        ];

    test('SITE 1 (copy report): each population line states its own n', () {
      final String out = buildRoamLogCopyText(
        events: sparseBefore(),
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final String beforeLine = out
          .split('\n')
          .firstWhere((String l) => l.startsWith('Signal before roam'));
      final String afterLine = out
          .split('\n')
          .firstWhere((String l) => l.startsWith('Signal after roam'));

      // The incomplete population MUST disclose. Without this, '-79 avg' reads
      // as the session's pre-roam floor when it is a single reading.
      expect(beforeLine, contains('1 of 4 roams'),
          reason: 'a line computed from 1 of 4 roams must say so');
      expect(beforeLine, contains('on the AP being left'),
          reason: 'the population label survives alongside the count');

      // The COMPLETE population stays silent — see the suppression rationale.
      expect(afterLine, isNot(contains('of 4 roams')),
          reason: 'a complete population must not print a count');
      expect(afterLine, contains('on the AP joined'));

      // n=1 must not degrade into a plural/singular mismatch or a bare number.
      expect(beforeLine, isNot(contains('1 of 4 roam,')));
      expect(beforeLine, isNot(contains('1 of 1')));
    });

    test('SITE 2 (share HTML tiles): incomplete tiles carry n, complete ones do not',
        () {
      final String doc = buildRoamLogShareHtml(
        events: sparseBefore(),
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final String tiles =
          doc.substring(doc.indexOf('class="stat"'), doc.indexOf('<table'));

      expect(tiles, contains('dBm avg before roam (1 of 4 roams)'),
          reason: 'the avg-before tile is computed from 1 of 4 roams');
      expect(tiles, contains('dBm weakest before roam (1 of 4 roams)'),
          reason: 'the weakest-before tile shares that population');
      expect(tiles, contains('dBm avg after roam'),
          reason: 'the complete tile still renders');
      expect(tiles, isNot(contains('dBm avg after roam (')),
          reason: 'a complete population must not print a count');
    });

    test('SITE 3 (narrative): an incomplete population is scoped in prose', () {
      final String doc = buildRoamLogShareHtml(
        events: sparseBefore(),
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final int glanceAt = doc.indexOf('Session at a glance');
      final String glance = doc.substring(glanceAt, doc.indexOf('</ul>', glanceAt));

      // A LEADING clause, not a third parenthetical: these sentences already
      // carry strongest/weakest timestamps, and the caveat belongs before the
      // number it qualifies.
      //
      // Asserted as the WHOLE sentence, not the prefix. The earlier version of
      // this test matched only 'Of 4 roams, 1 reported ...' and never read the
      // clause it produced after the semicolon — which is how it stayed green
      // while emitting 'every roam landed on', a universal over 37 roams that
      // were never measured. A prefix assertion on a generated sentence proves
      // the prefix, not the sentence.
      expect(
          glance,
          contains('Of 4 roams, 1 reported the signal it left; '
              'the one that did fired at -79 dBm.'),
          reason: 'the trigger sentence must state its sample size AND keep its '
              'quantifier inside that sample');

      // The complete destination population reads clean, with no count.
      expect(glance, contains('Roams landed between'));
      expect(glance, isNot(contains('reported the signal they landed on')),
          reason: 'a complete population must not be scoped');
    });

    // ---- HIGH-1: a universal must never outrun its population ----
    //
    // n == 1 ALWAYS forces strongest == weakest, so the universal branch is the
    // normal path on the sparse captures iOS produces, not a corner. The bug
    // this guards emitted a coverage clause and then contradicted it inside the
    // same sentence: "Of 40 roams, 3 reported the signal they landed on; every
    // roam landed on -53 dBm." Each shape asserts the FULL sentence.

    test('HIGH-1 n=1: the universal shrinks to the single roam that reported',
        () {
      final String doc = buildRoamLogShareHtml(
        events: sparseBefore(),
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final int g = doc.indexOf('Session at a glance');
      final String glance = doc.substring(g, doc.indexOf('</ul>', g));

      expect(glance, contains('the one that did fired at -79 dBm.'));
      // The universal that outran its population must be gone.
      expect(glance, isNot(contains('every roam fired')));
      expect(glance, isNot(contains('Every roam fired')));
      expect(glance, isNot(contains('every recorded roam fired')));
      // And the pronoun agrees with the count.
      expect(glance, isNot(contains('1 reported the signal they left')));
    });

    test('HIGH-1 n=1 on the POST-roam population: same quantifier, same pronoun',
        () {
      // The mirror of the test above. Asserting the pronoun and the quantifier
      // on the pre-roam population only left the post-roam string unguarded —
      // the two are built by separate call sites and one can regress alone.
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          fromRssi: -70,
          rssi: null,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          fromRssi: -80,
          rssi: null,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 2, 0),
          from: 'aa:bb:cc:dd:ee:03',
          to: 'aa:bb:cc:dd:ee:04',
          fromRssi: -75,
          rssi: -53,
        ),
      ];
      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final int g = doc.indexOf('Session at a glance');
      final String glance = doc.substring(g, doc.indexOf('</ul>', g));

      expect(
          glance,
          contains('Of 3 roams, 1 reported the signal it landed on; '
              'the one that did landed on -53 dBm.'));
      // The universal that outran its population, and the pronoun mismatch.
      expect(glance, isNot(contains('every roam landed on')));
      expect(glance, isNot(contains('Every roam landed on')));
      expect(glance, isNot(contains('1 reported the signal they landed on')));
      // Pre-roam is complete here, so it stays unscoped — the mirror image.
      expect(glance, contains('Roams fired between'));
      expect(glance, isNot(contains('reported the signal it left')));
    });

    test('HIGH-1 n=3 of 5: the universal is quantified "all 3", both populations',
        () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          fromRssi: -81,
          rssi: -53,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          rssi: null,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 2, 0),
          from: 'aa:bb:cc:dd:ee:03',
          to: 'aa:bb:cc:dd:ee:04',
          fromRssi: -81,
          rssi: -53,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 3, 0),
          from: 'aa:bb:cc:dd:ee:04',
          to: 'aa:bb:cc:dd:ee:05',
          rssi: null,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 4, 0),
          from: 'aa:bb:cc:dd:ee:05',
          to: 'aa:bb:cc:dd:ee:06',
          fromRssi: -81,
          rssi: -53,
        ),
      ];
      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final int g = doc.indexOf('Session at a glance');
      final String glance = doc.substring(g, doc.indexOf('</ul>', g));

      expect(
          glance,
          contains('Of 5 roams, 3 reported the signal they left; '
              'all 3 fired at -81 dBm.'));
      expect(
          glance,
          contains('Of 5 roams, 3 reported the signal they landed on; '
              'all 3 landed on -53 dBm.'));
      // The contradicting universal, in either population.
      expect(glance, isNot(contains('every roam landed on')));
      expect(glance, isNot(contains('Every roam landed on')));
    });

    test('HIGH-1 complete: the plain universal is exactly true, and unhedged',
        () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          fromRssi: -81,
          rssi: -53,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          fromRssi: -81,
          rssi: -53,
        ),
      ];
      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final int g = doc.indexOf('Session at a glance');
      final String glance = doc.substring(g, doc.indexOf('</ul>', g));

      expect(glance, contains('Every roam fired at -81 dBm.'));
      expect(glance, contains('Every roam landed on -53 dBm.'));
      // No coverage clause on a complete capture, and no hedge qualifying
      // nothing: "every RECORDED roam" is meaningless when all were recorded.
      expect(glance, isNot(contains('reported the signal')));
      expect(glance, isNot(contains('recorded roam')));
    });

    test('MEDIUM-3: the SNR tile carries n under the convention this fix created',
        () {
      // Before coverage notes existed, a bare tile meant nothing in particular.
      // Now that the RSSI tiles beside it disclose their sample size, a SILENT
      // tile asserts completeness by convention — so a partial SNR range
      // printed bare would lie in the vocabulary this change taught the reader.
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          fromRssi: -70,
          rssi: -53,
          snr: 21,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          fromRssi: -80,
          rssi: -54,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 2, 0),
          from: 'aa:bb:cc:dd:ee:03',
          to: 'aa:bb:cc:dd:ee:04',
          fromRssi: -75,
          rssi: -55,
          snr: 23,
        ),
      ];
      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final String tiles =
          doc.substring(doc.indexOf('class="stat"'), doc.indexOf('<table'));

      expect(tiles, contains('dB SNR range (2 of 3 roams)'),
          reason: 'an SNR range over 2 of 3 roams must say so, exactly as the '
              'RSSI tiles beside it do');
      // The RSSI populations are complete here, so they stay silent — which is
      // precisely what makes a silent SNR tile read as "all 3".
      expect(tiles, contains('dBm avg before roam'));
      expect(tiles, isNot(contains('dBm avg before roam (')));
    });

    test('a COMPLETE SNR population leaves the tile silent, like the others', () {
      final String doc = buildRoamLogShareHtml(
        events: <RoamEvent>[
          _roam(
            at: DateTime(2026, 7, 20, 9, 0, 0),
            from: 'aa:bb:cc:dd:ee:01',
            to: 'aa:bb:cc:dd:ee:02',
            fromRssi: -70,
            rssi: -53,
            snr: 21,
          ),
          _roam(
            at: DateTime(2026, 7, 20, 9, 1, 0),
            from: 'aa:bb:cc:dd:ee:02',
            to: 'aa:bb:cc:dd:ee:03',
            fromRssi: -75,
            rssi: -55,
            snr: 23,
          ),
        ],
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;
      final String tiles =
          doc.substring(doc.indexOf('class="stat"'), doc.indexOf('<table'));
      expect(tiles, contains('dB SNR range'));
      expect(tiles, isNot(contains('dB SNR range (')));
    });

    test('a COMPLETE capture prints no counts anywhere — the note is the signal',
        () {
      // Every roam in lopsided() reports both readings, so nothing was omitted
      // and every count would read "3 of 3". Printing that on every report is
      // what trains a reader to skim past the number on the one capture where
      // it matters.
      final String out = buildRoamLogCopyText(
        events: lopsided(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;
      final String doc = buildRoamLogShareHtml(
        events: lopsided(),
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;
      expect(out, isNot(contains('of 3 roams')));
      expect(doc, isNot(contains('of 3 roams')));
      expect(out, isNot(contains('3 of 3')));
      expect(doc, isNot(contains('3 of 3')));
    });

    test('BOUNDARY: neither population reported — no count, no invented n', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: null,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          rssi: null,
        ),
      ];
      final String out = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;

      // The existing honest-null path wins: there is no statistic to qualify,
      // so "0 of 2 roams" would be noise attached to nothing.
      expect(out, contains('Signal: not reported'));
      expect(out, isNot(contains('of 2 roams')));
      expect(out, isNot(contains('0 of')));
    });

    test('BOUNDARY: one population empty, the other complete', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: -55,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          rssi: -50,
        ),
      ];
      final String out = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'iOS',
      )!;

      // n=0 takes the not-reported path, never "0 of 2 roams" hung off an
      // average that does not exist.
      expect(out, contains('Signal before roam: not reported'));
      expect(out, isNot(contains('0 of 2 roams')));
      // The complete population is complete, so it stays silent.
      final String afterLine = out
          .split('\n')
          .firstWhere((String l) => l.startsWith('Signal after roam'));
      expect(afterLine, isNot(contains('of 2 roams')));
    });

    // fromRssiDbm is honest-null on the first roam (there is no prior AP). A
    // null must never become a 0 nor drag an average.
    test('a null pre-roam reading is skipped, never zeroed', () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: -55,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          fromRssi: -80,
          rssi: -50,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 2, 0),
          from: 'aa:bb:cc:dd:ee:03',
          to: 'aa:bb:cc:dd:ee:04',
          fromRssi: -70,
          rssi: -60,
        ),
      ];

      final String out = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;

      // Average of the two REAL pre-roam readings: (-80 + -70) / 2 = -75.
      // Counting the null as 0 would give -50; counting it as a third sample
      // would give -50 as well. Both are wrong.
      expect(out, contains('avg -75 dBm'));
      expect(out, isNot(contains('avg -50 dBm, strongest')));
      // A zero must never surface as a signal reading. Anchored so it cannot be
      // satisfied by the trailing 0 of a real reading such as "-80 dBm".
      expect(out, isNot(matches(RegExp(r'(^|[^0-9])0 dBm', multiLine: true))),
          reason: 'a null pre-roam reading must not become 0 dBm');
    });

    test('all pre-roam readings absent degrades honestly, no invented floor',
        () {
      final List<RoamEvent> events = <RoamEvent>[
        _roam(
          at: DateTime(2026, 7, 20, 9, 0, 0),
          from: 'aa:bb:cc:dd:ee:01',
          to: 'aa:bb:cc:dd:ee:02',
          rssi: -55,
        ),
        _roam(
          at: DateTime(2026, 7, 20, 9, 1, 0),
          from: 'aa:bb:cc:dd:ee:02',
          to: 'aa:bb:cc:dd:ee:03',
          rssi: -60,
        ),
      ];

      final String out = buildRoamLogCopyText(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;
      final String doc = buildRoamLogShareHtml(
        events: events,
        network: 'KeithNet',
        capturePlatform: 'macOS',
      )!;

      // The post-roam population still reports; the pre-roam one says so plainly
      // rather than inventing a floor (GL-005 honest-null).
      expect(out, contains('after roam'));
      expect(out, contains('Signal before roam: not reported'));
      expect(doc, isNot(contains('dBm weakest before roam')));
      expect(doc, contains('dBm avg after roam'));
    });
  });
}
