// Channel / Frequency Converter — bidirectional Wi-Fi channel <-> frequency.
//
// Two modes (segmented toggle, GL-003 sec 8.14.1):
//   1. Channel -> Frequency: pick band (2.4/5/6 GHz) + 20 MHz primary channel +
//      width. Shows the center frequency, the component 20 MHz channels, and the
//      low/high band edges for the bonded channel. For a 6 GHz 320 MHz primary
//      that lands in two overlapping 320 MHz channels (802.11be), or an interior
//      2.4 GHz 40 MHz primary (HT40- and HT40+), BOTH placements are shown.
//   2. Frequency -> Channel: enter MHz, get back the band + 20 MHz channel, with
//      the +/-1 MHz snap-to-grid tolerance, or an honest "no channel" reject.
//
// All math is the verified engine in data/channel_frequency_data.dart (vectors
// from channel-plan.md sec 7). channel<->frequency is universal physics; channel
// availability is regulatory and is surfaced as a caveat, never as a frequency
// change.
//
// HONESTY (Pax flags): the 320 MHz-1 / 320 MHz-2 scheme labels are NOT verified
// against the standard, so they are NOT printed; overlapping 320 MHz placements
// are shown by their components/center/edges with a neutral caveat. No IEEE
// clause numbers are printed in-app.
//
// States (SOP-007 sec 5):
//   - success     -> Channel mode always yields a result for a valid selection;
//                    Frequency mode yields a result for an in-plan frequency.
//   - empty       -> Frequency mode before any input: a prompt, copy disabled.
//   - error       -> Frequency mode off-grid / out-of-plan: honest reject.
//   - disabled    -> copy action disabled when there is nothing to copy.
//   - interactive -> hover/focus/pressed on the toggles, selects, field, copy.
//
// THEME: chrome from context.colors (dark sec 8 / light sec 8.20). No new tokens.
// Glyph note: ASCII hyphen-minus and +/- throughout; no em dash (GL-004).
//
// ICON: bespoke Tier-2 icon ships at assets/tool-icons/channel-frequency.svg
// (Charta). Resolved by catalog-id convention via ToolAssets.hasIcon — no
// per-tool wiring needed; the catalog tile picks it up automatically.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kChannelFrequencyToolId = 'channel-frequency';

/// Which direction the converter runs.
enum _ConvMode { channelToFreq, freqToChannel }

class ChannelFrequencyConverterScreen extends StatefulWidget {
  const ChannelFrequencyConverterScreen({super.key});

  @override
  State<ChannelFrequencyConverterScreen> createState() =>
      _ChannelFrequencyConverterScreenState();
}

class _ChannelFrequencyConverterScreenState
    extends State<ChannelFrequencyConverterScreen> {
  _ConvMode _mode = _ConvMode.channelToFreq;

  // ── Channel -> Frequency inputs ──
  WifiBand _band = WifiBand.band5;
  int _channel = 36;
  int _width = 20;

  // ── Frequency -> Channel input ──
  final TextEditingController _freqCtrl = TextEditingController();
  final FocusNode _freqFocus = FocusNode();

  static final List<TextInputFormatter> _unsignedDecimal =
      <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _freqCtrl.dispose();
    _freqFocus.dispose();
    super.dispose();
  }

  // ── Channel-mode invariants ────────────────────────────────────────────────

  /// When the band changes, keep the channel/width valid for the new band.
  void _onBandChanged(WifiBand band) {
    setState(() {
      _band = band;
      final List<int> channels = channelsFor(band);
      if (!channels.contains(_channel)) _channel = channels.first;
      if (!band.widthsMHz.contains(_width)) _width = 20;
    });
  }

  /// The wide-channel placements for the current Channel-mode selection.
  List<BondedChannel> get _placements => bondedChannels(
        band: _band,
        primaryChannel: _channel,
        widthMHz: _width,
      );

  /// The reverse-lookup result for the current Frequency-mode input, plus the
  /// parse state. `parsed` false means the field is empty/blank (empty state);
  /// `parsed` true with a null `match` means a real off-grid reject (error).
  ({bool parsed, double? mhz, ({WifiBand band, int channel})? match})
      get _freqState {
    final String raw = _freqCtrl.text.trim();
    if (raw.isEmpty) return (parsed: false, mhz: null, match: null);
    final double? mhz = double.tryParse(raw);
    if (mhz == null) return (parsed: false, mhz: null, match: null);
    return (parsed: true, mhz: mhz, match: frequencyToChannel(mhz));
  }

  // ── Copy payload (sec 8.16: every on-screen verdict carries its word) ──────

  String? _buildCopyText() {
    if (_mode == _ConvMode.channelToFreq) {
      final List<BondedChannel> placements = _placements;
      if (placements.isEmpty) return null;
      final StringBuffer b = StringBuffer()
        ..writeln('Channel -> Frequency')
        ..writeln(
          'Band ${_band.label}, channel $_channel, $_width MHz',
        );
      final List<String> flags = channelFlags(_band, _channel);
      final String? unii = uniiSubBand(_band, _channel);
      if (unii != null) b.writeln('Primary UNII sub-band: $unii');
      if (flags.isNotEmpty) b.writeln('Primary flags: ${flags.join(', ')}');
      for (int i = 0; i < placements.length; i++) {
        final BondedChannel p = placements[i];
        if (placements.length > 1) b.writeln('Placement ${i + 1}:');
        b
          ..writeln('  Center frequency: ${p.centerFreqMHz} MHz')
          ..writeln('  Center channel designator: ${p.centerChannel}')
          ..writeln(
            '  Component 20 MHz channels: ${p.components.join(', ')}',
          )
          ..writeln('  Band edges: ${p.lowEdgeMHz} - ${p.highEdgeMHz} MHz');
      }
      final String? caveat = regulatoryCaveat(_band, _channel);
      if (caveat != null) b.writeln('Note: $caveat');
      b
        ..writeln()
        ..writeln(kChannelFrequencyMikroTikNote)
        ..writeln()
        ..writeln(kChannelFrequencyNote);
      return b.toString().trimRight();
    }

    // Frequency -> Channel.
    final state = _freqState;
    if (!state.parsed) return null;
    final StringBuffer b = StringBuffer()..writeln('Frequency -> Channel');
    b.writeln('Input: ${state.mhz} MHz');
    final match = state.match;
    if (match == null) {
      b
        ..writeln(
          'Verdict: no Wi-Fi channel at this frequency (off-grid or out of plan).',
        )
        ..writeln(kChannelFrequencyMikroTikOffGridNote);
    } else {
      final int center = channelToFrequency(match.band, match.channel)!;
      final String? unii = uniiSubBand(match.band, match.channel);
      final List<String> flags = channelFlags(match.band, match.channel);
      b
        ..writeln('Verdict: ${match.band.label}, channel ${match.channel}')
        ..writeln('Channel center: $center MHz');
      if (unii != null) b.writeln('UNII sub-band: $unii');
      if (flags.isNotEmpty) b.writeln('Flags: ${flags.join(', ')}');
      final String? caveat = regulatoryCaveat(match.band, match.channel);
      if (caveat != null) b.writeln('Note: $caveat');
    }
    b
      ..writeln()
      ..writeln(kChannelFrequencyNote);
    return b.toString().trimRight();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel / Frequency'),
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
                      _modeCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      if (_mode == _ConvMode.channelToFreq) ...<Widget>[
                        _channelInputCard(text, mono),
                        const SizedBox(height: AppSpacing.md),
                        ..._channelResultCards(text, mono),
                      ] else ...<Widget>[
                        _freqInputCard(text, mono),
                        const SizedBox(height: AppSpacing.md),
                        _freqResultCard(text, mono),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _noteCard(text),
                      ToolHelpFooter(toolId: kChannelFrequencyToolId),
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

  Widget _modeCard(TextTheme text, AppMonoText mono) {
    return _card(
      child: AppToggle<_ConvMode>(
        label: 'Direction',
        value: _mode,
        expand: true,
        semanticLabel: 'Conversion direction',
        items: const <AppToggleItem<_ConvMode>>[
          (_ConvMode.channelToFreq, 'Channel -> Freq'),
          (_ConvMode.freqToChannel, 'Freq -> Channel'),
        ],
        onChanged: (_ConvMode m) => setState(() => _mode = m),
      ),
    );
  }

  // ── Channel -> Frequency ────────────────────────────────────────────────────

  Widget _channelInputCard(TextTheme text, AppMonoText mono) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<WifiBand>(
            label: 'Band',
            value: _band,
            expand: true,
            semanticLabel: 'Frequency band',
            items: WifiBand.values
                .map((WifiBand b) => (b, b.label))
                .toList(growable: false),
            onChanged: _onBandChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Channel',
            hint: '(20 MHz primary)',
            semanticLabel: '20 MHz primary channel',
            field: AppSelect<int>(
              value: _channel,
              semanticLabel: 'Channel',
              items: channelsFor(_band)
                  .map((int c) => (c, _channelOptionLabel(_band, c)))
                  .toList(growable: false),
              onChanged: (int c) => setState(() => _channel = c),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Channel width',
            hint: '(MHz)',
            semanticLabel: 'Channel width in MHz',
            field: AppSelect<int>(
              value: _width,
              semanticLabel: 'Channel width',
              items: _band.widthsMHz
                  .map((int w) => (w, '$w MHz'))
                  .toList(growable: false),
              onChanged: (int w) => setState(() => _width = w),
            ),
          ),
        ],
      ),
    );
  }

  /// Channel option label, annotating the two special-case channels so a user
  /// sees the trap before selecting.
  String _channelOptionLabel(WifiBand band, int channel) {
    if (band == WifiBand.band24 && channel == 14) return '14 (special)';
    if (band == WifiBand.band6 && channel == 2) return '2 (special)';
    return '$channel';
  }

  List<Widget> _channelResultCards(TextTheme text, AppMonoText mono) {
    final List<BondedChannel> placements = _placements;
    if (placements.isEmpty) {
      // Defensive: a valid primary + a valid band width always yields a
      // placement, so this is unreachable in normal use. Honest fallback rather
      // than a blank screen.
      return <Widget>[
        _card(
          child: Text(
            'This channel cannot form a $_width MHz channel in '
            '${_band.label}.',
            style: text.bodyMedium?.copyWith(color: context.colors.textPrimary),
          ),
        ),
      ];
    }

    final List<Widget> cards = <Widget>[];
    final bool multiple = placements.length > 1;
    if (multiple) {
      cards.add(_overlapNoticeCard(text, placements.length));
      cards.add(const SizedBox(height: AppSpacing.md));
    }
    for (int i = 0; i < placements.length; i++) {
      cards.add(
        _placementCard(
          text,
          mono,
          placements[i],
          index: multiple ? i + 1 : null,
        ),
      );
      if (i != placements.length - 1) {
        cards.add(const SizedBox(height: AppSpacing.md));
      }
    }
    return cards;
  }

  Widget _overlapNoticeCard(TextTheme text, int count) {
    final AppColorScheme colors = context.colors;
    final String reason = _width == 320
        ? '802.11be defines overlapping 320 MHz channels, so this primary falls '
            'in $count of them.'
        : 'This primary can bond on either side, giving $count placements at '
            '$_width MHz.';
    return _infoCard(
      icon: Icons.info_outline,
      tint: colors.statusInfo,
      child: Text(
        reason,
        style: text.bodySmall?.copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _placementCard(
    TextTheme text,
    AppMonoText mono,
    BondedChannel p, {
    int? index,
  }) {
    final AppColorScheme colors = context.colors;
    final List<String> primaryFlags = channelFlags(_band, _channel);
    final String? unii = uniiSubBand(_band, _channel);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (index != null) ...<Widget>[
            Text(
              'Placement $index',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          // Headline: the center frequency, the result a user is here for.
          Text(
            'Center frequency',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            '${p.centerFreqMHz} MHz',
            style: mono.outputLarge.copyWith(
              color: colors.textAccent,
              fontSize: AppTextSize.h2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Copy the BARE integer MHz (e.g. `5180`, not `5180 MHz (ch 36)`) so
          // it pastes clean into a MikroTik RouterOS frequency field. The
          // AppBar AppCopyAction still copies the full result.
          Align(
            alignment: Alignment.centerLeft,
            child: _CopyValueButton(
              value: '${p.centerFreqMHz}',
              label: 'Copy frequency',
              semanticLabel:
                  'Copy center frequency ${p.centerFreqMHz} megahertz',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Secondary MikroTik aside (not a banner): this center frequency is
          // exactly what a RouterOS operator enters.
          Text(
            kChannelFrequencyMikroTikNote,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(
            text,
            mono,
            label: 'Center channel',
            value: '${p.centerChannel}'
                '${p.widthMHz == 20 ? '' : ' (designator only)'}',
          ),
          _resultRow(
            text,
            mono,
            label: 'Component 20 MHz',
            value: p.components.join(', '),
          ),
          _resultRow(
            text,
            mono,
            label: 'Band edges',
            value: '${p.lowEdgeMHz} - ${p.highEdgeMHz} MHz',
          ),
          if (unii != null)
            _resultRow(text, mono, label: 'UNII sub-band', value: unii),
          if (primaryFlags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final String f in primaryFlags) _flagChip(text, f),
              ],
            ),
          ],
          ..._caveatBlock(text),
        ],
      ),
    );
  }

  // ── Frequency -> Channel ────────────────────────────────────────────────────

  Widget _freqInputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: LabeledField(
        label: 'Frequency',
        hint: '(MHz)',
        semanticLabel: 'Frequency in MHz',
        field: TextField(
          controller: _freqCtrl,
          focusNode: _freqFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _unsignedDecimal,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          style: mono.outputLarge.copyWith(fontSize: AppTextSize.fieldNumeric),
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: '5180'),
        ),
      ),
    );
  }

  Widget _freqResultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final state = _freqState;

    // EMPTY — no input yet.
    if (!state.parsed) {
      return _infoCard(
        icon: Icons.tune,
        tint: colors.textTertiary,
        child: Text(
          'Enter a frequency in MHz to find its Wi-Fi band and channel. '
          'Values within +/-1 MHz of a channel center snap to that channel.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      );
    }

    // ERROR — a real number that maps to no channel.
    final match = state.match;
    if (match == null) {
      return _infoCard(
        icon: Icons.error_outline,
        tint: colors.statusWarning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'No Wi-Fi channel',
              style: text.labelMedium?.copyWith(
                color: colors.statusWarning,
                fontWeight: colors.isLight ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${_trimMhz(state.mhz!)} MHz is off the channel grid or outside '
              'the 2.4 / 5 / 6 GHz Wi-Fi plan.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Honest reject stands — no channel is fabricated. MikroTik context
            // only: RouterOS can still run a non-standard center frequency.
            Text(
              kChannelFrequencyMikroTikOffGridNote,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      );
    }

    // SUCCESS.
    final int center = channelToFrequency(match.band, match.channel)!;
    final String? unii = uniiSubBand(match.band, match.channel);
    final List<String> flags = channelFlags(match.band, match.channel);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Channel',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            '${match.band.label}, ch ${match.channel}',
            style: mono.outputLarge.copyWith(
              color: colors.textAccent,
              fontSize: AppTextSize.h2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(text, mono, label: 'Channel center', value: '$center MHz'),
          if (unii != null)
            _resultRow(text, mono, label: 'UNII sub-band', value: unii),
          if (flags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final String f in flags) _flagChip(text, f),
              ],
            ),
          ],
          ..._caveatBlockFor(text, match.band, match.channel),
        ],
      ),
    );
  }

  // ── Shared result pieces ────────────────────────────────────────────────────

  List<Widget> _caveatBlock(TextTheme text) =>
      _caveatBlockFor(text, _band, _channel);

  List<Widget> _caveatBlockFor(TextTheme text, WifiBand band, int channel) {
    final String? caveat = regulatoryCaveat(band, channel);
    if (caveat == null) return const <Widget>[];
    final AppColorScheme colors = context.colors;
    return <Widget>[
      const SizedBox(height: AppSpacing.sm),
      Container(
        decoration: BoxDecoration(
          color: colors.statusWarningFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.statusWarning, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.public, size: 16, color: colors.statusWarning),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                caveat,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
  }) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 144,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              value,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _flagChip(TextTheme text, String label) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      child: Text(
        label,
        style: text.labelMedium?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _noteCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return _infoCard(
      icon: Icons.info_outline,
      tint: colors.textTertiary,
      child: Text(
        kChannelFrequencyNote,
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }

  // ── Card primitives ─────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color tint,
    required Widget child,
  }) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: child),
        ],
      ),
    );
  }

  String _trimMhz(double mhz) {
    if (mhz == mhz.roundToDouble()) return mhz.toStringAsFixed(0);
    return mhz.toString();
  }
}

/// Small inline affordance that copies a SINGLE value as plain text and confirms
/// in place with a §8.16-style glyph swap (copy -> check, no SnackBar). Used to
/// put the BARE integer center frequency (e.g. `5180`, not `5180 MHz (ch 36)`)
/// on the clipboard so it pastes clean into a MikroTik RouterOS frequency field.
/// The AppBar [AppCopyAction] still copies the full result alongside this.
class _CopyValueButton extends StatefulWidget {
  const _CopyValueButton({
    required this.value,
    required this.label,
    required this.semanticLabel,
  });

  /// The exact plain text written to the clipboard — here the bare integer MHz.
  final String value;

  /// Idle button label.
  final String label;

  /// Screen-reader label naming the value being copied (§8.9).
  final String semanticLabel;

  @override
  State<_CopyValueButton> createState() => _CopyValueButtonState();
}

class _CopyValueButtonState extends State<_CopyValueButton> {
  /// §8.16 confirm window — 1.5s, then auto-revert.
  static const Duration _confirmWindow = Duration(milliseconds: 1500);

  bool _confirmed = false;
  int _generation = 0;

  Future<void> _handleTap() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    // SC 4.1.3 — status reaches AT users without a visible toast (§8.16).
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Frequency copied',
      TextDirection.ltr,
    );
    final int generation = ++_generation;
    setState(() => _confirmed = true);
    Future<void>.delayed(_confirmWindow, () {
      if (!mounted || generation != _generation) return;
      setState(() => _confirmed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Duration swap = reduceMotion ? Duration.zero : AppMotion.fast;
    return Semantics(
      button: true,
      label: _confirmed ? 'Frequency copied' : widget.semanticLabel,
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          onPressed: _handleTap,
          icon: AnimatedSwitcher(
            duration: swap,
            child: Icon(
              _confirmed ? Icons.check : Icons.copy_outlined,
              key: ValueKey<bool>(_confirmed),
              size: 18,
              color: _confirmed ? colors.statusSuccess : null,
            ),
          ),
          label: Text(_confirmed ? 'Copied' : widget.label),
        ),
      ),
    );
  }
}
