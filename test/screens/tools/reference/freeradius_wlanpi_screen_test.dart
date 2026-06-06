// Widget tests for the FreeRADIUS on WLAN Pi how-to guide screen (v1.1).
//
// Coverage:
//  - the screen loads and renders its title + intro + credit;
//  - the prominent lab caveat banner renders its eyebrow + caveat text
//    (never color-only — the WORD carries the meaning, SC 1.4.1);
//  - the three numbered steps render their commands (scp / chmod / run);
//  - the primary download button is present and, when tapped, invokes the
//    share/save seam with the bundled script asset, the clean filename, and the
//    shell-script MIME type (the wiring contract);
//  - the inline script block drives its three explicit states from the injected
//    loader: loading (spinner) → success (the script text renders) and the
//    separate error path (honest copy, no crash);
//  - both the dark and light themes build without throwing.
//
// The script loader and the share seam are injected as fakes so the tests never
// touch a real asset bundle or a platform share channel.

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/pdf_download.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/freeradius_wlanpi_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fakeScript = '#!/bin/bash\n'
    'set -e\n'
    'echo "Installing FreeRADIUS..."\n'
    'sudo apt-get install -y freeradius freeradius-utils\n'
    'SECRET=secretwlanpros\n';

final Uint8List _fakeScriptBytes = Uint8List.fromList(utf8.encode(_fakeScript));

void main() {
  // Captures the args the screen passes to the share seam. The screen now hands
  // the seam already-decoded BYTES (not an asset path), proving the download
  // shares the exact bytes the inline view rendered.
  late List<({List<int> bytes, String filename, String mimeType})> calls;

  Future<void> fakeShare({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    ShareOrigin? shareOrigin,
  }) async {
    calls.add((bytes: bytes, filename: filename, mimeType: mimeType));
  }

  setUp(
    () => calls = <({List<int> bytes, String filename, String mimeType})>[],
  );

  // A guide screen with both seams faked; the script loader resolves
  // immediately with the fake script BYTES by default.
  Widget harness({
    Brightness brightness = Brightness.dark,
    ScriptLoader? loader,
  }) =>
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        home: FreeradiusWlanpiScreen(
          shareFn: fakeShare,
          scriptLoader: loader ?? () async => _fakeScriptBytes,
        ),
      );

  testWidgets('renders the title, intro, and credit', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('FreeRADIUS on WLAN Pi'), findsWidgets);
    // Credit line — the Ferney Munoz attribution is a hard requirement.
    expect(
      find.textContaining('Ferney Munoz'),
      findsWidgets,
    );
  });

  testWidgets('renders the prominent lab caveat (eyebrow + text, not color-only)',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('LAB / LEARNING SETUP — NOT PRODUCTION'), findsOneWidget);
    // The caveat carries its meaning in words, including the shared-secret name
    // and the "change before anything real" instruction.
    expect(find.textContaining('secretwlanpros'), findsWidgets);
    expect(
      find.textContaining('change the secret', findRichText: true),
      findsWidgets,
    );
    // A warning glyph accompanies the text (icon + text, never color alone).
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('renders the three numbered step commands', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Copy the script to the WLAN Pi'), findsOneWidget);
    expect(find.text('Make it executable'), findsOneWidget);
    expect(find.text('Run it'), findsOneWidget);

    // The command lines render (RichText, so match by substring).
    expect(
      find.textContaining('scp install_freeradius.sh', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('chmod +x install_freeradius.sh', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('./install_freeradius.sh', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('the download button is present', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Download install_freeradius.sh'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets(
      'tapping download invokes the share seam with the decoded script '
      'BYTES, clean filename, and shell-script MIME', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final Finder button = find.text('Download install_freeradius.sh');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(calls, hasLength(1));
    // The download shares the EXACT bytes the inline view rendered (the
    // inline-and-download-same-bytes invariant): the shared bytes round-trip to
    // the loaded script text.
    expect(calls.single.bytes, _fakeScriptBytes);
    expect(utf8.decode(calls.single.bytes), _fakeScript);
    expect(calls.single.filename, 'install_freeradius.sh');
    expect(calls.single.mimeType, 'text/x-shellscript');
  });

  testWidgets('the inline script renders after the loader resolves', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // The script header and the loaded body both render.
    expect(find.text('install_freeradius.sh'), findsWidgets);
    expect(
      find.textContaining('sudo apt-get install -y freeradius', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('shows a spinner while the script is still loading', (
    tester,
  ) async {
    // A loader that never completes within the test keeps the loading state.
    final Completer<Uint8List> pending = Completer<Uint8List>();
    await tester.pumpWidget(harness(loader: () => pending.future));
    await tester.pump(); // let initState's future register

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Resolve so the pending timer/future doesn't leak past the test.
    pending.complete(_fakeScriptBytes);
    await tester.pumpAndSettle();
  });

  testWidgets('shows an honest error state when the script fails to load', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(loader: () async => throw Exception('asset missing')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('The script could not be displayed here.'),
      findsOneWidget,
    );
    // The download path still works from the error state — the button remains.
    expect(find.text('Download install_freeradius.sh'), findsOneWidget);
  });

  testWidgets('builds in the light theme', (tester) async {
    await tester.pumpWidget(harness(brightness: Brightness.light));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('FreeRADIUS on WLAN Pi'), findsWidgets);
  });
}
