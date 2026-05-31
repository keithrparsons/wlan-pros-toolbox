// 802.11 Reason & Status Codes — an offline reference for the deauth /
// disassoc reason codes (RC) and association status codes (SC) that show up in
// PCAP analysis. Read-only; no input beyond a free-text filter.
//
// Data is reproduced verbatim from the RF Tools PWA `reason` tool view
// (RC_DATA / RC_GROUPS / SC_DATA in www/app.js). Codes are not invented; the
// groupings mirror the PWA exactly. Source: IEEE 802.11-2020 §9.4.1.7 (reason
// codes) and §9.4.1.9 (status codes).
//
// States (SOP-007 §5):
//  - success → the grouped reason/status tables render (the default; the
//    dataset is bundled in source, so there is no load step).
//  - empty   → a filter query that matches nothing; an honest "no match" card,
//    never a fabricated row.
// There is no loading or error state: the dataset is a compile-time const, so
// it cannot fail to load. There is no NetworkUnavailableView — this tool is
// fully offline on every platform.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One reason or status code: the numeric code and its meaning. Immutable.
class CodeEntry {
  const CodeEntry(this.code, this.meaning);

  /// The numeric code as it appears on the wire (RC or SC value).
  final int code;

  /// The plain-language meaning, verbatim from the PWA dataset.
  final String meaning;
}

/// A labeled group of codes (mirrors the PWA's RC_GROUPS / SC section heading).
class CodeGroup {
  const CodeGroup(this.label, this.entries);

  final String label;
  final List<CodeEntry> entries;
}

class ReasonCodesScreen extends StatefulWidget {
  const ReasonCodesScreen({super.key});

  /// Deauth / disassoc reason codes, grouped exactly as the PWA RC_GROUPS.
  /// Public + static so tests can assert known codes without pumping the UI.
  static const List<CodeGroup> reasonGroups = <CodeGroup>[
    CodeGroup('Common (seen in most captures)', <CodeEntry>[
      CodeEntry(1, 'Unspecified reason'),
      CodeEntry(2, 'Previous auth no longer valid (expired)'),
      CodeEntry(3, 'Deauth — STA leaving BSS (or IBSS)'),
      CodeEntry(4, 'Disassoc — inactivity timer expired'),
      CodeEntry(5, 'Disassoc — AP cannot handle all associated STAs (capacity)'),
      CodeEntry(6, 'Class 2 frame received from non-auth STA'),
      CodeEntry(7, 'Class 3 frame received from non-assoc STA'),
      CodeEntry(8, 'Disassoc — STA leaving BSS'),
      CodeEntry(9, 'STA requesting (re)assoc not auth with responding STA'),
    ]),
    CodeGroup('Capability / Channel mismatch', <CodeEntry>[
      CodeEntry(10, 'Disassoc — power capability element unacceptable'),
      CodeEntry(11, 'Disassoc — supported channels element unacceptable'),
    ]),
    CodeGroup('Security — frame / element errors', <CodeEntry>[
      CodeEntry(13, 'Invalid information element'),
      CodeEntry(14, 'MIC failure (TKIP or CCMP MIC check failed)'),
      CodeEntry(17, '4-Way Handshake Information Element mismatch'),
      CodeEntry(18, 'Invalid group cipher'),
      CodeEntry(19, 'Invalid pairwise cipher'),
      CodeEntry(20, 'Invalid AKMP (auth key management protocol)'),
      CodeEntry(21, 'Unsupported RSNE version'),
      CodeEntry(22, 'Invalid RSNE capabilities'),
      CodeEntry(24, 'Cipher suite rejected per security policy'),
    ]),
    CodeGroup('Security — handshake failures', <CodeEntry>[
      CodeEntry(15, '4-Way Handshake timeout'),
      CodeEntry(16, 'Group Key Handshake timeout'),
      CodeEntry(23, '802.1X authentication failed'),
    ]),
    CodeGroup('QoS / load management', <CodeEntry>[
      CodeEntry(34, 'Disassoc — QoS-related reason'),
      CodeEntry(35, 'Disassoc — insufficient bandwidth for QoS AP'),
      CodeEntry(36, 'Disassoc — excessive frames not acked (poor link)'),
      CodeEntry(37, 'Disassoc — STA transmitting outside TXOP'),
      CodeEntry(38, 'STA leaving BSS or resetting'),
      CodeEntry(39, 'Peer using unsupported cipher suite'),
    ]),
    CodeGroup('Fast Roaming (802.11r)', <CodeEntry>[
      CodeEntry(45, 'Invalid FTIE (Fast BSS Transition)'),
      CodeEntry(46, 'Requested PMKID not found'),
      CodeEntry(47, 'Invalid MDE (Mobility Domain Element)'),
      CodeEntry(48, 'Invalid FTE (Fast Transition Element)'),
    ]),
  ];

  /// Association status codes (most common subset), verbatim from PWA SC_DATA.
  /// Code 0 is the success value and is highlighted in the UI.
  static const CodeGroup statusGroup = CodeGroup(
    'Association Status Codes (most common)',
    <CodeEntry>[
      CodeEntry(0, 'Successful'),
      CodeEntry(1, 'Unspecified failure'),
      CodeEntry(10, 'Cannot support all requested capabilities'),
      CodeEntry(11, 'Reassociation denied — previous association not found'),
      CodeEntry(12, 'Association denied — reason outside scope of 802.11'),
      CodeEntry(13, 'Responding STA does not support specified auth algorithm'),
      CodeEntry(14, 'Auth sequence out of expected sequence'),
      CodeEntry(15, 'Auth rejected — challenge failure'),
      CodeEntry(16, 'Auth rejected — timeout waiting for next frame'),
      CodeEntry(17, 'Assoc denied — AP cannot handle additional associated STAs'),
      CodeEntry(18, 'Association denied — basic rates not supported'),
      CodeEntry(19, 'Association denied — short preamble not supported'),
      CodeEntry(23, 'Unspecified QoS failure'),
      CodeEntry(24, 'Association denied — QoS capacity insufficient'),
      CodeEntry(25, 'Association denied — poor link conditions'),
      CodeEntry(37, 'Association denied — requesting STA not supporting MFP'),
      CodeEntry(38, 'Association denied — AP requires MFP'),
      CodeEntry(72, 'Requesting STA does not support HT features'),
      CodeEntry(73, 'PCCO transition time not OK'),
      CodeEntry(76, 'Requesting STA does not support VHT features'),
      CodeEntry(104, 'Requesting STA does not support HE features'),
    ],
  );

  @override
  State<ReasonCodesScreen> createState() => _ReasonCodesScreenState();
}

class _ReasonCodesScreenState extends State<ReasonCodesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  /// True when [entry] matches the trimmed, lower-cased [_query] by code or
  /// meaning. An empty query matches everything.
  bool _matches(CodeEntry entry, String q) {
    if (q.isEmpty) return true;
    if (entry.code.toString().contains(q)) return true;
    return entry.meaning.toLowerCase().contains(q);
  }

  /// Apply the current filter to a group; returns null when nothing matches so
  /// the heading is dropped along with its (empty) table.
  CodeGroup? _filterGroup(CodeGroup group, String q) {
    if (q.isEmpty) return group;
    final List<CodeEntry> kept =
        group.entries.where((CodeEntry e) => _matches(e, q)).toList();
    if (kept.isEmpty) return null;
    return CodeGroup(group.label, kept);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // WCAG 4.1.3 — announce the live match count so AT users hear the tables
    // change as they type, without focus leaving the field.
    final String q = value.trim().toLowerCase();
    int n = 0;
    for (final CodeGroup g in ReasonCodesScreen.reasonGroups) {
      n += g.entries.where((CodeEntry e) => _matches(e, q)).length;
    }
    n += ReasonCodesScreen.statusGroup.entries
        .where((CodeEntry e) => _matches(e, q))
        .length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching codes' : '$n matching code${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('802.11 Reason Codes'),
        toolbarHeight: 64,
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
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
                children: [
                  ConceptGraphicBand(
                    toolId: 'reason-codes',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('reason-codes'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        '802.11 deauthentication reason codes and association status codes — '
        'referenced in Deauth, Disassoc, Auth, and Association Response frames '
        'during PCAP analysis.',
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Filter',
        hint: 'code number or keyword',
        semanticLabel: 'Filter codes by number or keyword',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: AppColors.primary,
          decoration: const InputDecoration(
            hintText: 'e.g. 15 or handshake',
          ),
        ),
      ),
    );
  }

  /// Build the filtered group cards plus the status-code card and footnote. An
  /// all-empty result yields a single "no match" card.
  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();

    final List<Widget> cards = <Widget>[];
    for (final CodeGroup g in ReasonCodesScreen.reasonGroups) {
      final CodeGroup? filtered = _filterGroup(g, q);
      if (filtered != null) {
        cards.add(_GroupCard(group: filtered));
        cards.add(const SizedBox(height: AppSpacing.sm));
      }
    }

    final CodeGroup? status = _filterGroup(ReasonCodesScreen.statusGroup, q);
    if (status != null) {
      cards.add(_GroupCard(group: status, highlightZero: true));
      cards.add(const SizedBox(height: AppSpacing.sm));
    }

    if (cards.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No reason or status code matches "${_query.trim()}".',
        ),
      ];
    }

    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      'Reason codes (RC) appear in Deauthentication and Disassociation frames. '
      'Status codes (SC) appear in Authentication, Association, and '
      'Reassociation Response frames. Source: IEEE 802.11-2020 §9.4.1.7 and '
      '§9.4.1.9.',
      style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// One group: a heading line followed by its code rows in a bordered card.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, this.highlightZero = false});

  final CodeGroup group;

  /// When true, code 0 renders in the success color (status-code success row).
  final bool highlightZero;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
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
            group.label,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...group.entries.map(
            (CodeEntry e) => _CodeRow(
              entry: e,
              highlight: highlightZero && e.code == 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// One code row: the numeric code in a fixed-width gutter, meaning beside it.
class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.entry, this.highlight = false});

  final CodeEntry entry;

  /// Render the code + meaning in the success color (the SC 0 "Successful" row).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color codeColor =
        highlight ? AppColors.statusSuccess : AppColors.textPrimary;
    final Color meaningColor =
        highlight ? AppColors.statusSuccess : AppColors.textSecondary;
    // Merge code + meaning into one semantic node so AT reads "15, 4-Way
    // Handshake timeout" as a single row instead of two fragments.
    return Semantics(
      container: true,
      label: '${entry.code}, ${entry.meaning}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '${entry.code}',
                style: text.bodyMedium?.copyWith(
                  color: codeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                entry.meaning,
                style: text.labelMedium?.copyWith(
                  color: meaningColor,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state card — mirrors the port reference's "no match" surface.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
