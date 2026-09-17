// MTU and MSS calculator.
//
// A tunnel goes up, small things work, big transfers stall. The cause is almost
// always that something in the path is taking bytes the endpoints never
// accounted for. This screen turns that into arithmetic a person can check.
//
// FORWARD: a link MTU and an encapsulation stack, giving the MSS that survives.
// INVERSE: an MSS seen working on the wire, giving the MTU the path really has
// and how many bytes are still unexplained. The inverse is the half that
// teaches, because a capture shows you the MSS and never tells you what ate the
// difference. A gap of 8 is PPPoE. A gap of 24 is GRE. A gap of 60 is
// WireGuard.
//
// WHAT THIS IS NOT. This is a CALCULATOR: pure arithmetic, every platform
// including web, no sockets. PATH MTU DISCOVERY is a different, unbuilt tool
// that probes a real path, needs bespoke dart:ffi on four platforms, and is
// gated on a spike nobody has run. Its spec is at
// `Deliverables/2026-07-08-vpn-network-tools-buildprep/spec-3-path-mtu.md`.
// Shipping this must not be read as having shipped that.
//
// THE MISCONCEPTION IT EXISTS TO KILL, and the reason a Wi-Fi tool should carry
// it rather than a generic network one: THE 802.11 HEADER IS NOT SUBTRACTED
// FROM MTU. Wi-Fi's MAC header is bigger than Ethernet's and it sits BELOW the
// IP layer, so it does not come out of the 1500-byte IP MTU. An 802.11 MSDU is
// 2304 bytes precisely so a 1500-byte IP packet fits with room over. The people
// most likely to get this wrong are the ones who know the 802.11 header best,
// which is exactly our audience, so the reference card states it outright.
//
// Edge cases:
// - Empty or non-numeric input blanks the outputs. House pattern.
// - A stack costing more than the link carries returns no MSS. That is a real
//   answer, not an error: TCP cannot pass one byte of payload.
// - A variable overhead (IPsec ESP) is a RANGE and is sized to its HIGH end.
//   Sizing to the low end produces a number that works until the day the
//   cipher or the padding changes.
// - An MTU below the IP version's documented floor is flagged, not blocked.
//
// Pure, no network, no platform APIs. Math lives in MtuMath so a future Path
// MTU Discovery tool can derive its effective MSS from the same arithmetic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/mtu_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Which direction the screen solves in.
enum MtuMode { forward, inverse }

/// Which IP version the headers are sized for.
enum MtuIpVersion { v4, v6 }

class MtuMssScreen extends StatefulWidget {
  const MtuMssScreen({super.key});

  /// Integer-only input. MTU and MSS are whole bytes; a decimal point here is
  /// always a typo and accepting one invites a fractional answer.
  static final List<TextInputFormatter> digitsOnly = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(5),
  ];

  @override
  State<MtuMssScreen> createState() => _MtuMssScreenState();
}

class _MtuMssScreenState extends State<MtuMssScreen> {
  final TextEditingController _mtuCtrl =
      TextEditingController(text: '${MtuMath.ethernetMtu}');
  final TextEditingController _mssCtrl = TextEditingController(text: '1452');

  final FocusNode _mtuFocus = FocusNode();
  final FocusNode _mssFocus = FocusNode();

  MtuMode _mode = MtuMode.forward;
  MtuIpVersion _ip = MtuIpVersion.v4;
  bool _timestamps = false;
  final Set<String> _tunnels = <String>{};

  @override
  void dispose() {
    _mtuCtrl.dispose();
    _mssCtrl.dispose();
    _mtuFocus.dispose();
    _mssFocus.dispose();
    super.dispose();
  }

  bool get _ipv6 => _ip == MtuIpVersion.v6;

  int? get _mtuIn => int.tryParse(_mtuCtrl.text.trim());
  int? get _mssIn => int.tryParse(_mssCtrl.text.trim());

  int get _headerBytes =>
      MtuMath.fixedHeaderBytes(ipv6: _ipv6, tcpTimestamps: _timestamps);
  int get _tunnelBytes => MtuMath.tunnelBytes(_tunnels);

  int? get _resultMss {
    final int? mtu = _mtuIn;
    if (mtu == null || mtu <= 0) return null;
    return MtuMath.mssFromMtu(
      linkMtu: mtu,
      ipv6: _ipv6,
      tcpTimestamps: _timestamps,
      tunnels: _tunnels,
    );
  }

  int? get _resultMtu {
    final int? mss = _mssIn;
    if (mss == null || mss <= 0) return null;
    return MtuMath.mtuFromMss(
      mss: mss,
      ipv6: _ipv6,
      tcpTimestamps: _timestamps,
      tunnels: _tunnels,
    );
  }

  int? get _gap {
    final int? mss = _mssIn;
    if (mss == null || mss <= 0) return null;
    return MtuMath.unexplainedBytes(
      mss: mss,
      ipv6: _ipv6,
      tcpTimestamps: _timestamps,
      tunnels: _tunnels,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MTU & MSS'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
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
                    children: <Widget>[
                      ConceptGraphicBand(
                        toolId: 'mtu-mss',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('mtu-mss'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _overheadCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'mtu-mss'),
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

  Widget _card({required Widget child}) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool forward = _mode == MtuMode.forward;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<MtuMode>(
            value: _mode,
            items: const <(MtuMode, String)>[
              (MtuMode.forward, 'MTU to MSS'),
              (MtuMode.inverse, 'MSS to MTU'),
            ],
            onChanged: (MtuMode m) => setState(() => _mode = m),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: forward ? 'Link MTU' : 'Observed MSS',
            hint: '(bytes)',
            semanticLabel: forward
                ? 'Link MTU in bytes'
                : 'Observed MSS in bytes',
            field: TextField(
              controller: forward ? _mtuCtrl : _mssCtrl,
              focusNode: forward ? _mtuFocus : _mssFocus,
              keyboardType: TextInputType.number,
              inputFormatters: MtuMssScreen.digitsOnly,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: colors.textAccent,
              decoration: InputDecoration(hintText: forward ? '1500' : '1452'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<MtuIpVersion>(
            value: _ip,
            items: const <(MtuIpVersion, String)>[
              (MtuIpVersion.v4, 'IPv4'),
              (MtuIpVersion.v6, 'IPv6'),
            ],
            onChanged: (MtuIpVersion v) => setState(() => _ip = v),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Switch(
                value: _timestamps,
                onChanged: (bool v) => setState(() => _timestamps = v),
                activeThumbColor: colors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'TCP timestamps (+${MtuMath.tcpTimestampsBytes} bytes)',
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Encapsulation in the path',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: MtuMath.overheads.map((MtuOverhead o) {
              final bool on = _tunnels.contains(o.id);
              return FilterChip(
                label: Text('${o.label}  ${o.costLabel}'),
                selected: on,
                onSelected: (bool v) => setState(() {
                  if (v) {
                    _tunnels.add(o.id);
                  } else {
                    _tunnels.remove(o.id);
                  }
                }),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool forward = _mode == MtuMode.forward;

    final List<Widget> rows = <Widget>[];

    if (forward) {
      final int? mss = _resultMss;
      rows.add(_bigRow(text, mono, 'MSS', mss == null ? '—' : '$mss', 'bytes'));
      if (mss == null && (_mtuIn ?? 0) > 0) {
        rows.add(_note(
          text,
          colors.statusDanger,
          'This stack costs more than the link carries, so TCP cannot pass a '
          'single byte of payload over it. That is the answer, not an error.',
        ));
      }
      final int? mtu = _mtuIn;
      if (mtu != null && MtuMath.isBelowIpFloor(mtu: mtu, ipv6: _ipv6)) {
        rows.add(_note(
          text,
          colors.statusWarning,
          _ipv6
              ? 'Below the ${MtuMath.ipv6MinimumMtu}-byte IPv6 minimum link '
                  'MTU (RFC 8200 s5). A link this small cannot carry IPv6.'
              : 'Below the ${MtuMath.ipv4MinimumReassembly}-byte IPv4 minimum '
                  'every host must accept (RFC 791 s3.2).',
        ));
      }
    } else {
      final int? mtu = _resultMtu;
      rows.add(_bigRow(text, mono, 'Path MTU', mtu == null ? '—' : '$mtu',
          'bytes'));
      final int? gap = _gap;
      if (gap != null && gap > 0) {
        final List<MtuOverhead> candidates = MtuMath.candidatesForGap(gap);
        rows.add(_note(
          text,
          colors.statusWarning,
          candidates.isEmpty
              ? '$gap bytes are unaccounted for against a 1500-byte Ethernet '
                  'MTU. Nothing on the list costs exactly that, so it is '
                  'either a stack of several or something not listed here.'
              : '$gap bytes are unaccounted for against a 1500-byte Ethernet '
                  'MTU. That is the cost of '
                  '${candidates.map((MtuOverhead o) => o.label).join(' or ')}, '
                  'which is a candidate and not a conclusion: several layers '
                  'share a byte count and a capture cannot tell them apart by '
                  'size alone.',
        ));
      } else if (gap != null && gap == 0) {
        rows.add(_note(
          text,
          colors.statusSuccess,
          'Fully accounted for. Nothing in the path is taking bytes beyond '
          'what you have selected.',
        ));
      }
    }

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _bigRow(
    TextTheme text,
    AppMonoText mono,
    String label,
    String value,
    String unit,
  ) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.labelLarge?.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(value, style: mono.outputLarge.copyWith(color: colors.textPrimary)),
          const SizedBox(width: AppSpacing.xs),
          Text(unit, style: text.labelMedium?.copyWith(color: colors.textTertiary)),
        ],
      ),
    );
  }

  Widget _note(TextTheme text, Color color, String message) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        message,
        style: text.bodySmall?.copyWith(color: color),
      ),
    );
  }

  Widget _overheadCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final String ipLabel = _ipv6 ? 'IPv6' : 'IPv4';
    final int ipBytes =
        _ipv6 ? MtuMath.ipv6HeaderBytes : MtuMath.ipv4HeaderBytes;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Where the bytes go',
              style: text.titleMedium?.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          _lineRow(text, mono, '$ipLabel header', '$ipBytes'),
          _lineRow(text, mono, 'TCP header', '${MtuMath.tcpHeaderBytes}'),
          if (_timestamps)
            _lineRow(
                text, mono, 'TCP timestamps', '${MtuMath.tcpTimestampsBytes}'),
          for (final String id in _tunnels)
            if (MtuMath.overheadById(id) case final MtuOverhead o)
              _lineRow(text, mono, o.label, o.costLabel),
          const Divider(height: AppSpacing.md),
          _lineRow(text, mono, 'Total', '${_headerBytes + _tunnelBytes}',
              bold: true),
        ],
      ),
    );
  }

  Widget _lineRow(
    TextTheme text,
    AppMonoText mono,
    String label,
    String value, {
    bool bold = false,
  }) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: bold ? colors.textPrimary : colors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : null,
              ),
            ),
          ),
          Text('$value bytes',
              style: mono.outputMedium.copyWith(color: colors.textPrimary)),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('The one people get wrong',
              style: text.titleMedium?.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The 802.11 header is not subtracted from MTU. Wi-Fi’s MAC '
            'header is larger than Ethernet’s, and it sits below the IP '
            'layer, so it does not come out of the 1500-byte IP MTU. An 802.11 '
            'MSDU is 2304 bytes precisely so a 1500-byte IP packet fits with '
            'room over. Wi-Fi does not shrink your MTU. A tunnel running over '
            'it does.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Overheads and their sources',
              style: text.titleMedium?.copyWith(color: colors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          for (final MtuOverhead o in MtuMath.overheads) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(o.label,
                            style: text.bodyMedium
                                ?.copyWith(color: colors.textPrimary)),
                      ),
                      Text('${o.costLabel} bytes',
                          style: mono.outputMedium
                              .copyWith(color: colors.textPrimary)),
                    ],
                  ),
                  Text(o.source,
                      style: text.labelSmall
                          ?.copyWith(color: colors.textTertiary)),
                  if (o.note != null)
                    Text(o.note!,
                        style: text.bodySmall
                            ?.copyWith(color: colors.textSecondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _buildCopyText() {
    final bool forward = _mode == MtuMode.forward;
    final StringBuffer b = StringBuffer()..writeln('MTU & MSS');

    if (forward) {
      final int? mss = _resultMss;
      final int? mtu = _mtuIn;
      if (mtu == null || mtu <= 0) return null;
      b.writeln('Link MTU: $mtu bytes');
      b.writeln('MSS: ${mss == null ? 'none, the stack exceeds the link' : '$mss bytes'}');
    } else {
      final int? mss = _mssIn;
      final int? mtu = _resultMtu;
      if (mss == null || mss <= 0) return null;
      b.writeln('Observed MSS: $mss bytes');
      b.writeln('Implied path MTU: $mtu bytes');
      final int? gap = _gap;
      if (gap != null && gap > 0) {
        b.writeln('Unaccounted for against 1500: $gap bytes');
      }
    }

    b.writeln('IP version: ${_ipv6 ? 'IPv6' : 'IPv4'}');
    if (_timestamps) b.writeln('TCP timestamps: on');
    for (final String id in _tunnels) {
      final MtuOverhead? o = MtuMath.overheadById(id);
      if (o != null) b.writeln('${o.label}: ${o.costLabel} bytes');
    }
    b.writeln('Total overhead: ${_headerBytes + _tunnelBytes} bytes');
    return b.toString().trimRight();
  }
}
