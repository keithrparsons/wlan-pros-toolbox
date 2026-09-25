// Every catalog tool ships with its own per-tool icon.
//
// Keith, 2026-09-25: "make sure ALL tools in the toolbox have a unique icon
// and not just the generic lightning bolt before we push the next update."
// A tool with no assets/tool-icons/<id>.svg falls back to the generic glyph in
// ToolRow, which is what Keith saw as the lightning bolt. On that date 19 of
// 186 tools on main had no icon, and nothing failed: the fallback is graceful
// by design (tool_assets.dart), so a missing icon was invisible to every test.
// This guard makes a missing icon a red build instead of a thing someone has
// to remember.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

void main() {
  test('every catalog tool has its own icon in assets/tool-icons/', () {
    final List<String> missing = <String>[
      for (final ToolCategory c in kToolCategories)
        for (final ToolEntry t in c.tools)
          if (!File('assets/tool-icons/${t.id}.svg').existsSync()) t.id,
    ];
    expect(missing, isEmpty,
        reason: 'these tools would render the generic fallback glyph; draw '
            'assets/tool-icons/<id>.svg to the GL-003 §8.6.1 spec');
  });
}
