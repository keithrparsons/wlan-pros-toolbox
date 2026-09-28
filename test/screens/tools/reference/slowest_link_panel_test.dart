// Widget tests for The Slowest Link Wins panel on the two field plates
// (research brief candidate 15): both plate routes carry it beside the
// unchanged PDF; the control moves the slowest-hop mark and the end-to-end
// number follows the minimum; the mark is in words, not color alone; the
// other PDF cards have no companion; wide and narrow windows lay out in
// both themes with no overflow.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/slowest_link_panel.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _openRoute(
  WidgetTester tester,
  String route, {
  Size size = const Size(1280, 900),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Builder(builder: (BuildContext c) => AppRouter.routes[route]!(c)),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  for (final String route in <String>[
    AppRouter.howDevicesAccessTheInternet,
    AppRouter.throughputTestingWhere,
  ]) {
    testWidgets(
      '$route: the plate keeps its PDF and gains the panel',
      (WidgetTester tester) async {
        await _openRoute(tester, route);
        final PdfReferenceScreen screen = tester.widget(
          find.byType(PdfReferenceScreen),
        );
        expect(screen.assetPath, startsWith('assets/field-plates/'));
        expect(screen.companion, isA<SlowestLinkPanel>());
        expect(find.byType(SlowestLinkPanel), findsOneWidget);
        expect(find.text('Try it: the slowest link wins'), findsOneWidget);
      },
      skip: Platform.isLinux,
    );
  }

  testWidgets('other PDF cards have no companion', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const PdfReferenceScreen(
          title: 'Top 20 Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/top-20-checklist.pdf',
          toolId: 'top-20-checklist',
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(PdfReferenceScreen.companionKey), findsNothing);
  }, skip: Platform.isLinux);

  testWidgets(
    'the control moves the mark and the total follows the minimum',
    (WidgetTester tester) async {
      await _openRoute(tester, AppRouter.throughputTestingWhere);
      // Opens on Switch port: a 100 Mbps port caps everything at 94.1.
      expect(find.text('Slowest hop: it sets the total'), findsOneWidget);
      expect(find.text('94.1 Mb/s'), findsNWidgets(2));
      expect(find.textContaining('the switch port.'), findsOneWidget);
      expect(
        find.textContaining('cannot make this internet faster'),
        findsOneWidget,
      );

      await _tap(tester, find.text('ISP plan'));
      expect(find.text('300.0 Mb/s'), findsNWidgets(2));
      expect(find.textContaining('the ISP plan.'), findsOneWidget);

      await _tap(tester, find.text('Wi-Fi'));
      expect(find.text('86.5 Mb/s'), findsNWidgets(2));
      expect(
        find.textContaining('raises the total to 300.0 Mb/s'),
        findsOneWidget,
      );
      expect(find.text('Slowest hop: it sets the total'), findsOneWidget);
    },
    skip: Platform.isLinux,
  );

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in const <Size>[
      Size(390, 844),
      Size(820, 1180),
      Size(1440, 900),
    ]) {
      testWidgets('$name ${size.width.toInt()}x${size.height.toInt()}: no '
          'overflow', (WidgetTester tester) async {
        await _openRoute(
          tester,
          AppRouter.howDevicesAccessTheInternet,
          size: size,
          theme: theme(),
        );
        for (final String choice in <String>[
          'Wi-Fi',
          'Switch',
          'ISP plan',
        ]) {
          await _tap(tester, find.text(choice));
          expect(tester.takeException(), isNull, reason: choice);
        }
      }, skip: Platform.isLinux);
    }
  }
}
