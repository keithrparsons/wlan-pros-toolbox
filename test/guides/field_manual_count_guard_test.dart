// The field manual states its own tool coverage in its header line, and that
// number is prose: nothing recomputes it, so it drifts silently every time a
// tool lands. It read 176 while the catalog carried 183.
//
// `assets/help/tool_help.json` already has exactly this guard and it has caught
// the same drift twice (2026-07, name 140 vs assertion 178; 2026-08, name 179
// vs assertion 181). The field manual had no equivalent, which is the whole
// reason it went stale and the help file did not.
//
// Keith, 2026-09-15: the Field Guide and the help files must always match the
// shipping software. This is the mechanical half of that.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('field manual header tool count == live tools in the catalog', () async {
    final String md =
        await rootBundle.loadString('assets/guides/field-manual.md');

    final RegExpMatch? m = RegExp(r'covers (\d+) tools').firstMatch(md);
    expect(m, isNotNull,
        reason: 'the field manual header must state "covers N tools"; if the '
            'wording changes, change this guard with it rather than deleting it');

    final int stated = int.parse(m!.group(1)!);
    final int live = kToolCategories
        .expand((ToolCategory c) => c.tools)
        .where((ToolEntry t) => t.isLive)
        .length;

    expect(stated, live,
        reason: 'assets/guides/field-manual.md says it covers $stated tools; '
            'the catalog carries $live live. Update the manual header AND add '
            'the new tools to the manual body, per the standing help-file rule: '
            'per-tool help alone is not enough, the field manual must keep pace.');
  });

  test('both guides carry the app-version placeholder, not a frozen number',
      () async {
    for (final String path in <String>[
      'assets/guides/field-manual.md',
      'assets/guides/user-guide.md',
    ]) {
      final String md = await rootBundle.loadString(path);
      expect(md, contains('{{app_version}}'),
          reason: '$path must use the {{app_version}} placeholder so the '
              'version line follows the build. A hardcoded version is the '
              'defect this placeholder exists to prevent.');
      expect(RegExp(r'app v\d+\.\d+\.\d+').hasMatch(md), isFalse,
          reason: '$path carries a hardcoded "app vX.Y.Z" string, which will '
              'be wrong at the next release.');
    }
  });
}
