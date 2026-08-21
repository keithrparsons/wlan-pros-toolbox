// Field & Trade Reference PRINT PLATES — bundle ↔ catalog ↔ screen integrity.
//
// The plate lookup is deliberately MECHANICAL: a screen's FieldPlateAction
// resolves its PDF as `assets/field-plates/<toolId>.pdf`. That buys simplicity
// at the cost of one failure mode — rename a catalog id, or drop a plate from
// pubspec, and the affordance still compiles and still renders. It only fails
// when a user taps it and gets the viewer's error state. This file closes that
// gap the same way catalog_route_integrity_test.dart closed the route gap.
//
// Guards, all against the REAL bundled files on disk rather than a hand-kept
// list (a list would drift with the thing it is supposed to check):
//   1. every wired screen's toolId has a bundled plate;
//   2. every bundled plate maps to a real, live catalog tool;
//   3. pubspec actually ships the directory;
//   4. plate 14 — the one with no native screen — is a live catalog entry
//      whose route resolves and whose asset path points into the plate bundle.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/widgets/field_plate_action.dart';

/// The thirteen native Field Reference screens that carry a FieldPlateAction.
/// Kept explicit: this list IS the contract, and a screen silently losing its
/// action should fail here rather than quietly stop offering its plate.
const List<String> kWiredPlateToolIds = <String>[
  'enclosure-ratings',
  'hazardous-locations',
  'nec-gotchas',
  'safety-basics',
  'plan-set-literacy',
  'site-access',
  'spectrum',
  'cloud-tool-trust',
  'network-in-scope',
  'facility-spaces',
  'healthcare-vertical',
  'credentials-licenses',
  'led-decoder',
];

/// Plate 14 — the only plate with no native screen behind it, so it is a
/// first-class catalog entry instead of an affordance on someone else's screen.
const String kStandalonePlateToolId = 'throughput-testing-where';

List<ToolEntry> _allTools() =>
    kToolCategories.expand((ToolCategory c) => c.tools).toList();

void main() {
  final Directory plateDir = Directory('assets/field-plates');

  group('field plate bundle integrity', () {
    test('the plate asset directory exists and is not empty', () {
      expect(
        plateDir.existsSync(),
        isTrue,
        reason: 'assets/field-plates/ is missing from the repo',
      );
      expect(plateDir.listSync().whereType<File>(), isNotEmpty);
    });

    test('every wired screen toolId has a bundled plate PDF', () {
      final List<String> missing = <String>[];
      for (final String id in kWiredPlateToolIds) {
        if (!File(fieldPlateAssetFor(id)).existsSync()) missing.add(id);
      }
      expect(
        missing,
        isEmpty,
        reason: 'wired screens with no bundled plate: ${missing.join(', ')}',
      );
    });

    test('the standalone plate is bundled', () {
      expect(
        File(fieldPlateAssetFor(kStandalonePlateToolId)).existsSync(),
        isTrue,
      );
    });

    test('every bundled plate maps to a live catalog tool', () {
      final Set<String> liveIds = _allTools()
          .where((ToolEntry t) => t.isLive)
          .map((ToolEntry t) => t.id)
          .toSet();

      final List<String> orphans = <String>[];
      for (final File f in plateDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.pdf')) continue;
        final String id = f.uri.pathSegments.last.replaceAll('.pdf', '');
        if (!liveIds.contains(id)) orphans.add(id);
      }
      expect(
        orphans,
        isEmpty,
        reason:
            'bundled plates with no live catalog tool of the same id: '
            '${orphans.join(', ')} — the lookup is by id, so these are '
            'unreachable dead weight in the app bundle',
      );
    });

    test('pubspec ships the plate directory', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('- assets/field-plates/'),
        isTrue,
        reason: 'plates on disk but not declared in pubspec assets',
      );
    });
  });

  group('standalone plate 14 wiring', () {
    test('is a live catalog entry whose route resolves', () {
      final ToolEntry entry = _allTools().firstWhere(
        (ToolEntry t) => t.id == kStandalonePlateToolId,
        orElse: () => throw StateError(
          '$kStandalonePlateToolId is not in the catalog',
        ),
      );
      expect(entry.isLive, isTrue);
      expect(AppRouter.routes.containsKey(entry.routeName), isTrue);
    });
  });
}
