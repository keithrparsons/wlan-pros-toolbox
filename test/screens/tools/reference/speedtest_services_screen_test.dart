// Speed Test Services screen + data + logo-resolver tests.
//
// Scope: this guards the NEW files only (data, logo resolver, screen). The
// catalog/route wiring is Larry's central registration pass and is intentionally
// NOT asserted here (those files are not touched on this branch). A fake
// launcher is injected so no real browser is opened.
//
// What it covers (per the build brief's definition of done):
//  - all 12 services render;
//  - search/filter narrows in place + the honest empty state;
//  - missing-logo graceful fallback (empty manifest) AND a present logo;
//  - url_launcher wired (tapping a card's link chip calls the launcher);
//  - the AppCopyAction is present and carries the honesty caveats + every row;
//  - the data-per-test confidence markers and the Orb monitor framing render.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/speedtest_logos.dart';
import 'package:wlan_pros_toolbox/data/speedtest_services_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/speedtest_services_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

Widget _harness({Future<bool> Function(Uri)? launcher}) => MaterialApp(
      theme: AppTheme.dark(),
      home: SpeedtestServicesScreen(launcher: launcher),
    );

void main() {
  // The screen reads the logo manifest synchronously; default every test to
  // "no logos built" so the fallback path is the baseline, then opt in.
  setUp(() => SpeedtestLogos.debugSetBundledAssets(<String>{}));
  tearDown(() => SpeedtestLogos.debugReset());

  group('data', () {
    test('exactly 12 Keith-approved services, all with unique slugs', () {
      expect(kSpeedtestServices.length, 12);
      final Set<String> slugs =
          kSpeedtestServices.map((SpeedtestService s) => s.slug).toSet();
      expect(slugs.length, 12, reason: 'slugs must be unique (logo keys)');
    });

    test('every service has a parseable https URL', () {
      for (final SpeedtestService s in kSpeedtestServices) {
        final Uri? uri = Uri.tryParse(s.url);
        expect(uri, isNotNull, reason: '${s.name} url unparseable');
        expect(uri!.scheme, 'https', reason: '${s.name} must be HTTPS');
      }
    });

    test('Orb is the single continuous-monitor entry', () {
      final List<SpeedtestService> monitors =
          kSpeedtestServices.where((SpeedtestService s) => s.isMonitor).toList();
      expect(monitors.length, 1);
      expect(monitors.single.slug, 'orb');
    });

    test('the shared-backend services carry a "runs on" note', () {
      for (final String slug in <String>['waveform', 'fast-com', 'isp-branded',
          'mlab-ndt']) {
        final SpeedtestService s = kSpeedtestServices
            .firstWhere((SpeedtestService s) => s.slug == slug);
        expect(s.backendNote, isNotNull, reason: '$slug needs a backend note');
      }
    });
  });

  group('logo resolver', () {
    test('empty manifest → no logo, falls back', () {
      SpeedtestLogos.debugSetBundledAssets(<String>{});
      expect(SpeedtestLogos.hasLogo('ookla'), isFalse);
      expect(SpeedtestLogos.logoFor('ookla'), isNull);
    });

    test('SVG is preferred over PNG when both are bundled', () {
      SpeedtestLogos.debugSetBundledAssets(<String>{
        'assets/speedtest-logos/ookla.svg',
        'assets/speedtest-logos/ookla.png',
      });
      final SpeedtestLogo? logo = SpeedtestLogos.logoFor('ookla');
      expect(logo, isNotNull);
      expect(logo!.format, SpeedtestLogoFormat.svg);
      expect(logo.path, 'assets/speedtest-logos/ookla.svg');
    });

    test('PNG resolves when only PNG is bundled', () {
      SpeedtestLogos.debugSetBundledAssets(<String>{
        'assets/speedtest-logos/cloudflare.png',
      });
      final SpeedtestLogo? logo = SpeedtestLogos.logoFor('cloudflare');
      expect(logo!.format, SpeedtestLogoFormat.png);
    });
  });

  group('screen', () {
    testWidgets('renders all 12 services, the hero, and the caveats',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      expect(find.text('Speed Test Services'), findsWidgets);
      // Hero + honesty caveats are on-screen, not just in data.
      expect(find.textContaining('not your'), findsWidgets);
      expect(find.textContaining('community-measured estimates'), findsOneWidget);
      expect(find.textContaining('Not all of these are independent'),
          findsOneWidget);
      expect(find.textContaining('no composite score'), findsOneWidget);

      // Scroll the whole list and confirm each service name appears at least
      // once. (Cards below the fold need scrolling into view.)
      for (final SpeedtestService s in kSpeedtestServices) {
        final Finder f = find.text(s.name);
        await tester.scrollUntilVisible(f, 300,
            scrollable: find.byType(Scrollable).first);
        expect(f, findsWidgets, reason: '${s.name} not rendered');
      }
    });

    testWidgets('the Orb monitor framing renders', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      final Finder orb = find.text('Orb');
      await tester.scrollUntilVisible(orb, 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Monitor, not a one-shot test'), findsOneWidget);
    });

    testWidgets('missing logo shows the name-initial fallback, no broken image',
        (tester) async {
      SpeedtestLogos.debugSetBundledAssets(<String>{});
      await tester.pumpWidget(_harness());
      await tester.pump();
      // Ookla's fallback initial "O" appears; no Image/Svg logo widget renders
      // for it (manifest is empty).
      expect(find.text('O'), findsWidgets);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('search narrows in place and shows the honest empty state',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'bufferbloat');
      await tester.pump();
      // Waveform's how/what mentions bufferbloat; Ookla should drop out.
      expect(find.text('Waveform Bufferbloat Test'), findsWidgets);
      expect(find.text('Ookla Speedtest'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzznotapresentword');
      await tester.pump();
      expect(find.text('No match'), findsOneWidget);
      expect(find.text('Waveform Bufferbloat Test'), findsNothing);
    });

    testWidgets('tapping a card link chip invokes the launcher with the URL',
        (tester) async {
      Uri? opened;
      await tester.pumpWidget(_harness(
        launcher: (Uri u) async {
          opened = u;
          return true;
        },
      ));
      await tester.pump();

      // Narrow to one service so its chip is reachable.
      await tester.enterText(find.byType(TextField), 'cloudflare');
      await tester.pump();

      final Finder chip = find.text('Visit site');
      await tester.ensureVisible(chip.first);
      await tester.pumpAndSettle();
      await tester.tap(chip.first, warnIfMissed: false);
      await tester.pump();
      expect(opened.toString(), 'https://speed.cloudflare.com');
    });

    testWidgets('the copy action is present and carries the caveats + rows',
        (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(find.byType(AppCopyAction), findsOneWidget);

      // Tap copy and read the clipboard payload.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map<Object?, Object?>)['text']
                as String?;
          }
          return null;
        },
      );
      await tester.tap(find.byType(AppCopyAction));
      await tester.pump();

      expect(copied, isNotNull);
      expect(copied, contains('Speed Test Services'));
      expect(copied, contains('Data caveat:'));
      expect(copied, contains('Ookla Speedtest'));
      expect(copied, contains('Runs on:'));
      // The data figure travels with its confidence marker.
      expect(copied, contains('(est.)'));

      // Flush AppCopyAction's 1.5s confirm-window timer before teardown.
      await tester.pump(const Duration(milliseconds: 1600));
    });
  });
}
