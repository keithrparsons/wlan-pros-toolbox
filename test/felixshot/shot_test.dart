@Tags(<String>['felixshot'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/bss_load_presentation.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/bss_load_screen.dart';
import 'package:wlan_pros_toolbox/services/network/bss_load_decoder.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

class _S implements BssLoadSource {
  _S(this.r);
  final BssLoadReading r;
  @override
  Future<BssLoadSnapshot> read() async => BssLoadSnapshot(
        reading: r,
        context: const BssLoadReadContext(
          platformExposesInformationElements: true,
          locationAuth: LocationAuthStatus.authorized,
        ),
        bssid: 'aa:bb:cc:dd:ee:ff',
      );
}

void main() {
  final Map<String, BssLoadReading> states = <String, BssLoadReading>{
    'clipped': const BssLoadUnavailable(
      BssLoadUnavailableReason.clippedWithoutSeeingElement11,
    ),
    'malformed-complete': const BssLoadUnavailable(
      BssLoadUnavailableReason.malformedLength,
      valueLength: 7,
    ),
  };
  for (final MapEntry<String, BssLoadReading> e in states.entries) {
    for (final bool light in <bool>[false, true]) {
      for (final double w in <double>[375, 768, 1280]) {
        testWidgets('${e.key} ${light ? "light" : "dark"} $w', (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = Size(w, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
              theme: light ? AppTheme.light() : AppTheme.dark(),
              home: BssLoadScreen(source: _S(e.value)),
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(BssLoadScreen),
            matchesGoldenFile(
              'shots/${e.key}-${light ? "light" : "dark"}-${w.toInt()}.png',
            ),
          );
        });
      }
    }
  }
}
