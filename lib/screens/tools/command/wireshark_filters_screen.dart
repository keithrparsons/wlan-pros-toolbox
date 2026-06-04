// Wireshark 802.11 Filters — grouped, filterable display + capture filters.
//
// Display filters (applied after capture, in the filter bar) and capture filters
// (BPF syntax, applied during capture) for 802.11 analysis. Read-only with a
// free-text filter. Data is the Pax research deliverable
// (pax-research-7-additions.md, "Wireshark 802.11 Filters"), sourced from the
// Wireshark dfref, the RadioTap dfref, pcap-filter(7), and IEEE 802.11-2020.
//
// Two corrections from Pax carried through verbatim:
//  1. The RSN cipher-suite vs AKM tables were REBUILT from IEEE 802.11-2020
//     Tables 9-149 (cipher = pcs/gcs.type) and 9-151 (AKM = akms.type); the
//     source card mislabeled cipher values as AKM. These tables use the
//     corrected field names.
//  2. The 5 GHz band filter: Pax flagged `radiotap.channel.flags.5ghz` as a
//     child-token to confirm against the running Wireshark build, with a SAFE
//     FALLBACK to `radiotap.channel.freq` ranges. Felix cannot verify the
//     child-token against a live Wireshark here, so the SAFE FALLBACK ships:
//     `radiotap.channel.freq >= 5000 && radiotap.channel.freq < 6000` (and a
//     2.4 GHz companion). `radiotap.channel.freq` is a documented dfref field;
//     this never ships an unverified token.
//
// States (SOP-007 §5):
//  - success → the filtered, grouped filter list renders (default; const
//    dataset, no load step).
//  - empty   → a filter query that matches nothing; an honest "no match" card.
// No loading / error / NetworkUnavailableView — fully offline on every platform
// (filters are reference text, never executed; GL-008 does not apply).
//
// Pattern: the reason_codes grouped-searchable idiom (see linux_wlan_commands).
// The filter syntax is the LIME column.
//
// Glyph note: ASCII hyphen-minus only; no em dash. "802.11" / "802.1X" casing.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One Wireshark filter: the exact syntax and what it matches. Immutable.
@immutable
class WiresharkFilter {
  const WiresharkFilter(this.filter, this.description);

  /// The exact filter syntax. LIME column.
  final String filter;

  /// What it matches.
  final String description;
}

/// A labeled group of filters (Frame type/subtype, Address, RSN AKM, etc.).
@immutable
class FilterGroup {
  const FilterGroup(this.label, this.filters);

  final String label;
  final List<WiresharkFilter> filters;
}

class WiresharkFiltersScreen extends StatefulWidget {
  const WiresharkFiltersScreen({super.key});

  static const String intro =
      'Display filters (applied after capture, in the filter bar) and capture '
      'filters (BPF syntax, applied during capture) for 802.11 analysis. Filter '
      'by syntax or task.';

  static const String caveat =
      'Display-filter field names match Wireshark\'s dfref. Capture filters use '
      'libpcap/BPF "type/subtype" syntax and only work when capturing with a '
      'RadioTap/PPI header.';

  static const String footnote =
      'type_subtype is the combined value (type in the high bits, subtype in '
      'the low bits) and matches IEEE 802.11 frame type/subtype assignments. '
      'Capture filters require capturing with a RadioTap header (monitor mode). '
      'For the full RSN cipher and AKM number-to-name map, see the RSN tables '
      'below or the WPA Security reference tool.';

  /// The grouped filter set, verbatim from the Pax research deliverable, with
  /// the 5 GHz/2.4 GHz band filters using the SAFE freq-range fallback (see
  /// file header). Public + static so tests can assert known rows.
  static const List<FilterGroup> groups = <FilterGroup>[
    FilterGroup('Frame type/subtype (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.fc.type == 0', 'All management frames'),
      WiresharkFilter('wlan.fc.type == 1', 'All control frames'),
      WiresharkFilter('wlan.fc.type == 2', 'All data frames'),
      WiresharkFilter('wlan.fc.type_subtype == 0', 'Association request'),
      WiresharkFilter('wlan.fc.type_subtype == 1', 'Association response'),
      WiresharkFilter('wlan.fc.type_subtype == 2', 'Reassociation request'),
      WiresharkFilter('wlan.fc.type_subtype == 3', 'Reassociation response'),
      WiresharkFilter('wlan.fc.type_subtype == 4', 'Probe request'),
      WiresharkFilter('wlan.fc.type_subtype == 5', 'Probe response'),
      WiresharkFilter('wlan.fc.type_subtype == 8', 'Beacon'),
      WiresharkFilter('wlan.fc.type_subtype == 9', 'ATIM'),
      WiresharkFilter('wlan.fc.type_subtype == 10', 'Disassociation'),
      WiresharkFilter('wlan.fc.type_subtype == 11', 'Authentication'),
      WiresharkFilter('wlan.fc.type_subtype == 12', 'Deauthentication'),
      WiresharkFilter('wlan.fc.type_subtype == 13', 'Action'),
      WiresharkFilter('wlan.fc.type_subtype == 24', 'Block Ack Request'),
      WiresharkFilter('wlan.fc.type_subtype == 25', 'Block Ack'),
      WiresharkFilter('wlan.fc.type_subtype == 26', 'PS-Poll'),
      WiresharkFilter('wlan.fc.type_subtype == 27', 'RTS'),
      WiresharkFilter('wlan.fc.type_subtype == 28', 'CTS'),
      WiresharkFilter('wlan.fc.type_subtype == 29', 'Ack'),
      WiresharkFilter('wlan.fc.type_subtype == 36', 'Null data (no payload)'),
      WiresharkFilter('wlan.fc.type_subtype == 40', 'QoS data'),
      WiresharkFilter('wlan.fc.type_subtype == 44', 'QoS Null (no data)'),
    ]),
    FilterGroup('Address (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.addr == aa:bb:cc:dd:ee:ff', 'Any address field equals this MAC (TA, RA, SA, or DA)'),
      WiresharkFilter('wlan.ta == aa:bb:cc:dd:ee:ff', 'Transmitter address'),
      WiresharkFilter('wlan.ra == aa:bb:cc:dd:ee:ff', 'Receiver address'),
      WiresharkFilter('wlan.sa == aa:bb:cc:dd:ee:ff', 'Source address'),
      WiresharkFilter('wlan.da == aa:bb:cc:dd:ee:ff', 'Destination address'),
    ]),
    FilterGroup('BSSID/SSID (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.bssid == aa:bb:cc:dd:ee:ff', 'Frames for a specific BSSID'),
      WiresharkFilter('wlan.ssid == "MyNetwork"', 'Frames carrying this SSID (beacons, probes)'),
      WiresharkFilter('wlan.ssid contains "Guest"', 'SSID contains a substring'),
    ]),
    FilterGroup('RadioTap (display)', <WiresharkFilter>[
      WiresharkFilter('radiotap.channel.freq == 2412', 'Captured on this channel center frequency (MHz)'),
      WiresharkFilter('radiotap.datarate >= 6', 'PHY data rate at least 6 Mb/s'),
      WiresharkFilter('radiotap.dbm_antsignal > -70', 'RSSI stronger than -70 dBm'),
      WiresharkFilter('radiotap.dbm_antnoise < -90', 'Noise floor below -90 dBm'),
      // SAFE FALLBACK (Pax flag): freq-range band filters instead of the
      // unverified radiotap.channel.flags.5ghz child-token. freq is a
      // documented dfref field.
      WiresharkFilter('radiotap.channel.freq >= 2400 && radiotap.channel.freq < 2500', 'Captured in the 2.4 GHz band (frequency range)'),
      WiresharkFilter('radiotap.channel.freq >= 5000 && radiotap.channel.freq < 5900', 'Captured in the 5 GHz band (frequency range)'),
      WiresharkFilter('radiotap.channel.freq >= 5925 && radiotap.channel.freq <= 7125', 'Captured in the 6 GHz band (frequency range)'),
    ]),
    FilterGroup('Capture filter (BPF)', <WiresharkFilter>[
      WiresharkFilter('type mgt', 'Only management frames'),
      WiresharkFilter('type ctl', 'Only control frames'),
      WiresharkFilter('type data', 'Only data frames'),
      WiresharkFilter('type mgt subtype beacon', 'Beacons only'),
      WiresharkFilter('type mgt subtype probe-req', 'Probe requests only'),
      WiresharkFilter('type mgt subtype deauth', 'Deauthentication frames only'),
      WiresharkFilter('type ctl subtype rts', 'RTS frames only'),
      WiresharkFilter('type ctl subtype ack', 'Acknowledgement frames only'),
      WiresharkFilter('wlan host aa:bb:cc:dd:ee:ff', 'Frames to/from this L2 address'),
    ]),
    // CORRECTED per Pax: cipher-suite selectors are pcs/gcs.type (Table 9-149),
    // NOT akms.type. The source card mislabeled these as AKM.
    FilterGroup('RSN cipher (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.rsn.pcs.type == 4', 'Pairwise cipher = CCMP-128 (00-0F-AC:4)'),
      WiresharkFilter('wlan.rsn.pcs.type == 8', 'Pairwise cipher = GCMP-128 (00-0F-AC:8)'),
      WiresharkFilter('wlan.rsn.pcs.type == 9', 'Pairwise cipher = GCMP-256 (00-0F-AC:9)'),
      WiresharkFilter('wlan.rsn.gcs.type == 2', 'Group cipher = TKIP (00-0F-AC:2)'),
    ]),
    // CORRECTED per Pax: AKM selectors are akms.type (Table 9-151).
    FilterGroup('RSN AKM (display)', <WiresharkFilter>[
      WiresharkFilter('wlan.rsn.akms.type == 1', 'AKM = 802.1X (00-0F-AC:1)'),
      WiresharkFilter('wlan.rsn.akms.type == 2', 'AKM = PSK (00-0F-AC:2)'),
      WiresharkFilter('wlan.rsn.akms.type == 8', 'AKM = SAE / WPA3-Personal (00-0F-AC:8)'),
      WiresharkFilter('wlan.rsn.akms.type == 18', 'AKM = OWE (00-0F-AC:18)'),
    ]),
  ];

  @override
  State<WiresharkFiltersScreen> createState() => _WiresharkFiltersScreenState();
}

class _WiresharkFiltersScreenState extends State<WiresharkFiltersScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  bool _matches(WiresharkFilter f, String q) {
    if (q.isEmpty) return true;
    return f.filter.toLowerCase().contains(q) ||
        f.description.toLowerCase().contains(q);
  }

  FilterGroup? _filterGroup(FilterGroup g, String q) {
    if (q.isEmpty) return g;
    if (g.label.toLowerCase().contains(q)) return g;
    final List<WiresharkFilter> kept =
        g.filters.where((WiresharkFilter f) => _matches(f, q)).toList();
    if (kept.isEmpty) return null;
    return FilterGroup(g.label, kept);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final String q = value.trim().toLowerCase();
    int n = 0;
    for (final FilterGroup g in WiresharkFiltersScreen.groups) {
      final FilterGroup? f = _filterGroup(g, q);
      if (f != null) n += f.filters.length;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching filters' : '$n matching filter${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wireshark 802.11 Filters'),
        toolbarHeight: 64,
        actions: const <Widget>[
        ],
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
                    toolId: 'wireshark-80211-filters',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('wireshark-80211-filters'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                  ToolHelpFooter(toolId: 'wireshark-80211-filters'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            WiresharkFiltersScreen.intro,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            WiresharkFiltersScreen.caveat,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
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
        hint: 'syntax or task',
        semanticLabel: 'Filter Wireshark filters by syntax or task',
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
            hintText: 'e.g. beacon or rsn',
          ),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();

    final List<Widget> cards = <Widget>[];
    for (final FilterGroup g in WiresharkFiltersScreen.groups) {
      final FilterGroup? f = _filterGroup(g, q);
      if (f != null) {
        cards.add(_GroupCard(group: f));
        cards.add(const SizedBox(height: AppSpacing.sm));
      }
    }

    if (cards.isEmpty) {
      return <Widget>[
        _MessageCard(
          icon: Icons.search_off,
          title: 'No match',
          body: 'No filter matches "${_query.trim()}".',
        ),
      ];
    }

    cards.add(_footnote(context));
    return cards;
  }

  Widget _footnote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      WiresharkFiltersScreen.footnote,
      style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// One group: a heading over its filter rows in a bordered card.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final FilterGroup group;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
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
          ...group.filters.map(
            (WiresharkFilter f) =>
                _FilterRow(filter: f, mono: mono, text: text),
          ),
        ],
      ),
    );
  }
}

/// One filter row: the mono syntax (lime) over its description.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.mono,
    required this.text,
  });

  final WiresharkFilter filter;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${filter.filter}, ${filter.description}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              filter.filter,
              style: mono.inlineCode.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              filter.description,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state card — mirrors the reason_codes "no match" surface.
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
