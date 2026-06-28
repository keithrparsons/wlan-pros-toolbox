// Registration + asset integrity for the two Ham Radio PDF reference cards
// (feat/ham-pdf-reference-cards, 2026-06-28).
//
// These two cards reuse the shared PdfReferenceScreen / pdfx viewer exactly like
// the laminated Wi-Fi cards, but live in the Quick Reference "Ham Radio"
// subgroup beside the in-app band references. This test pins the contract:
//   1. Both cards are in the quick-reference catalog with the agreed id, title,
//      route, live flag, and the "Ham Radio" subgroup.
//   2. Each route resolves to a registered builder (PdfReferenceScreen).
//   3. Both bundled PDF asset files are present on disk under the declared
//      assets/reference-cards/ directory.
//   4. pubspec declares the assets/reference-cards/ directory that carries them.
//   5. Each card has a help entry in assets/help/tool_help.json.
//
// Native PDF DECODE/RENDER (PDFKit) is proven separately on a real macOS device
// by integration_test/pdf_render_test.dart — that engine is a no-op in the
// headless flutter_test host, so it cannot be asserted here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';

void main() {
  // id → title contract for the two Ham Radio PDF cards. A rename here is a
  // deliberate breaking change, not an accident.
  const Map<String, String> hamPdfCards = <String, String>{
    'general-license-frequency-chart': 'General License Frequency Chart',
    'ham-radio-general-exam-study-notes': 'Ham Radio General Exam Study Notes',
  };

  group('Ham Radio PDF reference cards', () {
    test('both cards live in quick-reference Ham Radio subgroup', () {
      final ToolCategory quickRef = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'quick-reference',
      );
      final Map<String, ToolEntry> byId = <String, ToolEntry>{
        for (final ToolEntry t in quickRef.tools) t.id: t,
      };

      hamPdfCards.forEach((String id, String title) {
        expect(byId.containsKey(id), isTrue,
            reason: 'missing Ham PDF card "$id" in quick-reference');
        final ToolEntry t = byId[id]!;
        expect(t.title, title, reason: 'title mismatch for "$id"');
        expect(t.isLive, isTrue, reason: '"$id" must be live');
        expect(t.routeName, '/tools/$id',
            reason: 'route convention /tools/<id> for "$id"');
        expect(t.subgroup, 'Ham Radio',
            reason: '"$id" must sit in the Ham Radio subgroup');
      });
    });

    test('each card route resolves to a registered builder', () {
      for (final String id in hamPdfCards.keys) {
        expect(AppRouter.routes.containsKey('/tools/$id'), isTrue,
            reason: 'no registered route for Ham PDF card "$id"');
      }
    });

    test('both bundled PDF assets are present on disk', () {
      for (final String id in hamPdfCards.keys) {
        final File pdf = File('assets/reference-cards/$id.pdf');
        expect(pdf.existsSync(), isTrue,
            reason: 'bundled PDF missing: ${pdf.path}');
        expect(pdf.lengthSync(), greaterThan(0),
            reason: 'bundled PDF is empty: ${pdf.path}');
      }
    });

    test('pubspec declares the assets/reference-cards/ directory', () {
      final File pubspec = File('pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);
      expect(pubspec.readAsStringSync(), contains('assets/reference-cards/'),
          reason: 'reference-cards directory must be a declared asset bundle');
    });

    test('each card has a help entry in tool_help.json', () {
      final File help = File('assets/help/tool_help.json');
      expect(help.existsSync(), isTrue);
      final Map<String, dynamic> decoded =
          jsonDecode(help.readAsStringSync()) as Map<String, dynamic>;
      final Map<String, dynamic> tools =
          decoded['tools'] as Map<String, dynamic>;
      for (final String id in hamPdfCards.keys) {
        expect(tools.containsKey(id), isTrue,
            reason: 'missing help entry for Ham PDF card "$id"');
        final Map<String, dynamic> entry = tools[id] as Map<String, dynamic>;
        expect(entry['name'], hamPdfCards[id],
            reason: 'help name mismatch for "$id"');
        expect(entry['category'], 'Quick Reference',
            reason: '"$id" help category should be Quick Reference');
      }
    });
  });
}
