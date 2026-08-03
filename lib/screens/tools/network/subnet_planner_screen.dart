// Subnet Planner — the IPv4 block math that works on MORE THAN ONE network:
// carving a parent block into right-sized subnets (VLSM), and summarizing a
// list of networks into a covering block.
//
// ONE TILE, TWO MODES, ON PURPOSE. These are the two directions of the same
// operation over the same multi-line network list, and the site this capability
// was surveyed from ships them as separate landing pages because its business
// is search traffic. In an installed app the cost of a tile is a user scanning
// past it, so the split and the summarize live behind one segmented control
// and share their parsing. The single-network math stays where it already is,
// on the IPv4 Subnetting screen.
//
// States (SOP-007 §5):
//  - idle     → the form, seeded with a worked example so the screen never
//               opens blank.
//  - success  → the plan or the summary, live-recomputed on every keystroke.
//  - empty    → Split with no requirements typed yet is NOT an error: the whole
//               parent is reported free. Summarize with nothing valid yet is an
//               error, because there is no question to answer.
//  - error    → a malformed parent block, or a network list with no valid line.
//               A single bad LINE is not an error: it is reported with its line
//               number while the good lines still compute.
//  - disabled → not applicable; there is no run button, the math is live.
//
// All math is in [IpBlockMath] (pure, no Flutter, unit-tested). This file only
// renders it. No I/O of any kind, so the tool runs on every platform including
// web and there is no NetworkUnavailableView path.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/ip_block_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'value_row.dart';

/// Which question the screen is answering.
enum PlannerMode {
  /// Carve one parent block into right-sized subnets.
  split,

  /// Aggregate a list of networks into a covering block.
  summarize,
}

class SubnetPlannerScreen extends StatefulWidget {
  const SubnetPlannerScreen({super.key});

  @override
  State<SubnetPlannerScreen> createState() => _SubnetPlannerScreenState();
}

class _SubnetPlannerScreenState extends State<SubnetPlannerScreen> {
  // Seeded with a worked example, matching the IPv4 subnet calculator's habit
  // of opening on a result rather than a blank panel.
  final TextEditingController _parentCtrl = TextEditingController(
    text: '10.20.0.0/22',
  );
  final TextEditingController _reqCtrl = TextEditingController(
    text: 'Staff 500\nGuest 200\nIoT 100\nPtP link 2',
  );
  final TextEditingController _netsCtrl = TextEditingController(
    text: '10.0.0.0/24\n10.0.1.0/24\n10.0.2.0/24\n10.0.3.0/24',
  );

  PlannerMode _mode = PlannerMode.split;
  VlsmResult? _vlsm;
  SummaryResult? _summary;

  @override
  void initState() {
    super.initState();
    _parentCtrl.addListener(_recompute);
    _reqCtrl.addListener(_recompute);
    _netsCtrl.addListener(_recompute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _parentCtrl.dispose();
    _reqCtrl.dispose();
    _netsCtrl.dispose();
    super.dispose();
  }

  void _recompute() {
    setState(() {
      switch (_mode) {
        case PlannerMode.split:
          _vlsm = IpBlockMath.vlsm(
            parentCidr: _parentCtrl.text,
            requirementsText: _reqCtrl.text,
          );
        case PlannerMode.summarize:
          _summary = IpBlockMath.summarize(_netsCtrl.text);
      }
    });
  }

  void _onModeChanged(PlannerMode m) {
    if (m == _mode) return;
    setState(() => _mode = m);
    _recompute();
  }

  /// Thousands-grouped decimal, so a 4,278,124,544 stays readable.
  static String _grouped(int n) {
    final String s = n.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subnet Planner'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload. Null (→ disabled affordance) whenever there is no
  /// valid plan or summary to keep.
  String? _buildCopyText() {
    switch (_mode) {
      case PlannerMode.split:
        final VlsmResult? r = _vlsm;
        if (r == null || !r.isValid || r.parent == null) return null;
        final StringBuffer buf = StringBuffer()
          ..writeln('Subnet Planner: split ${r.parent!.cidr}')
          ..writeln(
            'Parent: ${r.parent!.cidr} '
            '(${_grouped(r.parent!.size)} addresses)',
          );
        for (final VlsmAllocation a in r.allocations) {
          if (a.isAllocated) {
            final Ipv4Block b = a.block!;
            buf.writeln(
              '${a.name}: ${b.cidr}  mask ${b.mask}  '
              'hosts ${b.firstHost} to ${b.lastHost}  '
              '(${_grouped(b.usableHosts)} usable, asked for '
              '${_grouped(a.requestedHosts)})',
            );
          } else {
            buf.writeln('${a.name}: NOT ALLOCATED. ${a.unallocatedReason}');
          }
        }
        buf.writeln(
          'Used: ${_grouped(r.usedAddresses)} addresses. '
          'Free: ${_grouped(r.freeAddresses)}.',
        );
        if (r.freeBlocks.isNotEmpty) {
          buf.writeln(
            'Free blocks: '
            '${r.freeBlocks.map((Ipv4Block b) => b.cidr).join(', ')}',
          );
        }
        for (final String n in r.notes) {
          buf.writeln(n);
        }
        return buf.toString().trimRight();

      case PlannerMode.summarize:
        final SummaryResult? r = _summary;
        if (r == null || !r.isValid || r.supernet == null) return null;
        final StringBuffer buf = StringBuffer()
          ..writeln('Subnet Planner: summarize')
          ..writeln(
            'Covering supernet: ${r.supernet!.cidr} '
            '(${_grouped(r.supernetAddresses)} addresses)',
          )
          ..writeln(
            'Exact blocks: '
            '${r.exactBlocks.map((Ipv4Block b) => b.cidr).join(', ')}',
          )
          ..writeln('Covered by your list: ${_grouped(r.coveredAddresses)}')
          ..writeln(
            'Extra addresses the supernet would advertise: '
            '${_grouped(r.extraAddresses)}',
          );
        if (r.extraBlocks.isNotEmpty) {
          buf.writeln(
            'Not in your list: '
            '${r.extraBlocks.map((Ipv4Block b) => b.cidr).join(', ')}',
          );
        }
        return buf.toString().trimRight();
    }
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: 'subnet-planner',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('subnet-planner'))
                    const SizedBox(height: AppSpacing.md),
                  AppToggle<PlannerMode>(
                    value: _mode,
                    semanticLabel: 'Planner mode',
                    expand: true,
                    items: const <AppToggleItem<PlannerMode>>[
                      (PlannerMode.split, 'Split'),
                      (PlannerMode.summarize, 'Summarize'),
                    ],
                    onChanged: _onModeChanged,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_mode == PlannerMode.split)
                    _splitForm(context)
                  else
                    _summarizeForm(context),
                  // WCAG 4.1.3 — the result subtree swaps without moving focus,
                  // so it is announced as a live region rather than silently.
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    child: _mode == PlannerMode.split
                        ? _splitResults(context)
                        : _summarizeResults(context),
                  ),
                  ToolHelpFooter(toolId: 'subnet-planner'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Forms ────────────────────────────────────────────────────────────────

  Widget _card(
    BuildContext context,
    List<Widget> children, {
    bool strong = false,
  }) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: strong ? colors.borderStrong : colors.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _hint(BuildContext context, String s) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        s,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String s) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        s,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _splitForm(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return _card(context, <Widget>[
      LabeledField(
        label: 'Block to carve up',
        field: TextField(
          controller: _parentCtrl,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9./ ]')),
          ],
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(
            hintText: '10.20.0.0/22 or 10.20.0.0 255.255.252.0',
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      LabeledField(
        label: 'Subnets you need',
        semanticLabel: 'Subnets you need, one per line',
        field: TextField(
          controller: _reqCtrl,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 4,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: 'Staff 500'),
        ),
      ),
      _hint(
        context,
        'One per line: a name then the number of hosts, or just the number. '
        'Blank lines and lines starting with # are skipped.',
      ),
    ]);
  }

  Widget _summarizeForm(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return _card(context, <Widget>[
      LabeledField(
        label: 'Networks to summarize',
        semanticLabel: 'Networks to summarize, one per line',
        field: TextField(
          controller: _netsCtrl,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 4,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: '10.0.0.0/24'),
        ),
      ),
      _hint(
        context,
        'One network per line. A prefix, a dotted mask, or a bare address read '
        'as a single host all work. Blank lines and # comments are skipped.',
      ),
    ]);
  }

  // ─── Results ──────────────────────────────────────────────────────────────

  Widget _errorCard(BuildContext context, String message) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _card(context, <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.edit_outlined, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
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
    ]);
  }

  /// The per-line problems block, shared by both modes. Renders nothing when
  /// every line parsed, so a clean input carries no noise.
  Widget _lineErrors(BuildContext context, List<ParsedNetworkLine> errors) {
    if (errors.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: _card(context, <Widget>[
        _sectionLabel(context, 'Lines that were skipped'),
        for (final ParsedNetworkLine e in errors)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.rowPadding,
            ),
            child: Text(
              'Line ${e.lineNumber}, "${e.raw}": ${e.error}',
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ),
      ]),
    );
  }

  Widget _noteText(BuildContext context, String s) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        s,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }

  Widget _splitResults(BuildContext context) {
    final VlsmResult? r = _vlsm;
    if (r == null) return const SizedBox.shrink();
    if (!r.isValid) return _errorCard(context, r.error!);

    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Ipv4Block parent = r.parent!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _card(context, <Widget>[
          _sectionLabel(context, 'Plan'),
          ValueRow(
            label: 'Parent',
            value: parent.cidr,
            identifier: true,
            emphasize: true,
          ),
          ValueRow(
            label: 'Addresses',
            value: _grouped(parent.size),
            mono: true,
          ),
          ValueRow(label: 'Used', value: _grouped(r.usedAddresses), mono: true),
          ValueRow(label: 'Free', value: _grouped(r.freeAddresses), mono: true),
        ], strong: true),
        for (final VlsmAllocation a in r.allocations) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          if (a.isAllocated)
            _card(context, <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      a.name,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    a.block!.cidr,
                    style: mono.robotoMono.copyWith(color: colors.textAccent),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ValueRow(
                label: 'Netmask',
                value: a.block!.mask,
                identifier: true,
              ),
              ValueRow(
                label: 'Host range',
                value: '${a.block!.firstHost} to ${a.block!.lastHost}',
                identifier: true,
              ),
              ValueRow(
                label: 'Broadcast',
                value: a.block!.broadcast,
                identifier: true,
              ),
              ValueRow(
                label: 'Usable',
                value:
                    '${_grouped(a.block!.usableHosts)} '
                    '(asked for ${_grouped(a.requestedHosts)})',
                mono: true,
              ),
            ])
          else
            _card(context, <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.report_gmailerrorred_outlined,
                    size: 20,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '${a.name}: not allocated',
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              _noteText(context, a.unallocatedReason!),
            ]),
        ],
        if (r.freeBlocks.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _card(context, <Widget>[
            _sectionLabel(context, 'Still free'),
            for (final Ipv4Block b in r.freeBlocks)
              ValueRow(
                label: b.cidr,
                value: '${_grouped(b.size)} addresses',
                mono: true,
              ),
          ]),
        ],
        if (r.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _card(context, <Widget>[
            _sectionLabel(context, 'Worth knowing'),
            for (final String n in r.notes) _noteText(context, n),
          ]),
        ],
        _lineErrors(context, r.lineErrors),
      ],
    );
  }

  Widget _summarizeResults(BuildContext context) {
    final SummaryResult? r = _summary;
    if (r == null) return const SizedBox.shrink();
    if (!r.isValid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _errorCard(context, r.error!),
          _lineErrors(context, r.lineErrors),
        ],
      );
    }

    final Ipv4Block sup = r.supernet!;
    final bool exactFit = r.extraAddresses == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _card(context, <Widget>[
          _sectionLabel(context, 'Covering supernet'),
          ValueRow(
            label: 'Supernet',
            value: sup.cidr,
            identifier: true,
            emphasize: true,
          ),
          ValueRow(label: 'Netmask', value: sup.mask, identifier: true),
          ValueRow(
            label: 'Range',
            value: '${sup.firstHost} to ${sup.lastHost}',
            identifier: true,
          ),
          ValueRow(
            label: 'Addresses',
            value: _grouped(r.supernetAddresses),
            mono: true,
          ),
          ValueRow(
            label: 'In your list',
            value: _grouped(r.coveredAddresses),
            mono: true,
          ),
          ValueRow(
            label: 'Extra',
            value: _grouped(r.extraAddresses),
            mono: true,
          ),
          _noteText(
            context,
            exactFit
                ? 'Your networks fill this block exactly. Advertising it adds '
                      'nothing you did not ask for.'
                : 'Advertising this one block also claims '
                      '${_grouped(r.extraAddresses)} addresses that are not in '
                      'your list. That is what makes a summary route pull in '
                      'traffic for networks you do not own.',
          ),
        ], strong: true),
        const SizedBox(height: AppSpacing.sm),
        _card(context, <Widget>[
          _sectionLabel(context, 'Exact cover'),
          for (final Ipv4Block b in r.exactBlocks)
            ValueRow(
              label: b.cidr,
              value: '${_grouped(b.size)} addresses',
              mono: true,
            ),
          _noteText(
            context,
            'The smallest set of blocks that covers your list and nothing '
            'else. Overlapping and touching networks are merged.',
          ),
        ]),
        if (r.extraBlocks.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _card(context, <Widget>[
            _sectionLabel(context, 'Inside the supernet, not in your list'),
            for (final Ipv4Block b in r.extraBlocks)
              ValueRow(
                label: b.cidr,
                value: '${_grouped(b.size)} addresses',
                mono: true,
              ),
          ]),
        ],
        if (r.inputs.any(
          (ParsedNetworkLine l) => l.hostBitsWereSet,
        )) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _card(context, <Widget>[
            _sectionLabel(context, 'Read as their network address'),
            for (final ParsedNetworkLine l in r.inputs)
              if (l.hostBitsWereSet)
                _noteText(
                  context,
                  'Line ${l.lineNumber}: "${l.raw}" has host bits set, so it '
                  'was read as ${l.block!.cidr}.',
                ),
          ]),
        ],
        _lineErrors(context, r.lineErrors),
      ],
    );
  }
}
