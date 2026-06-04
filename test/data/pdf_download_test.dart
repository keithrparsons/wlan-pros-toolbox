// Unit tests for pdfDownloadFilename — the pure, platform-free slug helper
// behind the PDF share/download action (Ticket 4).
//
// The helper turns a card title into a clean, filesystem- and
// Content-Disposition-safe download filename: `WLAN-Pros-<slug>.pdf`. These
// tests pin the exact output for the real card titles and the awkward cases
// (parens, dots, punctuation), so a future tweak to the slug rules can't
// silently produce a broken filename.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/pdf_download.dart';

void main() {
  group('pdfDownloadFilename', () {
    test('simple title slugifies to WLAN-Pros-<kebab>.pdf', () {
      expect(
        pdfDownloadFilename('Top 20 Wi-Fi Checklist'),
        'WLAN-Pros-Top-20-Wi-Fi-Checklist.pdf',
      );
    });

    test('parentheses are stripped, inner words kept', () {
      expect(
        pdfDownloadFilename('Extended Checklist (Non-Advertised Items)'),
        'WLAN-Pros-Extended-Checklist-Non-Advertised-Items.pdf',
      );
    });

    test('dots in the title collapse to hyphens', () {
      expect(
        pdfDownloadFilename('2.4 GHz Channel Allocations'),
        'WLAN-Pros-2-4-GHz-Channel-Allocations.pdf',
      );
    });

    test('the long MCS card title slugifies cleanly', () {
      expect(
        pdfDownloadFilename('Modulation and Coding Schemes (MCS Index)'),
        'WLAN-Pros-Modulation-and-Coding-Schemes-MCS-Index.pdf',
      );
    });

    test('no leading/trailing hyphens, no double hyphens', () {
      final String name = pdfDownloadFilename('  Bubble — Diagram!!  ');
      expect(name, startsWith('WLAN-Pros-'));
      expect(name, endsWith('.pdf'));
      // Strip the fixed prefix and the .pdf suffix; the slug body must contain
      // no leading/trailing hyphen and no doubled hyphen.
      final String slug = name
          .substring('WLAN-Pros-'.length, name.length - '.pdf'.length);
      expect(slug.startsWith('-'), isFalse);
      expect(slug.endsWith('-'), isFalse);
      expect(slug.contains('--'), isFalse);
    });

    test('output contains only filesystem-safe characters', () {
      for (final String title in <String>[
        'WLAN Pros Bubble Diagram',
        'Wireless LAN Troubleshooting Causes',
        '2.4 GHz Channel Allocations',
        '5 GHz Channel Allocations',
        '6 GHz Channel Allocations',
        'Modulation and Coding Schemes (MCS Index)',
        'Top 20 Wi-Fi Checklist',
        'Extended Wi-Fi Checklist',
        'Extended Checklist (Non-Advertised Items)',
        'Wi-Fi Connection Checklist',
      ]) {
        final String name = pdfDownloadFilename(title);
        // Only A-Z a-z 0-9 hyphen and the .pdf dot are permitted.
        expect(
          RegExp(r'^WLAN-Pros-[A-Za-z0-9-]+\.pdf$').hasMatch(name),
          isTrue,
          reason: 'unsafe filename for "$title": $name',
        );
      }
    });
  });
}
