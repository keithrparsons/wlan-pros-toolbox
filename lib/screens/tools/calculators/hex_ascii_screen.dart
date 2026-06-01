// Hex / ASCII — an interactive dec/hex/binary converter plus a printable-ASCII
// reference table.
//
// PART A — CONVERTER (pure Felix math, the dbm_watt_converter idiom):
//   Three linked unsigned-integer fields — decimal, hexadecimal, binary. Type
//   in any one; the other two update live. Empty/invalid input blanks the
//   mirror fields (no crash), exactly like the dBm/Watt converter's empty path.
//   Unsigned-integer domain (BigInt-backed so a long hex/bin string never
//   overflows). Hex accepts 0-9 a-f A-F (with an optional 0x prefix stripped);
//   binary accepts 0/1 (with an optional 0b prefix stripped); decimal accepts
//   digits only.
//
// PART B — ASCII REFERENCE TABLE (printable, decimal 32-126):
//   Each row's decimal, hex (2-digit), binary (8-bit), char, and name. The
//   char is DERIVED via String.fromCharCode(code) at build time, NOT hand-
//   transcribed — so the vertical-bar row (decimal 124, "|") is a real code
//   point, never a table-delimiter hazard (Pax flag). Names for the
//   symbol/space rows come from a small const map; digit/letter rows have none.
//
// States (SOP-007 §5):
//  - success     → the converter mirrors and the table render (default).
//  - empty/invalid → a blank or non-parseable field blanks the mirrors.
//  - interactive → typing in any field updates the others; keyboard focus ring
//    is the app-wide §8.3 input focus border.
// No loading / error / network — pure math + a const-derived table; works on
// every platform (GL-008 does not apply, nothing fetched, nothing shelled out).
//
// Glyph note: ASCII hyphen-minus only; no em dash. "Hyphen-minus" name verbatim.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One printable-ASCII row. The [char] is derived from [dec] via
/// String.fromCharCode, so the literal glyph is always correct (incl. "|").
@immutable
class AsciiRow {
  const AsciiRow({required this.dec, required this.name});

  /// Decimal code point, 32-126. LIME index column.
  final int dec;

  /// Short name for space/symbol rows; empty for digits and letters.
  final String name;

  /// Two-digit uppercase hexadecimal, e.g. `41`.
  String get hex => dec.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// 8-bit zero-padded binary, e.g. `01000001`.
  String get bin => dec.toRadixString(2).padLeft(8, '0');

  /// The printable glyph — derived, never hand-typed.
  String get char => String.fromCharCode(dec);
}

/// Pure unsigned-integer base conversion (dec <-> hex <-> bin). Public + static
/// so tests assert the math without pumping the UI. Returns `null` on an empty
/// or invalid string (the converter then blanks the mirror fields).
class HexAsciiConvert {
  HexAsciiConvert._();

  /// Parse a decimal string to a non-negative BigInt, or `null` if invalid.
  static BigInt? parseDecimal(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    if (!RegExp(r'^[0-9]+$').hasMatch(s)) return null;
    return BigInt.tryParse(s);
  }

  /// Parse a hex string (optional `0x` prefix) to a non-negative BigInt.
  static BigInt? parseHex(String raw) {
    String s = raw.trim();
    if (s.toLowerCase().startsWith('0x')) s = s.substring(2);
    if (s.isEmpty) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) return null;
    return BigInt.tryParse(s, radix: 16);
  }

  /// Parse a binary string (optional `0b` prefix) to a non-negative BigInt.
  static BigInt? parseBinary(String raw) {
    String s = raw.trim();
    if (s.toLowerCase().startsWith('0b')) s = s.substring(2);
    if (s.isEmpty) return null;
    if (!RegExp(r'^[01]+$').hasMatch(s)) return null;
    return BigInt.tryParse(s, radix: 2);
  }

  static String toDecimal(BigInt v) => v.toString();
  static String toHex(BigInt v) => v.toRadixString(16).toUpperCase();
  static String toBinary(BigInt v) => v.toRadixString(2);
}

class HexAsciiScreen extends StatefulWidget {
  const HexAsciiScreen({super.key});

  static const String intro =
      'Convert between decimal, hexadecimal, and binary, with a '
      'printable-ASCII reference table.';

  static const String caveat =
      'Converter handles unsigned integers. The table covers printable ASCII '
      '(decimal 32-126); the high range (128-255) varies by code page and is '
      'omitted on purpose.';

  static const String footnote =
      'Printable ASCII spans decimal 32 (space) to 126 (tilde). Codes 0-31 and '
      '127 are control characters (non-printing); codes 128-255 depend on the '
      'code page (Latin-1, Windows-1252, etc.) and are intentionally omitted. '
      'Hyphen-minus (decimal 45) is the standard ASCII hyphen.';

  /// Names for the space/symbol rows. Digits (48-57) and letters (65-90,
  /// 97-122) carry no name. Keys are the decimal code points.
  static const Map<int, String> names = <int, String>{
    32: 'Space',
    33: 'Exclamation mark',
    34: 'Double quote',
    35: 'Number sign',
    36: 'Dollar sign',
    37: 'Percent',
    38: 'Ampersand',
    39: 'Single quote',
    40: 'Left parenthesis',
    41: 'Right parenthesis',
    42: 'Asterisk',
    43: 'Plus',
    44: 'Comma',
    45: 'Hyphen-minus',
    46: 'Period',
    47: 'Forward slash',
    58: 'Colon',
    59: 'Semicolon',
    60: 'Less than',
    61: 'Equals',
    62: 'Greater than',
    63: 'Question mark',
    64: 'At sign',
    91: 'Left bracket',
    92: 'Backslash',
    93: 'Right bracket',
    94: 'Caret',
    95: 'Underscore',
    96: 'Backtick',
    123: 'Left brace',
    124: 'Vertical bar',
    125: 'Right brace',
    126: 'Tilde',
  };

  /// The printable-ASCII rows, decimal 32-126, derived (char/hex/bin computed).
  /// Public + static so tests can assert row count and known rows.
  static final List<AsciiRow> rows = List<AsciiRow>.generate(126 - 32 + 1, (
    int i,
  ) {
    final int dec = 32 + i;
    // Space renders as a glyph-less code point; show "(space)" as the name's
    // companion in the cell. The derived char for 32 is a literal space.
    return AsciiRow(dec: dec, name: names[dec] ?? '');
  });

  @override
  State<HexAsciiScreen> createState() => _HexAsciiScreenState();
}

class _HexAsciiScreenState extends State<HexAsciiScreen> {
  final TextEditingController _decCtrl = TextEditingController();
  final TextEditingController _hexCtrl = TextEditingController();
  final TextEditingController _binCtrl = TextEditingController();

  final FocusNode _decFocus = FocusNode();
  final FocusNode _hexFocus = FocusNode();
  final FocusNode _binFocus = FocusNode();

  static final List<TextInputFormatter> _decFmt = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
  ];
  static final List<TextInputFormatter> _hexFmt = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-FxX]')),
  ];
  static final List<TextInputFormatter> _binFmt = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[01bB]')),
  ];

  @override
  void dispose() {
    _decCtrl.dispose();
    _hexCtrl.dispose();
    _binCtrl.dispose();
    _decFocus.dispose();
    _hexFocus.dispose();
    _binFocus.dispose();
    super.dispose();
  }

  void _blankMirrors(TextEditingController keep) {
    if (keep != _decCtrl) _decCtrl.text = '';
    if (keep != _hexCtrl) _hexCtrl.text = '';
    if (keep != _binCtrl) _binCtrl.text = '';
  }

  void _spreadFrom(BigInt? v, TextEditingController source) {
    if (v == null) {
      _blankMirrors(source);
      setState(() {});
      return;
    }
    if (source != _decCtrl) _decCtrl.text = HexAsciiConvert.toDecimal(v);
    if (source != _hexCtrl) _hexCtrl.text = HexAsciiConvert.toHex(v);
    if (source != _binCtrl) _binCtrl.text = HexAsciiConvert.toBinary(v);
    setState(() {});
  }

  void _onDecChanged(String raw) =>
      _spreadFrom(HexAsciiConvert.parseDecimal(raw), _decCtrl);
  void _onHexChanged(String raw) =>
      _spreadFrom(HexAsciiConvert.parseHex(raw), _hexCtrl);
  void _onBinChanged(String raw) =>
      _spreadFrom(HexAsciiConvert.parseBinary(raw), _binCtrl);

  /// §8.16 copy payload — the CURRENT conversion as a labeled text block.
  ///
  /// The converter has no separate "result"; its three fields are kept in sync
  /// on every keystroke, so the decimal controller always holds the canonical
  /// value when the input is valid. Returns null (→ disabled) when the value is
  /// empty or unparseable (all mirrors blank). When the value is a single
  /// printable-ASCII code point (decimal 32-126), the matching character is
  /// added (space rendered as the word "space"), derived not transcribed.
  String? _buildCopyText() {
    final BigInt? v = HexAsciiConvert.parseDecimal(_decCtrl.text);
    if (v == null) return null;

    final StringBuffer buf = StringBuffer()
      ..writeln('Hex / ASCII')
      ..writeln('Decimal: ${HexAsciiConvert.toDecimal(v)}')
      ..writeln('Hexadecimal: ${HexAsciiConvert.toHex(v)}')
      ..writeln('Binary: ${HexAsciiConvert.toBinary(v)}');
    if (v >= BigInt.from(32) && v <= BigInt.from(126)) {
      final int code = v.toInt();
      final String glyph = code == 32 ? 'space' : String.fromCharCode(code);
      buf.writeln('Character: $glyph');
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hex / ASCII'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. The converter's three
        // fields are both input and output, so this copies the CURRENT
        // conversion: all three representations (decimal/hex/binary) plus the
        // ASCII character when the value is a single printable code point.
        // Disabled when no field holds a valid value (all mirrors blank).
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return Align(
              alignment: AppSpacing.calculatorVerticalAlignment(constraints),
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
                    children: [
                      ConceptGraphicBand(
                        toolId: 'hex-ascii',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('hex-ascii'))
                        const SizedBox(height: AppSpacing.md),
                      _introCard(text),
                      const SizedBox(height: AppSpacing.md),
                      _converterCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _tableCard(text, mono),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _introCard(TextTheme text) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            HexAsciiScreen.intro,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            HexAsciiScreen.caveat,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _converterCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConverterField(
            label: 'Decimal',
            unitHint: 'base 10',
            controller: _decCtrl,
            focusNode: _decFocus,
            formatters: _decFmt,
            onChanged: _onDecChanged,
            monoStyle: mono.outputLarge,
            hint: '65',
          ),
          const SizedBox(height: AppSpacing.sm),
          _ConverterField(
            label: 'Hexadecimal',
            unitHint: 'base 16',
            controller: _hexCtrl,
            focusNode: _hexFocus,
            formatters: _hexFmt,
            onChanged: _onHexChanged,
            monoStyle: mono.outputLarge,
            hint: '41',
          ),
          const SizedBox(height: AppSpacing.sm),
          _ConverterField(
            label: 'Binary',
            unitHint: 'base 2',
            controller: _binCtrl,
            focusNode: _binFocus,
            formatters: _binFmt,
            onChanged: _onBinChanged,
            monoStyle: mono.outputLarge,
            hint: '1000001',
          ),
        ],
      ),
    );
  }

  Widget _tableCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Printable ASCII (32-126)',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      _HeaderCell('Dec', width: 44),
                      _HeaderCell('Hex', width: 44),
                      _HeaderCell('Binary', width: 88),
                      _HeaderCell('Char', width: 48),
                      _HeaderCell('Name', width: 160),
                    ],
                  ),
                  const Divider(color: AppColors.border, height: AppSpacing.sm),
                  ...HexAsciiScreen.rows.map(
                    (AsciiRow r) => _AsciiTableRow(row: r, mono: mono),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            HexAsciiScreen.footnote,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One ASCII table row. The char cell shows "(space)" for code 32 (an invisible
/// glyph) so the cell is never blank; every other char renders its literal
/// glyph (incl. the vertical bar).
class _AsciiTableRow extends StatelessWidget {
  const _AsciiTableRow({required this.row, required this.mono});

  final AsciiRow row;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isSpace = row.dec == 32;
    final String charDisplay = isSpace ? '(space)' : row.char;
    final String spokenChar = isSpace ? 'space' : row.char;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Decimal ${row.dec}, hex ${row.hex}, binary ${row.bin}, '
          'character $spokenChar${row.name.isEmpty ? '' : ', ${row.name}'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                '${row.dec}',
                style: mono.inlineCode.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                row.hex,
                style: mono.inlineCode.copyWith(color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                row.bin,
                style: mono.inlineCode.copyWith(color: AppColors.textTertiary),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                charDisplay,
                style: mono.inlineCode.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: Text(
                row.name,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One label + input row for the converter, matching the dbm_watt idiom.
class _ConverterField extends StatelessWidget {
  const _ConverterField({
    required this.label,
    required this.unitHint,
    required this.controller,
    required this.focusNode,
    required this.formatters,
    required this.onChanged,
    required this.monoStyle,
    required this.hint,
  });

  final String label;
  final String unitHint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onChanged;
  final TextStyle monoStyle;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      hint: '($unitHint)',
      semanticLabel: '$label, $unitHint',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.text,
        inputFormatters: formatters,
        onChanged: onChanged,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
