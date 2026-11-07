// One big-screen breakpoint (Keith, 2026-11-07, iPhone Duo).
//
// Every screen picks its wide layout (desktop edge padding, side-by-side
// panels) from AppSpacing.wideLayoutMinWidth. Before the Duo, ~250 screens
// copied the literal 720, so the Duo's open screen (669pt upright) got the
// phone layout on every tool even after the home grid moved. This guard stops
// a literal from coming back.
//
// network_discovery_screen.dart keeps its own documented thresholds.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _literalWidthBreakpoint = RegExp(
  r'(maxWidth|width)\s*(>=|<)\s*720\b',
);

void main() {
  test('no screen hard-codes the old 720 big-screen width', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('network_discovery_screen.dart')) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (_literalWidthBreakpoint.hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
