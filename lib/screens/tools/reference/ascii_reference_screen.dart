// ASCII / Hex / Binary — a read-only reference for reading bytes, decoding hex
// dumps, and interpreting protocol fields.
//
// Data is reproduced verbatim from the team source of truth:
//   Deliverables/2026-05-31-ascii-hex-binary-reference/ascii-hex-binary-reference.json
//   (+ the .md layout guide). ASCII values per RFC 20 (US-ASCII); high-range
// guidance per ISO-8859-1, Windows-1252, and the Unicode/UTF-8 spec. The 128
// rows and every supplementary table are embedded as compile-time consts and
// invent nothing — numeric columns are the canonical dec/hex/oct/bin, printable
// glyphs are chr(n), control rows carry their mnemonic.
//
// States (SOP-007 §5):
//  - success → the how-to-read card, the control/printable tables, and the
//    supplementary quick-reference cards render. This is the default; the data
//    is a bundled const so it is always present.
//  - empty   → reachable only through the free-text filter: a query matching no
//    ASCII row yields an honest "no match" card, never a fabricated row. The
//    supplementary cards stay visible (they are not filtered — they are the
//    quick-reference an engineer scans regardless of the character query).
//  - loading / error → none. There is no async load, no network, and nothing to
//    parse at runtime, so a spinner or error surface would be theatre. Omitted
//    deliberately, matching the other reference screens. No NetworkUnavailable
//    view — fully offline on every platform (GL-008 does not apply: nothing to
//    shell out to, nothing to fabricate).
//
// Font convention (GL-003 §8.5): the fixed-width IDENTIFIER columns (dec / hex /
// oct / bin) render in Roboto Mono (AppMonoText.robotoMono) — the same choice
// the identifier columns elsewhere in the app use — so the binary octets and
// hex pairs align cleanly and read as data, not prose. The printable glyph also
// uses Roboto Mono so a lone `l`/`I`/`O`/`0` is unambiguous. Descriptions are
// regular sans (the §3 label scale). Inline code fragments inside descriptions
// (e.g. `\0`, `0x35`) keep the sans label run — they are short and already in a
// description clause, so a second mono register there would over-decorate.
//
// Wide-table decision (320px): the natural table here is six columns (Dec / Hex
// / Oct / Bin / Char / Description). A single horizontal row of six cells
// overflows a 320px phone. Rather than force a horizontal scroll on a 128-row
// table (awkward to scan), each row is laid out the way db_reference lays out
// its dB rows: the identifier columns sit on a fixed-width top line — Dec (38),
// Hex (40), Oct (44), Bin (mono 8-bit, ~92), Char/mnemonic (52) — and the
// human-readable description wraps on the line beneath. The four numeric gutters
// are width-bounded boxes, so they never push the row past the viewport; the
// description is the only flexible element and it wraps. The narrow
// supplementary place-value tables (nibble→hex, powers of two, hex place values)
// are genuinely tabular and short, so they use a horizontally-scrollable
// DataTable, matching mcs_index — the scroll never triggers at phone width
// because the content is narrow, but it is there as the overflow safety valve.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../labeled_field.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// Whether an ASCII row is a non-printing control code or a printable glyph.
enum AsciiCategory { control, printable }

/// One ASCII code point: its four numeric representations plus either a control
/// mnemonic or a printable glyph, and a plain-language description.
///
/// Mirrors the JSON `ascii[]` schema verbatim
/// ({ dec, hex, oct, bin, category, char?, mnemonic?, description }). Numeric
/// columns are the canonical values; [glyph] is chr(dec) for printable rows and
/// null for control rows; [mnemonic] is the abbreviation (NUL, LF, …) for
/// control rows and null for printable rows.
@immutable
class AsciiEntry {
  const AsciiEntry({
    required this.dec,
    required this.hex,
    required this.oct,
    required this.bin,
    required this.category,
    required this.description,
    this.glyph,
    this.mnemonic,
  }) : assert(
         (category == AsciiCategory.control) == (mnemonic != null),
         'control rows carry a mnemonic; printable rows do not',
       );

  /// Decimal value (0–127).
  final int dec;

  /// Two-digit uppercase hex (00–7F).
  final String hex;

  /// Three-digit octal (000–177).
  final String oct;

  /// 8-bit binary (high bit always 0 for standard ASCII).
  final String bin;

  /// Control vs printable.
  final AsciiCategory category;

  /// Meaning / notes, verbatim from the source.
  final String description;

  /// The printed character for printable rows; null for control rows.
  final String? glyph;

  /// The control mnemonic (e.g. `LF`) for control rows; null for printable.
  final String? mnemonic;

  /// The short token shown in the Char column: the mnemonic for control rows,
  /// the glyph for printable rows. Space is shown as the explicit token `SP`
  /// so an empty-looking cell is never mistaken for a missing value.
  String get charToken {
    if (category == AsciiCategory.control) return mnemonic!;
    if (glyph == ' ') return 'SP';
    return glyph!;
  }

  /// True when this row's match string contains the (already-lower-cased)
  /// query. Matches across every column a user might scan by: decimal, hex
  /// (with and without a `0x` prefix), octal, binary, the glyph/mnemonic, and
  /// the description. An empty query matches everything.
  bool matches(String q) {
    if (q.isEmpty) return true;
    if (dec.toString() == q || dec.toString().contains(q)) return true;
    final String h = hex.toLowerCase();
    if (h == q || h.contains(q) || '0x$h'.contains(q)) return true;
    if (oct.contains(q)) return true;
    if (bin.contains(q)) return true;
    if (mnemonic != null && mnemonic!.toLowerCase().contains(q)) return true;
    if (glyph != null && glyph!.toLowerCase() == q) return true;
    return description.toLowerCase().contains(q);
  }
}

/// A boundary block worth memorizing (digits, A–Z, a–z, space).
@immutable
class RangeBoundary {
  const RangeBoundary({
    required this.block,
    required this.decRange,
    required this.hexRange,
    required this.note,
  });

  final String block;
  final String decRange;
  final String hexRange;
  final String note;
}

/// One nibble → hex digit mapping (4-bit binary to a single hex character).
@immutable
class NibbleHex {
  const NibbleHex(this.bin, this.hex, this.dec);
  final String bin;
  final String hex;
  final int dec;
}

/// A power of two: the exponent and its value (value pre-formatted with the
/// thousands separators the source uses).
@immutable
class PowerOfTwo {
  const PowerOfTwo(this.exp, this.value);
  final int exp;
  final String value;
}

/// A hex place value: the position label (16^n) and its decimal weight.
@immutable
class HexPlaceValue {
  const HexPlaceValue(this.position, this.weight);
  final String position;
  final String weight;
}

/// One high-range encoding and its honest caveat.
@immutable
class HighRangeEncoding {
  const HighRangeEncoding(this.name, this.note);
  final String name;
  final String note;
}

/// ASCII / Hex / Binary reference screen (route `/tools/ascii-reference`).
class AsciiReferenceScreen extends StatefulWidget {
  const AsciiReferenceScreen({super.key});

  /// Catalog id (kebab-case) → resolves the optional concept graphic. Larry
  /// registers the matching catalog entry + icon separately; until then
  /// [ConceptGraphicBand] degrades to nothing.
  static const String toolId = 'ascii-reference';

  // ─── ASCII table (verbatim port of the JSON `ascii[]`) ───────────────────────

  /// The 33 control codes: 0–31 plus DEL (127). Public + const so tests assert
  /// against the same single source the UI renders.
  static const List<AsciiEntry> controlCodes = <AsciiEntry>[
    AsciiEntry(
      dec: 0,
      hex: '00',
      oct: '000',
      bin: '00000000',
      category: AsciiCategory.control,
      mnemonic: 'NUL',
      description: r'Null. String terminator in C. \0',
    ),
    AsciiEntry(
      dec: 1,
      hex: '01',
      oct: '001',
      bin: '00000001',
      category: AsciiCategory.control,
      mnemonic: 'SOH',
      description: 'Start of Heading',
    ),
    AsciiEntry(
      dec: 2,
      hex: '02',
      oct: '002',
      bin: '00000010',
      category: AsciiCategory.control,
      mnemonic: 'STX',
      description: 'Start of Text',
    ),
    AsciiEntry(
      dec: 3,
      hex: '03',
      oct: '003',
      bin: '00000011',
      category: AsciiCategory.control,
      mnemonic: 'ETX',
      description: 'End of Text. Ctrl-C interrupt',
    ),
    AsciiEntry(
      dec: 4,
      hex: '04',
      oct: '004',
      bin: '00000100',
      category: AsciiCategory.control,
      mnemonic: 'EOT',
      description: 'End of Transmission. Ctrl-D EOF',
    ),
    AsciiEntry(
      dec: 5,
      hex: '05',
      oct: '005',
      bin: '00000101',
      category: AsciiCategory.control,
      mnemonic: 'ENQ',
      description: 'Enquiry',
    ),
    AsciiEntry(
      dec: 6,
      hex: '06',
      oct: '006',
      bin: '00000110',
      category: AsciiCategory.control,
      mnemonic: 'ACK',
      description: 'Acknowledge',
    ),
    AsciiEntry(
      dec: 7,
      hex: '07',
      oct: '007',
      bin: '00000111',
      category: AsciiCategory.control,
      mnemonic: 'BEL',
      description: r'Bell / alert. \a',
    ),
    AsciiEntry(
      dec: 8,
      hex: '08',
      oct: '010',
      bin: '00001000',
      category: AsciiCategory.control,
      mnemonic: 'BS',
      description: r'Backspace. \b',
    ),
    AsciiEntry(
      dec: 9,
      hex: '09',
      oct: '011',
      bin: '00001001',
      category: AsciiCategory.control,
      mnemonic: 'HT',
      description: r'Horizontal Tab. \t',
    ),
    AsciiEntry(
      dec: 10,
      hex: '0A',
      oct: '012',
      bin: '00001010',
      category: AsciiCategory.control,
      mnemonic: 'LF',
      description: r'Line Feed / newline. \n',
    ),
    AsciiEntry(
      dec: 11,
      hex: '0B',
      oct: '013',
      bin: '00001011',
      category: AsciiCategory.control,
      mnemonic: 'VT',
      description: r'Vertical Tab. \v',
    ),
    AsciiEntry(
      dec: 12,
      hex: '0C',
      oct: '014',
      bin: '00001100',
      category: AsciiCategory.control,
      mnemonic: 'FF',
      description: r'Form Feed. \f',
    ),
    AsciiEntry(
      dec: 13,
      hex: '0D',
      oct: '015',
      bin: '00001101',
      category: AsciiCategory.control,
      mnemonic: 'CR',
      description: r'Carriage Return. \r',
    ),
    AsciiEntry(
      dec: 14,
      hex: '0E',
      oct: '016',
      bin: '00001110',
      category: AsciiCategory.control,
      mnemonic: 'SO',
      description: 'Shift Out',
    ),
    AsciiEntry(
      dec: 15,
      hex: '0F',
      oct: '017',
      bin: '00001111',
      category: AsciiCategory.control,
      mnemonic: 'SI',
      description: 'Shift In',
    ),
    AsciiEntry(
      dec: 16,
      hex: '10',
      oct: '020',
      bin: '00010000',
      category: AsciiCategory.control,
      mnemonic: 'DLE',
      description: 'Data Link Escape',
    ),
    AsciiEntry(
      dec: 17,
      hex: '11',
      oct: '021',
      bin: '00010001',
      category: AsciiCategory.control,
      mnemonic: 'DC1',
      description: 'Device Control 1 (XON, resume flow)',
    ),
    AsciiEntry(
      dec: 18,
      hex: '12',
      oct: '022',
      bin: '00010010',
      category: AsciiCategory.control,
      mnemonic: 'DC2',
      description: 'Device Control 2',
    ),
    AsciiEntry(
      dec: 19,
      hex: '13',
      oct: '023',
      bin: '00010011',
      category: AsciiCategory.control,
      mnemonic: 'DC3',
      description: 'Device Control 3 (XOFF, pause flow)',
    ),
    AsciiEntry(
      dec: 20,
      hex: '14',
      oct: '024',
      bin: '00010100',
      category: AsciiCategory.control,
      mnemonic: 'DC4',
      description: 'Device Control 4',
    ),
    AsciiEntry(
      dec: 21,
      hex: '15',
      oct: '025',
      bin: '00010101',
      category: AsciiCategory.control,
      mnemonic: 'NAK',
      description: 'Negative Acknowledge',
    ),
    AsciiEntry(
      dec: 22,
      hex: '16',
      oct: '026',
      bin: '00010110',
      category: AsciiCategory.control,
      mnemonic: 'SYN',
      description: 'Synchronous Idle',
    ),
    AsciiEntry(
      dec: 23,
      hex: '17',
      oct: '027',
      bin: '00010111',
      category: AsciiCategory.control,
      mnemonic: 'ETB',
      description: 'End of Transmission Block',
    ),
    AsciiEntry(
      dec: 24,
      hex: '18',
      oct: '030',
      bin: '00011000',
      category: AsciiCategory.control,
      mnemonic: 'CAN',
      description: 'Cancel',
    ),
    AsciiEntry(
      dec: 25,
      hex: '19',
      oct: '031',
      bin: '00011001',
      category: AsciiCategory.control,
      mnemonic: 'EM',
      description: 'End of Medium',
    ),
    AsciiEntry(
      dec: 26,
      hex: '1A',
      oct: '032',
      bin: '00011010',
      category: AsciiCategory.control,
      mnemonic: 'SUB',
      description: 'Substitute. Ctrl-Z',
    ),
    AsciiEntry(
      dec: 27,
      hex: '1B',
      oct: '033',
      bin: '00011011',
      category: AsciiCategory.control,
      mnemonic: 'ESC',
      description: 'Escape. Leads ANSI escape sequences',
    ),
    AsciiEntry(
      dec: 28,
      hex: '1C',
      oct: '034',
      bin: '00011100',
      category: AsciiCategory.control,
      mnemonic: 'FS',
      description: 'File Separator',
    ),
    AsciiEntry(
      dec: 29,
      hex: '1D',
      oct: '035',
      bin: '00011101',
      category: AsciiCategory.control,
      mnemonic: 'GS',
      description: 'Group Separator',
    ),
    AsciiEntry(
      dec: 30,
      hex: '1E',
      oct: '036',
      bin: '00011110',
      category: AsciiCategory.control,
      mnemonic: 'RS',
      description: 'Record Separator',
    ),
    AsciiEntry(
      dec: 31,
      hex: '1F',
      oct: '037',
      bin: '00011111',
      category: AsciiCategory.control,
      mnemonic: 'US',
      description: 'Unit Separator',
    ),
    AsciiEntry(
      dec: 127,
      hex: '7F',
      oct: '177',
      bin: '01111111',
      category: AsciiCategory.control,
      mnemonic: 'DEL',
      description:
          'Delete. Not strictly a control code; erased tape by punching all 7 holes',
    ),
  ];

  /// The 95 printable characters: space (32) through tilde (126).
  static const List<AsciiEntry> printableChars = <AsciiEntry>[
    AsciiEntry(
      dec: 32,
      hex: '20',
      oct: '040',
      bin: '00100000',
      category: AsciiCategory.printable,
      glyph: ' ',
      description: 'Space',
    ),
    AsciiEntry(
      dec: 33,
      hex: '21',
      oct: '041',
      bin: '00100001',
      category: AsciiCategory.printable,
      glyph: '!',
      description: 'Exclamation mark',
    ),
    AsciiEntry(
      dec: 34,
      hex: '22',
      oct: '042',
      bin: '00100010',
      category: AsciiCategory.printable,
      glyph: '"',
      description: 'Double quote',
    ),
    AsciiEntry(
      dec: 35,
      hex: '23',
      oct: '043',
      bin: '00100011',
      category: AsciiCategory.printable,
      glyph: '#',
      description: 'Number sign / hash',
    ),
    AsciiEntry(
      dec: 36,
      hex: '24',
      oct: '044',
      bin: '00100100',
      category: AsciiCategory.printable,
      glyph: r'$',
      description: 'Dollar sign',
    ),
    AsciiEntry(
      dec: 37,
      hex: '25',
      oct: '045',
      bin: '00100101',
      category: AsciiCategory.printable,
      glyph: '%',
      description: 'Percent',
    ),
    AsciiEntry(
      dec: 38,
      hex: '26',
      oct: '046',
      bin: '00100110',
      category: AsciiCategory.printable,
      glyph: '&',
      description: 'Ampersand',
    ),
    AsciiEntry(
      dec: 39,
      hex: '27',
      oct: '047',
      bin: '00100111',
      category: AsciiCategory.printable,
      glyph: "'",
      description: 'Single quote / apostrophe',
    ),
    AsciiEntry(
      dec: 40,
      hex: '28',
      oct: '050',
      bin: '00101000',
      category: AsciiCategory.printable,
      glyph: '(',
      description: 'Left parenthesis',
    ),
    AsciiEntry(
      dec: 41,
      hex: '29',
      oct: '051',
      bin: '00101001',
      category: AsciiCategory.printable,
      glyph: ')',
      description: 'Right parenthesis',
    ),
    AsciiEntry(
      dec: 42,
      hex: '2A',
      oct: '052',
      bin: '00101010',
      category: AsciiCategory.printable,
      glyph: '*',
      description: 'Asterisk',
    ),
    AsciiEntry(
      dec: 43,
      hex: '2B',
      oct: '053',
      bin: '00101011',
      category: AsciiCategory.printable,
      glyph: '+',
      description: 'Plus',
    ),
    AsciiEntry(
      dec: 44,
      hex: '2C',
      oct: '054',
      bin: '00101100',
      category: AsciiCategory.printable,
      glyph: ',',
      description: 'Comma',
    ),
    AsciiEntry(
      dec: 45,
      hex: '2D',
      oct: '055',
      bin: '00101101',
      category: AsciiCategory.printable,
      glyph: '-',
      description: 'Hyphen / minus',
    ),
    AsciiEntry(
      dec: 46,
      hex: '2E',
      oct: '056',
      bin: '00101110',
      category: AsciiCategory.printable,
      glyph: '.',
      description: 'Period / dot',
    ),
    AsciiEntry(
      dec: 47,
      hex: '2F',
      oct: '057',
      bin: '00101111',
      category: AsciiCategory.printable,
      glyph: '/',
      description: 'Forward slash',
    ),
    AsciiEntry(
      dec: 48,
      hex: '30',
      oct: '060',
      bin: '00110000',
      category: AsciiCategory.printable,
      glyph: '0',
      description: 'Digit zero',
    ),
    AsciiEntry(
      dec: 49,
      hex: '31',
      oct: '061',
      bin: '00110001',
      category: AsciiCategory.printable,
      glyph: '1',
      description: 'Digit one',
    ),
    AsciiEntry(
      dec: 50,
      hex: '32',
      oct: '062',
      bin: '00110010',
      category: AsciiCategory.printable,
      glyph: '2',
      description: 'Digit two',
    ),
    AsciiEntry(
      dec: 51,
      hex: '33',
      oct: '063',
      bin: '00110011',
      category: AsciiCategory.printable,
      glyph: '3',
      description: 'Digit three',
    ),
    AsciiEntry(
      dec: 52,
      hex: '34',
      oct: '064',
      bin: '00110100',
      category: AsciiCategory.printable,
      glyph: '4',
      description: 'Digit four',
    ),
    AsciiEntry(
      dec: 53,
      hex: '35',
      oct: '065',
      bin: '00110101',
      category: AsciiCategory.printable,
      glyph: '5',
      description: 'Digit five',
    ),
    AsciiEntry(
      dec: 54,
      hex: '36',
      oct: '066',
      bin: '00110110',
      category: AsciiCategory.printable,
      glyph: '6',
      description: 'Digit six',
    ),
    AsciiEntry(
      dec: 55,
      hex: '37',
      oct: '067',
      bin: '00110111',
      category: AsciiCategory.printable,
      glyph: '7',
      description: 'Digit seven',
    ),
    AsciiEntry(
      dec: 56,
      hex: '38',
      oct: '070',
      bin: '00111000',
      category: AsciiCategory.printable,
      glyph: '8',
      description: 'Digit eight',
    ),
    AsciiEntry(
      dec: 57,
      hex: '39',
      oct: '071',
      bin: '00111001',
      category: AsciiCategory.printable,
      glyph: '9',
      description: 'Digit nine',
    ),
    AsciiEntry(
      dec: 58,
      hex: '3A',
      oct: '072',
      bin: '00111010',
      category: AsciiCategory.printable,
      glyph: ':',
      description: 'Colon',
    ),
    AsciiEntry(
      dec: 59,
      hex: '3B',
      oct: '073',
      bin: '00111011',
      category: AsciiCategory.printable,
      glyph: ';',
      description: 'Semicolon',
    ),
    AsciiEntry(
      dec: 60,
      hex: '3C',
      oct: '074',
      bin: '00111100',
      category: AsciiCategory.printable,
      glyph: '<',
      description: 'Less than',
    ),
    AsciiEntry(
      dec: 61,
      hex: '3D',
      oct: '075',
      bin: '00111101',
      category: AsciiCategory.printable,
      glyph: '=',
      description: 'Equals',
    ),
    AsciiEntry(
      dec: 62,
      hex: '3E',
      oct: '076',
      bin: '00111110',
      category: AsciiCategory.printable,
      glyph: '>',
      description: 'Greater than',
    ),
    AsciiEntry(
      dec: 63,
      hex: '3F',
      oct: '077',
      bin: '00111111',
      category: AsciiCategory.printable,
      glyph: '?',
      description: 'Question mark',
    ),
    AsciiEntry(
      dec: 64,
      hex: '40',
      oct: '100',
      bin: '01000000',
      category: AsciiCategory.printable,
      glyph: '@',
      description: 'At sign',
    ),
    AsciiEntry(
      dec: 65,
      hex: '41',
      oct: '101',
      bin: '01000001',
      category: AsciiCategory.printable,
      glyph: 'A',
      description: 'Uppercase A',
    ),
    AsciiEntry(
      dec: 66,
      hex: '42',
      oct: '102',
      bin: '01000010',
      category: AsciiCategory.printable,
      glyph: 'B',
      description: 'Uppercase B',
    ),
    AsciiEntry(
      dec: 67,
      hex: '43',
      oct: '103',
      bin: '01000011',
      category: AsciiCategory.printable,
      glyph: 'C',
      description: 'Uppercase C',
    ),
    AsciiEntry(
      dec: 68,
      hex: '44',
      oct: '104',
      bin: '01000100',
      category: AsciiCategory.printable,
      glyph: 'D',
      description: 'Uppercase D',
    ),
    AsciiEntry(
      dec: 69,
      hex: '45',
      oct: '105',
      bin: '01000101',
      category: AsciiCategory.printable,
      glyph: 'E',
      description: 'Uppercase E',
    ),
    AsciiEntry(
      dec: 70,
      hex: '46',
      oct: '106',
      bin: '01000110',
      category: AsciiCategory.printable,
      glyph: 'F',
      description: 'Uppercase F',
    ),
    AsciiEntry(
      dec: 71,
      hex: '47',
      oct: '107',
      bin: '01000111',
      category: AsciiCategory.printable,
      glyph: 'G',
      description: 'Uppercase G',
    ),
    AsciiEntry(
      dec: 72,
      hex: '48',
      oct: '110',
      bin: '01001000',
      category: AsciiCategory.printable,
      glyph: 'H',
      description: 'Uppercase H',
    ),
    AsciiEntry(
      dec: 73,
      hex: '49',
      oct: '111',
      bin: '01001001',
      category: AsciiCategory.printable,
      glyph: 'I',
      description: 'Uppercase I',
    ),
    AsciiEntry(
      dec: 74,
      hex: '4A',
      oct: '112',
      bin: '01001010',
      category: AsciiCategory.printable,
      glyph: 'J',
      description: 'Uppercase J',
    ),
    AsciiEntry(
      dec: 75,
      hex: '4B',
      oct: '113',
      bin: '01001011',
      category: AsciiCategory.printable,
      glyph: 'K',
      description: 'Uppercase K',
    ),
    AsciiEntry(
      dec: 76,
      hex: '4C',
      oct: '114',
      bin: '01001100',
      category: AsciiCategory.printable,
      glyph: 'L',
      description: 'Uppercase L',
    ),
    AsciiEntry(
      dec: 77,
      hex: '4D',
      oct: '115',
      bin: '01001101',
      category: AsciiCategory.printable,
      glyph: 'M',
      description: 'Uppercase M',
    ),
    AsciiEntry(
      dec: 78,
      hex: '4E',
      oct: '116',
      bin: '01001110',
      category: AsciiCategory.printable,
      glyph: 'N',
      description: 'Uppercase N',
    ),
    AsciiEntry(
      dec: 79,
      hex: '4F',
      oct: '117',
      bin: '01001111',
      category: AsciiCategory.printable,
      glyph: 'O',
      description: 'Uppercase O',
    ),
    AsciiEntry(
      dec: 80,
      hex: '50',
      oct: '120',
      bin: '01010000',
      category: AsciiCategory.printable,
      glyph: 'P',
      description: 'Uppercase P',
    ),
    AsciiEntry(
      dec: 81,
      hex: '51',
      oct: '121',
      bin: '01010001',
      category: AsciiCategory.printable,
      glyph: 'Q',
      description: 'Uppercase Q',
    ),
    AsciiEntry(
      dec: 82,
      hex: '52',
      oct: '122',
      bin: '01010010',
      category: AsciiCategory.printable,
      glyph: 'R',
      description: 'Uppercase R',
    ),
    AsciiEntry(
      dec: 83,
      hex: '53',
      oct: '123',
      bin: '01010011',
      category: AsciiCategory.printable,
      glyph: 'S',
      description: 'Uppercase S',
    ),
    AsciiEntry(
      dec: 84,
      hex: '54',
      oct: '124',
      bin: '01010100',
      category: AsciiCategory.printable,
      glyph: 'T',
      description: 'Uppercase T',
    ),
    AsciiEntry(
      dec: 85,
      hex: '55',
      oct: '125',
      bin: '01010101',
      category: AsciiCategory.printable,
      glyph: 'U',
      description: 'Uppercase U',
    ),
    AsciiEntry(
      dec: 86,
      hex: '56',
      oct: '126',
      bin: '01010110',
      category: AsciiCategory.printable,
      glyph: 'V',
      description: 'Uppercase V',
    ),
    AsciiEntry(
      dec: 87,
      hex: '57',
      oct: '127',
      bin: '01010111',
      category: AsciiCategory.printable,
      glyph: 'W',
      description: 'Uppercase W',
    ),
    AsciiEntry(
      dec: 88,
      hex: '58',
      oct: '130',
      bin: '01011000',
      category: AsciiCategory.printable,
      glyph: 'X',
      description: 'Uppercase X',
    ),
    AsciiEntry(
      dec: 89,
      hex: '59',
      oct: '131',
      bin: '01011001',
      category: AsciiCategory.printable,
      glyph: 'Y',
      description: 'Uppercase Y',
    ),
    AsciiEntry(
      dec: 90,
      hex: '5A',
      oct: '132',
      bin: '01011010',
      category: AsciiCategory.printable,
      glyph: 'Z',
      description: 'Uppercase Z',
    ),
    AsciiEntry(
      dec: 91,
      hex: '5B',
      oct: '133',
      bin: '01011011',
      category: AsciiCategory.printable,
      glyph: '[',
      description: 'Left square bracket',
    ),
    AsciiEntry(
      dec: 92,
      hex: '5C',
      oct: '134',
      bin: '01011100',
      category: AsciiCategory.printable,
      glyph: '\\',
      description: 'Backslash',
    ),
    AsciiEntry(
      dec: 93,
      hex: '5D',
      oct: '135',
      bin: '01011101',
      category: AsciiCategory.printable,
      glyph: ']',
      description: 'Right square bracket',
    ),
    AsciiEntry(
      dec: 94,
      hex: '5E',
      oct: '136',
      bin: '01011110',
      category: AsciiCategory.printable,
      glyph: '^',
      description: 'Caret / circumflex',
    ),
    AsciiEntry(
      dec: 95,
      hex: '5F',
      oct: '137',
      bin: '01011111',
      category: AsciiCategory.printable,
      glyph: '_',
      description: 'Underscore',
    ),
    AsciiEntry(
      dec: 96,
      hex: '60',
      oct: '140',
      bin: '01100000',
      category: AsciiCategory.printable,
      glyph: '`',
      description: 'Backtick / grave accent',
    ),
    AsciiEntry(
      dec: 97,
      hex: '61',
      oct: '141',
      bin: '01100001',
      category: AsciiCategory.printable,
      glyph: 'a',
      description: 'Lowercase a',
    ),
    AsciiEntry(
      dec: 98,
      hex: '62',
      oct: '142',
      bin: '01100010',
      category: AsciiCategory.printable,
      glyph: 'b',
      description: 'Lowercase b',
    ),
    AsciiEntry(
      dec: 99,
      hex: '63',
      oct: '143',
      bin: '01100011',
      category: AsciiCategory.printable,
      glyph: 'c',
      description: 'Lowercase c',
    ),
    AsciiEntry(
      dec: 100,
      hex: '64',
      oct: '144',
      bin: '01100100',
      category: AsciiCategory.printable,
      glyph: 'd',
      description: 'Lowercase d',
    ),
    AsciiEntry(
      dec: 101,
      hex: '65',
      oct: '145',
      bin: '01100101',
      category: AsciiCategory.printable,
      glyph: 'e',
      description: 'Lowercase e',
    ),
    AsciiEntry(
      dec: 102,
      hex: '66',
      oct: '146',
      bin: '01100110',
      category: AsciiCategory.printable,
      glyph: 'f',
      description: 'Lowercase f',
    ),
    AsciiEntry(
      dec: 103,
      hex: '67',
      oct: '147',
      bin: '01100111',
      category: AsciiCategory.printable,
      glyph: 'g',
      description: 'Lowercase g',
    ),
    AsciiEntry(
      dec: 104,
      hex: '68',
      oct: '150',
      bin: '01101000',
      category: AsciiCategory.printable,
      glyph: 'h',
      description: 'Lowercase h',
    ),
    AsciiEntry(
      dec: 105,
      hex: '69',
      oct: '151',
      bin: '01101001',
      category: AsciiCategory.printable,
      glyph: 'i',
      description: 'Lowercase i',
    ),
    AsciiEntry(
      dec: 106,
      hex: '6A',
      oct: '152',
      bin: '01101010',
      category: AsciiCategory.printable,
      glyph: 'j',
      description: 'Lowercase j',
    ),
    AsciiEntry(
      dec: 107,
      hex: '6B',
      oct: '153',
      bin: '01101011',
      category: AsciiCategory.printable,
      glyph: 'k',
      description: 'Lowercase k',
    ),
    AsciiEntry(
      dec: 108,
      hex: '6C',
      oct: '154',
      bin: '01101100',
      category: AsciiCategory.printable,
      glyph: 'l',
      description: 'Lowercase l',
    ),
    AsciiEntry(
      dec: 109,
      hex: '6D',
      oct: '155',
      bin: '01101101',
      category: AsciiCategory.printable,
      glyph: 'm',
      description: 'Lowercase m',
    ),
    AsciiEntry(
      dec: 110,
      hex: '6E',
      oct: '156',
      bin: '01101110',
      category: AsciiCategory.printable,
      glyph: 'n',
      description: 'Lowercase n',
    ),
    AsciiEntry(
      dec: 111,
      hex: '6F',
      oct: '157',
      bin: '01101111',
      category: AsciiCategory.printable,
      glyph: 'o',
      description: 'Lowercase o',
    ),
    AsciiEntry(
      dec: 112,
      hex: '70',
      oct: '160',
      bin: '01110000',
      category: AsciiCategory.printable,
      glyph: 'p',
      description: 'Lowercase p',
    ),
    AsciiEntry(
      dec: 113,
      hex: '71',
      oct: '161',
      bin: '01110001',
      category: AsciiCategory.printable,
      glyph: 'q',
      description: 'Lowercase q',
    ),
    AsciiEntry(
      dec: 114,
      hex: '72',
      oct: '162',
      bin: '01110010',
      category: AsciiCategory.printable,
      glyph: 'r',
      description: 'Lowercase r',
    ),
    AsciiEntry(
      dec: 115,
      hex: '73',
      oct: '163',
      bin: '01110011',
      category: AsciiCategory.printable,
      glyph: 's',
      description: 'Lowercase s',
    ),
    AsciiEntry(
      dec: 116,
      hex: '74',
      oct: '164',
      bin: '01110100',
      category: AsciiCategory.printable,
      glyph: 't',
      description: 'Lowercase t',
    ),
    AsciiEntry(
      dec: 117,
      hex: '75',
      oct: '165',
      bin: '01110101',
      category: AsciiCategory.printable,
      glyph: 'u',
      description: 'Lowercase u',
    ),
    AsciiEntry(
      dec: 118,
      hex: '76',
      oct: '166',
      bin: '01110110',
      category: AsciiCategory.printable,
      glyph: 'v',
      description: 'Lowercase v',
    ),
    AsciiEntry(
      dec: 119,
      hex: '77',
      oct: '167',
      bin: '01110111',
      category: AsciiCategory.printable,
      glyph: 'w',
      description: 'Lowercase w',
    ),
    AsciiEntry(
      dec: 120,
      hex: '78',
      oct: '170',
      bin: '01111000',
      category: AsciiCategory.printable,
      glyph: 'x',
      description: 'Lowercase x',
    ),
    AsciiEntry(
      dec: 121,
      hex: '79',
      oct: '171',
      bin: '01111001',
      category: AsciiCategory.printable,
      glyph: 'y',
      description: 'Lowercase y',
    ),
    AsciiEntry(
      dec: 122,
      hex: '7A',
      oct: '172',
      bin: '01111010',
      category: AsciiCategory.printable,
      glyph: 'z',
      description: 'Lowercase z',
    ),
    AsciiEntry(
      dec: 123,
      hex: '7B',
      oct: '173',
      bin: '01111011',
      category: AsciiCategory.printable,
      glyph: '{',
      description: 'Left curly brace',
    ),
    AsciiEntry(
      dec: 124,
      hex: '7C',
      oct: '174',
      bin: '01111100',
      category: AsciiCategory.printable,
      glyph: '|',
      description: 'Vertical bar / pipe',
    ),
    AsciiEntry(
      dec: 125,
      hex: '7D',
      oct: '175',
      bin: '01111101',
      category: AsciiCategory.printable,
      glyph: '}',
      description: 'Right curly brace',
    ),
    AsciiEntry(
      dec: 126,
      hex: '7E',
      oct: '176',
      bin: '01111110',
      category: AsciiCategory.printable,
      glyph: '~',
      description: 'Tilde',
    ),
  ];

  /// All 128 rows in code-point order (control 0–31, printable 32–126, DEL 127).
  /// DEL sorts last by category in the source layout but at code point 127; this
  /// list re-orders to numeric order for any caller that wants it. The UI
  /// renders the two category groups separately (per the .md layout).
  static List<AsciiEntry> get allByCodePoint {
    final List<AsciiEntry> all = <AsciiEntry>[
      ...controlCodes,
      ...printableChars,
    ]..sort((AsciiEntry a, AsciiEntry b) => a.dec.compareTo(b.dec));
    return all;
  }

  // ─── Supplementary quick-reference sections (verbatim port of the JSON) ──────

  /// Range boundaries worth memorizing (JSON `rangeBoundaries`).
  static const List<RangeBoundary> rangeBoundaries = <RangeBoundary>[
    RangeBoundary(
      block: 'Digits 0–9',
      decRange: '48–57',
      hexRange: '0x30–0x39',
      note:
          'Low nibble of a digit is the digit itself. Subtract 0x30 to get the numeric value.',
    ),
    RangeBoundary(
      block: 'Uppercase A–Z',
      decRange: '65–90',
      hexRange: '0x41–0x5A',
      note: 'A = 65 = 0x41.',
    ),
    RangeBoundary(
      block: 'Lowercase a–z',
      decRange: '97–122',
      hexRange: '0x61–0x7A',
      note: 'a = 97 = 0x61.',
    ),
    RangeBoundary(
      block: 'Space',
      decRange: '32',
      hexRange: '0x20',
      note: 'First printable character.',
    ),
  ];

  /// The case bit (JSON `caseBit`) — rendered as a fixed explanatory card.
  static const String caseBitSummary =
      'Uppercase and lowercase letters differ by exactly one bit: bit 5, value '
      '0x20 (decimal 32). The single most useful ASCII trick.';
  static const String caseBitToLower = 'Upper → lower: OR with 0x20, or add 32';
  static const String caseBitToUpper =
      'Lower → upper: AND with 0xDF, or subtract 32';
  static const String caseBitToggle = 'Toggle case: XOR with 0x20';
  static const String caseBitNote =
      'Applies only to the 52 letters. Range-check before applying.';

  /// Nibble → hex map (JSON `nibbleToHex`).
  static const List<NibbleHex> nibbleToHex = <NibbleHex>[
    NibbleHex('0000', '0', 0),
    NibbleHex('0001', '1', 1),
    NibbleHex('0010', '2', 2),
    NibbleHex('0011', '3', 3),
    NibbleHex('0100', '4', 4),
    NibbleHex('0101', '5', 5),
    NibbleHex('0110', '6', 6),
    NibbleHex('0111', '7', 7),
    NibbleHex('1000', '8', 8),
    NibbleHex('1001', '9', 9),
    NibbleHex('1010', 'A', 10),
    NibbleHex('1011', 'B', 11),
    NibbleHex('1100', 'C', 12),
    NibbleHex('1101', 'D', 13),
    NibbleHex('1110', 'E', 14),
    NibbleHex('1111', 'F', 15),
  ];

  /// Powers of two (JSON `powersOfTwo`); values pre-formatted with separators.
  static const List<PowerOfTwo> powersOfTwo = <PowerOfTwo>[
    PowerOfTwo(0, '1'),
    PowerOfTwo(1, '2'),
    PowerOfTwo(2, '4'),
    PowerOfTwo(3, '8'),
    PowerOfTwo(4, '16'),
    PowerOfTwo(5, '32'),
    PowerOfTwo(6, '64'),
    PowerOfTwo(7, '128'),
    PowerOfTwo(8, '256'),
    PowerOfTwo(9, '512'),
    PowerOfTwo(10, '1,024'),
    PowerOfTwo(11, '2,048'),
    PowerOfTwo(12, '4,096'),
    PowerOfTwo(16, '65,536'),
    PowerOfTwo(24, '16,777,216'),
    PowerOfTwo(32, '4,294,967,296'),
  ];

  /// Hex place values (JSON `hexPlaceValues`).
  static const List<HexPlaceValue> hexPlaceValues = <HexPlaceValue>[
    HexPlaceValue('16^0', '1'),
    HexPlaceValue('16^1', '16'),
    HexPlaceValue('16^2', '256'),
    HexPlaceValue('16^3', '4,096'),
    HexPlaceValue('16^4', '65,536'),
  ];

  /// High-range honesty section (JSON `highRange`).
  static const String highRangeSummary =
      'ASCII stops at 127. Bytes 128–255 mean different things depending on the '
      'encoding; there is no single "extended ASCII".';
  static const List<HighRangeEncoding> highRangeEncodings = <HighRangeEncoding>[
    HighRangeEncoding(
      'UTF-8',
      'Modern default. Bytes 0–127 identical to ASCII. Any byte 128–255 is part of a multi-byte sequence (2–4 bytes); a high byte never stands alone as one character.',
    ),
    HighRangeEncoding(
      'ISO-8859-1 (Latin-1)',
      'Single-byte. 128–159 are C1 control codes; 160–255 are printable Western European characters.',
    ),
    HighRangeEncoding(
      'Windows-1252',
      'Like Latin-1 but replaces most of 128–159 with printable glyphs (curly quotes, em dash, euro). Common source of mojibake.',
    ),
  ];
  static const String highRangeRule =
      'Bytes 0–127 are portable ASCII. Bytes 128–255 are not portable; know the '
      'encoding before decoding. When in doubt assume UTF-8 and decode '
      'multi-byte sequences.';

  // ─── Base64 (RFC 4648) ───────────────────────────────────────────────────────

  /// Base64 explainer (RFC 4648 §4). How the 3-byte → 4-character mapping works.
  static const String base64Summary =
      'Base64 (RFC 4648) encodes arbitrary bytes as ASCII text. It takes 3 bytes '
      '(24 bits) at a time and splits them into four 6-bit groups, mapping each '
      'group to one character. The 64-character alphabet is indexed 0–63.';

  /// The 64-character standard Base64 alphabet (RFC 4648 §4), index → glyph.
  /// 0–25 = A–Z, 26–51 = a–z, 52–61 = 0–9, 62 = '+', 63 = '/'.
  static const String base64Alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  /// The four contiguous ranges of the standard Base64 alphabet.
  static const List<RangeBoundary> base64Ranges = <RangeBoundary>[
    RangeBoundary(
      block: 'Uppercase A–Z',
      decRange: '0–25',
      hexRange: 'A–Z',
      note: 'Index 0 = A.',
    ),
    RangeBoundary(
      block: 'Lowercase a–z',
      decRange: '26–51',
      hexRange: 'a–z',
      note: 'Index 26 = a.',
    ),
    RangeBoundary(
      block: 'Digits 0–9',
      decRange: '52–61',
      hexRange: '0–9',
      note: 'Index 52 = 0.',
    ),
    RangeBoundary(
      block: 'Symbols + and /',
      decRange: '62–63',
      hexRange: '+ /',
      note: 'Index 62 = +, 63 = /. URL-safe variant uses - and _.',
    ),
  ];

  /// Base64 padding rules (RFC 4648 §4): how '=' signals the input length.
  static const String base64Padding =
      'The "=" character is padding, not part of the alphabet. It pads the output '
      'to a multiple of 4 characters so a decoder knows how many input bytes the '
      'final group held.';
  static const String base64PadThree =
      '3 input bytes → 4 chars, no padding (e.g. "Man" → "TWFu").';
  static const String base64PadTwo =
      '2 input bytes → 3 chars + one "=" (e.g. "Ma" → "TWE=").';
  static const String base64PadOne =
      '1 input byte → 2 chars + two "==" (e.g. "M" → "TQ==").';
  static const String base64Note =
      'URL-safe Base64 (RFC 4648 §5) swaps + for - and / for _, and often omits '
      'padding. Otherwise the alphabet is identical.';

  @override
  State<AsciiReferenceScreen> createState() => _AsciiReferenceScreenState();
}

class _AsciiReferenceScreenState extends State<AsciiReferenceScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// The control rows surviving the current filter.
  List<AsciiEntry> get _control => AsciiReferenceScreen.controlCodes
      .where((AsciiEntry e) => e.matches(_query))
      .toList();

  /// The printable rows surviving the current filter.
  List<AsciiEntry> get _printable => AsciiReferenceScreen.printableChars
      .where((AsciiEntry e) => e.matches(_query))
      .toList();

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
    // WCAG 4.1.3 — announce the live match count so AT users hear the table
    // change as they type, without focus leaving the field.
    final int n = _control.length + _printable.length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0
          ? 'No matching characters'
          : '$n matching character${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASCII / Hex / Binary'),
        toolbarHeight: 64,
        // §8.16 — copy the FULL reference as TSV: the complete 128-row ASCII
        // table plus every supplementary section, independent of the on-screen
        // filter (the filter only narrows what is displayed; the static dataset
        // is the result worth keeping). Always enabled.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the entire ASCII / Hex / Binary reference as TSV.
  /// Many sections, each with its own subtitle + header + rows:
  ///   1. Control codes (33): Dec / Hex / Oct / Bin / Char / Description.
  ///   2. Printable characters (95): same columns.
  ///   3. Range boundaries: Block / Decimal / Hex / Note.
  ///   4. The case bit (0x20): a labelled block of summary + operations + note.
  ///   5. Nibble to hex map: Bin / Hex / Dec.
  ///   6. Powers of two: Exponent / Value.
  ///   7. Hex place values: Position / Weight.
  ///   8. High range (128-255): summary + Encoding / Note rows + the rule.
  /// The Char column carries the control mnemonic (printable rows show the
  /// glyph, with the space rendered as the token "SP") via [AsciiEntry.charToken].
  /// Always non-null: the data is static const, so copy is never disabled and
  /// is unaffected by the screen's filter.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()..writeln('ASCII / Hex / Binary');

    void writeAsciiTable(String title, List<AsciiEntry> rows) {
      buf
        ..writeln()
        ..writeln(title)
        ..writeln(
          <String>['Dec', 'Hex', 'Oct', 'Bin', 'Char', 'Description'].join(tab),
        );
      for (final AsciiEntry e in rows) {
        buf.writeln(
          <String>[
            '${e.dec}',
            e.hex,
            e.oct,
            e.bin,
            e.charToken,
            e.description,
          ].join(tab),
        );
      }
    }

    writeAsciiTable(
      'Control codes (0–31, plus 127)',
      AsciiReferenceScreen.controlCodes,
    );
    writeAsciiTable(
      'Printable characters (32–126)',
      AsciiReferenceScreen.printableChars,
    );

    // 3. Range boundaries.
    buf
      ..writeln()
      ..writeln('Range boundaries worth memorizing')
      ..writeln(<String>['Block', 'Decimal', 'Hex', 'Note'].join(tab));
    for (final RangeBoundary b in AsciiReferenceScreen.rangeBoundaries) {
      buf.writeln(<String>[b.block, b.decRange, b.hexRange, b.note].join(tab));
    }

    // 4. The case bit — prose block, one line per fact.
    buf
      ..writeln()
      ..writeln('The case bit (0x20)')
      ..writeln(AsciiReferenceScreen.caseBitSummary)
      ..writeln(AsciiReferenceScreen.caseBitToLower)
      ..writeln(AsciiReferenceScreen.caseBitToUpper)
      ..writeln(AsciiReferenceScreen.caseBitToggle)
      ..writeln(AsciiReferenceScreen.caseBitNote);

    // 5. Nibble to hex.
    buf
      ..writeln()
      ..writeln('Nibble → hex map')
      ..writeln(<String>['Bin', 'Hex', 'Dec'].join(tab));
    for (final NibbleHex n in AsciiReferenceScreen.nibbleToHex) {
      buf.writeln(<String>[n.bin, n.hex, '${n.dec}'].join(tab));
    }

    // 6. Powers of two.
    buf
      ..writeln()
      ..writeln('Powers of two')
      ..writeln(<String>['Exponent', 'Value'].join(tab));
    for (final PowerOfTwo p in AsciiReferenceScreen.powersOfTwo) {
      buf.writeln(<String>['2^${p.exp}', p.value].join(tab));
    }

    // 7. Hex place values.
    buf
      ..writeln()
      ..writeln('Hex place values')
      ..writeln(<String>['Position', 'Weight'].join(tab));
    for (final HexPlaceValue h in AsciiReferenceScreen.hexPlaceValues) {
      buf.writeln(<String>[h.position, h.weight].join(tab));
    }

    // 8. High range.
    buf
      ..writeln()
      ..writeln('High range (128–255): no single "extended ASCII"')
      ..writeln(AsciiReferenceScreen.highRangeSummary)
      ..writeln(<String>['Encoding', 'Note'].join(tab));
    for (final HighRangeEncoding e in AsciiReferenceScreen.highRangeEncodings) {
      buf.writeln(<String>[e.name, e.note].join(tab));
    }
    buf.writeln(AsciiReferenceScreen.highRangeRule);

    // 9. Base64 alphabet (RFC 4648).
    buf
      ..writeln()
      ..writeln('Base64 alphabet (RFC 4648)')
      ..writeln(AsciiReferenceScreen.base64Summary)
      ..writeln('Alphabet (index 0-63): ${AsciiReferenceScreen.base64Alphabet}')
      ..writeln(<String>['Block', 'Index', 'Chars', 'Note'].join(tab));
    for (final RangeBoundary b in AsciiReferenceScreen.base64Ranges) {
      buf.writeln(<String>[b.block, b.decRange, b.hexRange, b.note].join(tab));
    }
    buf
      ..writeln(AsciiReferenceScreen.base64Padding)
      ..writeln(AsciiReferenceScreen.base64PadThree)
      ..writeln(AsciiReferenceScreen.base64PadTwo)
      ..writeln(AsciiReferenceScreen.base64PadOne)
      ..writeln(AsciiReferenceScreen.base64Note);

    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        final List<AsciiEntry> control = _control;
        final List<AsciiEntry> printable = _printable;
        final bool noMatch = control.isEmpty && printable.isEmpty;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: AsciiReferenceScreen.toolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(AsciiReferenceScreen.toolId))
                    const SizedBox(height: AppSpacing.md),
                  _howToReadCard(text, mono),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(),
                  const SizedBox(height: AppSpacing.sm),
                  if (noMatch)
                    _noMatchCard(text)
                  else ...<Widget>[
                    if (control.isNotEmpty) ...<Widget>[
                      _AsciiTableCard(
                        heading: 'Control codes (0–31, plus 127)',
                        subheading:
                            '${control.length} of 33 — commands, not glyphs. '
                            'TAB, LF, CR, ESC, NUL and the XON/XOFF pair still '
                            'matter daily.',
                        rows: control,
                        text: text,
                        mono: mono,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    if (printable.isNotEmpty) ...<Widget>[
                      _AsciiTableCard(
                        heading: 'Printable characters (32–126)',
                        subheading:
                            '${printable.length} of 95 — space, punctuation, '
                            'the ten digits, and the 52 letters.',
                        rows: printable,
                        text: text,
                        mono: mono,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _crlfNoteCard(text, mono),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _rangeBoundariesCard(text, mono),
                  const SizedBox(height: AppSpacing.sm),
                  _caseBitCard(text, mono),
                  const SizedBox(height: AppSpacing.sm),
                  _nibbleToHexCard(text, mono),
                  const SizedBox(height: AppSpacing.sm),
                  _powersOfTwoCard(text, mono),
                  const SizedBox(height: AppSpacing.sm),
                  _hexPlaceValuesCard(text, mono),
                  const SizedBox(height: AppSpacing.sm),
                  _highRangeCard(text),
                  const SizedBox(height: AppSpacing.sm),
                  _base64Card(text, mono),
                  ToolHelpFooter(toolId: 'ascii-reference'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Cards ───────────────────────────────────────────────────────────────────

  Widget _howToReadCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'How to read this',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _legendLine('Dec', 'decimal value (0–127)', text, mono),
          _legendLine('Hex', 'base-16, two digits (00–7F)', text, mono),
          _legendLine('Oct', 'octal, base-8 (000–177)', text, mono),
          _legendLine('Bin', '8-bit binary (high bit always 0)', text, mono),
          _legendLine('Char', 'the glyph, or a control mnemonic', text, mono),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Control codes (0–31 and 127) do not print. Printable characters '
            'run 32–126, a block of 95 glyphs including the space (shown as SP).',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _legendLine(
    String term,
    String def,
    TextTheme text,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              term,
              style: mono.robotoMono.copyWith(
                fontSize: AppTextSize.caption,
                // Mono legend term is a foreground accent → darkened-lime in
                // light (§8.20.2).
                color: colors.textAccent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              def,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchCard() {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: null,
      headingText: Theme.of(context).textTheme,
      child: LabeledField(
        label: 'Filter',
        hint: 'char, code, or keyword',
        semanticLabel: 'Filter the ASCII table by character, code, or keyword',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(
            hintText: 'e.g. 65, 0x41, LF, or newline',
          ),
        ),
      ),
    );
  }

  Widget _noMatchCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: null,
      headingText: text,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.search_off, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No match',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No ASCII character matches "${_queryCtrl.text.trim()}". The '
                  'quick-reference tables below are unaffected.',
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _crlfNoteCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Newlines on the wire',
      headingText: text,
      child: Text.rich(
        TextSpan(
          style: text.labelMedium?.copyWith(color: colors.textTertiary),
          children: <InlineSpan>[
            const TextSpan(
              text:
                  'A network newline (CRLF, used by HTTP, SMTP, and many '
                  'protocols) is the two-byte sequence CR + LF = ',
            ),
            TextSpan(
              text: '0D 0A',
              style: mono.robotoMono.copyWith(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
            TextSpan(text: '. Unix uses LF alone ('),
            TextSpan(
              text: '0A',
              style: mono.robotoMono.copyWith(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
            const TextSpan(text: '); classic Mac OS used CR alone ('),
            TextSpan(
              text: '0D',
              style: mono.robotoMono.copyWith(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
            const TextSpan(
              text:
                  '). Mixing them causes a large share of "works on my '
                  'machine" parsing bugs.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangeBoundariesCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Range boundaries worth memorizing',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final RangeBoundary b in AsciiReferenceScreen.rangeBoundaries)
            ReferenceRowSemantics(
              label: rowLabel(b.block, <String?>[
                'decimal ${b.decRange}',
                'hex ${b.hexRange}',
                b.note,
              ]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            b.block,
                            style: text.labelLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${b.decRange}  ·  ${b.hexRange}',
                          style: mono.robotoMono.copyWith(
                            fontSize: AppTextSize.caption,
                            color: colors.textAccent,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                    Text(
                      b.note,
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ASCII digit → value: subtract 48 (0x30). Value → ASCII digit: add '
            '48. The digit n is byte 0x30 + n.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _caseBitCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'The case bit (0x20)',
      headingText: text,
      child: ReferenceRowSemantics(
        label: rowLabel('Case bit 0x20', <String?>[
          AsciiReferenceScreen.caseBitSummary,
          AsciiReferenceScreen.caseBitToLower,
          AsciiReferenceScreen.caseBitToUpper,
          AsciiReferenceScreen.caseBitToggle,
          AsciiReferenceScreen.caseBitNote,
        ]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              AsciiReferenceScreen.caseBitSummary,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            _opLine(AsciiReferenceScreen.caseBitToLower, text, mono),
            _opLine(AsciiReferenceScreen.caseBitToUpper, text, mono),
            _opLine(AsciiReferenceScreen.caseBitToggle, text, mono),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AsciiReferenceScreen.caseBitNote,
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opLine(String op, TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '·  ',
            style: text.labelMedium?.copyWith(color: colors.textAccent),
          ),
          Expanded(
            child: Text(
              op,
              style: mono.robotoMono.copyWith(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nibbleToHexCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    return _Card(
      heading: 'Nibble → hex map',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Genuinely narrow + tabular → horizontal scroll is the overflow
          // safety valve (mcs_index idiom) but never triggers at phone width.
          // HorizontalScrollTable signals the sideways scroll on web.
          HorizontalScrollTable(
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Bin')),
                DataColumn(label: Text('Hex')),
                DataColumn(label: Text('Dec'), numeric: true),
              ],
              rows: AsciiReferenceScreen.nibbleToHex.map((NibbleHex n) {
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        container: true,
                        label:
                            'binary ${n.bin}, hex ${n.hex}, decimal ${n.dec}',
                        child: ExcludeSemantics(
                          child: Text(
                            n.bin,
                            style: mono.robotoMono.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          n.hex,
                          style: mono.robotoMono.copyWith(
                            color: colors.textAccent,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          '${n.dec}',
                          style: mono.robotoMono.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A byte is two nibbles. Convert each independently, then concatenate. '
            'Example: 1100 1010 → high C, low A → 0xCA = 202.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _powersOfTwoCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Powers of two',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final PowerOfTwo p in AsciiReferenceScreen.powersOfTwo)
            ReferenceRowSemantics(
              label: '2 to the power ${p.exp} equals ${p.value}',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xxs / 2,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        '2^${p.exp}',
                        style: mono.robotoMono.copyWith(
                          fontSize: AppTextSize.caption,
                          color: colors.textAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        p.value,
                        style: mono.robotoMono.copyWith(
                          fontSize: AppTextSize.caption,
                          color: colors.textPrimary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The eight bits of a byte carry place values 128, 64, 32, 16, 8, 4, '
            '2, 1. They sum to 255 — the largest value one byte holds.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _hexPlaceValuesCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Hex place values',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final HexPlaceValue h in AsciiReferenceScreen.hexPlaceValues)
            ReferenceRowSemantics(
              label: '${h.position} weight ${h.weight}',
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xxs / 2,
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        h.position,
                        style: mono.robotoMono.copyWith(
                          fontSize: AppTextSize.caption,
                          color: colors.textAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        h.weight,
                        style: mono.robotoMono.copyWith(
                          fontSize: AppTextSize.caption,
                          color: colors.textPrimary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Two hex digits = one byte (0–255). Four = 16 bits. Eight = a 32-bit '
            'IPv4 word. Twelve = a 48-bit MAC address.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _highRangeCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'High range (128–255): no single "extended ASCII"',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AsciiReferenceScreen.highRangeSummary,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final HighRangeEncoding e
              in AsciiReferenceScreen.highRangeEncodings)
            ReferenceRowSemantics(
              label: rowLabel(e.name, <String?>[e.note]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      e.name,
                      style: text.labelLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      e.note,
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AsciiReferenceScreen.highRangeRule,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _base64Card(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Base64 alphabet (RFC 4648)',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AsciiReferenceScreen.base64Summary,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The 64-character alphabet as one mono run, scrollable so it never
          // overflows a 320px phone (identifier string, Roboto Mono per §8.5).
          HorizontalScrollTable(
            child: Semantics(
              label:
                  'Standard Base64 alphabet, index 0 to 63: '
                  'A to Z, a to z, 0 to 9, plus, slash',
              child: ExcludeSemantics(
                child: Text(
                  AsciiReferenceScreen.base64Alphabet,
                  style: mono.robotoMono.copyWith(
                    fontSize: AppTextSize.caption,
                    color: colors.textAccent,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final RangeBoundary b in AsciiReferenceScreen.base64Ranges)
            ReferenceRowSemantics(
              label: rowLabel(b.block, <String?>[
                'index ${b.decRange}',
                'characters ${b.hexRange}',
                b.note,
              ]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        b.block,
                        style: text.labelLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'idx ${b.decRange}',
                      style: mono.robotoMono.copyWith(
                        fontSize: AppTextSize.caption,
                        color: colors.textAccent,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Padding',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AsciiReferenceScreen.base64Padding,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _opLine(AsciiReferenceScreen.base64PadThree, text, mono),
          _opLine(AsciiReferenceScreen.base64PadTwo, text, mono),
          _opLine(AsciiReferenceScreen.base64PadOne, text, mono),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AsciiReferenceScreen.base64Note,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One control/printable table inside a bordered card. Each row is a two-line
/// layout (numeric identifier gutters on the top line, description beneath) so
/// the six-column dataset fits a 320px phone without a horizontal scroll.
class _AsciiTableCard extends StatelessWidget {
  const _AsciiTableCard({
    required this.heading,
    required this.subheading,
    required this.rows,
    required this.text,
    required this.mono,
  });

  final String heading;
  final String subheading;
  final List<AsciiEntry> rows;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            heading,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subheading,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _AsciiHeaderRow(),
          Divider(color: colors.border, height: AppSpacing.sm),
          for (final AsciiEntry e in rows)
            _AsciiRow(entry: e, text: text, mono: mono),
        ],
      ),
    );
  }
}

/// Column-label row for an ASCII table. The fixed gutter widths match
/// [_AsciiRow] so labels sit above their columns.
class _AsciiHeaderRow extends StatelessWidget {
  const _AsciiHeaderRow();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = text.labelSmall?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _AsciiRow.decW,
            child: Text('Dec', style: style),
          ),
          SizedBox(
            width: _AsciiRow.hexW,
            child: Text('Hex', style: style),
          ),
          SizedBox(
            width: _AsciiRow.octW,
            child: Text('Oct', style: style),
          ),
          SizedBox(
            width: _AsciiRow.binW,
            child: Text('Bin', style: style),
          ),
          SizedBox(
            width: _AsciiRow.charW,
            child: Text('Char', style: style),
          ),
        ],
      ),
    );
  }
}

/// One ASCII code-point row. Top line: dec / hex / oct / bin / char in
/// fixed-width gutters (Roboto Mono identifiers, GL-003 §8.5). Second line: the
/// wrapping description. The whole row reads as one screen-reader node via
/// [ReferenceRowSemantics].
class _AsciiRow extends StatelessWidget {
  const _AsciiRow({
    required this.entry,
    required this.text,
    required this.mono,
  });

  final AsciiEntry entry;
  final TextTheme text;
  final AppMonoText mono;

  // Fixed gutter widths — sized so the four numeric columns + the char token
  // fit inside a 320px phone. The card content area is ~254px at 320px wide;
  // these gutters total 252 (2px slack), leaving the description its own
  // full-width line beneath. "00000000" fits binW; 3-char mnemonics fit charW.
  static const double decW = 34;
  static const double hexW = 34;
  static const double octW = 40;
  static const double binW = 94;
  static const double charW = 50;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool isControl = entry.category == AsciiCategory.control;
    // Char token: lime for a control mnemonic (it is the row's identity), high-
    // contrast primary text for a printable glyph.
    final Color charColor = isControl ? colors.textAccent : colors.textPrimary;

    final TextStyle idStyle = mono.robotoMono.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textSecondary,
    );

    return ReferenceRowSemantics(
      label: rowLabel(
        isControl
            ? 'Control ${entry.mnemonic}'
            : 'Character ${entry.charToken}',
        <String?>[
          'decimal ${entry.dec}',
          'hex ${entry.hex}',
          'octal ${entry.oct}',
          'binary ${entry.bin}',
          entry.description,
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: decW,
                  child: Text(
                    '${entry.dec}',
                    style: idStyle.copyWith(color: colors.textPrimary),
                  ),
                ),
                SizedBox(
                  width: hexW,
                  child: Text(entry.hex, style: idStyle),
                ),
                SizedBox(
                  width: octW,
                  child: Text(entry.oct, style: idStyle),
                ),
                SizedBox(
                  width: binW,
                  child: Text(entry.bin, style: idStyle),
                ),
                SizedBox(
                  width: charW,
                  child: Text(
                    entry.charToken,
                    style: mono.robotoMono.copyWith(
                      fontSize: AppTextSize.caption,
                      color: charColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                entry.description,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared surface-1 card with an optional heading. Mirrors the db_reference
/// `_Card` idiom; `heading` may be null for the search/empty cards that carry
/// no section title.
class _Card extends StatelessWidget {
  const _Card({
    required this.heading,
    required this.headingText,
    required this.child,
  });

  final String? heading;
  final TextTheme headingText;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (heading != null) ...<Widget>[
            Text(
              heading!,
              style: headingText.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          child,
        ],
      ),
    );
  }
}
