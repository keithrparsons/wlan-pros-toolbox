// Screen-level wiring test for the Field & Trade Reference "Download PDF"
// control (2026-07-05).
//
// Proves the contract that matters for correctness: EACH field-reference screen
// (and the LED Decoder's master comparison card) mounts exactly one
// ReferencePdfDownloadCard pointing at ITS OWN plate PDF
// (assets/reference-pdf/<tool-id>.pdf) — never the wrong file — and that the
// control is OMITTED when the PDF is not bundled (graceful degradation), so a
// build that ships without the plate never shows a dead download.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/reference_images.dart';
import 'package:wlan_pros_toolbox/data/reference_pdfs.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/adjacent_radio_systems_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cloud_tool_trust_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/credentials_licenses_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/enclosure_ratings_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/facility_spaces_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/hazardous_locations_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/healthcare_vertical_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/led_decoder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/nec_gotchas_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/network_in_scope_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/plan_set_literacy_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/safety_basics_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/site_access_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/reference_pdf_download.dart';

/// The screen -> plate-id mapping under test. The id resolves the bundled PDF
/// (`assets/reference-pdf/<id>.pdf`) — one distinct file per screen.
final Map<String, Widget> _screens = <String, Widget>{
  'enclosure-ratings': const EnclosureRatingsScreen(),
  'hazardous-locations': const HazardousLocationsScreen(),
  'nec-gotchas': const NecGotchasScreen(),
  'safety-basics': const SafetyBasicsScreen(),
  'plan-set-literacy': const PlanSetLiteracyScreen(),
  'site-access': const SiteAccessScreen(),
  'adjacent-radio-systems': const AdjacentRadioSystemsScreen(),
  'cloud-tool-trust': const CloudToolTrustScreen(),
  'network-in-scope': const NetworkInScopeScreen(),
  'facility-spaces': const FacilitySpacesScreen(),
  'healthcare-vertical': const HealthcareVerticalScreen(),
  'credentials-licenses': const CredentialsLicensesScreen(),
  // The LED Decoder's download rides the cross-vendor comparison plate id
  // (distinct from the interactive tool id) at the top of the vendor picker.
  'led-master-comparison': const LedDecoderScreen(),
};

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(414, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark(), home: screen),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    ReferencePdfs.debugReset();
    ReferenceImages.debugReset();
  });

  group('every field-reference screen wires ITS OWN plate PDF', () {
    _screens.forEach((String id, Widget screen) {
      testWidgets('$id downloads assets/reference-pdf/$id.pdf', (tester) async {
        // Only this screen's PDF is bundled — proves the control never points at
        // a sibling plate.
        ReferencePdfs.debugSetBundled(<String>{ReferencePdfs.pathFor(id)});
        // No PNG bundled — the on-screen plate is omitted, the download is not.
        ReferenceImages.debugSetBundled(const <String>{});

        await _pump(tester, screen);

        final Finder card = find.byType(ReferencePdfDownloadCard);
        expect(card, findsOneWidget, reason: '$id: one download control');
        final ReferencePdfDownloadCard widget =
            tester.widget<ReferencePdfDownloadCard>(card);
        expect(
          widget.assetPath,
          'assets/reference-pdf/$id.pdf',
          reason: '$id: correct plate file',
        );
        expect(find.text('Download PDF'), findsOneWidget);
      });
    });
  });

  group('graceful degradation — no PDF bundled, no download control', () {
    _screens.forEach((String id, Widget screen) {
      testWidgets('$id omits the control when the PDF is absent', (tester) async {
        ReferencePdfs.debugSetBundled(const <String>{});
        ReferenceImages.debugSetBundled(const <String>{});

        await _pump(tester, screen);

        expect(
          find.byType(ReferencePdfDownloadCard),
          findsNothing,
          reason: '$id: control must self-omit without a bundled PDF',
        );
        expect(tester.takeException(), isNull);
      });
    });
  });
}
