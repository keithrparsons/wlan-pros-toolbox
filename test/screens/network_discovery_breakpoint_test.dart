// Network Discovery — the table/card layout boundary, pinned by behaviour.
//
// WHY THIS FILE EXISTS. `_tableBreakpoint = 760` carried a careful comment
// explaining that 760 sits below the macOS window's declared 800pt default so a
// fresh install with no saved window frame still gets the customer-requested
// table. Nothing enforced any of it: mutating the constant to 799 left all 30
// existing tests green. The reasoning was load-bearing product behaviour living
// in a comment, which is to say it was not protected at all.
//
// These tests assert the WIDTHS THAT SHIP, not the value of the constant. A
// test that reads `_tableBreakpoint` and compares it to 760 would pass for any
// value the constant happened to hold, including a broken one — it would pin
// the number to itself. So each case below states a width a user actually gets
// and asserts which layout they get there.
//
// GL-003 §8.7.1 (ratified 2026-07-20) is the governing rule: "a breakpoint that
// gates whether a feature is VISIBLE AT ALL must sit below 800," where 800 is
// the declared macOS launch width. These tests enforce that floor for this
// screen. They do not invent a competing rule.
//
// One caution §8.7.1 also records: the figure **860** appears in this screen's
// own source comment as a SCREENSHOT COMPARISON width and has since been
// repeated as if it were a launch width. It is not. Nothing in `macos/Runner/`
// contains 860, and MainFlutterWindow.swift reuses the nib's frame, so the
// launch width is 800. Asserting against 860 would let a breakpoint anywhere in
// 801-860 pass here and still be invisible to every fresh install — which is
// precisely the 900px failure this file exists to prevent. Assert against 800.
//
// MUTATION-TESTED. Moving the constant must turn something red:
//   * 760 → 799 fails 'table renders at 768' (satisfies §8.7.1's letter, defeats
//     its intent: a default window nudged one point narrower loses the table).
//   * 760 → 700 fails 'cards render at 740' (the table breakpoint collapses
//     into --app-bp-desktop = 720, and the two thresholds stop answering
//     different questions).
//   * A no-op mutant (760 → 761) stays green, and that is deliberate: these
//     tests pin the BAND the breakpoint must live in, not the literal 760. A
//     test asserting `_tableBreakpoint == 760` would pass for whatever value the
//     constant happened to hold and would prove only that the number equals
//     itself.
// All three were run. See the session log.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_discovery_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_discovery_table.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/arp_reader.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/device_type.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_discovery_engine.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_host.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The macOS window's declared default content width, in points — GL-003
/// §8.7.1's "visibility floor".
///
/// NOT a guess and NOT a number chosen because it was convenient to test at: it
/// is read back from `macos/Runner/Base.lproj/MainMenu.xib` by
/// [_declaredMacOsDefaultWidth] below, and the anchor test asserts the two
/// still agree. A previous pass on this screen verified at a width the author
/// picked rather than the width users are actually given, looked straight at
/// the bug, and recorded a pass. Reading the xib is how that does not happen
/// twice.
const double kMacOsDefaultWindowWidth = 800;

/// Parses the `contentRect` width out of the macOS main-window xib.
double _declaredMacOsDefaultWidth() {
  final File xib = File('macos/Runner/Base.lproj/MainMenu.xib');
  if (!xib.existsSync()) {
    fail(
      'macos/Runner/Base.lproj/MainMenu.xib not found. The macOS default '
      'window size is the anchor for the table breakpoint; if this file moved, '
      're-derive the breakpoint against the new declaration rather than '
      'deleting this test.',
    );
  }
  final RegExp re = RegExp(
    r'<rect key="contentRect"[^>]*\bwidth="([0-9.]+)"',
  );
  final Match? m = re.firstMatch(xib.readAsStringSync());
  if (m == null) {
    fail('No contentRect width found in MainMenu.xib.');
  }
  return double.parse(m.group(1)!);
}

class _FakeEngine implements LanDiscoveryEngine {
  _FakeEngine(this._result);

  final DiscoveryResult _result;

  @override
  DiscoveryResult? get lastResult => _result;

  @override
  Stream<DiscoveryProgress> run() async* {
    yield const DiscoveryProgress(DiscoveryPhase.seeding, 0.02);
    yield const DiscoveryProgress(DiscoveryPhase.complete, 1.0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DiscoveryResult _result() => DiscoveryResult(
      hosts: <LanHost>[
        LanHost(
          ip: '10.0.10.5',
          openPorts: <int>{80},
          mac: 'fc:ec:da:01:23:45',
          vendor: 'Ubiquiti',
          deviceType: DeviceType.webServer,
        ),
        LanHost(
          ip: '10.0.10.6',
          openPorts: <int>{22},
          deviceType: DeviceType.unknown,
        ),
      ],
      subnetLabel: '10.0.10.1–10.0.10.254',
      sweptIps: const <String>['10.0.10.5', '10.0.10.6'],
      selfIp: '10.0.10.20',
      gateway: '10.0.10.1',
      arp: const ArpReadResult(available: true),
    );

void main() {
  final MacOuiService oui =
      MacOuiService.fromTable(<String, String>{'FCECDA': 'Ubiquiti'});

  /// Scans at [width] and reports whether the sortable table rendered.
  Future<bool> tableRendersAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: NetworkDiscoveryScreen(
          service: oui,
          engineFactory: () => _FakeEngine(_result()),
          glanceCard: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.tap(find.text('Scan local network'));
    await tester.pumpAndSettle();

    // Sanity: the results actually rendered at this width, so a "no table"
    // verdict means "cards instead", never "nothing at all".
    expect(
      find.text('2 hosts found'),
      findsOneWidget,
      reason: 'results did not render at ${width}pt — the width case is void',
    );
    return tester.any(find.byType(NetworkDiscoveryTable));
  }

  test('the macOS window still declares the 800pt default this file assumes',
      () {
    // Guards the ANCHOR, not the breakpoint. If someone changes the default
    // window size, the breakpoint reasoning must be re-derived rather than
    // silently invalidated.
    expect(
      _declaredMacOsDefaultWidth(),
      kMacOsDefaultWindowWidth,
      reason:
          'MainMenu.xib no longer declares an 800pt content width. The table '
          'breakpoint was chosen to sit below that default; re-derive it.',
    );
  });

  testWidgets(
      'table renders at the declared macOS default window width (800pt)',
      (WidgetTester tester) async {
    // The customer-requested table must be visible on a fresh install, with no
    // saved window frame and no instruction to widen anything.
    expect(
      await tableRendersAt(tester, kMacOsDefaultWindowWidth),
      isTrue,
      reason:
          'a fresh macOS install opens at ${kMacOsDefaultWindowWidth}pt and '
          'must get the table — the feature is otherwise invisible on launch.',
    );
  });

  testWidgets('table renders at 768pt — headroom below the macOS default',
      (WidgetTester tester) async {
    // A breakpoint that merely squeaks under 800 is not a working breakpoint:
    // nudging the default window a few points narrower would drop the table.
    // 768pt is also the long-standing small-window/tablet width, so this is a
    // width users genuinely occupy, not a probe placed to satisfy a mutant.
    expect(
      await tableRendersAt(tester, 768),
      isTrue,
      reason:
          'the table must survive a window narrowed slightly from the macOS '
          'default; a breakpoint in (768, 800] leaves no usable headroom.',
    );
  });

  testWidgets('cards render at 740pt — above desktop padding, below the table',
      (WidgetTester tester) async {
    // 740pt sits between --app-bp-desktop (720) and _tableBreakpoint (760) on
    // purpose: it pins that the two thresholds are DISTINCT. "Is there room for
    // desktop padding" and "is there room for a table to beat a card" are
    // different questions, and collapsing them is what a downward mutation of
    // the table breakpoint does.
    //
    // THIS TEST PINS AN OPEN QUESTION'S CURRENT ANSWER, NOT A SETTLED ONE.
    // GL-003 §8.7.1 explicitly does not decide whether 760 should collapse into
    // 720: the captures that justified 900 → 760 were taken at 800 and 860, so
    // nobody has ever looked at this screen between 720 and 760. If Keith later
    // rules that the table also beats the card at 720, this test SHOULD go red
    // — that is the point. Do not "fix" it by widening the tolerance; change it
    // when the ruling lands, and cite the ruling.
    expect(
      await tableRendersAt(tester, 740),
      isFalse,
      reason:
          'at 740pt the table has not earned its columns yet — this width must '
          'still get cards, or the table breakpoint has collapsed into the '
          'desktop breakpoint.',
    );
  });

  testWidgets('cards render at phone width (320pt)',
      (WidgetTester tester) async {
    expect(await tableRendersAt(tester, 320), isFalse);
  });
}
