// Widget tests for the SSL/TLS Inspector screen — focused on the two pieces
// wired in to close Vera's LOW-1 finding:
//   1. the "Show full subject / issuer" disclosure that surfaces the full
//      structured DN (subjectFields / issuerFields), and
//   2. the "Copy PEM" affordance that writes the raw PEM to the clipboard and
//      flips to a "Copied" state.
//
// The service is faked by overriding `inspect`, so no socket is opened.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ssl_inspect_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ssl_inspect_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

const String _pem = '-----BEGIN CERTIFICATE-----\nABC123FAKEPEMBODY==\n'
    '-----END CERTIFICATE-----';

/// A service that returns a fixed successful result without touching a socket.
class _FakeSslInspectService extends SslInspectService {
  _FakeSslInspectService(this._result);

  final SslInspectResult _result;

  @override
  Future<SslInspectResult> inspect({
    required String rawHost,
    int port = SslInspectService.defaultPort,
    Duration timeout = const Duration(seconds: 8),
    DateTime? now,
  }) async =>
      _result;
}

InspectedCertificate _cert({String pem = _pem}) {
  final CertValidity validity = CertValidity.compute(
    notBefore: DateTime.utc(2026, 1, 1),
    notAfter: DateTime.utc(2027, 1, 1),
    now: DateTime.utc(2026, 6, 1),
  );
  return InspectedCertificate(
    subjectCommonName: 'example.com',
    subjectOrg: 'Example Inc',
    issuerCommonName: 'Example Root CA',
    issuerOrg: 'Example Trust',
    subjectFields: const <DnField>[
      DnField(label: 'CN', value: 'example.com'),
      DnField(label: 'O', value: 'Example Inc'),
      DnField(label: 'OU', value: 'Web Services'),
      DnField(label: 'L', value: 'Provo'),
      DnField(label: 'ST', value: 'Utah'),
      DnField(label: 'C', value: 'US'),
    ],
    issuerFields: const <DnField>[
      DnField(label: 'CN', value: 'Example Root CA'),
      DnField(label: 'O', value: 'Example Trust'),
    ],
    validity: validity,
    serialNumber: '0A:2B:3C',
    signatureAlgorithm: 'sha256WithRSAEncryption',
    publicKeyAlgorithm: 'rsaEncryption',
    publicKeyBits: 2048,
    sha256Fingerprint: 'AA:BB:CC',
    sha1Fingerprint: 'DD:EE:FF',
    subjectAltNames: const <String>['example.com', 'www.example.com'],
    pem: pem,
  );
}

Future<void> _pumpAndInspect(
  WidgetTester tester,
  SslInspectResult result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: SslInspectScreen(service: _FakeSslInspectService(result)),
    ),
  );
  await tester.enterText(find.byType(TextField).first, 'example.com');
  await tester.pump();
  await tester.tap(find.text('Inspect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('full subject DN is hidden until the disclosure is tapped',
      (WidgetTester tester) async {
    final SslInspectResult result = SslInspectResult.success(
      host: 'example.com',
      port: 443,
      certificate: _cert(),
      alpn: 'h2',
      handshakeMs: 42,
    );
    await _pumpAndInspect(tester, result);

    // Summary rows are always present.
    expect(find.text('example.com'), findsWidgets);
    // OU / L / ST detail-only values are NOT shown before expanding.
    expect(find.text('Web Services'), findsNothing);
    expect(find.text('Provo'), findsNothing);

    // Tap the subject disclosure (scroll it into view first — the result list
    // is taller than the 800x600 test viewport).
    final Finder disclosure = find.text('Show full subject');
    await tester.ensureVisible(disclosure);
    await tester.pumpAndSettle();
    await tester.tap(disclosure);
    await tester.pumpAndSettle();

    expect(find.text('Web Services'), findsOneWidget);
    expect(find.text('Provo'), findsOneWidget);
    expect(find.text('Utah'), findsOneWidget);
  });

  testWidgets('Copy PEM writes the raw PEM to the clipboard and flips to Copied',
      (WidgetTester tester) async {
    // Intercept clipboard platform calls.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    final SslInspectResult result = SslInspectResult.success(
      host: 'example.com',
      port: 443,
      certificate: _cert(),
      alpn: null,
      handshakeMs: 10,
    );
    await _pumpAndInspect(tester, result);

    expect(find.text('Copy PEM'), findsOneWidget);
    final Finder copyBtn = find.text('Copy PEM');
    await tester.ensureVisible(copyBtn);
    await tester.pumpAndSettle();
    await tester.tap(copyBtn);
    await tester.pump();

    expect(copied, _pem);
    expect(find.text('Copied'), findsOneWidget);

    // Clean up the timer-driven revert.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Copy PEM affordance is absent when the cert has no PEM',
      (WidgetTester tester) async {
    final SslInspectResult result = SslInspectResult.success(
      host: 'example.com',
      port: 443,
      certificate: _cert(pem: ''),
      alpn: null,
      handshakeMs: 10,
    );
    await _pumpAndInspect(tester, result);

    expect(find.text('Copy PEM'), findsNothing);
  });

  // Regression: the app-wide §8.3 a11y pass cleared the global
  // `Theme.focusColor` to transparent, which stripped the keyboard-focus
  // affordance from this disclosure's bare InkWell. It has no bordered
  // container to swap a ring onto, so the fix restores a visible focus overlay
  // locally with an explicit lime `focusColor`. This guards SC 2.4.7 / §8.9.
  testWidgets('disclosure InkWell exposes a local lime focusColor affordance',
      (WidgetTester tester) async {
    final SslInspectResult result = SslInspectResult.success(
      host: 'example.com',
      port: 443,
      certificate: _cert(),
      alpn: 'h2',
      handshakeMs: 42,
    );
    await _pumpAndInspect(tester, result);

    // The disclosure row is the InkWell wrapping the "Show full subject" label.
    final Finder disclosure = find.text('Show full subject');
    await tester.ensureVisible(disclosure);
    await tester.pumpAndSettle();

    final Finder disclosureInkWell = find.ancestor(
      of: disclosure,
      matching: find.byType(InkWell),
    );
    expect(disclosureInkWell, findsWidgets);

    final InkWell inkWell =
        tester.widgetList<InkWell>(disclosureInkWell).first;
    expect(
      inkWell.focusColor,
      AppColors.primary.withValues(alpha: 0.16),
      reason: 'Disclosure must keep a visible keyboard-focus overlay after the '
          'global focusColor was cleared to transparent.',
    );
  });
}
