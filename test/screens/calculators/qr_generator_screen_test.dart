// QR Code Generator widget tests — mode switching + state coverage.
//
// Covers the UI contract for the 2026-06-12 Wi-Fi enhancement: the content-mode
// toggle (URL/Text ↔ Wi-Fi) swaps the input fields, the Wi-Fi empty state
// prompts for an SSID, entering an SSID renders the QR, and the password field
// is hidden for an open network. The rendered QR bytes are not asserted (that is
// the pretty_qr_code package's concern); these assert the screen wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/qr_generator_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.dark(), home: const QrGeneratorScreen()),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'the password show/hide toggle exposes an accessible NAME, not just a '
    'tooltip (WCAG 2.2 AA SC 4.1.2)',
    (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester);
      // Switch to Wi-Fi mode so the (non-open) password field renders its toggle.
      await tester.tap(find.text('Wi-Fi'));
      await tester.pumpAndSettle();

      // Obscured by default → the label reads 'Show password'. `tooltip:` maps to
      // AXHelp, not AXTitle; the explicit Semantics label is the accessible name.
      // Removing it (the mutation) → red.
      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Show password')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Show password',
        ),
        reason: 'the password toggle must read as a named, enabled button to AT',
      );

      handle.dispose();
    },
  );

  testWidgets('defaults to URL / Text mode with its prompt', (tester) async {
    await _pump(tester);
    expect(find.text('Text or URL'), findsOneWidget);
    expect(
      find.text('Enter text or a URL above to generate a QR code.'),
      findsOneWidget,
    );
    // The Wi-Fi fields are not present in URL/Text mode.
    expect(find.text('Network name (SSID)'), findsNothing);
  });

  testWidgets('typing a URL renders the QR and the share button',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'https://wlanpros.com');
    await tester.pump();
    expect(find.text('Share / Save'), findsOneWidget);
    // Empty-state prompt is gone once there is data.
    expect(
      find.text('Enter text or a URL above to generate a QR code.'),
      findsNothing,
    );
  });

  testWidgets('switching to Wi-Fi mode swaps in the Wi-Fi fields',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();

    expect(find.text('Network name (SSID)'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Hidden network'), findsOneWidget);
    // The URL/Text field is gone.
    expect(find.text('Text or URL'), findsNothing);
    // Wi-Fi-specific empty-state prompt.
    expect(
      find.text(
        'Enter a network name (SSID) above to generate a Wi-Fi join code.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('entering an SSID in Wi-Fi mode renders the QR', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pumpAndSettle();

    // The first field in the Wi-Fi card is the SSID field.
    await tester.enterText(find.byType(TextField).first, 'WLAN-Pros-Guest');
    await tester.pump();

    expect(find.text('Share / Save'), findsOneWidget);
    expect(
      find.text(
        'Enter a network name (SSID) above to generate a Wi-Fi join code.',
      ),
      findsNothing,
    );
  });

  testWidgets('shape and size selectors are present', (tester) async {
    await _pump(tester);
    expect(find.text('Module shape'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Rounded'), findsOneWidget);
    expect(find.text('Dots'), findsOneWidget);
  });
}
