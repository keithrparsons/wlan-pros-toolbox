// VoIP over Wi-Fi Filters - grouped, filterable Wireshark display filters for
// voice traffic on a wireless network.
//
// Anyone can list `sip` and `rtp`. This card exists because a WLAN pro reaches
// for VoIP filters to answer three questions that are specifically about the
// air, and a generic enterprise VoIP filter sheet answers none of them:
//   1. Did the QoS marking survive the trip onto the air?
//   2. Did the call break at a roam?
//   3. Is power save eating it?
//
// EVERY FILTER STRING IN THIS FILE WAS COMPILED WITH `dftest` AGAINST A LIVE
// WIRESHARK 4.6.6 BEFORE IT SHIPPED (2026-09-15). dftest is the display-filter
// compiler Wireshark ships for exactly this purpose; it exits non-zero on an
// unknown field. A filter that does not parse is worse than an absent one,
// because the reader concludes their capture is empty rather than their filter
// wrong. The verifier lives at
// Deliverables/2026-09-15-voip-filters-card/verify_filters.py in myPKA, and
// test/screens/command/voip_wifi_filters_screen_test.dart re-asserts the
// dataset shape. Re-run the verifier after any edit to the filter strings.
//
// FOUR FIELDS THAT MUST NEVER APPEAR HERE. `rtp.analysis.lost`,
// `rtp.analysis.jitter`, `rtp.analysis.delta`, and `rtp.analysis.out_of_seq`
// all FAILED to compile: "is not a valid protocol or protocol field." They are
// a plausible-looking guess, not Wireshark fields. Wireshark's computed
// per-stream loss and jitter is a STATISTIC, not a filterable field, which is
// why this card carries a separate tshark-tap group instead. A test pins their
// absence.
//
// States (SOP-007 §5):
//  - success -> the filtered, grouped filter list renders (default; const
//    dataset, no load step).
//  - empty   -> a filter query that matches nothing; an honest "no match" card.
// No loading / error / NetworkUnavailableView - fully offline on every platform
// (filters are reference text, never executed; GL-008 does not apply).
//
// Pattern: the grouped-searchable idiom of wireshark_filters_screen.dart, with
// one addition - a group may carry a `note`, the teaching paragraph that
// belongs WITH its filters rather than buried in the help sheet. The filter
// syntax is the LIME column (GL-003 §2.6 / §8.2 `textAccent`).
//
// Glyph note: ASCII hyphen-minus only; no em dash. "802.11" / "802.1X" casing;
// "Wi-Fi" hyphenated with a capital F.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// One VoIP-over-Wi-Fi filter: the exact syntax and what it finds. Immutable.
@immutable
class VoipFilter {
  const VoipFilter(this.filter, this.description);

  /// The exact filter syntax, verified to compile. LIME column.
  final String filter;

  /// What it finds.
  final String description;
}

/// A labeled group of filters, optionally carrying the teaching paragraph that
/// belongs with them.
@immutable
class VoipFilterGroup {
  const VoipFilterGroup(this.label, this.filters, {this.note});

  final String label;
  final List<VoipFilter> filters;

  /// The short teaching passage rendered under the group heading, above the
  /// rows. `null` where the rows speak for themselves.
  final String? note;
}

class VoipWifiFiltersScreen extends StatefulWidget {
  const VoipWifiFiltersScreen({super.key});

  static const String intro =
      'Wireshark display filters for voice over Wi-Fi: the signaling, the '
      'media, and the three questions a WLAN pro asks that a generic VoIP '
      'filter sheet does not answer. Did the QoS marking survive the trip onto '
      'the air, did the call break at a roam, and is power save eating it. '
      'Filter by syntax or task.';

  static const String caveat =
      'Every filter here was compiled against Wireshark 4.6.6 before it '
      'shipped. The filters that combine an IP field with an 802.11 field need '
      'both headers visible in the same frame, so they want a monitor-mode '
      'capture of an open or decrypted network, not a capture taken on the '
      'client\'s own interface.';

  /// Cross-link to the DSCP / QoS Markings tool - the tool that explains the
  /// marking this card teaches you to check. The screen is read-only and does
  /// not navigate; this is a discoverability pointer, matching the CIDR table's
  /// pointer to the subnet calculator.
  static const String dscpCrossLink =
      'The marking this card teaches you to check is explained in full by the '
      'DSCP / QoS Markings tool: the DSCP class values, the User Priority to '
      'access-category mapping, and the default-mapping trap that drops voice '
      'into the video queue.';

  static const String footnote =
      'Frame type and subtype values are shown in hexadecimal here (0x02 is '
      'Reassociation request, 0x0c is Deauthentication); the Wireshark 802.11 '
      'Filters tool shows the same values in decimal and Wireshark accepts '
      'either form. RTP payload type numbers follow RFC 3551. The RTCP field '
      'names are Wireshark\'s own, with its own labels: rtcp.ssrc.fraction is '
      '"Fraction lost", rtcp.ssrc.cum_nr is "Cumulative number of packets '
      'lost", rtcp.ssrc.high_seq is "Highest sequence number received", and '
      'rtcp.ssrc.jitter is "Interarrival jitter" - a figure in RTP timestamp '
      'units, not milliseconds. Wireshark has no rtp.analysis display filter of '
      'any kind: its per-stream loss and jitter is a statistic, reached by the '
      'tshark tap above or by Telephony then RTP then RTP Streams. The app runs '
      'nothing - these are reference text you copy into Wireshark. Source: '
      'every filter compiled with dftest against Wireshark 4.6.6 on 2026-09-15; '
      'RTP and RTCP per RFC 3550 and RFC 3551; DSCP to User Priority per RFC '
      '8325.';

  /// The grouped filter set. Every `filter` string here compiles under
  /// Wireshark 4.6.6 (see the file header). Public + static so tests can assert
  /// known rows and pin the four fields that must never appear.
  static const List<VoipFilterGroup> groups = <VoipFilterGroup>[
    VoipFilterGroup('Find the call: signaling (display)', <VoipFilter>[
      VoipFilter('sip', 'All SIP signaling'),
      VoipFilter('sip.Method == "INVITE"', 'Call setup attempts'),
      VoipFilter(
        'sip.Method == "BYE"',
        'Call teardown, the normal end of a call',
      ),
      VoipFilter(
        'sip.Status-Code >= 400',
        'Failed setup, and the code says why',
      ),
      VoipFilter(
        'sip.Status-Code == 486',
        'Busy Here: the callee declined or was already on a call',
      ),
      VoipFilter(
        'sip.Call-ID',
        'Present on every message of one dialog; match on it to follow a single call',
      ),
      VoipFilter(
        'sip.resend == 1',
        'Retransmitted SIP messages, which on Wi-Fi often means the first copy never made it off the air',
      ),
      VoipFilter(
        'sdp',
        'The media negotiation, including the codec actually chosen',
      ),
      VoipFilter(
        'sdp.media.format',
        'The payload formats offered and answered',
      ),
      VoipFilter('udp.port == 5060', 'SIP over UDP on the default port'),
      VoipFilter('tcp.port == 5060', 'SIP over TCP on the default port'),
    ]),
    VoipFilterGroup('Find the media: RTP (display)', <VoipFilter>[
      VoipFilter('rtp', 'The media stream itself'),
      VoipFilter(
        'rtcp',
        'The control stream, which carries the endpoint\'s own loss and jitter report',
      ),
      VoipFilter(
        'rtp.ssrc == 0x12345678',
        'One stream, by its synchronization source. Substitute the SSRC from your own capture',
      ),
      VoipFilter(
        'rtp.seq',
        'Sequence number; the gap either side of a break is what you measure',
      ),
      VoipFilter(
        'rtp.timestamp',
        'Sampling instant of the first octet, for checking packet spacing',
      ),
      VoipFilter(
        'rtp.marker == 1',
        'Talkspurt starts, for spotting a restart after a gap',
      ),
      VoipFilter('rtp.p_type', 'Payload type: which codec is actually in use'),
      VoipFilter('rtp.p_type == 0', 'G.711 PCMU (mu-law)'),
      VoipFilter('rtp.p_type == 8', 'G.711 PCMA (A-law)'),
      VoipFilter('rtp.p_type == 9', 'G.722'),
      VoipFilter('rtp.p_type == 18', 'G.729'),
      VoipFilter(
        'rtp.setup-frame',
        'Wireshark\'s link back to the SDP frame that set this stream up',
      ),
    ]),
    // THE SECTION THAT JUSTIFIES THE CARD.
    VoipFilterGroup(
      'Did the QoS marking survive? (display)',
      <VoipFilter>[
        VoipFilter(
          'ip.dsfield.dscp == 46',
          'EF, what voice should be marked on the wire',
        ),
        VoipFilter(
          'wlan.qos.priority == 6',
          'User Priority 6, the Voice access category on the air',
        ),
        VoipFilter(
          'ip.dsfield.dscp == 46 && wlan.qos.priority != 6',
          'THE BUG: marked EF on the wire, not Voice on the air',
        ),
        VoipFilter(
          'ip.dsfield.dscp == 46 && wlan.qos.priority == 5',
          'The classic signature: EF landed in UP 5, which is the Video access category',
        ),
        VoipFilter(
          'rtp && wlan.qos.priority == 0',
          'Media riding Best Effort, the same fault seen from the other end',
        ),
        VoipFilter(
          'ip.dsfield.dscp == 0 && rtp',
          'Media that arrived carrying no marking at all',
        ),
        VoipFilter(
          'sip && ip.dsfield.dscp == 0',
          'Signaling that arrived unmarked',
        ),
        VoipFilter(
          'ip.dsfield.dscp == 40',
          'CS5, the signaling class in the RFC 4594 service model',
        ),
        VoipFilter(
          'ip.dsfield.dscp == 34',
          'AF41, the usual interactive-video marking',
        ),
        VoipFilter(
          'wlan.qos.priority',
          'Every QoS data frame that carries a User Priority at all',
        ),
      ],
      note:
          'DSCP lives in the IP header and User Priority lives in the 802.11 '
          'header, so something has to map one to the other. When that mapping '
          'is missing, wrong, or stripped by a tunnel, the call competes with '
          'everything else on the channel and the wire still looks perfect. '
          'Most gear, absent an explicit policy, derives User Priority from the '
          'top three bits of the DSCP value: EF is 46, which is 101110 in '
          'binary, and 101 is 5, so EF lands in UP 5 and the Video access '
          'category rather than Voice. That is why the third filter below '
          'usually turns up UP 5 rather than nothing.',
    ),
    VoipFilterGroup(
      'Did it break at a roam? (display)',
      <VoipFilter>[
        VoipFilter(
          'wlan.fc.type_subtype == 0x02',
          'Reassociation request, the roam itself',
        ),
        VoipFilter('wlan.fc.type_subtype == 0x03', 'Reassociation response'),
        VoipFilter(
          'wlan.fc.type_subtype == 0x0b',
          'Authentication, the frame before the reassociation',
        ),
        VoipFilter(
          'wlan.fc.type_subtype == 0x0c',
          'Deauthentication, a roam that was not the client\'s idea',
        ),
        // CORRECTED 2026-09-17 (Vera F1). This read `== 55` and called it the
        // Mobility Domain element. Wireshark's own registry, read out of the
        // 4.6.6 binary: 54 is Mobility Domain, 55 is Fast BSS Transition. The
        // filter COMPILED either way, which is why no verifier caught it.
        //
        // 54 is the right number for this row's question. The MDE is what a
        // beacon, probe response and association request carry to advertise
        // that FT is available; the FTE rides in the FT exchange itself. A pro
        // asking "is 802.11r on this SSID" filters beacons, and with == 55 got
        // zero hits and concluded FT was off.
        VoipFilter(
          'wlan.tag.number == 54',
          'Mobility Domain element, present when 802.11r Fast Transition is in play',
        ),
        VoipFilter(
          'rtp.ssrc == 0x12345678 && wlan.fc.retry == 1',
          'Retries on the one stream you are following',
        ),
      ],
      note:
          'The method is the part worth writing down. Filter to one rtp.ssrc, '
          'note the sequence numbers either side of the gap, then look at what '
          'the client did in between. A roam that costs 300 ms is audible. A '
          'roam that costs 50 ms is not. An RTP gap that lines up with a '
          'reassociation is a roaming problem wearing a VoIP costume.',
    ),
    VoipFilterGroup(
      'Is power save eating it? (display)',
      <VoipFilter>[
        VoipFilter(
          'wlan.fc.pwrmgt == 1',
          'Client telling the AP it is going to sleep',
        ),
        VoipFilter(
          'wlan.fc.pwrmgt == 1 && rtp',
          'A voice client sleeping mid-call',
        ),
        VoipFilter(
          'wlan.fc.type_subtype == 0x2c',
          'QoS Null, how a client usually announces the state change',
        ),
        VoipFilter(
          'wlan.fc.type_subtype == 0x1a',
          'PS-Poll, the legacy way a client retrieves one buffered frame',
        ),
        VoipFilter(
          'wlan.qos.eosp == 1',
          'End of service period, the AP closing a U-APSD burst',
        ),
      ],
      note:
          'A voice client that sleeps between packets sounds exactly like a '
          'network with loss, and the far end\'s own report will call it loss. '
          'The Power Management bit rides in the frame control field of every '
          'frame, so watch for where it flips rather than looking for a single '
          'announcement.',
    ),
    VoipFilterGroup(
      'What the endpoint itself says: RTCP (display)',
      <VoipFilter>[
        VoipFilter('rtcp.pt == 200', 'Sender Report'),
        VoipFilter(
          'rtcp.pt == 201',
          'Receiver Report, which carries the numbers below',
        ),
        VoipFilter(
          'rtcp.ssrc.fraction',
          'Fraction lost, Wireshark\'s own label for the field',
        ),
        VoipFilter('rtcp.ssrc.fraction > 0', 'Any report that admits to loss'),
        VoipFilter('rtcp.ssrc.cum_nr', 'Cumulative number of packets lost'),
        VoipFilter('rtcp.ssrc.high_seq', 'Highest sequence number received'),
        VoipFilter('rtcp.ssrc.jitter', 'Interarrival jitter'),
        VoipFilter(
          'rtcp.ssrc.jitter > 30',
          'Jitter above 30 timestamp units; at an 8 kHz clock one unit is 125 microseconds',
        ),
        VoipFilter(
          'rtcp.senderssrc',
          'The SSRC of the sender the report is about',
        ),
      ],
      note:
          'An RTCP receiver report is a measurement rather than an inference: '
          'it is the far endpoint stating what it actually received. That makes '
          'it the honest answer to a question this app deliberately does not '
          'compute for you.',
    ),
    // The dead end that produced the best section on the card.
    VoipFilterGroup(
      'Loss and jitter: two sources, and the disagreement is the finding',
      <VoipFilter>[
        VoipFilter(
          'tshark -q -z rtp,streams -r capture.pcapng',
          'Per-stream loss and jitter as THIS capture saw it',
        ),
        VoipFilter(
          'tshark -q -z sip,stat -r capture.pcapng',
          'SIP method and response-code counts across the capture',
        ),
        VoipFilter(
          'tshark -q -z follow,sip -r capture.pcapng',
          'Follow one SIP dialog end to end',
        ),
        VoipFilter(
          'Telephony > RTP > RTP Streams',
          'The same per-stream figures in the Wireshark GUI',
        ),
      ],
      note:
          'These are tshark statistics taps and GUI menu paths, NOT display '
          'filters - do not type them into the filter bar. Wireshark computes '
          'per-stream loss and jitter as a statistic, and there is no '
          'rtp.analysis field to filter on. So there are two sources for loss '
          'and jitter and they measure different things. The RTCP fields above '
          'are what the FAR ENDPOINT reported about what it received. The tap '
          'below is what THIS CAPTURE saw. When the two disagree, that is the '
          'finding: the capture point and the endpoint did not experience the '
          'same stream, which on Wi-Fi usually means the loss happened between '
          'them.',
    ),
  ];

  @override
  State<VoipWifiFiltersScreen> createState() => _VoipWifiFiltersScreenState();
}

class _VoipWifiFiltersScreenState extends State<VoipWifiFiltersScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  bool _matches(VoipFilter f, String q) {
    if (q.isEmpty) return true;
    return f.filter.toLowerCase().contains(q) ||
        f.description.toLowerCase().contains(q);
  }

  VoipFilterGroup? _filterGroup(VoipFilterGroup g, String q) {
    if (q.isEmpty) return g;
    if (g.label.toLowerCase().contains(q)) return g;
    final List<VoipFilter> kept = g.filters
        .where((VoipFilter f) => _matches(f, q))
        .toList();
    if (kept.isEmpty) return null;
    return VoipFilterGroup(g.label, kept, note: g.note);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final String q = value.trim().toLowerCase();
    int n = 0;
    for (final VoipFilterGroup g in VoipWifiFiltersScreen.groups) {
      final VoipFilterGroup? f = _filterGroup(g, q);
      if (f != null) n += f.filters.length;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching rows' : '$n matching row${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 plain-text payload - every group with its teaching note and its
  /// exact syntax, so a reader can paste the whole sheet.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('VoIP over Wi-Fi Filters')
      ..writeln()
      ..writeln(VoipWifiFiltersScreen.intro)
      ..writeln();
    for (final VoipFilterGroup g in VoipWifiFiltersScreen.groups) {
      b.writeln(g.label);
      final String? note = g.note;
      if (note != null) b.writeln('  $note');
      for (final VoipFilter f in g.filters) {
        b.writeln('  ${f.filter}$tab${f.description}');
      }
      b.writeln();
    }
    b
      ..writeln(VoipWifiFiltersScreen.dscpCrossLink)
      ..writeln()
      ..writeln(VoipWifiFiltersScreen.footnote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoIP over Wi-Fi Filters'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
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
              maxWidth: AppSpacing.contentMaxWidth,
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
                    toolId: 'voip-wifi-filters',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('voip-wifi-filters'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _crossLinkCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ..._results(context),
                  ToolHelpFooter(toolId: 'voip-wifi-filters'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
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
        children: [
          Text(
            VoipWifiFiltersScreen.intro,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            VoipWifiFiltersScreen.caveat,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Pointer card to the DSCP / QoS Markings tool. Rendered as its own surface
  /// above the search so it reads as guidance, not as a filter row.
  Widget _crossLinkCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        VoipWifiFiltersScreen.dscpCrossLink,
        style: text.labelMedium?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Filter',
        hint: 'syntax or task',
        semanticLabel: 'Filter VoIP over Wi-Fi filters by syntax or task',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: 'e.g. roam or dscp'),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final String q = _query.trim().toLowerCase();

    final List<Widget> cards = <Widget>[];
    for (final VoipFilterGroup g in VoipWifiFiltersScreen.groups) {
      final VoipFilterGroup? f = _filterGroup(g, q);
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      VoipWifiFiltersScreen.footnote,
      style: text.labelSmall?.copyWith(color: colors.textTertiary),
    );
  }
}

/// One group: a heading, an optional teaching note, then its filter rows.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final VoipFilterGroup group;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String? note = group.note;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              note,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          ...group.filters.map(
            (VoipFilter f) => _FilterRow(filter: f, mono: mono, text: text),
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

  final VoipFilter filter;
  final AppMonoText mono;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${filter.filter}, ${filter.description}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              filter.filter,
              style: mono.inlineCode.copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              filter.description,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state card - mirrors the 802.11 filters "no match" surface.
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
