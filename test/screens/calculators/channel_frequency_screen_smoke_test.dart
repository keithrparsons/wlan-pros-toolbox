// Smoke + state-coverage render test for the Channel / Frequency converter.
//
// Verifies the screen builds in both modes and renders the verified results, the
// reject/empty states, and the overlap notice. Not a golden — a behavioral guard
// that the wiring (toggle -> selects -> result cards) holds.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_frequency_converter_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host() => MaterialApp(
      theme: AppTheme.dark(),
      home: const ChannelFrequencyConverterScreen(),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ToolHelpLoader.ensureLoaded();
  });

  testWidgets('renders Channel -> Freq mode with a center frequency',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    // Default selection is 5 GHz ch 36 @ 20 MHz -> 5180 MHz center.
    expect(find.text('5180 MHz'), findsOneWidget);
    expect(find.text('Channel / Frequency'), findsOneWidget);
  });

  testWidgets('shows the secondary MikroTik note under the center frequency',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    // The MikroTik aside renders on the channel -> frequency result.
    expect(
      find.textContaining('center frequency you enter directly'),
      findsOneWidget,
    );
  });

  testWidgets('Copy frequency yields the BARE integer MHz (no unit, no channel)',
      (WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    // Default 5 GHz ch 36 @ 20 MHz -> center 5180. Copy must be exactly "5180".
    final Finder copyBtn = find.widgetWithText(OutlinedButton, 'Copy frequency');
    expect(copyBtn, findsOneWidget);
    await tester.ensureVisible(copyBtn);
    await tester.pumpAndSettle();
    await tester.tap(copyBtn);
    await tester.pump(const Duration(milliseconds: 50));
    expect(copied, '5180');

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    // Let the 1.5s in-place confirm timer (copy -> check -> revert) elapse so
    // no Timer is left pending at teardown.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('switching to Freq -> Channel shows the empty prompt then a result',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Freq -> Channel'));
    await tester.pumpAndSettle();
    // Empty state copy present before input.
    expect(
      find.textContaining('Enter a frequency in MHz'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '5935');
    await tester.pumpAndSettle();
    // 5935 -> 6 GHz channel 2 (special).
    expect(find.text('6 GHz, ch 2'), findsOneWidget);
  });

  testWidgets('off-grid frequency is honestly rejected',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Freq -> Channel'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5187');
    await tester.pumpAndSettle();
    expect(find.text('No Wi-Fi channel'), findsOneWidget);
    // The reject stands AND carries the MikroTik-aware context line.
    expect(
      find.textContaining('MikroTik can still run this center frequency'),
      findsOneWidget,
    );
  });
}
