// The About screen's update line, rendered through the REAL AboutScreen.
//
// The load-bearing assertion is the negative one: an `unknown` result must not
// produce anything that reads like reassurance. A check that failed and a check
// that succeeded look different on screen, and only the successful one is
// allowed to say the build is current.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/about_screen.dart';
import 'package:wlan_pros_toolbox/services/app_update_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _kUpToDate = 'This is the latest published version.';
const String _kUnknown = 'Could not check for a newer version.';

/// An AppUpdateService pinned to the direct-download channel with a scripted
/// fetch, so the About screen renders a chosen verdict offline.
AppUpdateService scripted(ReleaseFetcher fetcher) => AppUpdateService(
      fetcher: fetcher,
      resolveChannel: () => UpdateChannel.githubReleases,
      getStore: SharedPreferences.getInstance,
    );

/// The About screen is a scrolling list, so the version section only builds
/// when the viewport is tall enough. Same tall-surface approach the sibling
/// about_screen_test.dart uses for its content assertions.
/// Pump in EITHER theme. Defaulting every test to dark is how a light-only
/// contrast bug survived this suite once already, so the theme is an explicit
/// parameter and at least one test renders light.
Future<void> pumpAbout(
  WidgetTester tester,
  AppUpdateService svc, {
  bool light = false,
}) async {
  tester.view.physicalSize = const Size(420, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.light() : AppTheme.dark(),
      home: AboutScreen(updateService: svc),
    ),
  );
  await tester.pumpAndSettle();
}

/// WCAG 2.2 relative luminance, per the W3C definition.
double _luminance(Color c) {
  double channel(double v) {
    final double s = v / 255.0;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

/// Contrast ratio between two opaque colors, 1.0 to 21.0.
double _contrast(Color fg, Color bg) {
  final double a = _luminance(fg);
  final double b = _luminance(bg);
  final double hi = a > b ? a : b;
  final double lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Deterministic runtime build identity, so the version read resolves
    // immediately and the update check is what is under test.
    PackageInfo.setMockInitialValues(
      appName: 'WLAN Pros Toolbox',
      packageName: 'com.wlanpros.toolbox',
      version: '1.8.1',
      buildNumber: '26071901',
      buildSignature: '',
    );
  });

  testWidgets('an up-to-date result states the build is current',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{'tag_name': 'v0.0.1'}),
    );
    expect(find.text(_kUpToDate), findsOneWidget);
    expect(find.text(_kUnknown), findsNothing);
  });

  testWidgets('an available update names the version and offers a link',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{
            'tag_name': 'v99.0.0',
            'html_url': 'https://example.invalid/releases/tag/v99.0.0',
          }),
    );
    expect(find.text('Version 99.0.0 is available.'), findsOneWidget);
    expect(find.text('Get the update'), findsOneWidget);
    expect(find.text(_kUpToDate), findsNothing);
  });

  testWidgets('a failed check says so and NEVER claims the build is current',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => throw const JsonHttpException(
            JsonHttpErrorKind.transport,
            'Failed host lookup: api.github.com',
          )),
    );
    expect(find.text(_kUnknown), findsOneWidget);
    // The whole point: no reassurance, and no download link.
    expect(find.text(_kUpToDate), findsNothing);
    expect(find.text('Get the update'), findsNothing);
  });

  testWidgets('unknown differs from up to date in WORDING, not just color',
      (WidgetTester tester) async {
    // The color assertion alone is far too weak: swapping the two strings would
    // keep the colors distinct and still tell an offline user their build is
    // current. The WORDING is what the user actually reads, so assert that
    // first and treat color as the secondary signal.
    await pumpAbout(
      tester,
      scripted((Duration _) async => throw const JsonHttpException(
            JsonHttpErrorKind.transport,
            'offline',
          )),
    );
    final Text unknownText = tester.widget<Text>(find.text(_kUnknown));
    final Color unknownColor = unknownText.style!.color!;

    // The failed state must not contain any claim about being current.
    expect(unknownText.data, isNot(contains('latest')));
    expect(unknownText.data, contains('Could not check'));

    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{'tag_name': 'v0.0.1'}),
    );
    final Text upToDateText = tester.widget<Text>(find.text(_kUpToDate));
    final Color upToDateColor = upToDateText.style!.color!;

    expect(upToDateText.data, isNot(unknownText.data));
    expect(upToDateText.data, contains('latest'));
    expect(unknownColor, isNot(upToDateColor));
  });

  testWidgets('LIGHT MODE: the update line clears WCAG AA on the card surface',
      (WidgetTester tester) async {
    // This is the test that was missing. The suite rendered dark only, so a
    // foreground that fails contrast on white shipped unnoticed. Lime is
    // fill-only on light (§8.20.2), and a bare `accent` foreground here
    // measures 3.11:1 against the card.
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{
            'tag_name': 'v99.0.0',
            'html_url': 'https://example.invalid/x',
          }),
      light: true,
    );

    final AppColorScheme colors = AppColorScheme.light();
    final Color fg = tester
        .widget<Text>(find.text('Version 99.0.0 is available.'))
        .style!
        .color!;

    expect(
      _contrast(fg, colors.surface1),
      greaterThanOrEqualTo(4.5),
      reason: 'WCAG 2.2 AA for body text on the surface1 card',
    );
    // And name the actual rule, so a regression to `accent` is unambiguous.
    expect(fg, colors.textAccent);
    expect(fg, isNot(colors.accent));
  });

  testWidgets('DARK MODE: the update line also clears WCAG AA',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{
            'tag_name': 'v99.0.0',
            'html_url': 'https://example.invalid/x',
          }),
    );
    final AppColorScheme colors = AppColorScheme.dark();
    final Color fg = tester
        .widget<Text>(find.text('Version 99.0.0 is available.'))
        .style!
        .color!;
    expect(_contrast(fg, colors.surface1), greaterThanOrEqualTo(4.5));
  });

  testWidgets('LIGHT MODE: the up-to-date and unknown lines clear WCAG AA',
      (WidgetTester tester) async {
    final AppColorScheme colors = AppColorScheme.light();

    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{'tag_name': 'v0.0.1'}),
      light: true,
    );
    expect(
      _contrast(
        tester.widget<Text>(find.text(_kUpToDate)).style!.color!,
        colors.surface1,
      ),
      greaterThanOrEqualTo(4.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpAbout(
      tester,
      scripted((Duration _) async => throw const JsonHttpException(
            JsonHttpErrorKind.transport,
            'offline',
          )),
      light: true,
    );
    expect(
      _contrast(
        tester.widget<Text>(find.text(_kUnknown)).style!.color!,
        colors.surface1,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('the update line is a live region so it is announced',
      (WidgetTester tester) async {
    // The line is inserted after first paint with no focus change; without a
    // live region a screen-reader user is never told (WCAG 2.2 SC 4.1.3).
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpAbout(
      tester,
      scripted((Duration _) async => <String, dynamic>{
            'tag_name': 'v99.0.0',
            'html_url': 'https://example.invalid/x',
          }),
    );

    // The live region wraps the line, so assert it is an ANCESTOR of the text
    // rather than merged into the text node itself.
    final Finder liveRegion = find.ancestor(
      of: find.text('Version 99.0.0 is available.'),
      matching: find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.liveRegion == true,
      ),
    );
    expect(liveRegion, findsOneWidget);
    handle.dispose();
  });

  group('copied About text carries the update state', () {
    /// Read the text the §8.16 copy action would place on the clipboard.
    Future<String> copiedText(WidgetTester tester) async {
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            captured = (call.arguments as Map<Object?, Object?>)['text']
                as String?;
          }
          return null;
        },
      );
      await tester.tap(find.byTooltip('Copy About text'));
      await tester.pumpAndSettle();
      // §8.16 shows a 1500ms "Copied" confirmation; let it lapse so no timer
      // outlives the widget tree.
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      expect(captured, isNotNull, reason: 'copy action produced no text');
      return captured!;
    }

    testWidgets('an available update lands in the copied text with its URL',
        (WidgetTester tester) async {
      await pumpAbout(
        tester,
        scripted((Duration _) async => <String, dynamic>{
              'tag_name': 'v99.0.0',
              'html_url': 'https://example.invalid/releases/tag/v99.0.0',
            }),
      );
      final String text = await copiedText(tester);
      expect(text, contains('Version 99.0.0 is available'));
      expect(text, contains('https://example.invalid/releases/tag/v99.0.0'));
    });

    testWidgets('a failed check is copied honestly, not as reassurance',
        (WidgetTester tester) async {
      await pumpAbout(
        tester,
        scripted((Duration _) async => throw const JsonHttpException(
              JsonHttpErrorKind.transport,
              'offline',
            )),
      );
      final String text = await copiedText(tester);
      expect(text, contains(_kUnknown));
      expect(text, isNot(contains('latest published version')));
    });

    testWidgets('a store-managed build copies no update claim at all',
        (WidgetTester tester) async {
      await pumpAbout(
        tester,
        AppUpdateService(
          fetcher: (Duration _) async =>
              <String, dynamic>{'tag_name': 'v99.0.0'},
          resolveChannel: () => UpdateChannel.managedByStore,
          getStore: SharedPreferences.getInstance,
        ),
      );
      final String text = await copiedText(tester);
      expect(text, isNot(contains('is available')));
      expect(text, isNot(contains(_kUpToDate)));
      expect(text, isNot(contains(_kUnknown)));
      // The rest of the About text is still there.
      expect(text, contains('Version and Feedback'));
    });
  });

  testWidgets('a store-managed build shows no update line at all',
      (WidgetTester tester) async {
    await pumpAbout(
      tester,
      AppUpdateService(
        fetcher: (Duration _) async => <String, dynamic>{'tag_name': 'v99.0.0'},
        resolveChannel: () => UpdateChannel.managedByStore,
        getStore: SharedPreferences.getInstance,
      ),
    );
    expect(find.text(_kUpToDate), findsNothing);
    expect(find.text(_kUnknown), findsNothing);
    expect(find.text('Get the update'), findsNothing);
    expect(find.textContaining('is available.'), findsNothing);
  });

  testWidgets('nothing is claimed before the check resolves',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final Completer<Map<String, dynamic>> gate =
        Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AboutScreen(
          updateService: scripted((Duration _) => gate.future),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The About screen has rendered; the check has not answered.
    expect(find.text('Version and Feedback'), findsOneWidget);
    expect(find.text(_kUpToDate), findsNothing);
    expect(find.text(_kUnknown), findsNothing);

    gate.complete(<String, dynamic>{'tag_name': 'v0.0.1'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(_kUpToDate), findsOneWidget);
  });
}
