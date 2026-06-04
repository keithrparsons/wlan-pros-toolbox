// Content-type classification for a tool — the WORD shown on the neutral
// ContentTypeChip (GL-003 §8.17). This is a category label, NOT a verdict: it
// says what KIND of thing a row is so a reader can scan the type at a glance.
//
// The chip's color is always neutral (§8.17); only the word (and an optional
// neutral glyph) differentiates types. This file owns the id → (word, glyph)
// mapping so the category screen and the search results screen agree.

import 'package:flutter/material.dart';

import 'tool_catalog.dart';

/// A content type: its display word and an optional neutral glyph.
enum ContentType {
  table('Table', Icons.table_rows_outlined),
  card('Card', Icons.crop_portrait_outlined),
  checklist('Checklist', Icons.checklist_outlined),
  cli('CLI', Icons.terminal_outlined),
  calculator('Tool', Icons.calculate_outlined),
  diagnostic('Live', Icons.sensors_outlined),
  utility('Tool', Icons.build_outlined);

  const ContentType(this.label, this.glyph);

  /// The type word shown on the chip (e.g. "Table").
  final String label;

  /// A neutral leading glyph (tinted neutral by ContentTypeChip, never status).
  final IconData glyph;
}

/// The 10 bundled PDF "card" tool ids (rendered by PdfReferenceScreen). These
/// are the laminated cards — their content type is "Card", not "Table".
const Set<String> _pdfCardIds = <String>{
  'bubble-diagram',
  'troubleshooting-causes',
  'channel-allocations-24ghz',
  'channel-allocations-5ghz',
  'channel-allocations-6ghz',
  'mcs-index-card',
  'top-20-checklist',
  'extended-checklist',
  'extended-checklist-nonadvertised',
  'connection-checklist',
};

/// The interactive (tappable) checklist tool ids.
const Set<String> _interactiveChecklistIds = <String>{
  'checklist-ap-install',
  'checklist-client-test',
};

/// The CLI / capture reference-sheet tool ids.
const Set<String> _cliSheetIds = <String>{
  'cli-commands',
  'linux-wlan-commands',
  'wireshark-80211-filters',
};

/// Classifies a [tool] into a [ContentType] for its §8.17 chip.
///
/// Resolution order: PDF cards → interactive checklists → CLI sheets → by
/// category (quick-reference tables, rf-calculators calculators, test-network
/// live diagnostics) → utility fallback for the networking tools.
ContentType contentTypeFor(ToolEntry tool, String categoryId) {
  if (_pdfCardIds.contains(tool.id)) return ContentType.card;
  if (_interactiveChecklistIds.contains(tool.id)) return ContentType.checklist;
  if (_cliSheetIds.contains(tool.id)) return ContentType.cli;

  switch (categoryId) {
    case 'quick-reference':
      return ContentType.table;
    case 'rf-calculators':
      return ContentType.calculator;
    case 'test-network':
      return ContentType.diagnostic;
    default:
      return ContentType.utility;
  }
}
