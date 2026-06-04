// IPv4 Subnet Calculator tool — network/broadcast/host math from an address +
// CIDR prefix or dotted mask. Pure-Dart, runs on every platform incl. web.
//
// INPUT MODEL: two fields.
//   1. Address — accepts a bare address ("10.20.0.0") OR address-with-prefix
//      ("10.20.0.0/22"); an inline /prefix wins and disables the second field.
//   2. Prefix or mask — a CIDR prefix ("22" or "/22") OR a dotted mask
//      ("255.255.252.0"). Ignored when the address already carries a /prefix.
//
// States (SOP-007 §5):
//  - idle      → form only.
//  - success   → the full breakdown (live-recomputes on every valid keystroke).
//  - error     → malformed address / bad prefix / bad mask, via the inline
//                error block (matching Port Scan's validation style).
//  - empty     → not applicable: a valid /32 still yields a single-host result,
//                a valid /31 yields a two-host result — both are real results.
//
// NO NetworkUnavailableView: this tool does no I/O, so there is no web-blocked
// path. It is the live replacement for the "IP Subnetting (IPv4)" placeholder.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/subnet_calc_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import 'value_row.dart';
import '../labeled_field.dart';

class SubnetCalcScreen extends StatefulWidget {
  const SubnetCalcScreen({super.key, this.service});

  final SubnetCalcService? service;

  @override
  State<SubnetCalcScreen> createState() => _SubnetCalcScreenState();
}

class _SubnetCalcScreenState extends State<SubnetCalcScreen> {
  late final SubnetCalcService _service;
  final TextEditingController _addrCtrl = TextEditingController(
    text: '10.20.0.0',
  );
  final TextEditingController _prefixCtrl = TextEditingController(text: '22');

  SubnetResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? const SubnetCalcService();
    _addrCtrl.addListener(_recompute);
    _prefixCtrl.addListener(_recompute);
    // Seed an initial result so the screen opens on the success state with a
    // worked example rather than a blank panel.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
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
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'ipv4-subnet'),
        ],
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
    final SubnetResult? r = _result;
    if (r == null || !r.isValid) return null;

    String val(String? s) =>
        (s == null || s.trim().isEmpty) ? 'Unavailable' : s;
    final String? hostNote = switch (r.prefix) {
      31 => 'RFC 3021 point-to-point — both addresses are usable hosts.',
      32 => 'Single-host route — one address, no network/broadcast.',
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
                  _formCard(context),
                  // WCAG 4.1.3 — the calculator live-recomputes on every
                  // keystroke and swaps the results/error card without moving
                  // focus, so a screen reader hears nothing on its own. A
                  // liveRegion on the results/error subtree lets the framework
                  // announce the change AND debounce rapid keystroke recomputes
                  // (vs. a per-keystroke sendAnnouncement, which machine-guns
                  // the SR). The form fields carry their own label semantics via
                  // LabeledField in a separate subtree, so there is no
                  // double-announcement here.
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
              cursorColor: AppColors.primary,
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
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                hintText: '22 or 255.255.252.0',
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Enter a CIDR prefix (e.g. 22) or a dotted mask (255.255.252.0). '
            'A /prefix typed after the address wins.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _resultsCard(BuildContext context, SubnetResult r) {
    final TextTheme text = Theme.of(context).textTheme;
    // RFC 3021 / single-host annotations so the host counts aren't surprising.
    final String? hostNote = switch (r.prefix) {
      31 => 'RFC 3021 point-to-point — both addresses are usable hosts.',
      32 => 'Single-host route — one address, no network/broadcast.',
      _ => null,
    };

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
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
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
