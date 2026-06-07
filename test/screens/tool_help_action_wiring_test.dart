// Verifies the §8.16.1 help-footer migration: the per-tool help affordance now
// lives in a shared ToolHelpFooter at the END of each tool screen's scroll body
// (NOT as an Icons.help_outline IconButton in the AppBar). This sweep covers the
// non-calculator tool screens that carried the old AppBar ToolHelpAction —
// reference tables, networking tools, command sheets, the dbm/Watt converter,
// the shared PDF reference viewer (keyed per card id), and the tappable
// checklists (keyed per checklist id). The calculator screens were migrated in
// the same pass and are covered elsewhere; these are the remaining screens.
//
// Each screen resolves its own catalog id via helpForId(); since all ids have
// entries, a correctly-migrated screen shows exactly one ToolHelpFooter and its
// "About this tool" button, and NO "Help"-tooltip AppBar action. The real
// bundled help store is loaded (ensureLoaded) so the lookups resolve the same
// entries the app sees — a typo'd id would render no footer and fail the find.
//
// net_quality and wifi_info are intentionally NOT covered here: they keep their
// own bespoke help affordance and were deliberately left untouched by the sweep.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/dbm_watt_converter.dart';
import 'package:wlan_pros_toolbox/screens/tools/checklists/checklist_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/cli_commands_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/linux_wlan_commands_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/command/wireshark_filters_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mcs_index_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wpa_security_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

void main() {
  // Load the real bundled help store once so helpForId() resolves entries.
  setUpAll(() async {
    await ToolHelpLoader.ensureLoaded();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: screen),
    );
    await tester.pump();
  }

  // A correctly-migrated screen shows exactly one ToolHelpFooter (the body
  // "About this tool" row), and NO "Help"-tooltip AppBar action — the help glyph
  // is gone from the AppBar (§8.16.1). The footer itself carries an
  // Icons.help_outline glyph and the "About this tool" label.
  void expectFooterPresentNoAppBarHelp(WidgetTester tester) {
    expect(find.byType(ToolHelpFooter), findsOneWidget);
    expect(find.text('About this tool'), findsOneWidget);
    // The retired AppBar help affordance carried a "Help" tooltip — it must be
    // gone now that help lives in the footer.
    expect(find.byTooltip('Help'), findsNothing);
  }

  group('help footer wired onto reference screens', () {
    testWidgets('Channel Map', (t) async {
      await pump(t, const ChannelMapScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
    testWidgets('MCS index', (t) async {
      await pump(t, const McsIndexScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
    testWidgets('WPA security', (t) async {
      await pump(t, const WpaSecurityScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
  });

  group('help footer wired onto command sheets', () {
    testWidgets('Network CLI commands', (t) async {
      await pump(t, const CliCommandsScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
    testWidgets('Linux / WLAN commands', (t) async {
      await pump(t, const LinuxWlanCommandsScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
    testWidgets('Wireshark 802.11 filters', (t) async {
      await pump(t, const WiresharkFiltersScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
  });

  group('help footer wired onto the converter', () {
    testWidgets('dBm / Watt converter (footer is the only help affordance)', (
      t,
    ) async {
      await pump(t, const DbmWattConverterScreen());
      expectFooterPresentNoAppBarHelp(t);
    });
  });

  group('shared PDF viewer keys the footer to the SPECIFIC card id', () {
    testWidgets('Top 20 checklist card → top-20-checklist help', (t) async {
      await pump(
        t,
        const PdfReferenceScreen(
          title: 'Top 20 Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/top-20-checklist.pdf',
          toolId: 'top-20-checklist',
        ),
      );
      expectFooterPresentNoAppBarHelp(t);
    });
    testWidgets('MCS index CARD → mcs-index-card help (distinct id)', (t) async {
      await pump(
        t,
        const PdfReferenceScreen(
          title: 'Modulation and Coding Schemes (MCS Index)',
          assetPath: 'assets/reference-cards/mcs-index-card.pdf',
          toolId: 'mcs-index-card',
        ),
      );
      expectFooterPresentNoAppBarHelp(t);
    });
  });

  group('checklist screen keys the footer to the SPECIFIC checklist id', () {
    testWidgets('checklist-ap-install shows the footer', (t) async {
      await pump(
        t,
        const ChecklistScreen(
          checklist: Checklist.smokeTest,
          toolId: 'checklist-ap-install',
        ),
      );
      expectFooterPresentNoAppBarHelp(t);
    });

    testWidgets('checklist with null toolId shows NO help footer', (t) async {
      await pump(
        t,
        const ChecklistScreen(checklist: Checklist.smokeTest),
      );
      // A null toolId means the screen appends no ToolHelpFooter at all, and the
      // AppBar never carried a help action.
      expect(find.byType(ToolHelpFooter), findsNothing);
      expect(find.text('About this tool'), findsNothing);
      expect(find.byTooltip('Help'), findsNothing);
    });
  });
}
