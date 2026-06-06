// Dual Orbs on WLAN Pi — wiring + screen tests (v1.1).
//
// Guards:
//   (a) the catalog/route/subgroup wiring for the new `dual-orb-wlanpi` id,
//   (b) the screen renders the approved-preview content (title, intro, the
//       accurate caveat box, the install steps + commands, the download button,
//       the cloned-image + reconfigure notes, the useful commands, the link-outs,
//       the Ferney Munoz credit, and the help footer),
//   (c) the download button calls the share seam with the REAL `.deb` filename
//       and the Debian MIME type (a fake share fn is injected so the test never
//       touches a platform channel),
//   (d) the screen renders in BOTH light and dark themes,
//   (e) a real help entry exists for the id so the §8.16.1 footer is not faked.

import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/pdf_download.dart' show ShareOrigin;
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/guides/dual_orb_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_help_footer.dart';

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'dual-orb-wlanpi');

/// Records the arguments passed to the share seam, returning success. The screen
/// now hands the seam already-decoded BYTES (not an asset path).
class _FakeShare {
  List<int>? bytes;
  String? filename;
  String? mimeType;
  int calls = 0;

  Future<void> call({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? title,
    ShareOrigin? shareOrigin,
  }) async {
    calls++;
    this.bytes = bytes;
    this.filename = filename;
    this.mimeType = mimeType;
  }
}

Widget _harness({AssetShareFn? shareFn, ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: shareFn == null
          ? const DualOrbScreen()
          : DualOrbScreen(shareFn: shareFn),
    );

void main() {
  setUpAll(() async {
    await ToolHelpLoader.ensureLoaded();
  });

  group('catalog + route wiring', () {
    test('the tool id resolves to a live ToolEntry in Quick Reference', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Dual Orbs on WLAN Pi');
      expect(entry.routeName, '/tools/dual-orb-wlanpi');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Guides');
    });

    test('the route resolves to a registered builder', () {
      expect(AppRouter.routes.containsKey('/tools/dual-orb-wlanpi'), isTrue);
    });

    test('"Guides" is a known subgroup header for quick-reference', () {
      expect(
        kCategorySubgroupOrder['quick-reference']!.contains('Guides'),
        isTrue,
      );
    });

    test('the entry sits in the quick-reference category', () {
      final ToolCategory qr = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      expect(qr.tools.any((ToolEntry t) => t.id == 'dual-orb-wlanpi'), isTrue);
    });

    test('the tool has search keywords (incl. orb)', () {
      final List<String>? kw = kToolKeywords['dual-orb-wlanpi'];
      expect(kw, isNotNull);
      expect(kw, contains('orb'));
    });

    test('a real help entry exists so the footer is not faked', () {
      final ToolHelp? help = helpForId('dual-orb-wlanpi');
      expect(help, isNotNull);
      expect(help!.name, 'Dual Orbs on WLAN Pi');
    });
  });

  group('screen render', () {
    Future<void> pump(WidgetTester tester, {ThemeData? theme}) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness(theme: theme));
      await tester.pumpAndSettle();
    }

    testWidgets('renders the title, intro, and the accurate caveat',
        (tester) async {
      await pump(tester);
      expect(find.text('Dual Orbs on WLAN Pi'), findsWidgets);
      expect(find.text('WHAT THIS INSTALLS'), findsOneWidget);
      // The accurate, GL-005 caveat language.
      expect(
        find.textContaining('free, open-source Orb sensor'),
        findsOneWidget,
      );
      // "up to 5 devices" appears in BOTH the caveat and the orb.net link
      // subtitle — both are correct, so assert it is present (one-or-more).
      expect(find.textContaining('up to 5 devices'), findsWidgets);
    });

    testWidgets('renders the install steps and their commands', (tester) async {
      await pump(tester);
      expect(find.text('Install'), findsOneWidget);
      expect(
        find.textContaining('sudo apt install ./wlanpi-dual-orb_1.1.3_all.deb'),
        findsWidgets,
      );
      expect(find.textContaining('sudo reboot'), findsWidgets);
      expect(find.textContaining('scp wlanpi-dual-orb_1.1.3_all.deb'),
          findsWidgets);
    });

    testWidgets('renders the reset-identity and reconfigure commands',
        (tester) async {
      await pump(tester);
      expect(find.textContaining('sudo orb-reset-identity'), findsWidgets);
      expect(find.textContaining('sudo orb-wifi-configure'), findsWidgets);
    });

    testWidgets('renders the download button, links, credit, and help footer',
        (tester) async {
      await pump(tester);
      expect(find.text('Download wlanpi-dual-orb.deb'), findsOneWidget);
      expect(find.textContaining('orb.net'), findsWidgets);
      expect(find.text('WLAN Pi project'), findsOneWidget);
      expect(find.textContaining('Ferney Munoz'), findsWidgets);
      expect(find.byType(ToolHelpFooter), findsOneWidget);
      expect(find.text('About this tool'), findsOneWidget);
    });

    testWidgets('renders in the light theme without throwing', (tester) async {
      await pump(tester, theme: AppTheme.light());
      expect(find.text('Download wlanpi-dual-orb.deb'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('download action', () {
    testWidgets(
        'loads + decodes the base64 asset and calls the share seam with the '
        'real .deb BYTES, filename, and MIME type', (tester) async {
      final _FakeShare fake = _FakeShare();
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness(shareFn: fake.call));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Download wlanpi-dual-orb.deb'));
      await tester.pumpAndSettle();

      expect(fake.calls, 1);
      expect(fake.filename, 'wlanpi-dual-orb_1.1.3_all.deb');
      expect(fake.mimeType, 'application/vnd.debian.binary-package');
      // The screen loaded the real `.b64` asset and decoded it: the shared bytes
      // are the genuine Debian package, which begins with the `ar` archive magic
      // `!<arch>\n`. (Proves the runtime base64.decode path, not just the wiring.)
      final List<int> shared = fake.bytes!;
      expect(shared, isNotEmpty);
      expect(utf8.decode(shared.sublist(0, 8)), '!<arch>\n');
    });
  });
}
