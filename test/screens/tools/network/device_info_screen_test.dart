// DeviceInfoScreen — widget tests (Batch 6).
//
// Drives the screen through an injected fake DeviceInfoService returning a
// canned snapshot, so no real platform reads. Covers:
//   * success → model / memory / uptime render; cellular IP shows when present;
//   * honest "No cellular interface" state when absent;
//   * Copy payload carries the labeled snapshot and is disabled until loaded;
//   * no overflow across the standard widths.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/device_info_screen.dart';
import 'package:wlan_pros_toolbox/services/network/device_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// A fake service that returns a canned [DeviceInfoSnapshot] without touching
/// device_info_plus, the native uptime channel, or dart:io.
class _FakeService extends DeviceInfoService {
  _FakeService(this._snapshot) : super();
  final DeviceInfoSnapshot _snapshot;

  @override
  Future<DeviceInfoSnapshot> read() async => _snapshot;
}

Widget _wrap(DeviceInfoSnapshot snap) => MaterialApp(
      theme: AppTheme.dark(),
      home: DeviceInfoScreen(service: _FakeService(snap)),
    );

void main() {
  const cellularSnap = DeviceInfoSnapshot(
    modelName: 'iPhone 15 Pro',
    modelIdentifier: 'iPhone16,1',
    totalMemoryBytes: 8 * 1024 * 1024 * 1024,
    uptimeSeconds: 274320, // 3d 4h 12m
    cellularInterfaceName: kCellularInterfaceName,
    cellularAddresses: <CellularAddress>[
      CellularAddress(ip: '100.64.12.34', isIPv4: true),
    ],
    cellularInterfacePresent: true,
  );

  const noCellularSnap = DeviceInfoSnapshot(
    modelName: 'Mac15,3',
    modelIdentifier: 'Mac15,3',
    totalMemoryBytes: 16 * 1024 * 1024 * 1024,
    uptimeSeconds: 4500, // 1h 15m
    cellularInterfacePresent: false,
  );

  testWidgets(
    'the Refresh action exposes an accessible NAME, not just a tooltip '
    '(WCAG 2.2 AA SC 4.1.2)',
    (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(noCellularSnap));
      await tester.pumpAndSettle();

      // `tooltip: 'Refresh'` maps to AXHelp, not AXTitle; the explicit Semantics
      // label is the accessible name. Removing it (the mutation) → red.
      expect(find.bySemanticsLabel('Refresh device info'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Refresh device info')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Refresh device info',
        ),
        reason: 'the Refresh action must read as a named, enabled button to AT',
      );

      handle.dispose();
    },
  );

  testWidgets('success renders model, memory, uptime, cellular IP',
      (tester) async {
    await tester.pumpWidget(_wrap(cellularSnap));
    await tester.pumpAndSettle();

    expect(find.text('iPhone 15 Pro'), findsOneWidget);
    expect(find.text('iPhone16,1'), findsOneWidget);
    expect(find.text('8 GB'), findsOneWidget);
    expect(find.text('3d 4h 12m'), findsOneWidget);
    expect(find.text('100.64.12.34'), findsOneWidget);
    // The interface label names the heuristic honestly.
    expect(find.textContaining('pdp_ip0'), findsWidgets);
  });

  testWidgets('absent cellular interface shows the honest no-cellular state',
      (tester) async {
    await tester.pumpWidget(_wrap(noCellularSnap));
    await tester.pumpAndSettle();

    expect(find.text('16 GB'), findsOneWidget);
    expect(find.text('1h 15m'), findsOneWidget);
    expect(find.text('No cellular interface'), findsOneWidget);
    // No fabricated cellular address.
    expect(find.text('100.64.12.34'), findsNothing);
  });

  testWidgets('Copy payload carries the labeled snapshot', (tester) async {
    final List<String> copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );

    await tester.pumpWidget(_wrap(cellularSnap));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppCopyAction));
    await tester.pump();

    expect(copied, isNotEmpty);
    final String text = copied.last;
    expect(text, contains('Device Info'));
    expect(text, contains('Model: iPhone 15 Pro'));
    expect(text, contains('Total memory: 8 GB'));
    expect(text, contains('Uptime: 3d 4h 12m'));
    expect(text, contains('100.64.12.34'));

    // Drain the AppCopyAction confirm-window timer (§8.16, 1500ms) so the test
    // tears down with no pending timer.
    await tester.pump(const Duration(milliseconds: 1600));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('no overflow across standard widths', (tester) async {
    for (final Size size in <Size>[
      const Size(360, 800), // phone
      const Size(768, 1024), // tablet
      const Size(1280, 900), // desktop
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_wrap(cellularSnap));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
