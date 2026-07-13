// Vera SC 2.4.7 (Focus Visible) re-gate — the FreeRADIUS download focus state
// after the app_theme.dart elevatedButtonTheme fix (HEAD a2bb46a).
//
// Confirms, in BOTH light and dark, that a visible §8.3 keyboard focus ring
// renders on:
//   1. FreeRADIUS download button (ElevatedButton.icon).
//
// Ring spec under test (§8.3 / §8.20.3-B):
//   dark  → 2px brand lime  AppColors.primary  (#A1CC3A)
//   light → 3px darkened-lime textAccent       (#5A7A1C)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/freeradius_wlanpi_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

// Expected ring, per brightness, straight from §8.3 / §8.20.3-B.
const Color _ringDark = AppColors.primary; // #A1CC3A
const Color _ringLight = Color(0xFF5A7A1C); // darkened-lime textAccent
double _ringWidth(Brightness b) => b == Brightness.light ? 3 : 2;
Color _ringColor(Brightness b) => b == Brightness.light ? _ringLight : _ringDark;

Widget _app(Widget child, Brightness b) {
  return MaterialApp(
    theme: b == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    darkTheme: AppTheme.dark(),
    themeMode: b == Brightness.light ? ThemeMode.light : ThemeMode.dark,
    home: child,
  );
}

/// Resolves the *effective* ButtonStyle Flutter paints for an ElevatedButton —
/// the widget's own inline `style` merged onto the ambient
/// `ElevatedButtonTheme.style` — exactly as ButtonStyleButton.build does, then
/// returns the `side` it resolves for the focused state. This is the real paint
/// path: if the inline `ElevatedButton.styleFrom(...)` clobbered `side`, this
/// would surface it.
BorderSide? _focusedSideOf(WidgetTester tester, Finder buttonFinder) {
  final BuildContext ctx = tester.element(buttonFinder);
  final ElevatedButton button = tester.widget(buttonFinder);
  final ButtonStyle? themeStyle = ElevatedButtonTheme.of(ctx).style;
  final ButtonStyle? widgetStyle = button.style;
  // ButtonStyleButton merges the widget style ONTO the theme style.
  final ButtonStyle effective =
      widgetStyle?.merge(themeStyle) ?? themeStyle ?? const ButtonStyle();
  return effective.side?.resolve(<WidgetState>{WidgetState.focused});
}

void main() {
  for (final Brightness b in <Brightness>[Brightness.dark, Brightness.light]) {
    final String mode = b == Brightness.light ? 'light' : 'dark';

    group('SC 2.4.7 download/link focus ring — $mode', () {
      testWidgets(
        '1. FreeRADIUS ElevatedButton.icon paints the §8.3 ring on focus',
        (WidgetTester tester) async {
          await tester.pumpWidget(_app(const FreeradiusWlanpiScreen(), b));
          // FreeRADIUS carries an ambient animation in one mode; settle a fixed
          // span instead of pumpAndSettle (which never quiesces).
          await tester.pump(const Duration(milliseconds: 600));

          final Finder btn = find.widgetWithText(
            ElevatedButton,
            'Download install_freeradius.sh',
          );
          expect(btn, findsOneWidget,
              reason: 'FreeRADIUS download button must be present.');

          final BorderSide? side = _focusedSideOf(tester, btn);
          expect(side, isNotNull,
              reason:
                  'Effective focused-state side must be non-null — the theme '
                  'fix must survive the inline styleFrom merge.');
          expect(side!.color, _ringColor(b));
          expect(side.width, _ringWidth(b));
        },
      );
    });
  }
}
