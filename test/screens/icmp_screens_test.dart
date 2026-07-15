// Widget tests for the two ICMP-foundation screens. These verify the
// platform-gated UI states render WITHOUT a device or the dart_ping package —
// the screens take an injected IcmpService with a platform override and a fake
// backend, so the honest per-platform copy is asserted directly.
//
// Not covered (correctly): a live ICMP run. The brief forbids device-dependent
// tests; the streaming/sequencing logic itself is covered in
// test/services/icmp_service_test.dart against the same fake backend.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/icmp_ping_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/mobile_traceroute_screen.dart';
import 'package:wlan_pros_toolbox/services/network/icmp_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Fake backend that never opens a socket; emits nothing. The widget tests
/// here exercise idle/unavailable states, not a run, so an empty stream is fine.
class _SilentBackend implements IcmpBackend {
  const _SilentBackend();

  @override
  Stream<IcmpReply> echo({
    required String host,
    required int count,
    required Duration interval,
    required Duration timeout,
    int? ttl,
    Future<void>? cancel,
  }) =>
      const Stream<IcmpReply>.empty();
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.dark(), home: child);

void main() {
  group('ICMP Ping screen', () {
    testWidgets('Android: shows the ICMP form, labelled as true ICMP',
        (tester) async {
      await tester.pumpWidget(_wrap(IcmpPingScreen(
        service: IcmpService(
          platformOverride: 'android',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(find.text('Ping (ICMP)'), findsOneWidget); // app bar (renamed)
      expect(find.text('Ping'), findsOneWidget); // action button
      expect(
        find.textContaining('true ICMP, not a TCP probe'),
        findsOneWidget,
      );
    });

    testWidgets('desktop: shows the sandboxed-desktop card pointing at TCP Ping',
        (tester) async {
      await tester.pumpWidget(_wrap(IcmpPingScreen(
        service: IcmpService(
          platformOverride: 'macos',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(find.text('ICMP ping runs on mobile'), findsOneWidget);
      expect(find.text('Open TCP Ping'), findsOneWidget);
      // The form action button must NOT be present on the sandboxed state.
      expect(find.widgetWithText(FilledButton, 'Ping'), findsNothing);
    });

    // Honesty regression: the Windows/Linux reason must NOT claim a false
    // technical impossibility. Windows ICMP echo (IcmpSendEcho) and Linux user
    // `ping` need no raw socket — the feature is just not wired into these desktop
    // builds. The card must say that plainly and point at TCP Ping.
    testWidgets('Windows: honest "not wired yet", never a false raw-socket claim',
        (tester) async {
      await tester.pumpWidget(_wrap(IcmpPingScreen(
        service: IcmpService(
          platformOverride: 'windows',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(
        find.textContaining('ICMP ping is not wired into this Windows build yet'),
        findsOneWidget,
      );
      expect(find.text('Open TCP Ping'), findsOneWidget);
      // Must NOT assert a false impossibility or blame another platform.
      expect(find.textContaining('raw'), findsNothing);
      expect(find.textContaining('socket'), findsNothing);
      expect(find.textContaining('Sandbox'), findsNothing);
      expect(find.textContaining('macOS'), findsNothing);
    });

    testWidgets('Linux: honest "not wired yet", never a false raw-socket claim',
        (tester) async {
      await tester.pumpWidget(_wrap(IcmpPingScreen(
        service: IcmpService(
          platformOverride: 'linux',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(
        find.textContaining('ICMP ping is not wired into this Linux build yet'),
        findsOneWidget,
      );
      expect(find.text('Open TCP Ping'), findsOneWidget);
      expect(find.textContaining('raw'), findsNothing);
      expect(find.textContaining('elevated privileges'), findsNothing);
    });

    testWidgets('blank host shows inline validation, no crash', (tester) async {
      await tester.pumpWidget(_wrap(IcmpPingScreen(
        service: IcmpService(
          platformOverride: 'android',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      await tester.tap(find.widgetWithText(FilledButton, 'Ping'));
      await tester.pump();
      expect(find.text('Enter a host or IP.'), findsOneWidget);
    });
  });

  group('Mobile Traceroute screen', () {
    testWidgets('Android: shows the TTL-walk form', (tester) async {
      await tester.pumpWidget(_wrap(MobileTracerouteScreen(
        service: IcmpService(
          platformOverride: 'android',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(find.text('Traceroute (Mobile)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Trace'), findsOneWidget);
      expect(
        find.textContaining('ICMP TTL-walk, not the system'),
        findsOneWidget,
      );
    });

    testWidgets('iOS: honest "not available on iOS" card, no form',
        (tester) async {
      await tester.pumpWidget(_wrap(MobileTracerouteScreen(
        service: IcmpService(
          platformOverride: 'ios',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(find.text('Traceroute is not available on iOS'), findsOneWidget);
      expect(
        find.textContaining('does not surface the Time-Exceeded'),
        findsOneWidget,
      );
      expect(find.text('Open ICMP Ping'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Trace'), findsNothing);
    });

    testWidgets('desktop: points at the system Traceroute tool',
        (tester) async {
      await tester.pumpWidget(_wrap(MobileTracerouteScreen(
        service: IcmpService(
          platformOverride: 'macos',
          isWebOverride: false,
          backend: const _SilentBackend(),
        ),
      )));
      expect(
          find.text('Use the system Traceroute on desktop'), findsOneWidget);
      expect(find.text('Open Traceroute'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Trace'), findsNothing);
    });
  });
}
