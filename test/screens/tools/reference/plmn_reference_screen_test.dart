// Widget overflow regression for the PLMN ID Reference screen.
//
// The screen's parsing/search/grouping logic is covered by
// test/services/plmn_reference_service_test.dart. This file adds the
// rendered-pixel guard: pump the screen at 320/375/768/1280 widths in BOTH
// light and dark themes (this is a light/dark-aware screen — every color via
// context.colors) and assert no RenderFlex overflow. A pre-built service is
// injected so the test does not depend on the bundled asset load
// (PlmnReferenceScreen.service hook).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/plmn_reference_screen.dart';
import 'package:wlan_pros_toolbox/services/network/plmn_reference_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "_meta": { "count": 5 },
  "plmn": [
    { "mcc": "310", "mnc": "004", "plmn_id": "310004", "country": "United States", "region": "US", "carrier": "Verizon", "operator": "Verizon Wireless", "status": "operational" },
    { "mcc": "310", "mnc": "053", "plmn_id": "310053", "country": "United States", "region": "US", "carrier": "Virgin Mobile", "operator": "T-Mobile US", "status": "operational" },
    { "mcc": "310", "mnc": "370", "plmn_id": "310370", "country": "United States", "region": "GU", "carrier": "Docomo Pacific", "operator": "NTT DoCoMo Pacific", "status": "operational" },
    { "mcc": "313", "mnc": "100", "plmn_id": "313100", "country": "United States", "region": "US", "carrier": "FirstNet", "operator": "AT&T FirstNet", "status": "operational" },
    { "mcc": "314", "mnc": "100", "plmn_id": "314100", "country": "United States", "region": "US", "carrier": "Reserved for Public Safety", "operator": "Reserved for Public Safety", "status": "reserved" }
  ]
}
''';

void main() {
  testWidgets('renders without overflow at 320/375/768/1280 widths in both '
      'themes', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final PlmnReferenceService svc = PlmnReferenceService.fromJson(_fixture);
    final List<ThemeData> themes = <ThemeData>[
      AppTheme.dark(),
      AppTheme.light(),
    ];
    for (final ThemeData theme in themes) {
      for (final double width in <double>[320, 375, 768, 1280]) {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: PlmnReferenceScreen(service: svc),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'overflow at ${width}px / ${theme.brightness}');
      }
    }
  });

  testWidgets('shows the honest no-match state for a query that matches nothing',
      (tester) async {
    final PlmnReferenceService svc = PlmnReferenceService.fromJson(_fixture);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PlmnReferenceScreen(service: svc),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-no-carrier');
    await tester.pump();

    expect(find.textContaining('No US PLMN code matches'), findsOneWidget);
  });
}
