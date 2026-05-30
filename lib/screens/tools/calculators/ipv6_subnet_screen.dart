// IPv6 Subnet Calculator — expand/compress an IPv6 address and compute its
// network, first/last addresses, host count, and address type from a prefix.
//
// Math mirrors the RF Tools PWA (app.js calcIPv6 / expandIPv6 / compressIPv6 /
// detectIPv6Type, line 2155+) exactly, ported to Dart BigInt 128-bit math so
// the native app and the PWA agree field-for-field:
//   expand     — pad each group to 4 hex digits, fill the :: run with zeros.
//   compress   — collapse the longest run of all-zero groups to "::".
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
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
  })  : error = null;

  const Ipv6Result.invalid(this.error)
      : expanded = '',
        compressed = '',
        network = '',
        first = '',
        last = '',
        hosts = '',
        type = '';

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

  /// Non-null when input was rejected; all other fields are empty.
  final String? error;

  bool get isValid => error == null;
}

class Ipv6SubnetScreen extends StatefulWidget {
  const Ipv6SubnetScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Ports app.js: expandIPv6, compressIPv6, calcIPv6, detectIPv6Type.

  static final BigInt _mask128 = (BigInt.one << 128) - BigInt.one;
  static final BigInt _mask64 = (BigInt.one << 64) - BigInt.one;

  /// Expand an IPv6 literal to its full 8-group, 4-hex-digit form.
  /// Mirrors PWA expandIPv6. Throws [FormatException] on a malformed group
  /// layout (e.g. too many groups, more than one "::").
  static String expandIPv6(String addr) {
    if (addr.contains('::')) {
      // Reject more than one "::" — the PWA's split on "::" silently keeps the
      // first two parts; we treat anything but exactly one "::" as malformed so
      // the caller surfaces the invalid-format error instead of a wrong answer.
      if ('::'.allMatches(addr).length != 1) {
        throw const FormatException('multiple "::" runs');
      }
      final List<String> halves = addr.split('::');
      final List<String> left =
          halves[0].isEmpty ? <String>[] : halves[0].split(':');
      final List<String> right =
          halves[1].isEmpty ? <String>[] : halves[1].split(':');
      final int missing = 8 - left.length - right.length;
      if (missing < 1) {
        throw const FormatException('"::" with no zero groups to fill');
      }
      final List<String> mid = List<String>.filled(missing, '0000');
      return <String>[...left, ...mid, ...right]
          .map((String g) => g.padLeft(4, '0'))
          .join(':');
    }
    return addr.split(':').map((String g) => g.padLeft(4, '0')).join(':');
  }

  /// Compress a full 8-group form to canonical "::" notation.
  /// Mirrors PWA compressIPv6: collapse the LONGEST run of all-zero groups.
  static String compressIPv6(String full) {
    List<String?> parts = full.split(':').cast<String?>();
    int bestStart = -1, bestLen = 0;
    int curStart = -1, curLen = 0;
    for (int i = 0; i < parts.length; i++) {
      if (parts[i] == '0000') {
        if (curStart < 0) {
          curStart = i;
          curLen = 1;
        } else {
          curLen++;
        }
        if (curLen > bestLen) {
          bestStart = curStart;
          bestLen = curLen;
        }
      } else {
        curStart = -1;
        curLen = 0;
      }
    }

    if (bestLen > 1) {
      parts = <String?>[
        ...parts.sublist(0, bestStart),
        null,
        ...parts.sublist(bestStart + bestLen),
      ];
      final String joined = parts
          .map((String? p) =>
              p == null ? '' : BigInt.parse(p, radix: 16).toRadixString(16))
          .join(':')
          .replaceAll(RegExp(r'^:|:$'), '')
          .replaceFirst(':::', '::');
      return joined.isEmpty ? '::' : joined;
    }
    return parts
        .map((String? p) => BigInt.parse(p!, radix: 16).toRadixString(16))
        .join(':');
  }

  /// Render a 128-bit value to the full 8-group form. Mirrors PWA bigToFull.
  static String bigToFull(BigInt n) {
    final BigInt hi = (n >> 64) & _mask64;
    final BigInt lo = n & _mask64;
    String toHex(BigInt v) {
      final String s = v.toRadixString(16).padLeft(16, '0');
      // Split into 4-hex-digit groups.
      return <String>[
        s.substring(0, 4),
        s.substring(4, 8),
        s.substring(8, 12),
        s.substring(12, 16),
      ].join(':');
    }

    return '${toHex(hi)}:${toHex(lo)}';
  }

  /// Parse the expanded form to a 128-bit BigInt. Mirrors PWA word packing.
  static BigInt toBigInt(String expanded) {
    final List<String> parts = expanded.split(':');
    BigInt v = BigInt.zero;
    for (final String p in parts) {
      v = (v << 16) | BigInt.parse(p, radix: 16);
    }
    return v;
  }

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
  ///   hostBits > 63 → "More than 2⁶³"
  ///   hostBits == 0 → "1 address"
  ///   else          → `2^N = <grouped count> addresses`
  static String hostsForPrefix(int prefix) {
    final int hostBits = 128 - prefix;
    if (hostBits > 63) return 'More than 2⁶³'; // "More than 2⁶³"
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
    try {
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
    );
  }

  @override
  State<Ipv6SubnetScreen> createState() => _Ipv6SubnetScreenState();
}

class _Ipv6SubnetScreenState extends State<Ipv6SubnetScreen> {
  final TextEditingController _addrCtrl =
      TextEditingController(text: '2001:db8::1');
  final TextEditingController _prefixCtrl = TextEditingController(text: '32');

  Ipv6Result? _result;

  // Address: hex digits, colon, and the optional IPv4-tail dot. Prefix:
  // digits and a leading slash. No spaces — these are typed literals.
  static final List<TextInputFormatter> _addrFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f:.]')),
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
    // Seed an initial result so the screen opens on a worked example.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  void _recompute() {
    final String addr = _addrCtrl.text.trim();
    final String rawPrefix = _prefixCtrl.text.replaceFirst('/', '').trim();

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
                  // §8.6.2 concept-graphic header band — first child, above
                  // the input card. Self-collapses when no graphic is
                  // bundled, so the 24px gap below it disappears too.
                  ConceptGraphicBand(
                      toolId: 'ipv6-subnet', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('ipv6-subnet'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  // WCAG 4.1.3 — the calculator live-recomputes and swaps the
                  // results/error card without moving focus. A liveRegion on
                  // the swapped subtree lets the framework announce the change.
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      liveRegion: true,
                      child: _result!.isValid
                          ? _resultsCard(context, _result!)
                          : _errorCard(context, _result!.error!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
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
          LabeledField(
            label: 'IPv6 address',
            field: TextField(
              controller: _addrCtrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              inputFormatters: _addrFormatters,
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                hintText: '2001:db8::1',
              ),
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
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '64'),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Enter an IPv6 address (compressed "::" allowed) and a prefix '
            'length 0–128.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _resultsCard(BuildContext context, Ipv6Result r) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subnet',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueRow(
            label: 'Network',
            value: r.network,
            mono: true,
            emphasize: true,
          ),
          ValueRow(label: 'Expanded', value: r.expanded, mono: true),
          ValueRow(label: 'Compressed', value: r.compressed, mono: true),
          ValueRow(label: 'First', value: r.first, mono: true),
          ValueRow(label: 'Last', value: r.last, mono: true),
          ValueRow(label: 'Addresses', value: r.hosts, mono: true),
          ValueRow(label: 'Type', value: r.type),
        ],
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message) {
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
          Icon(Icons.edit_outlined, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Check your input',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
