// Break it on the 802.1X and EAP Ladder (spec 42): the select and what it
// offers, each fault drawn with the shared failure marker, the readouts and
// copy text of a failed ladder, the retry inputs, phone and desktop widths in
// both themes, and the presenter (fullest fault state at the three standard
// windows, B cycling the fault). The sequences themselves are pinned in
// test/services/wifi_lab/eap_ladder_fault_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_failure.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

const String _selectLabel = 'Break it: choose what goes wrong';

Future<EapLadderController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  LadderConfig? initial,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: true,
        ),
        child: EapLadderScreen(initial: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<EapLadderStage>(find.byType(EapLadderStage)).controller;
}

AppSelect<LadderFault> _select(WidgetTester tester) =>
    tester.widget<AppSelect<LadderFault>>(
      find.byWidgetPredicate(
        (Widget w) =>
            w is AppSelect<LadderFault> && w.semanticLabel == _selectLabel,
      ),
    );

/// The fullest fault ladder for each fault: the longest method it applies
/// to, most retries.
const List<LadderConfig> _faulted = <LadderConfig>[
  LadderConfig(
    method: LadderMethod.eapTls,
    certFragments: kMaxCertFragments,
    fault: LadderFault.untrustedServerCert,
  ),
  LadderConfig(method: LadderMethod.peap, fault: LadderFault.wrongPassword),
  LadderConfig(
    method: LadderMethod.eapTtls,
    fault: LadderFault.wrongRadiusSecret,
    faultRetries: kMaxFaultRetries,
  ),
  LadderConfig(
    method: LadderMethod.psk,
    fault: LadderFault.wrongPsk,
    faultRetries: kMaxFaultRetries,
  ),
  LadderConfig(
    method: LadderMethod.sae,
    fault: LadderFault.wrongSaePassword,
    faultRetries: kMaxFaultRetries,
  ),
];

void main() {
  testWidgets('the select offers None and the faults that apply', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _pump(tester);
    List<LadderFault> offered() => <LadderFault>[
      for (final AppSelectItem<LadderFault> i in _select(tester).items) i.$1,
    ];
    expect(_select(tester).value, LadderFault.none);
    expect(offered(), <LadderFault>[
      LadderFault.none,
      LadderFault.untrustedServerCert,
      LadderFault.wrongRadiusSecret,
    ]);
    c.method = LadderMethod.psk;
    await tester.pumpAndSettle();
    expect(offered(), <LadderFault>[LadderFault.none, LadderFault.wrongPsk]);

    // Choosing through the select's own callback changes the ladder.
    _select(tester).onChanged(LadderFault.wrongPsk);
    await tester.pumpAndSettle();
    expect(c.config.fault, LadderFault.wrongPsk);
    expect(c.sequence.failed, isTrue);
    expect(find.text('Retries (illustrative)'), findsOneWidget);
  });

  testWidgets('roam modes other than Full disable the select and say why', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _pump(tester);
    c.fault = LadderFault.untrustedServerCert;
    c.roam = LadderRoam.pmkCaching;
    await tester.pumpAndSettle();
    expect(_select(tester).enabled, isFalse);
    expect(_select(tester).value, LadderFault.none);
    expect(find.textContaining('Break it works on a full'), findsOneWidget);
    expect(c.sequence.failed, isFalse);
  });

  testWidgets('untrusted certificate: marks, band, caption, readouts, copy', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _pump(
      tester,
      initial: const LadderConfig(fault: LadderFault.untrustedServerCert),
    );
    c.showAll();
    await tester.pumpAndSettle();
    final int failures = c.sequence.messages
        .where((LadderMessage m) => m.failure)
        .length;
    expect(failures, 3); // the alert, the Access-Reject, the deauth
    expect(find.byType(LadderFailureMark), findsNWidgets(failures));
    expect(find.byType(LadderLostMark), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^Stopped here. Server certificate not')),
      findsOneWidget,
    );
    // The milestones this ladder never reaches are not drawn at all.
    expect(find.textContaining('Traffic protected:'), findsNothing);
    expect(find.textContaining('What the help desk sees'), findsOneWidget);
    expect(find.text('What never happened'), findsOneWidget);
    expect(find.textContaining('Broken: Server certificate'), findsOneWidget);

    final String copy = c.copyText();
    expect(copy, contains('Break it: Server certificate not trusted'));
    expect(copy, contains('unknown_ca (48) [failure]'));
    expect(copy, contains('Stopped here: '));
    expect(copy, contains('What the help desk sees: '));
    expect(copy, contains('Estimated time until it stops'));
    expect(copy, isNot(contains('Skipped versus full')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong shared secret: every Access-Request is a lost arrow', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _pump(
      tester,
      initial: const LadderConfig(
        fault: LadderFault.wrongRadiusSecret,
        faultRetries: 3,
      ),
    );
    c.showAll();
    await tester.pumpAndSettle();
    expect(find.byType(LadderLostMark), findsNWidgets(4));
    expect(find.byType(LadderFailureMark), findsNothing);
    expect(c.copyText(), contains('[no answer]'));
    // A retry change keeps the fault and redraws.
    c.faultRetries = 1;
    await tester.pumpAndSettle();
    expect(c.sequence.failed, isTrue);
    expect(
      c.sequence.messages.where((LadderMessage m) => m.lost),
      hasLength(2),
    );
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[360, 390, 1280]) {
      for (final LadderConfig cfg in _faulted) {
        testWidgets(
          '${cfg.fault.name} at $w px, $themeName: fits, no sideways scroll',
          (WidgetTester tester) async {
            final EapLadderController c = await _pump(
              tester,
              width: w,
              theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
              initial: cfg,
            );
            c.showAll();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final Scrollable s in tester.widgetList<Scrollable>(
              find.byType(Scrollable),
            )) {
              expect(s.axisDirection, AxisDirection.down);
            }
            expect(c.sequence.failed, isTrue);
            expect(
              find.bySemanticsLabel(RegExp('^Stopped here')),
              findsOneWidget,
            );
          },
        );
      }
    }
  }

  // Keith, 2026-09-29: at 390 px "Deauthentication" broke mid-word in the
  // ladder ("Deauthenticatio" / "n"). No text on the ladder may break inside
  // a word, at 360 or 390 px, in any fault ladder or in the ordinary one.
  // A break after a hyphen ("4-" / "way") is a word boundary.
  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[360, 390]) {
      for (final LadderConfig cfg in <LadderConfig>[
        ..._faulted,
        for (final LadderMethod m in LadderMethod.values)
          LadderConfig(method: m),
      ]) {
        testWidgets(
          '${cfg.method.name} ${cfg.fault.name} at $w px, $themeName: no '
          'ladder text breaks inside a word',
          (WidgetTester tester) async {
            final EapLadderController c = await _pump(
              tester,
              width: w,
              height: 8000,
              theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
              initial: cfg,
            );
            c.showAll();
            await tester.pumpAndSettle();
            final List<String> broken = <String>[];
            for (final Element e in find
                .descendant(
                  of: find.byType(EapLadderStage),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
              final RenderParagraph p = e.renderObject! as RenderParagraph;
              final String text = p.text.toPlainText();
              for (final RegExpMatch word in RegExp(
                r'[^\s-]+-?',
              ).allMatches(text)) {
                final Set<double> tops = <double>{
                  for (final TextBox b in p.getBoxesForSelection(
                    TextSelection(
                      baseOffset: word.start,
                      extentOffset: word.end,
                    ),
                  ))
                    b.top.roundToDouble(),
                };
                if (tops.length > 1) broken.add('${word[0]} in "$text"');
              }
            }
            expect(broken, isEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  group('presenter', () {
    Future<EapLadderController> present(
      WidgetTester tester, {
      required Size window,
      ThemeData? theme,
    }) async {
      setWindow(tester, window);
      installFakeWindow();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.dark(),
          home: const EapLadderScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      expect(find.byType(PresenterLayout), findsOneWidget);
      return tester
          .widget<EapLadderStage>(find.byType(EapLadderStage).last)
          .controller;
    }

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size window in const <Size>[
        Size(1920, 1080),
        Size(1440, 900),
        Size(1470, 923),
      ]) {
        for (final LadderConfig cfg in _faulted) {
          testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
              '${cfg.fault.name}: fits with the whole failed ladder', (
            WidgetTester tester,
          ) async {
            final EapLadderController c = await present(
              tester,
              window: window,
              theme: theme(),
            );
            c.method = cfg.method;
            c.certFragments = cfg.certFragments.toDouble();
            c.fault = cfg.fault;
            c.faultRetries = cfg.faultRetries.toDouble();
            c.showAll();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            expect(c.sequence.failed, isTrue);
            expect(controlsOverflow(tester), 0);
            final ScrollableState ladder = tester.state<ScrollableState>(
              find.descendant(
                of: find.descendant(
                  of: find.byKey(PresenterLayout.stageKey),
                  matching: find.byKey(EapLadderStage.ladderScrollKey),
                ),
                matching: find.byType(Scrollable),
              ),
            );
            expect(
              pageScrollables(tester).where((ScrollableState s) => s != ladder),
              isEmpty,
            );
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
          });
        }
      }
    }

    testWidgets('B cycles None and the faults for the method', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await present(
        tester,
        window: const Size(1920, 1080),
      );
      expect(c.config.method, LadderMethod.eapTls);
      final List<LadderFault> seen = <LadderFault>[];
      for (int i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.pump();
        seen.add(c.config.fault);
      }
      expect(seen, <LadderFault>[
        LadderFault.untrustedServerCert,
        LadderFault.wrongRadiusSecret,
        LadderFault.none,
      ]);
      expect(
        c.presenterActions.extra.map((PresenterExtraKey k) => k.keyLabel),
        contains('B'),
      );
    });
  });
}
