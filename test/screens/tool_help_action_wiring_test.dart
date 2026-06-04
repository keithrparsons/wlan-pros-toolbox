// Verifies the per-tool help sweep: the shared ToolHelpAction (Icons.help_outline
// with the "Help" tooltip) is actually present in the AppBar of the
// non-calculator tool screens it was wired onto — reference tables, networking
// tools, command sheets, the dbm/Watt converter, the shared PDF reference
// viewer (keyed per card id), and the tappable checklists (keyed per checklist
// id). The calculator screens were wired in Phase 1 and are covered elsewhere;
// these are the ~53 remaining screens from the sweep.
//
// Each screen resolves its own catalog id via helpForId(); since all 86 ids
// have entries, a correctly-wired screen shows exactly one help button. The
// real bundled help store is loaded (ensureLoaded) so the lookups resolve the
// same entries the app sees — this also proves the toolIds passed in match
// real entries (a typo'd id would render no button and fail the count).
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
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_channels_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wpa_security_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_action.dart';

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

  // A correctly-wired screen shows exactly one ToolHelpAction, and that action
  // resolves to a single Icons.help_outline IconButton with the "Help" tooltip.
  void expectHelpPresent(WidgetTester tester) {
    expect(find.byType(ToolHelpAction), findsOneWidget);
    expect(
      find.widgetWithIcon(IconButton, Icons.help_outline),
      findsOneWidget,
    );
    expect(find.byTooltip('Help'), findsOneWidget);
  }

  group('help action wired onto reference screens', () {
    testWidgets('Wi-Fi channels', (t) async {
      await pump(t, const WifiChannelsScreen());
      expectHelpPresent(t);
    });
    testWidgets('MCS index', (t) async {
      await pump(t, const McsIndexScreen());
      expectHelpPresent(t);
    });
    testWidgets('WPA security', (t) async {
      await pump(t, const WpaSecurityScreen());
      expectHelpPresent(t);
    });
  });

  group('help action wired onto command sheets', () {
    testWidgets('Network CLI commands', (t) async {
      await pump(t, const CliCommandsScreen());
      expectHelpPresent(t);
    });
    testWidgets('Linux / WLAN commands', (t) async {
      await pump(t, const LinuxWlanCommandsScreen());
      expectHelpPresent(t);
    });
    testWidgets('Wireshark 802.11 filters', (t) async {
      await pump(t, const WiresharkFiltersScreen());
      expectHelpPresent(t);
    });
  });

  group('help action wired onto the converter', () {
    testWidgets('dBm / Watt converter (help is the only action)', (t) async {
      await pump(t, const DbmWattConverterScreen());
      expectHelpPresent(t);
    });
  });

  group('shared PDF viewer keys help to the SPECIFIC card id', () {
    testWidgets('Top 20 checklist card → top-20-checklist help', (t) async {
      await pump(
        t,
        const PdfReferenceScreen(
          title: 'Top 20 Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/top-20-checklist.pdf',
          toolId: 'top-20-checklist',
        ),
      );
      expectHelpPresent(t);
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
      expectHelpPresent(t);
    });
  });

  group('checklist screen keys help to the SPECIFIC checklist id', () {
    testWidgets('checklist-ap-install shows help', (t) async {
      await pump(
        t,
        const ChecklistScreen(
          checklist: Checklist.smokeTest,
          toolId: 'checklist-ap-install',
        ),
      );
      expectHelpPresent(t);
    });

    testWidgets('checklist with null toolId shows NO help action', (t) async {
      await pump(
        t,
        const ChecklistScreen(checklist: Checklist.smokeTest),
      );
      // The screen builds with actions: null when toolId is null, so neither the
      // action widget nor the help button is in the tree.
      expect(find.byType(ToolHelpAction), findsNothing);
      expect(
        find.widgetWithIcon(IconButton, Icons.help_outline),
        findsNothing,
      );
    });
  });
}
