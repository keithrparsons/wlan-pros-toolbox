// WifiToolsComparisonService tests + a guard on the REAL bundled asset.
//
// Coverage:
// - The pure parser: a well-formed fixture, malformed rows dropped, garbage
//   document → empty-but-valid service, meta + estimate disclaimers preserved
//   verbatim (GL-005), modeled-estimate figures parsed without recompute.
// - Search: substring across vendor/product/notes/cost/activity, no-match
//   returns empty (never fabricated), empty query returns all.
// - The REAL bundled asset (assets/data/wifi_tools_comparison.json): parses,
//   carries the date-stamp + estimate + beta disclaimers, and TAMOSOFT IS ABSENT
//   from every activity, toolkit, and vendor list (Keith 2026-06-05).

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_tools_comparison_screen.dart'
    show kWifiToolsComparisonAsset;
import 'package:wlan_pros_toolbox/services/network/wifi_tools_comparison_service.dart';

const String _fixture = '''
{
  "_meta": {
    "pricingDate": "July 2026",
    "pricingNote": "Pricing as of July 2026. Confirm current pricing with the vendor before you buy.",
    "estimateNote": "Cost figures are modeled estimates, not vendor-published quotes.",
    "betaNote": "This comparison is in beta review.",
    "neutralityNote": "This is not a ranking.",
    "noLogosNote": "No vendor logos or product photos appear here.",
    "currency": "USD",
    "tcoLabel": "3-year TCO",
    "source": "V6 workbook + Pax brief 2026-06-05"
  },
  "activities": [
    {
      "id": "design",
      "title": "Wi-Fi Design",
      "intro": "Design is the planning phase.",
      "configs": [
        { "vendor": "Ekahau", "product": "AI Pro + Connect", "costModel": "subscription", "upFront": 7990, "tco3yr": 11980, "notes": "AI Pro with 4G/5G planning." },
        { "vendor": "Hamina", "product": "Planner", "costModel": "subscription", "upFront": 980, "tco3yr": 2940, "notes": "SaaS pricing." },
        { "vendor": "", "product": "broken no vendor", "costModel": "quote", "notes": "dropped" }
      ]
    },
    {
      "id": "spectrum",
      "title": "Spectrum Analysis",
      "intro": "Spectrum analysis looks below Wi-Fi.",
      "configs": [
        { "vendor": "Oscium", "product": "Chanalyzer + Wi-Spy Lucid", "costModel": "perpetual", "upFront": 1599, "tco3yr": 1899, "notes": "Triband spectrum analyzer." }
      ]
    },
    { "title": "", "configs": [] }
  ],
  "toolkits": [
    { "vendor": "Sidos", "product": "Wave, Cloud & MicroApps", "tco3yr": 8964, "notes": "No spectrum analysis." }
  ],
  "vendors": [
    { "name": "Ekahau", "summary": "Design and survey company.", "website": "https://www.ekahau.com", "docs": "https://support.ekahau.com" },
    { "name": "", "summary": "dropped no name", "website": "", "docs": "" }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WifiToolsComparisonService.fromJson (pure parse)', () {
    final WifiToolsComparisonService svc =
        WifiToolsComparisonService.fromJson(_fixture);

    test('parses activities and drops a structurally broken config', () {
      // Design (2 valid, broken row dropped) + Spectrum (1). The empty-title
      // activity is dropped.
      expect(svc.activities, hasLength(2));
      expect(svc.activities.first.title, 'Wi-Fi Design');
      expect(svc.activities.first.configs, hasLength(2));
      expect(svc.configCount, 3);
    });

    test('preserves the disclaimer + date-stamp meta verbatim (GL-005)', () {
      final WifiToolsComparisonMeta m = svc.meta;
      expect(m.pricingDate, 'July 2026');
      expect(m.pricingNote, contains('Confirm current pricing'));
      expect(m.estimateNote, contains('modeled estimates'));
      expect(m.betaNote, contains('beta review'));
      expect(m.neutralityNote, contains('not a ranking'));
      expect(m.noLogosNote, contains('No vendor logos'));
      expect(m.tcoLabel, '3-year TCO');
    });

    test('parses modeled-estimate figures without recompute', () {
      final WifiToolConfig c = svc.activities.first.configs.first;
      expect(c.vendor, 'Ekahau');
      expect(c.upFront, 7990);
      expect(c.tco3yr, 11980);
      // The service never derives TCO from up-front — it carries the asset value.
      expect(c.costModel, WifiToolCostModel.subscription);
    });

    test('parses the toolkit roll-up and the per-vendor list, dropping broken',
        () {
      expect(svc.toolkits, hasLength(1));
      expect(svc.toolkits.first.vendor, 'Sidos');
      expect(svc.vendors, hasLength(1)); // the no-name vendor is dropped
      expect(svc.vendors.first.website, 'https://www.ekahau.com');
    });

    test('garbage documents yield an empty-but-valid service', () {
      expect(WifiToolsComparisonService.fromJson('[]').activities, isEmpty);
      expect(WifiToolsComparisonService.fromJson('not json').configCount, 0);
      expect(
        WifiToolsComparisonService.fromJson('{"nope": true}').vendors,
        isEmpty,
      );
    });
  });

  group('search', () {
    final WifiToolsComparisonService svc =
        WifiToolsComparisonService.fromJson(_fixture);

    test('empty query returns every activity unfiltered', () {
      expect(svc.search('').length, svc.activities.length);
    });

    test('substring narrows across vendor / product / activity', () {
      final List<WifiToolActivity> hit = svc.search('oscium');
      expect(hit, hasLength(1));
      expect(hit.first.title, 'Spectrum Analysis');
      expect(hit.first.configs.first.vendor, 'Oscium');
    });

    test('matches on cost model label', () {
      final List<WifiToolActivity> hit = svc.search('perpetual');
      expect(hit, hasLength(1));
      expect(hit.first.configs.first.vendor, 'Oscium');
    });

    test('no-match returns an empty list, never a fabricated activity', () {
      expect(svc.search('zzznotpresent'), isEmpty);
    });
  });

  group('real bundled asset', () {
    late WifiToolsComparisonService svc;

    setUpAll(() async {
      final String raw = await rootBundle.loadString(kWifiToolsComparisonAsset);
      svc = WifiToolsComparisonService.fromJson(raw);
    });

    test('parses with the four activities in order', () {
      expect(
        svc.activities.map((WifiToolActivity a) => a.title).toList(),
        <String>[
          'Wi-Fi Design',
          'Wi-Fi Validation',
          'Spectrum Analysis',
          'Wi-Fi Troubleshooting',
        ],
      );
      expect(svc.configCount, greaterThan(20));
    });

    test('carries the July 2026 date-stamp + modeled-estimate + beta disclaimers',
        () {
      final WifiToolsComparisonMeta m = svc.meta;
      // Pinned to the July 2026 refresh (was February 2026). The stamp is a
      // user-facing honesty claim, so it is guarded exactly.
      expect(m.pricingDate, 'July 2026');
      expect(m.pricingNote, contains('July 2026'));
      expect(m.pricingNote.toLowerCase(), contains('pricing as of'));
      expect(m.estimateNote.toLowerCase(), contains('modeled estimate'));
      expect(m.betaNote.toLowerCase(), contains('beta'));
      expect(m.noLogosNote.toLowerCase(), contains('logo'));
    });

    test('WLAN Pi R4 + Wi-Fi NIC is the verified \$350 (July 2026 drop from '
        '\$400; Big QAM)', () {
      final Iterable<WifiToolConfig> allConfigs = svc.activities
          .expand((WifiToolActivity a) => a.configs);
      final WifiToolConfig r4 = allConfigs.firstWhere(
        (WifiToolConfig c) =>
            c.vendor == 'WLAN Pi' && c.product.contains('R4'),
        orElse: () => throw StateError('WLAN Pi R4 config missing'),
      );
      expect(r4.upFront, 350, reason: 'R4 up-front must be the verified \$350');
      expect(r4.tco3yr, 350, reason: 'R4 3-yr TCO must be the verified \$350');
    });

    test('every config carries non-empty vendor + product', () {
      for (final WifiToolActivity a in svc.activities) {
        for (final WifiToolConfig c in a.configs) {
          expect(c.vendor, isNotEmpty);
          expect(c.product, isNotEmpty);
        }
      }
    });

    test('Intuitibits spectrum config is WFE Pro 3 + 1 NXT-2000 = \$1,325 '
        '(vendor-confirmed Pro 3 \$129.99 + NXT-2000 \$1,195; no double-count, Ferney F7)', () {
      final WifiToolActivity spectrum = svc.activities.firstWhere(
        (WifiToolActivity a) => a.title == 'Spectrum Analysis',
      );
      final WifiToolConfig intui = spectrum.configs.firstWhere(
        (WifiToolConfig c) => c.vendor == 'Intuitibits',
      );
      expect(intui.product, 'WiFi Explorer Pro 3 + NXT-2000');
      expect(intui.upFront, 1325);
      expect(intui.tco3yr, 1325);
    });

    test('Tamosoft is absent from every activity, toolkit, and vendor list', () {
      bool mentionsTamosoft(String s) {
        final String l = s.toLowerCase();
        return l.contains('tamosoft') ||
            l.contains('tamograph') ||
            l.contains('commview');
      }

      for (final WifiToolActivity a in svc.activities) {
        for (final WifiToolConfig c in a.configs) {
          expect(mentionsTamosoft(c.vendor), isFalse,
              reason: 'Tamosoft vendor in ${a.title}');
          expect(mentionsTamosoft(c.product), isFalse,
              reason: 'Tamosoft product in ${a.title}');
        }
      }
      for (final WifiToolkit t in svc.toolkits) {
        expect(mentionsTamosoft(t.vendor), isFalse);
        expect(mentionsTamosoft(t.product), isFalse);
      }
      for (final WifiToolVendor v in svc.vendors) {
        expect(mentionsTamosoft(v.name), isFalse);
      }
    });
  });
}
