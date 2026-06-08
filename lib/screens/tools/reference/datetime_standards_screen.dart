// Date & Time Standards - read-only reference card for ISO 8601 / RFC 3339
// date-time formats, UTC-offset notation, the Unix epoch + 2038 problem, leap
// seconds (UTC vs TAI), and NTP stratum levels.
//
// Data ported verbatim from the verified dataset at
// Deliverables/2026-06-08-reference-batch/time-encoding-improvements-data.md
// SECTION 1 (DATE / TIME STANDARDS - NEW PAGE), subsections 1A-1F. Every value
// traces to a primary standard (ISO 8601-1:2019, RFC 3339, RFC 5905,
// POSIX.1-2017, BIPM/IERS).
//
// Pure read-only reference - no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading / empty /
// error / disabled state because nothing is fetched, parsed, can be empty, or
// can be toggled (SOP-007 §5: states handled by being structurally impossible,
// not skipped). GL-008 network/subprocess rules do not apply - nothing to
// fabricate, nothing to shell out to.
//
// Pattern: mirrors poe_reference_screen exactly - Scaffold + AppBar
// (toolbarHeight 64) with the §8.16 AppCopyAction, SafeArea(top: false),
// LayoutBuilder isDesktop @720, ConstrainedBox to calculatorMaxWidth,
// SingleChildScrollView of cards, ConceptGraphicBand header, ToolHelpFooter.
// Wide tables render inside the HorizontalScrollTable + IntrinsicWidth
// fixed-width-cell idiom so columns align and never overflow a phone-width card.
// Each row is wrapped in ReferenceRowSemantics so a screen reader announces it
// as one node keyed on its first column.
//
// Honesty note (GL-005, flagged in the source data §1E): the UTC-TAI offset of
// -37 s is a STATIC EDUCATIONAL VALUE current as of the 2017-01-01 leap second.
// It is rendered with an explicit "static value" status badge and a footnote
// pointing at the IERS Bulletin C, so the page never presents a time-sensitive
// figure as a live truth.
//
// Glyph note: "802.1X"/"802.3" style identifiers are not used here; ASCII
// hyphen-minus only (the "UTC - TAI" minus and the "-37 s" offset); no em dash.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One ISO 8601 format row: a named concept, its format mask, an example, and a
/// note. Mirrors the source §1A table columns.
@immutable
class IsoFormat {
  const IsoFormat({
    required this.concept,
    required this.format,
    required this.example,
    required this.note,
  });

  /// What the format represents, e.g. "Calendar date".
  final String concept;

  /// The format mask, e.g. `YYYY-MM-DD`.
  final String format;

  /// A worked example, e.g. `2026-06-08`.
  final String example;

  /// Clarifying note (basic-format variant, separators, profile rules).
  final String note;
}

/// One UTC-offset notation row (§1B).
@immutable
class OffsetNotation {
  const OffsetNotation({
    required this.notation,
    required this.meaning,
    required this.example,
  });

  /// The notation token, e.g. `Z` or `+hh:mm`.
  final String notation;

  /// What it means.
  final String meaning;

  /// A worked example.
  final String example;
}

/// One Unix-epoch / 2038 fact row (§1D).
@immutable
class EpochFact {
  const EpochFact({required this.item, required this.value});

  /// The item, e.g. "2038 rollover instant".
  final String item;

  /// The value / definition.
  final String value;
}

/// One leap-second / timescale definition row (§1E).
@immutable
class TimescaleTerm {
  const TimescaleTerm({required this.term, required this.definition});

  /// The term, e.g. "TAI", "UTC", "Leap second".
  final String term;

  /// Its definition.
  final String definition;
}

/// One NTP stratum row (§1F).
@immutable
class NtpStratum {
  const NtpStratum({required this.stratum, required this.meaning});

  /// The stratum label, e.g. "0", "1", "4-15", "16".
  final String stratum;

  /// What that stratum means.
  final String meaning;
}

class DatetimeStandardsScreen extends StatelessWidget {
  const DatetimeStandardsScreen({super.key});

  static const String _toolId = 'datetime-standards';

  /// §1A - ISO 8601-1:2019 core formats. Ported verbatim from the dataset.
  static const List<IsoFormat> isoFormats = <IsoFormat>[
    IsoFormat(
      concept: 'Calendar date',
      format: 'YYYY-MM-DD',
      example: '2026-06-08',
      note: 'Extended format. Basic omits separators: 20260608',
    ),
    IsoFormat(
      concept: 'Time of day',
      format: 'hh:mm:ss',
      example: '14:30:00',
      note: '24-hour clock. Basic format: 143000',
    ),
    IsoFormat(
      concept: 'Time with fraction',
      format: 'hh:mm:ss.sss',
      example: '14:30:00.250',
      note: 'Comma also permitted as decimal sign; period is the common profile',
    ),
    IsoFormat(
      concept: 'Combined date-time',
      format: 'YYYY-MM-DDThh:mm:ss',
      example: '2026-06-08T14:30:00',
      note: 'T separates date and time',
    ),
    IsoFormat(
      concept: 'Week date',
      format: 'YYYY-Www-D',
      example: '2026-W24-1',
      note: 'Www = ISO week 01-53; D = weekday 1 (Mon) to 7 (Sun)',
    ),
    IsoFormat(
      concept: 'Ordinal date',
      format: 'YYYY-DDD',
      example: '2026-159',
      note: 'DDD = day of year, 001-366',
    ),
    IsoFormat(
      concept: 'Year-month',
      format: 'YYYY-MM',
      example: '2026-06',
      note: 'Reduced precision',
    ),
    IsoFormat(
      concept: 'Duration',
      format: 'PnYnMnDTnHnMnS',
      example: 'P3Y6M4DT12H30M5S',
      note: '3 yr, 6 mo, 4 d, 12 h, 30 min, 5 s. T separates date from time part',
    ),
    IsoFormat(
      concept: 'Duration (weeks)',
      format: 'PnW',
      example: 'P2W',
      note: '2 weeks; not combined with other elements',
    ),
    IsoFormat(
      concept: 'Time interval',
      format: '<start>/<end>',
      example: '2026-06-08T00:00Z/2026-06-09T00:00Z',
      note: 'Also <start>/<duration> or <duration>/<end>',
    ),
  ];

  /// ISO week rule + RFC 3339 profile note, shown as the §1A/§1C footnote.
  static const String isoFootnote =
      'ISO week 01 is the week containing the year\'s first Thursday (the '
      'week with 4 January); a year has 52 or 53 weeks. RFC 3339 is the strict '
      'Internet profile of ISO 8601 used by logs, APIs, and JSON timestamps: '
      'always YYYY-MM-DDThh:mm:ss with a mandatory offset (Z or +/-hh:mm). It '
      'forbids many ISO forms (week dates, ordinal dates, durations, basic '
      'format). Example: 2026-06-08T14:30:00.000Z';

  /// §1B - UTC vs local offset notation.
  static const List<OffsetNotation> offsets = <OffsetNotation>[
    OffsetNotation(
      notation: 'Z',
      meaning: 'UTC ("Zulu"); zero offset',
      example: '2026-06-08T14:30:00Z',
    ),
    OffsetNotation(
      notation: '+hh:mm',
      meaning: 'Local time ahead of UTC',
      example: '2026-06-08T14:30:00+02:00',
    ),
    OffsetNotation(
      notation: '-hh:mm',
      meaning: 'Local time behind UTC',
      example: '2026-06-08T09:30:00-05:00',
    ),
    OffsetNotation(
      notation: '(none)',
      meaning: 'Local time, offset unknown (avoid for logs/interchange)',
      example: '2026-06-08T14:30:00',
    ),
  ];

  static const String offsetFootnote =
      'Z and +00:00 denote the same instant. RFC 3339 4.3 permits -00:00 to '
      'signal "UTC offset unknown", distinct from +00:00.';

  /// §1D - Unix epoch and the 2038 problem.
  static const List<EpochFact> epochFacts = <EpochFact>[
    EpochFact(item: 'Epoch (time zero)', value: '1970-01-01T00:00:00Z'),
    EpochFact(
      item: 'Definition',
      value: 'Seconds elapsed since the epoch, excluding leap seconds (POSIX)',
    ),
    EpochFact(item: 'Signed 32-bit limit', value: '2,147,483,647 seconds'),
    EpochFact(
      item: '2038 rollover instant',
      value: '2038-01-19T03:14:07Z (last second representable in signed int32)',
    ),
    EpochFact(
      item: 'Failure mode',
      value: 'At +1 s the counter overflows to -2,147,483,648 = '
          '1901-12-13T20:45:52Z',
    ),
    EpochFact(
      item: 'Fix',
      value: '64-bit signed time_t; range extends ~292 billion years past '
          'the epoch',
    ),
  ];

  /// §1E - leap-second / timescale terms.
  static const List<TimescaleTerm> timescales = <TimescaleTerm>[
    TimescaleTerm(
      term: 'TAI',
      definition: 'International Atomic Time. Continuous, no leap seconds. '
          'The pure atomic timescale.',
    ),
    TimescaleTerm(
      term: 'UTC',
      definition: 'Coordinated Universal Time. Atomic rate, kept within '
          '0.9 s of astronomical UT1 by inserting leap seconds.',
    ),
    TimescaleTerm(
      term: 'Leap second',
      definition: 'An extra second (23:59:60Z) inserted at end of June or '
          'December when needed. Always positive in practice; a negative leap '
          'second is defined but has never occurred.',
    ),
    TimescaleTerm(
      term: 'GPS time',
      definition: 'A third scale: continuous like TAI, offset from TAI by a '
          'fixed -19 s (GPS = TAI - 19 s); thus GPS is ahead of UTC by the '
          'leap-second count minus 19.',
    ),
  ];

  /// §1E - the UTC-TAI offset, surfaced separately because it is a STATIC
  /// educational value (current as of the 2017-01-01 leap second), not a live
  /// figure. Flagged with a "static value" badge + a verify-against-IERS note.
  static const String utcTaiOffsetValue = 'UTC = TAI - 37 s';
  static const String utcTaiOffsetCaption =
      'UTC has been behind TAI by a growing whole number of seconds since 1972.';
  static const String utcTaiOffsetVerifyNote =
      'Static educational value, current as of the 2017-01-01 leap second; no '
      'leap second has been added since. The CGPM resolved in 2022 to end '
      'leap-second insertion by or before 2035, so this value is stable. '
      'Verify against the IERS Bulletin C if an exact current offset is '
      'load-bearing.';

  /// §1F - NTP stratum levels (RFC 5905).
  static const List<NtpStratum> strata = <NtpStratum>[
    NtpStratum(
      stratum: '0',
      meaning: 'Reference clock (not networked): atomic clock, GPS receiver, '
          'radio clock. Not directly reachable over NTP.',
    ),
    NtpStratum(
      stratum: '1',
      meaning: 'Primary server: directly synchronized to a stratum-0 device.',
    ),
    NtpStratum(
      stratum: '2',
      meaning: 'Secondary server: synced to a stratum-1 server over the network.',
    ),
    NtpStratum(stratum: '3', meaning: 'Synced to a stratum-2 server.'),
    NtpStratum(
      stratum: '4-15',
      meaning: 'Each level one hop further from the reference; same pattern.',
    ),
    NtpStratum(
      stratum: '16',
      meaning: '"Unsynchronized" - the sentinel value meaning the clock '
          'is not synchronized.',
    ),
  ];

  static const String ntpFootnote =
      'Valid synchronized strata are 1-15. The packet-header stratum 0 is a '
      '"kiss-o\'-death" / unspecified marker, distinct from the stratum-0 '
      'reference-clock concept.';

  static const String _intro =
      'ISO 8601 / RFC 3339 date-time formats, UTC-offset notation, the Unix '
      'epoch and 2038 problem, leap seconds, and NTP stratum levels. '
      'Read-only reference; values trace to primary standards.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Date & Time Standards'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload - every section as a TSV block (subtitle + header +
  /// rows). Static data, so always enabled / non-null. The UTC-TAI offset is
  /// emitted with its "static value" qualifier so the copied text carries the
  /// same honesty flag the screen shows.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Date & Time Standards')
      ..writeln()
      ..writeln('ISO 8601 core formats')
      ..writeln(<String>['Concept', 'Format', 'Example', 'Note'].join(tab));
    for (final IsoFormat f in isoFormats) {
      buf.writeln(
        <String>[f.concept, f.format, f.example, f.note].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('UTC vs local offset notation')
      ..writeln(<String>['Notation', 'Meaning', 'Example'].join(tab));
    for (final OffsetNotation o in offsets) {
      buf.writeln(<String>[o.notation, o.meaning, o.example].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Unix epoch and the 2038 problem')
      ..writeln(<String>['Item', 'Value'].join(tab));
    for (final EpochFact e in epochFacts) {
      buf.writeln(<String>[e.item, e.value].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Leap seconds (UTC vs TAI)')
      ..writeln(<String>['Term', 'Definition'].join(tab));
    for (final TimescaleTerm t in timescales) {
      buf.writeln(<String>[t.term, t.definition].join(tab));
    }
    buf
      ..writeln(
        <String>[
          'UTC - TAI offset',
          '$utcTaiOffsetValue (static educational value; '
              'verify against IERS Bulletin C)',
        ].join(tab),
      )
      ..writeln()
      ..writeln('NTP stratum levels (RFC 5905)')
      ..writeln(<String>['Stratum', 'Meaning'].join(tab));
    for (final NtpStratum s in strata) {
      buf.writeln(<String>[s.stratum, s.meaning].join(tab));
    }
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
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
                  ConceptGraphicBand(toolId: _toolId, isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic(_toolId))
                    const SizedBox(height: AppSpacing.md),
                  _IntroText(text: _intro),
                  const SizedBox(height: AppSpacing.sm),
                  _isoCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _offsetCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _epochCard(colors, text),
                  const SizedBox(height: AppSpacing.md),
                  _leapCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _ntpCard(colors, text, mono),
                  ToolHelpFooter(toolId: _toolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _isoCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'ISO 8601 core formats',
      footnote: isoFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Concept', width: 136),
          _HeaderCell('Format', width: 168),
          _HeaderCell('Example', width: 230),
          _HeaderCell('Note', width: 300),
        ],
      ),
      rows: isoFormats.map((IsoFormat f) {
        return ReferenceRowSemantics(
          label: rowLabel(f.concept, <String?>[
            'format ${f.format}',
            'example ${f.example}',
            f.note,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 136,
                  child: Text(
                    f.concept,
                    style: text.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    f.format,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: Text(
                    f.example,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: Text(
                    f.note,
                    style: text.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _offsetCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'UTC vs local offset notation',
      footnote: offsetFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Notation', width: 96),
          _HeaderCell('Meaning', width: 250),
          _HeaderCell('Example', width: 230),
        ],
      ),
      rows: offsets.map((OffsetNotation o) {
        return ReferenceRowSemantics(
          label: rowLabel(o.notation, <String?>[o.meaning, 'example ${o.example}']),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    o.notation,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: Text(
                    o.meaning,
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: Text(
                    o.example,
                    style: mono.inlineCode.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _epochCard(AppColorScheme colors, TextTheme text) {
    return _SectionCard(
      title: 'Unix epoch and the 2038 problem',
      children: <Widget>[
        for (final EpochFact e in epochFacts)
          ReferenceRowSemantics(
            label: rowLabel(e.item, <String?>[e.value]),
            child: _KeyValueRow(item: e.item, value: e.value),
          ),
      ],
    );
  }

  Widget _leapCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _SectionCard(
      title: 'Leap seconds (UTC vs TAI)',
      children: <Widget>[
        for (final TimescaleTerm t in timescales)
          ReferenceRowSemantics(
            label: rowLabel(t.term, <String?>[t.definition]),
            child: _KeyValueRow(item: t.term, value: t.definition),
          ),
        // The UTC-TAI offset, flagged as a static educational value (not live).
        ReferenceRowSemantics(
          label:
              'UTC minus TAI offset: $utcTaiOffsetValue. $utcTaiOffsetCaption '
              'Static educational value. $utcTaiOffsetVerifyNote',
          child: _OffsetBadgeRow(
            value: utcTaiOffsetValue,
            caption: utcTaiOffsetCaption,
            verifyNote: utcTaiOffsetVerifyNote,
          ),
        ),
      ],
    );
  }

  Widget _ntpCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'NTP stratum levels (RFC 5905)',
      footnote: ntpFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Stratum', width: 72),
          _HeaderCell('Meaning', width: 360),
        ],
      ),
      rows: strata.map((NtpStratum s) {
        return ReferenceRowSemantics(
          label: rowLabel('Stratum ${s.stratum}', <String?>[s.meaning]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    s.stratum,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 360,
                  child: Text(
                    s.meaning,
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Intro paragraph, secondary text on the canvas.
class _IntroText extends StatelessWidget {
  const _IntroText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.labelMedium?.copyWith(color: colors.textSecondary),
    );
  }
}

/// A label · value attribute line for the list-style cards (epoch, leap).
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.item, required this.value});

  final String item;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              item,
              style: t.labelMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: t.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The UTC-TAI offset row, rendered with an explicit "static value" status
/// badge so the time-sensitive figure never reads as a live truth (GL-005).
/// The badge uses the §8.13 `StatusTone.warning` token (border + 12% fill); the
/// "STATIC VALUE" word always accompanies the color, so color is never the sole
/// carrier of meaning (SC 1.4.1), and the §8.13 border clears SC 1.4.11 on
/// surface1.
class _OffsetBadgeRow extends StatelessWidget {
  const _OffsetBadgeRow({
    required this.value,
    required this.caption,
    required this.verifyNote,
  });

  final String value;
  final String caption;
  final String verifyNote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color tone = colors.statusToneColor(StatusTone.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  'UTC - TAI offset',
                  style: t.labelMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: tone, width: 1),
                ),
                child: Text(
                  'STATIC VALUE',
                  style: t.labelSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: mono.inlineCode.copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            caption,
            style: t.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            verifyNote,
            style: t.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// A titled card wrapping list-style rows, separated by hairline dividers.
/// Matches the wpa_security `_SectionCard` idiom.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: colors.border));
      }
      rows.add(children[i]);
    }
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
            title,
            style: t.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows,
        ],
      ),
    );
  }
}

/// Card surface wrapping a wide table: title over a horizontally-scrolling
/// IntrinsicWidth grid (header + rows share one width so columns align), with an
/// optional full-width footnote beneath. Verbatim from the poe_reference idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
