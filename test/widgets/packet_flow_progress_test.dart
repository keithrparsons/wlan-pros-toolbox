// Tests for the packet-flow loading widget — the presentation layer over the
// connection-test phases (Felix, 2026-06-13). Covers the component contract
// (caption + percentage always rendered as the non-color carrier), the
// stage→lit-node mapping, the live-region announcement, and the reduced-motion
// fallback (the loop is stopped and the dot parks).

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/packet_flow_progress.dart';

Widget _host({
  required PacketFlowStage stage,
  required double fraction,
  String caption = 'Testing your internet speed…',
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: PacketFlowProgress(
          caption: caption,
          fraction: fraction,
          stage: stage,
        ),
      ),
    ),
  );
}

void main() {
  group('PacketFlowStage', () {
    test('lit-node count maps to stage', () {
      expect(PacketFlowStage.none.litNodes, 0);
      expect(PacketFlowStage.you.litNodes, 1);
      expect(PacketFlowStage.ap.litNodes, 2);
      expect(PacketFlowStage.all.litNodes, 3);
    });

    test('active segment is 0 for You/none and 1 for AP/all', () {
      expect(PacketFlowStage.none.activeSegment, 0);
      expect(PacketFlowStage.you.activeSegment, 0);
      expect(PacketFlowStage.ap.activeSegment, 1);
      expect(PacketFlowStage.all.activeSegment, 1);
    });
  });

  testWidgets('renders the caption and percentage as the non-color carrier',
      (tester) async {
    await tester.pumpWidget(
      _host(stage: PacketFlowStage.you, fraction: 0.42),
    );
    expect(find.text('Testing your internet speed…'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    // The painted path is present.
    expect(find.byType(CustomPaint), findsWidgets);
    // Stop the repeating controller before the test tears down.
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('exposes a progress live region for screen readers',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(stage: PacketFlowStage.ap, fraction: 0.7),
    );
    // The live region carries the phase + percentage.
    expect(
      find.bySemanticsLabel(
        RegExp('Testing your internet speed…, 70 percent complete'),
      ),
      findsOneWidget,
    );
    handle.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('reduced motion: no ticking controller drives the frame',
      (tester) async {
    await tester.pumpWidget(
      _host(
        stage: PacketFlowStage.you,
        fraction: 0.3,
        disableAnimations: true,
      ),
    );
    // With reduced motion on, the widget settles (no perpetual animation), so a
    // pumpAndSettle returns rather than timing out on a repeating controller.
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsOneWidget);
    expect(
      SchedulerBinding.instance.hasScheduledFrame,
      isFalse,
      reason: 'reduced motion must not leave a repeating animation scheduled',
    );
  });

  testWidgets('complete stage stops the loop and parks the path',
      (tester) async {
    await tester.pumpWidget(
      _host(stage: PacketFlowStage.all, fraction: 1.0),
    );
    // All three nodes lit + complete → the loop is stopped, so the tree settles.
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
  });
}
