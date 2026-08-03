// IPv4 Subnet Calculator tool — network/broadcast/host math from an address +
// CIDR prefix or dotted mask. Pure-Dart, runs on every platform incl. web.
//
// TWO MODES, added 2026-08-02, both IPv4 mask arithmetic on the screen the
// user is already looking at rather than on new tiles
// (Deliverables/2026-08-02-iptoolkits-survey/BRIEF.md:142 and :154).
//
// SUBNET MODE — INPUT MODEL: two fields.
//   1. Address — accepts a bare address ("10.20.0.0") OR address-with-prefix
//      ("10.20.0.0/22"); an inline /prefix wins and disables the second field.
//   2. Prefix or mask — a CIDR prefix ("22" or "/22") OR a dotted mask
//      ("255.255.252.0"). Ignored when the address already carries a /prefix.
//   The result carries a "Number forms" block: the address as an integer, as
//   hex, and the address AND mask as 32 bits with the prefix boundary drawn on
//   them. The address shown in binary is the one TYPED, not the network base,
//   because seeing 10.20.0.37 against a /22 boundary is what teaches which bits
//   are host bits.
//
// RANGE MODE — two endpoints in, the minimal set of CIDR blocks out. The first
// field also accepts a whole block, which runs the conversion the other way:
// type 10.4.16.0/20 and read its range. A range that does not start on a CIDR
// boundary, or is not a whole power of two long, needs more than one block, and
// the screen says how many and why rather than rounding to a block that would
// cover addresses the user did not ask for.
//
// States (SOP-007 §5):
//  - idle      → form only (an empty first field in Range mode; an empty
//                prefix field in Subnet mode).
//  - success   → the full breakdown (live-recomputes on every valid keystroke).
//  - error     → malformed address / bad prefix / bad mask / a last address
//                before the first, via the inline error block.
//  - empty     → not applicable: a valid /32 still yields a single-host result,
//                a valid /31 yields a two-host result — both are real results.
//
// NO NetworkUnavailableView: this tool does no I/O, so there is no web-blocked
// path. It is the live replacement for the "IP Subnetting (IPv4)" placeholder.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/interface_info_service.dart';
import '../../../services/network/ip_block_math.dart';
import '../../../services/network/ipv4_forms.dart';
import '../../../services/network/subnet_calc_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'value_row.dart';
import '../labeled_field.dart';

/// Which of the two questions the screen is answering. Both are IPv4 mask
/// arithmetic on one screen, per the 2026-08-02 survey ruling that a capability
/// belonging on a screen the user is already looking at goes THERE, not onto a
/// new tile (Deliverables/2026-08-02-iptoolkits-survey/BRIEF.md:142 and :154).
enum SubnetCalcMode {
  /// An address plus a prefix or mask, giving the full subnet breakdown.
  subnet,

  /// A start and end address, giving the minimal set of CIDR blocks that
  /// covers the range exactly, and the reverse when a block is typed instead.
  range,
}

class SubnetCalcScreen extends StatefulWidget {
  const SubnetCalcScreen({super.key, this.service, this.interfaceInfo});

  final SubnetCalcService? service;

  /// Injectable interface-info reader so a test can script (or skip) the
  /// device-IP prefill. Defaults to the production reader; null after default
  /// when constructed const-free.
  final InterfaceInfoService? interfaceInfo;

  @override
  State<SubnetCalcScreen> createState() => _SubnetCalcScreenState();
}

class _SubnetCalcScreenState extends State<SubnetCalcScreen> {
  late final SubnetCalcService _service;
  // BF5-6: prefilled with the device's own IP network + mask on open (see
  // _prefillFromDevice). These are the fallback worked-example values used when
  // the device IP can't be read (web, no network, permission), so the screen
  // never opens blank.
  final TextEditingController _addrCtrl = TextEditingController(
    text: '10.20.0.0',
  );
  final TextEditingController _prefixCtrl = TextEditingController(text: '22');

  /// Range mode's two endpoints. The first also accepts a whole block, which
  /// is the "and back" direction.
  final TextEditingController _startCtrl = TextEditingController(
    text: '10.4.16.0',
  );
  final TextEditingController _endCtrl = TextEditingController(
    text: '10.4.31.255',
  );

  SubnetCalcMode _mode = SubnetCalcMode.subnet;
  SubnetResult? _result;
  RangeResult? _range;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? const SubnetCalcService();
    _addrCtrl.addListener(_recompute);
    _prefixCtrl.addListener(_recompute);
    _startCtrl.addListener(_recomputeRange);
    _endCtrl.addListener(_recomputeRange);
    // Seed an initial result so the screen opens on the success state with a
    // worked example rather than a blank panel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recompute();
      _recomputeRange();
    });
    // BF5-6: try to replace the worked example with the device's current IP +
    // subnet mask. Best-effort and non-blocking — on web / no-network / no
    // permission the worked example above stays.
    _prefillFromDevice();
  }

  /// BF5-6 — read the device's primary IPv4 + subnet mask and prefill the form
  /// so the calculator opens on the user's own network. Honest fallback: if no
  /// usable IPv4/mask comes back, the worked-example defaults remain untouched.
  Future<void> _prefillFromDevice() async {
    final InterfaceInfoService reader =
        widget.interfaceInfo ?? InterfaceInfoService();
    InterfaceInfoSnapshot snap;
    try {
      snap = await reader.read();
    } catch (_) {
      return; // keep the worked example
    }
    if (!mounted) return;
    final String? ip = snap.primaryIPv4;
    final String? mask = snap.wifi.subnetMask;
    // Only prefill when BOTH a routable IPv4 and a dotted mask are known — a
    // bare IP with no mask would change the example to something half-real.
    if (ip == null || ip.isEmpty || mask == null || mask.isEmpty) return;
    // Don't clobber the field if the user has already started typing.
    if (_addrCtrl.text != '10.20.0.0' || _prefixCtrl.text != '22') return;
    _addrCtrl.text = ip;
    _prefixCtrl.text = mask;
    _recompute();
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _prefixCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _recomputeRange() {
    final RangeResult? r = IpBlockMath.rangeToBlocks(
      start: _startCtrl.text,
      end: _endCtrl.text,
    );
    setState(() => _range = r);
  }

  void _recompute() {
    final String rawAddr = _addrCtrl.text.trim();
    final String rawPrefix = _prefixCtrl.text.trim();

    // An inline "address/prefix" takes precedence over the second field.
    String address = rawAddr;
    int? prefix;
    String? mask;
    bool inlinePrefix = false;

    if (rawAddr.contains('/')) {
      final List<String> parts = rawAddr.split('/');
      address = parts[0].trim();
      if (parts.length == 2) {
        prefix = int.tryParse(parts[1].trim());
        inlinePrefix = true;
      } else {
        // More than one slash — let the service reject the malformed address.
        address = rawAddr;
      }
    }

    if (!inlinePrefix) {
      if (rawPrefix.isEmpty) {
        setState(() => _result = null);
        return;
      }
      final String cleaned = rawPrefix.replaceFirst('/', '').trim();
      if (cleaned.contains('.')) {
        // Dotted mask.
        mask = cleaned;
      } else {
        prefix = int.tryParse(cleaned);
        if (prefix == null) {
          setState(() {
            _result = const SubnetResult.invalid(
              'Prefix must be a number 0–32, or enter a dotted mask like '
              '255.255.252.0.',
            );
          });
          return;
        }
      }
    } else if (prefix == null) {
      setState(() {
        _result = const SubnetResult.invalid(
          'The /prefix after the address must be a number 0–32.',
        );
      });
      return;
    }

    if (address.isEmpty) {
      setState(() => _result = null);
      return;
    }

    final SubnetResult r = _service.calculate(
      address: address,
      prefix: prefix,
      mask: mask,
    );
    setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IP Subnetting (IPv4)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled while the input is
        // empty or malformed (no valid breakdown); copies the subnet breakdown
        // as a labeled text block. Copy leads; this screen has no help icon.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the IPv4 subnet breakdown as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// before the first compute, an empty field, or a malformed address/prefix/mask
  /// (the inline error card has nothing to keep). Field order and values match
  /// the on-screen [_resultsCard]; /31 and /32 have no broadcast, so that line is
  /// written as "Unavailable" (honest blank, GL-005) rather than fabricated. The
  /// RFC 3021 / single-host note copies when present.
  String? _buildCopyText() {
    if (_mode == SubnetCalcMode.range) {
      final RangeResult? rr = _range;
      if (rr == null || !rr.isValid) return null;
      final StringBuffer buf = StringBuffer()
        ..writeln('IPv4 Range')
        ..writeln('First: ${rr.firstAddress}')
        ..writeln('Last: ${rr.lastAddress}')
        ..writeln('Total IPs: ${_grouped(rr.totalAddresses)}')
        ..writeln(
          'Blocks (${rr.blocks.length}): '
          '${rr.blocks.map((Ipv4Block b) => b.cidr).join(', ')}',
        );
      return buf.toString().trimRight();
    }

    final SubnetResult? r = _result;
    if (r == null || !r.isValid) return null;

    String val(String? s) =>
        (s == null || s.trim().isEmpty) ? 'Unavailable' : s;
    final String? hostNote = switch (r.prefix) {
      31 => 'RFC 3021 point-to-point: both addresses are usable hosts.',
      32 => 'Single-host route: one address, no network/broadcast.',
      _ => null,
    };

    final StringBuffer buf = StringBuffer()
      ..writeln('IPv4 Subnet')
      ..writeln('Network: ${val(r.networkAddress)}/${r.prefix}')
      ..writeln('Netmask: ${val(r.dottedMask)}')
      ..writeln('Wildcard: ${val(r.wildcardMask)}')
      ..writeln('Broadcast: ${val(r.broadcastAddress)}')
      ..writeln('First host: ${val(r.firstHost)}')
      ..writeln('Last host: ${val(r.lastHost)}')
      ..writeln('Total IPs: ${r.totalAddresses ?? 'Unavailable'}')
      ..writeln('Usable hosts: ${r.usableHosts ?? 'Unavailable'}');
    if (hostNote != null) buf.writeln(hostNote);

    final int? addrInt = (r.inputAddress == null || r.prefix == null)
        ? null
        : SubnetCalcService.parseIpv4ToInt(r.inputAddress!);
    if (addrInt != null) {
      buf
        ..writeln('Address: ${r.inputAddress}')
        ..writeln('Integer: ${Ipv4Forms.toInteger(addrInt)}')
        ..writeln('Hex: ${Ipv4Forms.toHex(addrInt)}')
        ..writeln(
          'Address in binary: '
          '${Ipv4Forms.toBinary(addrInt, boundary: r.prefix)}',
        )
        ..writeln(
          'Netmask in binary: '
          '${Ipv4Forms.toBinary(SubnetCalcService.maskIntForPrefix(r.prefix!), boundary: r.prefix)}',
        );
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
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                    toolId: 'ipv4-subnet',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ipv4-subnet'))
                    const SizedBox(height: AppSpacing.md),
                  AppToggle<SubnetCalcMode>(
                    value: _mode,
                    semanticLabel: 'Calculator mode',
                    expand: true,
                    items: const <AppToggleItem<SubnetCalcMode>>[
                      (SubnetCalcMode.subnet, 'Subnet'),
                      (SubnetCalcMode.range, 'Range'),
                    ],
                    onChanged: (SubnetCalcMode m) {
                      if (m == _mode) return;
                      setState(() => _mode = m);
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_mode == SubnetCalcMode.subnet)
                    _formCard(context)
                  else
                    _rangeFormCard(context),
                  // WCAG 4.1.3 — the calculator live-recomputes on every
                  // keystroke and swaps the results/error card without moving
                  // focus, so a screen reader hears nothing on its own. A
                  // liveRegion on the results/error subtree lets the framework
                  // announce the change AND debounce rapid keystroke recomputes
                  // (vs. a per-keystroke sendAnnouncement, which machine-guns
                  // the SR). The form fields carry their own label semantics via
                  // LabeledField in a separate subtree, so there is no
                  // double-announcement here.
                  if (_mode == SubnetCalcMode.subnet && _result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      liveRegion: true,
                      child: _result!.isValid
                          ? _resultsCard(context, _result!)
                          : _errorCard(context, _result!.error!),
                    ),
                  ],
                  if (_mode == SubnetCalcMode.range && _range != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      liveRegion: true,
                      child: _range!.isValid
                          ? _rangeResultsCard(context, _range!)
                          : _errorCard(context, _range!.error!),
                    ),
                  ],
                  ToolHelpFooter(toolId: 'ipv4-subnet'),
                ],
              ),
            ),
          ),
        );
      },
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
            label: 'IPv4 address',
            field: TextField(
              controller: _addrCtrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9./]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(
                hintText: '10.20.0.0 or 10.20.0.0/22',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Prefix or mask',
            semanticLabel: 'Prefix or subnet mask',
            field: TextField(
              controller: _prefixCtrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9./]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(
                hintText: '22 or 255.255.252.0',
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Enter a CIDR prefix (e.g. 22) or a dotted mask (255.255.252.0). '
            'A /prefix typed after the address wins.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Range mode's form: two endpoints, where the first also accepts a whole
  /// block so the conversion runs both ways from one field.
  Widget _rangeFormCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool fromBlock = _range?.derivedFromBlock ?? false;
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
          LabeledField(
            label: 'First address',
            semanticLabel: 'First address, or a whole CIDR block',
            field: TextField(
              controller: _startCtrl,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9./]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(
                hintText: '10.4.16.0 or 10.4.16.0/20',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Last address',
            field: TextField(
              controller: _endCtrl,
              enabled: !fromBlock,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '10.4.31.255'),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fromBlock
                ? 'The first field carries a /prefix, so the range comes from '
                      'that block and this field is ignored. Remove the prefix '
                      'to type two endpoints instead.'
                : 'Type two endpoints to get the blocks that cover them, or '
                      'type a whole block in the first field to get its range.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _rangeResultsCard(BuildContext context, RangeResult r) {
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
        children: <Widget>[
          Text(
            // NOT "Range": that is the toggle's label, and two identical
            // strings on one screen make the control ambiguous to a screen
            // reader and to a test.
            'Address range',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueRow(label: 'First', value: r.firstAddress, identifier: true),
          ValueRow(label: 'Last', value: r.lastAddress, identifier: true),
          ValueRow(
            label: 'Total IPs',
            value: _grouped(r.totalAddresses),
            mono: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            r.isSingleBlock
                ? 'Covered by 1 block'
                : 'Covered by ${r.blocks.length} blocks',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final Ipv4Block b in r.blocks)
            ValueRow(
              label: b.cidr,
              value: '${_grouped(b.size)} addresses',
              mono: true,
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            r.hostBitsWereSet
                ? 'That block was typed with host bits set, so it was read as '
                      '${r.blocks.first.cidr}.'
                : r.isSingleBlock
                ? 'This range lands exactly on one CIDR boundary, so a single '
                      'block covers it with nothing left over.'
                : 'A range only collapses to one block when it starts on a '
                      'CIDR boundary and is a whole power of two long. This one '
                      'does not, so it takes ${r.blocks.length} blocks to cover '
                      'it exactly and no fewer.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  /// Thousands-grouped decimal so a 4,294,967,296 stays readable.
  static String _grouped(int n) {
    final String s = n.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  Widget _resultsCard(BuildContext context, SubnetResult r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // RFC 3021 / single-host annotations so the host counts aren't surprising.
    final String? hostNote = switch (r.prefix) {
      31 => 'RFC 3021 point-to-point: both addresses are usable hosts.',
      32 => 'Single-host route: one address, no network/broadcast.',
      _ => null,
    };
    // The address AS TYPED, not the network base: seeing 10.20.0.37 against
    // the /22 boundary is what teaches which bits are host bits. Null only if
    // the address somehow failed to re-parse, in which case the block is
    // omitted rather than shown wrong.
    final int? addrInt = (r.inputAddress == null || r.prefix == null)
        ? null
        : SubnetCalcService.parseIpv4ToInt(r.inputAddress!);

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
          ValueRow(
            label: 'Network',
            value: '${r.networkAddress}/${r.prefix}',
            identifier: true,
            emphasize: true,
          ),
          ValueRow(label: 'Netmask', value: r.dottedMask, identifier: true),
          ValueRow(label: 'Wildcard', value: r.wildcardMask, identifier: true),
          ValueRow(
            label: 'Broadcast',
            // /31 and /32 have no broadcast — ValueRow renders the unavailable
            // treatment for a null value, which is the honest answer here.
            value: r.broadcastAddress,
            identifier: true,
          ),
          ValueRow(label: 'First host', value: r.firstHost, identifier: true),
          ValueRow(label: 'Last host', value: r.lastHost, identifier: true),
          ValueRow(
            label: 'Total IPs',
            value: '${r.totalAddresses}',
            mono: true,
          ),
          ValueRow(
            label: 'Usable hosts',
            value: '${r.usableHosts}',
            mono: true,
          ),
          if (hostNote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              hostNote,
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          // ── Number forms (2026-08-02) ──────────────────────────────────
          // The same address as an integer, as hex, and as bits. These are
          // ROWS on this result rather than their own tile, per the survey
          // ruling (BRIEF.md:145): three output rows do not earn a tile.
          // The binary pair is the reason the block exists. Rendering the
          // address and the mask as 32 bits with the separator sitting
          // exactly at the prefix, mid-octet when the prefix is mid-octet,
          // shows what "the mask marks the boundary" means better than the
          // sentence does.
          if (addrInt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Number forms',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ValueRow(
              label: 'Integer',
              value: _grouped(Ipv4Forms.toInteger(addrInt)),
              mono: true,
            ),
            ValueRow(
              label: 'Hex',
              value: Ipv4Forms.toHex(addrInt),
              identifier: true,
            ),
            ValueRow(
              label: 'Dotted hex',
              value: Ipv4Forms.toDottedHex(addrInt),
              identifier: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            _binaryLine(
              context,
              'Address',
              Ipv4Forms.toBinary(addrInt, boundary: r.prefix),
            ),
            _binaryLine(
              context,
              'Netmask',
              Ipv4Forms.toBinary(
                SubnetCalcService.maskIntForPrefix(r.prefix!),
                boundary: r.prefix,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The slash sits where the /${r.prefix} ends. Everything left of '
              'it is the network, everything right of it is the host.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  /// A full-width monospace binary row. These strings are 35 characters and do
  /// not fit the label/value column split a [ValueRow] uses, so the label sits
  /// on its own line above the bits and the bits get the whole width. On the
  /// narrowest phone the line still wraps rather than overflowing.
  Widget _binaryLine(BuildContext context, String label, String bits) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$label in binary',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          SelectableText(
            bits,
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
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
