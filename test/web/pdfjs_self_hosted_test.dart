// Guard: web/index.html must keep pdf.js SELF-HOSTED, never CDN.
//
// WHY THIS TEST EXISTS
// The bundled "PDF reference card" tools render via pdfx, which on web needs
// pdf.js. The Toolbox is offline-branded, so we ship pdf.js 4.6.82 under
// web/pdfjs/ and reference it with LOCAL relative paths from web/index.html —
// no CDN, no runtime remote fetch.
//
// THE HAZARD THIS GUARDS
// `flutter pub run pdfx:install_web` (pdfx 2.9.x) rewrites web/index.html to
// inject jsdelivr CDN <script> tags for pdfjs-dist@4.6.82, silently
// reintroducing a remote dependency and breaking the offline promise. This bit
// us once already. If anyone re-runs install_web and re-injects the CDN refs,
// THIS TEST GOES RED.
//
// WHAT IT ASSERTS
//   1. index.html references the local self-hosted engine + worker paths
//      (pdfjs/build/pdf.min.mjs and pdfjs/build/pdf.worker.mjs).
//   2. index.html contains NO remote pdf.js references — no jsdelivr / cdnjs /
//      unpkg / cdn.* hostname appears in a <script src> or worker-path string.
//      (We match real script srcs and CDN hostnames, NOT the word "cdn" in the
//      explanatory prose comment — that comment is allowed to name the hazard.)
//   3. The engine files actually exist on disk under web/pdfjs/build/.
//
// If pdfjs-dist is ever version-bumped: re-bundle web/pdfjs/, keep the local
// paths in web/index.html, and this test keeps the CDN out.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Resolve repo-relative paths. `flutter test` runs from the package root,
  // so web/ is directly reachable. Fail loudly if it isn't, so a future test
  // harness change can't make this guard silently pass.
  final File indexHtmlFile = File('web/index.html');
  final File engineFile = File('web/pdfjs/build/pdf.min.mjs');
  final File workerFile = File('web/pdfjs/build/pdf.worker.mjs');

  group('pdf.js is self-hosted (no CDN regression)', () {
    test('web/index.html exists', () {
      expect(
        indexHtmlFile.existsSync(),
        isTrue,
        reason: 'Expected web/index.html at ${indexHtmlFile.absolute.path}. '
            'Run this test from the package root.',
      );
    });

    test('index.html references the local self-hosted engine + worker', () {
      final String html = indexHtmlFile.readAsStringSync();

      // The <script src> for the engine must be the local relative path.
      expect(
        RegExp(r'''<script\s+src=["']pdfjs/build/pdf\.min\.mjs["']''')
            .hasMatch(html),
        isTrue,
        reason: 'web/index.html must load the engine from the local '
            'self-hosted path: <script src="pdfjs/build/pdf.min.mjs">. '
            'If this failed, pdfx:install_web likely clobbered index.html with '
            'CDN <script> tags — restore the local web/pdfjs/ paths.',
      );

      // The worker path must point at the local relative worker file.
      expect(
        html.contains('pdfjs/build/pdf.worker.mjs'),
        isTrue,
        reason: 'web/index.html must set workerSrc to the local self-hosted '
            "path 'pdfjs/build/pdf.worker.mjs'. If this failed, install_web "
            'likely rewrote the worker to a CDN URL — restore the local path.',
      );
    });

    test('index.html has NO remote pdf.js / CDN reference', () {
      final String html = indexHtmlFile.readAsStringSync();

      // Strip HTML comments first so the explanatory banner — which is ALLOWED
      // to name "jsdelivr", "CDN", and "pdfx:install_web" to warn future devs —
      // does not trip the guard. We only police live markup/script.
      final String live = html.replaceAll(
        RegExp(r'<!--.*?-->', dotAll: true),
        '',
      );

      // Known CDN hostnames that install_web (or a careless edit) would inject.
      // Matched as real hostnames, not the bare word "cdn" in prose.
      const List<String> cdnHosts = <String>[
        'cdn.jsdelivr.net',
        'jsdelivr',
        'cdnjs.cloudflare.com',
        'cdnjs',
        'unpkg.com',
        'unpkg',
      ];
      for (final String host in cdnHosts) {
        expect(
          live.toLowerCase().contains(host.toLowerCase()),
          isFalse,
          reason: 'web/index.html (outside comments) references a remote CDN '
              '"$host". pdf.js must stay self-hosted under web/pdfjs/. This is '
              'almost certainly the pdfx:install_web regression — re-point the '
              '<script src> and workerSrc at the local pdfjs/build/ paths.',
        );
      }

      // Defense in depth: no protocol-qualified "cdn." hostname (e.g.
      // https://cdn.example.com/...) and no remote pdfjs-dist URL of any host
      // may appear in live markup. Catches CDNs we did not enumerate above.
      expect(
        RegExp(r'''src\s*=\s*["']https?://''').hasMatch(live),
        isFalse,
        reason: 'web/index.html (outside comments) has an absolute remote '
            '<script src="http(s)://...">. The pdf.js engine and worker must '
            'load from local web/pdfjs/ paths only — no remote scripts.',
      );
      expect(
        RegExp(r'''https?://[^"'\s]*pdfjs''', caseSensitive: false)
            .hasMatch(live),
        isFalse,
        reason: 'web/index.html (outside comments) has a remote pdfjs URL. '
            'pdf.js must stay self-hosted under web/pdfjs/.',
      );
    });

    test('the self-hosted engine + worker files exist on disk', () {
      expect(
        engineFile.existsSync(),
        isTrue,
        reason: 'Missing self-hosted engine at '
            '${engineFile.absolute.path}. web/index.html points at '
            'pdfjs/build/pdf.min.mjs but the file is gone — re-bundle '
            'web/pdfjs/ from pdfjs-dist@4.6.82.',
      );
      expect(
        workerFile.existsSync(),
        isTrue,
        reason: 'Missing self-hosted worker at '
            '${workerFile.absolute.path}. web/index.html points at '
            'pdfjs/build/pdf.worker.mjs but the file is gone — re-bundle '
            'web/pdfjs/ from pdfjs-dist@4.6.82.',
      );

      // A clobbered/truncated engine is as bad as a missing one. Sanity-check
      // the files carry real bytes (the 4.6.82 build is ~330 KB / ~2.1 MB).
      expect(
        engineFile.lengthSync(),
        greaterThan(10000),
        reason: 'web/pdfjs/build/pdf.min.mjs is suspiciously small — '
            'it may be truncated or a placeholder. Re-bundle pdfjs-dist@4.6.82.',
      );
      expect(
        workerFile.lengthSync(),
        greaterThan(10000),
        reason: 'web/pdfjs/build/pdf.worker.mjs is suspiciously small — '
            'it may be truncated or a placeholder. Re-bundle pdfjs-dist@4.6.82.',
      );
    });
  });
}
