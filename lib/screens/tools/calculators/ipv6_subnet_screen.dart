// IPv6 Subnet Calculator — expand/compress an IPv6 address and compute its
// network, first/last addresses, host count, and address type from a prefix.
//
// Math mirrors the RF Tools PWA (app.js calcIPv6 / expandIPv6 / compressIPv6 /
// detectIPv6Type, line 2155+), ported to Dart BigInt 128-bit math so the native
// app and the PWA agree field-for-field — with ONE deliberate divergence, ruled
// by Keith on 2026-08-02 and marked below:
//   expand     — pad each group to 4 hex digits, fill the :: run with zeros.
//   compress   — collapse the longest run of all-zero groups to "::".
//                DIVERGES FROM THE PWA, on purpose. The PWA drops half the "::"
//                when the zero run touches either end, so it prints "fe80/10"
//                and "ffff:c000:201", which are not addresses. This screen uses
//                the RFC 5952 compressor; see [compressIPv6].
//   network    — address & prefix-mask (128-bit).
//   first/last — network (first) and network | host-mask (last).
//   hosts      — 2^(128-prefix), shown as a count; ">2^63" above 63 host bits.
//   type       — RFC special-range detection from the expanded form.
//
// INPUT MODEL: two fields, matching the PWA (#ipv6-addr + #ipv6-prefix).
//   1. Address — an IPv6 literal, with or without "::" compression. Case
//      insensitive (lowercased before parsing, as the PWA does).
//   2. Prefix  — a number 0–128. A leading "/" is tolerated.
//
// Result presentation matches the IPv4 subnet calculator idiom: form card +
// live-recomputed results/error card wrapped in a Semantics liveRegion, fields
// via LabeledField, value lines via ValueRow.
//
// States (SOP-007 §5):
//  - idle    → form only (empty address blanks the result, no error).
//  - success → the full breakdown, live-recomputed on every valid keystroke.
//  - error   → empty/invalid address or out-of-range prefix → inline error card.
//
// Pure-Dart, no I/O, no platform APIs. All math is static on the public widget
// class so it is unit-testable against the PWA values.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/ipv6_address.dart';
import '../../../services/network/ipv6_transition.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../network/value_row.dart';
import '../labeled_field.dart';

/// The computed breakdown for a valid IPv6 address + prefix, or an error.
/// Mirrors the PWA's set of rendered fields (sv('ipv6-…')).
class Ipv6Result {
  const Ipv6Result({
    required this.expanded,
    required this.compressed,
    required this.network,
    required this.first,
    required this.last,
    required this.hosts,
    required this.type,
    this.zone,
  }) : error = null;

  const Ipv6Result.invalid(this.error)
    : expanded = '',
      compressed = '',
      network = '',
      first = '',
      last = '',
      hosts = '',
      type = '',
      zone = null;

  /// Full 8-group, 4-hex-digit form (PWA ipv6-expanded).
  final String expanded;

  /// Canonical compressed form (PWA ipv6-compressed).
  final String compressed;

  /// Network address with /prefix (PWA ipv6-network).
  final String network;

  /// First address in the prefix = network (PWA ipv6-first).
  final String first;

  /// Last address in the prefix (PWA ipv6-last).
  final String last;

  /// Host-count string (PWA ipv6-hosts).
  final String hosts;

  /// RFC range label (PWA ipv6-type).
  final String type;

  /// The zone index the user typed (`en0` from `fe80::1%en0`), or null when
  /// they typed none. A zone is a LOCAL interface selector, not part of the
  /// 128 bits, so it is stripped before any math. It is carried here so the
  /// screen can show it back rather than silently swallowing something the
  /// user typed — a value that vanishes with no acknowledgement reads as a
  /// tool that did not understand the input.
  ///
  /// Carries its READING, not just its text ([Ipv6Zone]): `%25` and `%2512`
  /// each have two defensible readings, and a bare `String?` would force the
  /// screen to print one of them as though it were the only one.
  final Ipv6Zone? zone;

  /// Non-null when input was rejected; all other fields are empty.
  final String? error;

  bool get isValid => error == null;
}

/// The one definition of what the screen says about a zone index, used by both
/// the rendered row and the copy payload so the two cannot drift.
///
/// WHY THIS EXISTS (Vera gate 2026-08-02, MEDIUM-1): the Zone row rendered a
/// bare `Zone: 25` for `fe80::1%25` with no caveat and no alternate reading.
/// The parser standing on one reading is correct — RFC 4007 keeps the zone
/// outside the 128 bits, so the math is untouched either way — but the ROW was
/// stating a guess as a fact. Tests that pin both readings are not a user
/// surface ([[feedback_ui_rendered_a_decision_it_lacked]]).
String zoneHelperText(Ipv6Zone zone) {
  switch (zone.reading) {
    case Ipv6ZoneReading.certain:
      return 'A zone names a local interface, so it is not part of the '
          'address and changes nothing above.';
    case Ipv6ZoneReading.bareTwentyFive:
      return 'Read as interface index 25. In a URL "%25" means "%", so a zone '
          'name may have been cut off. Either way the address is the same.';
    case Ipv6ZoneReading.escapedDigits:
      return 'Read as a URL, where "%25" means "%", so the zone is '
          '${zone.value}. Typed outside a URL it would be ${zone.alternate}. '
          'Either way the address is the same.';
  }
}

class Ipv6SubnetScreen extends StatefulWidget {
  const Ipv6SubnetScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Ports app.js: expandIPv6, compressIPv6, calcIPv6, detectIPv6Type.

  // EXTRACTED 2026-08-02: the four text/number primitives below moved verbatim
  // to [Ipv6Address] (lib/services/network/ipv6_address.dart) so the MAC bit
  // decoder and the transition-address decoder can reach them without importing
  // a widget. These statics are THIN DELEGATES, not duplicates — there is
  // exactly one definition of each algorithm, and every existing caller and
  // test that says `Ipv6SubnetScreen.expandIPv6(...)` still resolves.
  static final BigInt _mask128 = Ipv6Address.mask128;

  /// Expand an IPv6 literal to its full 8-group, 4-hex-digit form.
  /// Mirrors PWA expandIPv6. Throws [FormatException] on a malformed group
  /// layout (e.g. too many groups, more than one "::").
  static String expandIPv6(String addr) => Ipv6Address.expand(addr);

  /// Compress a full 8-group form to canonical "::" notation, collapsing the
  /// LONGEST run of all-zero groups (RFC 5952 §4.2).
  ///
  /// KEITH'S RULING, 2026-08-02: this screen uses the RFC-correct compressor.
  /// It previously delegated to a PWA-parity version that dropped half the
  /// "::" whenever the zero run touched either end, so the Network row printed
  /// `2001:db8/64` and `fe80/10` and the Compressed row printed
  /// `ffff:c000:201` — none of which is an IPv6 literal. Vera's gate proved
  /// the harm by pasting the screen's own Compressed value back into its own
  /// field and getting "Invalid IPv6 address format"
  /// (Deliverables/2026-08-02-ip-address-math-gate/evidence/paste-back-proof/).
  ///
  /// Text parity with the PWA is therefore NOT claimed for compression, and is
  /// deliberately given up: the PWA's strings were the defect. Parity still
  /// holds for expansion, the 128-bit math, host counts, and type detection.
  /// The paste-back property is guarded in ipv6_subnet_screen_test.dart.
  static String compressIPv6(String full) => Ipv6Address.compress(full);

  /// Render a 128-bit value to the full 8-group form. Mirrors PWA bigToFull.
  static String bigToFull(BigInt n) => Ipv6Address.fromBigInt(n);

  /// Parse the expanded form to a 128-bit BigInt. Mirrors PWA word packing.
  static BigInt toBigInt(String expanded) => Ipv6Address.toBigInt(expanded);

  /// RFC range label from the expanded form. Mirrors PWA detectIPv6Type.
  static String detectIPv6Type(String full) {
    if (full.startsWith('0000:0000:0000:0000:0000:0000:0000:0000')) {
      return 'Unspecified (::)';
    }
    if (full.startsWith('0000:0000:0000:0000:0000:0000:0000:0001')) {
      return 'Loopback (::1)';
    }
    if (full.startsWith('fe80')) return 'Link-Local (fe80::/10)';
    if (full.startsWith('fc') || full.startsWith('fd')) {
      return 'Unique Local (fc00::/7)';
    }
    if (full.startsWith('ff')) return 'Multicast (ff00::/8)';
    if (full.startsWith('2002')) return 'IPv4-mapped 6to4 (2002::/16)';
    if (full.startsWith('0000:0000:0000:0000:0000:ffff')) {
      return 'IPv4-mapped (::ffff:0:0/96)';
    }
    if (full.startsWith('2001:0db8')) return 'Documentation (2001:db8::/32)';
    return 'Global Unicast';
  }

  /// Host-count string for a prefix. Mirrors PWA hosts logic:
  ///   hostBits > 63 → "More than 2^63"
  ///   hostBits == 0 → "1 address"
  ///   else          → `2^N = <grouped count> addresses`
  static String hostsForPrefix(int prefix) {
    final int hostBits = 128 - prefix;
    if (hostBits > 63) return 'More than 2^63'; // "More than 2^63"
    if (hostBits == 0) return '1 address';
    final BigInt count = BigInt.two.pow(hostBits);
    return '2^$hostBits = ${_grouped(count)} addresses';
  }

  /// Thousands-grouped decimal, matching JS Number/BigInt toLocaleString()
  /// for the en-US default (comma every 3 digits).
  static String _grouped(BigInt n) {
    final String s = n.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  /// Full calculation. Mirrors PWA calcIPv6 end to end: validate, expand,
  /// 128-bit mask math, then emit every rendered field.
  static Ipv6Result calculate(String rawAddress, int prefix) {
    final String raw = rawAddress.trim();
    if (raw.isEmpty) {
      return const Ipv6Result.invalid('Enter an IPv6 address.');
    }
    if (prefix < 0 || prefix > 128) {
      return const Ipv6Result.invalid('Prefix must be 0–128.');
    }

    String expanded;
    Ipv6Zone? zone;
    try {
      // A zone index is read for display and stripped for the math; see
      // [Ipv6Address.zoneParse]. A malformed one (empty, or repeated) throws
      // here rather than being quietly truncated off.
      zone = Ipv6Address.zoneParse(raw);
      expanded = expandIPv6(raw.toLowerCase());
    } on FormatException {
      return const Ipv6Result.invalid('Invalid IPv6 address format.');
    }

    final List<String> groups = expanded.split(':');
    final RegExp hex4 = RegExp(r'^[0-9a-f]{4}$');
    if (groups.length != 8 || groups.any((String g) => !hex4.hasMatch(g))) {
      return const Ipv6Result.invalid('Invalid IPv6 address format.');
    }

    final BigInt full = toBigInt(expanded);

    final BigInt mask = prefix == 0
        ? BigInt.zero
        : ((BigInt.one << prefix) - BigInt.one) << (128 - prefix);
    final BigInt network = full & mask;
    final BigInt hostMask = (~mask) & _mask128;
    final BigInt last = network | hostMask;

    final String netFull = bigToFull(network);
    final String lastFull = bigToFull(last);
    final String addrFull = bigToFull(full);

    return Ipv6Result(
      expanded: addrFull,
      compressed: compressIPv6(addrFull),
      network: '${compressIPv6(netFull)}/$prefix',
      first: compressIPv6(netFull),
      last: compressIPv6(lastFull),
      hosts: hostsForPrefix(prefix),
      type: detectIPv6Type(addrFull),
      zone: zone,
    );
  }

  @override
  State<Ipv6SubnetScreen> createState() => _Ipv6SubnetScreenState();
}

class _Ipv6SubnetScreenState extends State<Ipv6SubnetScreen> {
  final TextEditingController _addrCtrl = TextEditingController(
    text: '2001:db8::1',
  );
  final TextEditingController _prefixCtrl = TextEditingController(text: '32');

  /// The transition section's own IPv4 field (item 8, IPv4 -> IPv6). The
  /// IPv6 -> IPv4 direction reads the address field above, so the section
  /// answers both directions without a second IPv6 input.
  final TextEditingController _v4Ctrl = TextEditingController(
    text: '192.0.2.1',
  );

  Ipv6Result? _result;

  // Screen-reader announcement gating (Vera calculator-gate finding #8 — IPv6
  // live-region verbosity). The result subtree recomputes and repaints on every
  // keystroke so a sighted user sees the breakdown update live, but a
  // liveRegion that re-announces the full 8-line breakdown on every character
  // floods VoiceOver / TalkBack. So the visual recompute stays synchronous while
  // the liveRegion flag is held false during active typing and flipped true
  // only after a short pause, so the screen reader announces the settled result
  // once instead of per-keystroke. The flag also gates on a settled value so the
  // very first paint (the seeded example) does not announce on screen entry.
  bool _announce = false;
  Timer? _announceTimer;

  // Pause after the last keystroke before the result is allowed to announce.
  static const Duration _announceDebounce = Duration(milliseconds: 600);

  // Address: hex digits, colon, and the optional IPv4-tail dot. Prefix:
  // digits and a leading slash. No spaces — these are typed literals.
  /// WIDENED 2026-08-02, and this was a live defect, not a nicety.
  ///
  /// This used to allow `[0-9A-Fa-f:.]` only. Paste a link-local straight off
  /// `ifconfig` — `fe80::1%en0` — and the filter deleted the `%` and the `n`,
  /// leaving `fe80::1e0`. That is a VALID but DIFFERENT address, so the screen
  /// computed a full, confident, wrong breakdown with nothing on it to say
  /// characters had been removed. A silent mangle is worse than a rejection:
  /// a rejection tells you to look, a mangle does not.
  ///
  /// The set now covers what an interface name can contain, and validation —
  /// not the keyboard filter — decides whether the address is real. A stray
  /// letter now reaches "Invalid IPv6 address format." instead of vanishing.
  static final List<TextInputFormatter> _addrFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z:.%_-]')),
  ];
  static final List<TextInputFormatter> _prefixFormatters =
      <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
      ];

  @override
  void initState() {
    super.initState();
    _addrCtrl.addListener(_recompute);
    _prefixCtrl.addListener(_recompute);
    _v4Ctrl.addListener(() => setState(() {}));
    // Seed an initial result so the screen opens on a worked example.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _announceTimer?.cancel();
    _addrCtrl.dispose();
    _prefixCtrl.dispose();
    _v4Ctrl.dispose();
    super.dispose();
  }

  /// Restart the announce-debounce on every recompute: hold the liveRegion
  /// silent while the user is actively typing, then flip it true once typing
  /// settles so the screen reader announces the final result a single time.
  void _scheduleAnnounce() {
    if (_announce) setState(() => _announce = false);
    _announceTimer?.cancel();
    _announceTimer = Timer(_announceDebounce, () {
      if (mounted) setState(() => _announce = true);
    });
  }

  void _recompute() {
    final String addr = _addrCtrl.text.trim();
    final String rawPrefix = _prefixCtrl.text.replaceFirst('/', '').trim();

    // Every keystroke restarts the announce debounce so the liveRegion only
    // speaks the settled result, never the per-character intermediate states.
    _scheduleAnnounce();

    // Empty address → blank the panel, no error (idle state).
    if (addr.isEmpty) {
      setState(() => _result = null);
      return;
    }

    // Empty prefix → blank rather than error, so an in-progress entry doesn't
    // flash a red card while the user is still typing the prefix.
    if (rawPrefix.isEmpty) {
      setState(() => _result = null);
      return;
    }

    final int? prefix = int.tryParse(rawPrefix);
    if (prefix == null) {
      setState(() {
        _result = const Ipv6Result.invalid('Prefix must be 0–128.');
      });
      return;
    }

    setState(() => _result = Ipv6SubnetScreen.calculate(addr, prefix));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IPv6 Subnet Calculator'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled while the input is
        // empty or malformed (no valid breakdown); copies the IPv6 breakdown as
        // a labeled text block. Copy leads; this screen has no help icon.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the IPv6 subnet breakdown as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// before the first compute, an empty address/prefix, or an invalid address /
  /// out-of-range prefix (the inline error card has nothing to keep). Field
  /// order and values match the on-screen [_resultsCard].
  String? _buildCopyText() {
    final Ipv6Result? r = _result;
    if (r == null || !r.isValid) return null;

    final StringBuffer buf = StringBuffer()
      ..writeln('IPv6 Subnet')
      ..writeln('Network: ${r.network}')
      ..writeln('Expanded: ${r.expanded}')
      ..writeln('Compressed: ${r.compressed}')
      ..writeln('First: ${r.first}')
      ..writeln('Last: ${r.last}')
      ..writeln('Addresses: ${r.hosts}')
      ..writeln('Type: ${r.type}');
    // Matches the on-screen row: present only when the user typed a zone.
    // The caveat travels ONLY when the reading is uncertain, and it travels
    // because it qualifies the VALUE — pasting a bare "Zone: 25" into a ticket
    // would re-commit MEDIUM-1 in another medium. The certain-case helper line
    // is an explanation rather than a qualifier, so it stays on screen with
    // the transition section's other notes and out of the payload.
    final Ipv6Zone? z = r.zone;
    if (z != null) {
      buf.writeln('Zone: ${z.value}');
      if (!z.isCertain) buf.writeln('Zone note: ${zoneHelperText(z)}');
    }

    // The transition decode travels with the breakdown, but ONLY when an IPv4
    // address was actually found. Pasting "Embedded IPv4: none" into a ticket
    // is noise, and pasting nothing is the honest alternative.
    final Ipv6ToIpv4Result t = Ipv6Transition.decode(_addrCtrl.text);
    if (t.isValid && t.hasIpv4) {
      buf
        ..writeln('Embedded IPv4: ${t.ipv4} (${t.label}, ${t.rfc})')
        ..writeln('Which is: ${t.ipv4Role}');
      if (t.teredoServer != null) {
        buf.writeln(
          'Teredo server: ${t.teredoServer}, '
          'client port ${t.teredoPort}',
        );
      }
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    return LayoutBuilder(
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
                  // §8.6.2 concept-graphic header band — first child, above
                  // the input card. Self-collapses when no graphic is
                  // bundled, so the 24px gap below it disappears too.
                  ConceptGraphicBand(
                    toolId: 'ipv6-subnet',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ipv6-subnet'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  // WCAG 4.1.3 — the calculator live-recomputes and swaps the
                  // results/error card without moving focus. A liveRegion on
                  // the swapped subtree lets the framework announce the change.
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      // liveRegion only after typing settles (finding #8): the
                      // breakdown still repaints live for sighted users, but the
                      // screen reader announces the settled result once instead
                      // of re-reading all eight lines on every keystroke.
                      liveRegion: _announce,
                      child: _result!.isValid
                          ? _resultsCard(context, _result!)
                          : _errorCard(context, _result!.error!),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _transitionCard(context),
                  ToolHelpFooter(toolId: 'ipv6-subnet'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Transition addresses — the IPv4-in-IPv6 formats, both directions.
  ///
  /// Item 7 (IPv6 -> IPv4) reads the SAME address field the breakdown above
  /// uses, because that is the field a pasted log line lands in. Item 8
  /// (IPv4 -> IPv6) needs an IPv4 address, so it carries one small field of its
  /// own. A section, not a tile: neither direction is a question a user goes
  /// looking for, they are both "what am I looking at" moments that happen
  /// while already on this screen
  /// (Deliverables/2026-08-02-iptoolkits-survey/BRIEF.md:128 and :129).
  Widget _transitionCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final Ipv6ToIpv4Result decoded = Ipv6Transition.decode(_addrCtrl.text);
    final Ipv4ToIpv6Result encoded = Ipv6Transition.encode(_v4Ctrl.text);

    Widget heading(String s) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        s,
        style: text.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );

    Widget note(String s) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        s,
        style: text.labelSmall?.copyWith(color: colors.textTertiary),
      ),
    );

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
          heading('IPv4 inside this address'),
          if (!decoded.isValid)
            note(
              'Enter a valid IPv6 address above and this section will say '
              'whether it carries an IPv4 address.',
            )
          else ...<Widget>[
            ValueRow(
              label: 'Format',
              value: decoded.label,
              emphasize: decoded.hasIpv4,
            ),
            if (decoded.rfc != null)
              ValueRow(label: 'Defined in', value: decoded.rfc),
            if (decoded.hasIpv4) ...<Widget>[
              ValueRow(
                label: 'IPv4',
                value: decoded.ipv4,
                identifier: true,
                emphasize: true,
              ),
              if (decoded.ipv4Role != null)
                ValueRow(label: 'Which is', value: decoded.ipv4Role),
            ],
            if (decoded.teredoServer != null)
              ValueRow(
                label: 'Teredo server',
                value: decoded.teredoServer,
                identifier: true,
              ),
            if (decoded.teredoPort != null)
              ValueRow(
                label: 'Client port',
                value: '${decoded.teredoPort}',
                mono: true,
              ),
            if (decoded.note != null) note(decoded.note!),
          ],
          const SizedBox(height: AppSpacing.md),
          heading('An IPv4 address written as IPv6'),
          LabeledField(
            label: 'IPv4 address',
            field: TextField(
              controller: _v4Ctrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '192.0.2.1'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (!encoded.isValid)
            note(encoded.error!)
          else ...<Widget>[
            ValueRow(
              label: 'As IPv4-mapped',
              value: encoded.mappedDotted,
              identifier: true,
              emphasize: true,
            ),
            ValueRow(
              label: 'Same, in hex',
              value: encoded.mappedHex,
              identifier: true,
            ),
            ValueRow(
              label: 'NAT64',
              value: encoded.nat64Dotted,
              identifier: true,
            ),
            ValueRow(
              label: '6to4 prefix',
              value: encoded.sixToFourPrefix,
              identifier: true,
            ),
            ValueRow(
              label: 'As IPv4-compatible',
              value: encoded.compatibleDotted,
              identifier: true,
            ),
            note(
              'IPv4-mapped is what a dual-stack socket shows for an IPv4 peer; '
              'it is not something you configure. The 6to4 value is a PREFIX '
              'for a whole site, not a host address. The NAT64 line uses the '
              'well-known 64:ff9b::/96 prefix; a network running its own '
              'prefix will differ. IPv4-compatible is deprecated and is here '
              'only so you can recognize one in an old configuration.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _formCard(BuildContext context) {
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
          LabeledField(
            label: 'IPv6 address',
            field: TextField(
              controller: _addrCtrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              inputFormatters: _addrFormatters,
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '2001:db8::1'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Prefix length',
            semanticLabel: 'Prefix length in bits',
            field: TextField(
              controller: _prefixCtrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: _prefixFormatters,
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '64'),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Enter an IPv6 address (compressed "::" allowed) and a prefix '
            'length 0–128.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _resultsCard(BuildContext context, Ipv6Result r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subnet',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Each readout is wrapped so a screen reader announces "Network:
          // 2001:db8::/64" as one node instead of the label and value as
          // separate fragments (Vera finding #6). The shared ValueRow widget
          // lives outside calculators/, so the wrap is applied at the call site.
          _semanticRow(
            'Network',
            r.network,
            ValueRow(
              label: 'Network',
              value: r.network,
              mono: true,
              emphasize: true,
            ),
          ),
          _semanticRow(
            'Expanded',
            r.expanded,
            ValueRow(label: 'Expanded', value: r.expanded, mono: true),
          ),
          _semanticRow(
            'Compressed',
            r.compressed,
            ValueRow(label: 'Compressed', value: r.compressed, mono: true),
          ),
          _semanticRow(
            'First',
            r.first,
            ValueRow(label: 'First', value: r.first, mono: true),
          ),
          _semanticRow(
            'Last',
            r.last,
            ValueRow(label: 'Last', value: r.last, mono: true),
          ),
          _semanticRow(
            'Addresses',
            r.hosts,
            ValueRow(label: 'Addresses', value: r.hosts, mono: true),
          ),
          _semanticRow('Type', r.type, ValueRow(label: 'Type', value: r.type)),
          // Only when the user typed one. A zone index names a LOCAL
          // interface, so it is stripped before the math — but it is shown
          // back, because a value that disappears with no acknowledgement
          // reads as an input the tool failed to understand.
          //
          // The row is followed by its helper line in every case: when the
          // reading is certain it says why the value changed nothing, and when
          // it is not it names the other reading instead of letting the row
          // pass a guess off as a fact (Vera MEDIUM-1, 2026-08-02).
          if (r.zone != null) ...<Widget>[
            _semanticRow(
              'Zone',
              r.zone!.value,
              ValueRow(label: 'Zone', value: r.zone!.value, mono: true),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                zoneHelperText(r.zone!),
                // bodySmall, NOT the labelSmall this screen's other notes use.
                // GL-003 §8.5.0's standing rule: a caption or label that wraps
                // to 3+ lines is promoted to a body style rather than squeezed
                // into the caption register. Measured at 390 dp the "%2512"
                // string wraps to three lines, so the caption register is not
                // available to it.
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Wraps a result [ValueRow] so a screen reader announces `<label>: <value>`
  /// as one node (Vera finding #6). [child] must be the visually-rendered row
  /// for [label]/[value]; the wrapper only changes the semantics tree.
  Widget _semanticRow(String label, String? value, Widget child) {
    final bool blank = value == null || value.trim().isEmpty;
    return Semantics(
      label: label,
      value: blank ? 'not calculated' : value,
      excludeSemantics: true,
      child: child,
    );
  }

  Widget _errorCard(BuildContext context, String message) {
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
          Icon(Icons.edit_outlined, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Check your input',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
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
