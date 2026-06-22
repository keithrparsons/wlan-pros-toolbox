// NtpScreen — widget smoke tests.
//
// Drives the screen through its injected NtpService seam (a fake that returns a
// canned NtpResult), so no live UDP/socket work. Covers:
//   * idle → form only, no results card;
//   * success → the reading rows render (server, stratum, offset verdict word,
//     delay), with the offset StatusChip verdict carried as a WORD (§8.13);
//   * error → an honest failure message renders, no fabricated reading;
//   * the Copy payload carries the labeled report including the verdict word;
//   * no overflow across the standard widths.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ntp_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ntp_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// A fake service returning a fixed [NtpResult] for every query.
class _FakeNtpService extends NtpService {
  _FakeNtpService(this._result);
  final NtpResult _result;

  @override
  Future<NtpResult> query({
    String server = kDefaultNtpServer,
    Duration timeout = NtpService.defaultTimeout,
  }) async =>
      _result;
}

NtpResult _successResult({int offsetMs = 42, int delayMs = 18}) {
  final DateTime serverUtc =
      DateTime.utc(2026, 6, 21, 14, 30, 0, 120);
  return NtpResult.success(
    server: 'time.apple.com',
    resolvedIp: '17.253.4.125',
    reading: NtpReading(
      stratum: 1,
      serverUtc: serverUtc,
      deviceTime: serverUtc.add(Duration(milliseconds: -offsetMs)),
      offsetMs: offsetMs,
      delayMs: delayMs,
    ),
  );
}

Widget _host(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    );

void main() {
  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('idle: form only, default server, no results card',
      (tester) async {
    await tester.pumpWidget(
      _host(NtpScreen(service: _FakeNtpService(_successResult()))),
    );

    expect(find.text('Check time'), findsOneWidget);
    expect(find.text('NTP server'), findsOneWidget);
    // Default server prefilled.
    expect(find.text('time.apple.com'), findsWidgets);
    // No results yet.
    expect(find.text('Clock offset'), findsNothing);
    expect(find.text('Round-trip delay'), findsNothing);
  });

  testWidgets('success: renders the reading rows and offset verdict word',
      (tester) async {
    // 142 ms positive offset → above the ±50 ms in-sync window → "behind".
    await tester.pumpWidget(
      _host(NtpScreen(service: _FakeNtpService(_successResult(offsetMs: 142)))),
    );

    await tester.tap(find.text('Check time'));
    await tester.pumpAndSettle();

    expect(find.text('Stratum'), findsOneWidget);
    expect(find.textContaining('Primary server'), findsOneWidget);
    expect(find.text('Clock offset'), findsOneWidget);
    expect(find.text('+142 ms'), findsOneWidget);
    // The verdict is carried as a WORD (never color-only, §8.13): a positive
    // offset above the in-sync window means the device is behind the server.
    expect(find.textContaining('behind'), findsWidgets);
    expect(find.text('Round-trip delay'), findsOneWidget);
    expect(find.text('18 ms'), findsOneWidget);
    // Resolved IP renders.
    expect(find.text('17.253.4.125'), findsOneWidget);
  });

  testWidgets('success: a small offset reads as "in sync"', (tester) async {
    await tester.pumpWidget(
      _host(NtpScreen(service: _FakeNtpService(_successResult(offsetMs: 4)))),
    );
    await tester.tap(find.text('Check time'));
    await tester.pumpAndSettle();
    expect(find.textContaining('in sync'), findsWidgets);
  });

  testWidgets('error: an honest failure message renders, no reading',
      (tester) async {
    final NtpResult err = NtpResult.failure(
      server: 'time.apple.com',
      message: 'No reply within 3s. The server may be unreachable.',
    );
    await tester.pumpWidget(
      _host(NtpScreen(service: _FakeNtpService(err))),
    );
    await tester.tap(find.text('Check time'));
    await tester.pumpAndSettle();

    expect(find.text('Time check failed'), findsOneWidget);
    expect(find.textContaining('No reply within 3s'), findsOneWidget);
    // No fabricated reading rows.
    expect(find.text('Clock offset'), findsNothing);
  });

  testWidgets('Copy payload carries the labeled report with the verdict word',
      (tester) async {
    await tester.pumpWidget(
      _host(NtpScreen(service: _FakeNtpService(_successResult(offsetMs: 142)))),
    );
    await tester.tap(find.text('Check time'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppCopyAction));
    await tester.pump();

    expect(clipboardWrites, isNotEmpty);
    final String copied = clipboardWrites.last;
    expect(copied, contains('Time Server (NTP)'));
    expect(copied, contains('Server: time.apple.com'));
    expect(copied, contains('Resolved IP: 17.253.4.125'));
    expect(copied, contains('Clock offset: +142 ms'));
    expect(copied, contains('behind'));
    expect(copied, contains('Round-trip delay: 18 ms'));

    // Drain the AppCopyAction confirm-window timer (§8.16, 1500ms).
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('no overflow across standard widths', (tester) async {
    for (final double width in <double>[360, 768, 1280]) {
      await tester.pumpWidget(
        _host(
          NtpScreen(service: _FakeNtpService(_successResult())),
          size: Size(width, 900),
        ),
      );
      await tester.tap(find.text('Check time'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at width $width');
    }
  });
}
