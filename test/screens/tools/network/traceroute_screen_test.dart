// Widget tests for the Traceroute (System) screen's three load-bearing states:
//  - not launchable (this build cannot spawn the system traceroute): the
//    upfront guidance renders and there is no Trace control to mislead the
//    user. Rendered through NetworkUnavailableView (the same surface the web
//    state uses), so an expected platform limit reads as "not available", not
//    an error.
//  - launchable + a real run: hops render and no unavailable card appears.
//  - launchable but the run returns an unavailable verdict: the post-run
//    unavailable card renders (this IS a genuine failure).
//
// The service is faked so no Process is spawned and no network is touched.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/traceroute_screen.dart';
import 'package:wlan_pros_toolbox/services/network/traceroute_service.dart';

/// Test double for [TracerouteService] that never touches Process or network.
/// [launchable] drives the upfront capability probe; [hops] and [result] drive
/// what a Trace run streams back.
class _FakeTracerouteService extends TracerouteService {
  _FakeTracerouteService({
    required this.launchable,
    this.hops = const <TracerouteHop>[],
    this.result = const TracerouteComplete(reachedTarget: true),
  }) : super(platformOverride: 'macos');

  final bool launchable;
  final List<TracerouteHop> hops;
  final TracerouteResult result;

  @override
  Future<bool> isLaunchable() async => launchable;

  @override
  Stream<TracerouteEvent> trace({
    required String host,
    int maxHops = 30,
    Future<void>? cancel,
  }) async* {
    for (final TracerouteHop hop in hops) {
      yield TracerouteEvent.hop(hop);
    }
    yield TracerouteEvent.done(result);
  }
}

void main() {
  testWidgets('not launchable: shows upfront guidance, no Trace button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TracerouteScreen(
          service: _FakeTracerouteService(launchable: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Traceroute is not available in this build'),
      findsOneWidget,
    );
    expect(find.textContaining('Ping (TCP)'), findsOneWidget);
    expect(find.text('Trace'), findsNothing);
  });

  testWidgets('launchable: runs and renders hops with no unavailable card', (
    WidgetTester tester,
  ) async {
    final List<TracerouteHop> hops = <TracerouteHop>[
      const TracerouteHop(ttl: 1, ip: '10.0.0.1', rttsMs: <double>[1.2]),
      const TracerouteHop(ttl: 2, ip: '203.0.113.5', rttsMs: <double>[12.4]),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TracerouteScreen(
          service: _FakeTracerouteService(launchable: true, hops: hops),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trace'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('Trace'));
    await tester.pumpAndSettle();

    // Each hop address can surface in more than one descendant (the selectable
    // address cell and its enclosing row), so assert presence, not a single
    // match. The point of this test is that hops render and no unavailable
    // card is shown.
    expect(find.textContaining('10.0.0.1'), findsWidgets);
    expect(find.textContaining('203.0.113.5'), findsWidgets);
    expect(find.text('Traceroute unavailable'), findsNothing);
  });

  testWidgets(
      'launchable but run returns TracerouteUnavailable: shows unavailable card',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TracerouteScreen(
          service: _FakeTracerouteService(
            launchable: true,
            result: const TracerouteUnavailable(
              reason: TracerouteUnavailableReason.binaryUnavailable,
              detail: 'blocked',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('Trace'));
    await tester.pumpAndSettle();

    expect(find.text('Traceroute unavailable'), findsOneWidget);
    expect(find.textContaining('blocked'), findsOneWidget);
  });
}
