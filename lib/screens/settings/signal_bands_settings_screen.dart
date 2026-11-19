// Signal Bands settings: the user's own RSSI band boundaries.
//
// Keith Parsons, 19 Nov 2026: the app ships his default scale (Excellent -66
// dBm and stronger, Good -67 to -72, Fair -73 to -78, Poor -79 to -84,
// Unusable -85 and weaker), but there is no industry consensus on RSSI bands,
// so the user must be able to set every boundary and reset to his defaults.
//
// Four whole-number fields, one per boundary (the weakest reading of
// Excellent, Good, Fair and Poor). Unusable is everything weaker than Poor, so
// the five bands are contiguous by construction: no gaps, no overlaps. The
// preview shows the five ranges as typed; Save is enabled only when every
// field is valid (whole numbers, -100 to -30 dBm, each weaker than the one
// above). Reset restores Keith's defaults. Both write [RssiScaleStore], the
// one source every grade in the app reads.
//
// Reached from the Signal Thresholds screen ("Change signal bands") and the
// About screen's Signal bands section. US spelling, no em dashes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/network/rssi_scale.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../tools/reference/signal_thresholds_screen.dart'
    show SignalGrade, SignalThresholdsScreen;

class SignalBandsSettingsScreen extends StatefulWidget {
  const SignalBandsSettingsScreen({super.key, this.store});

  /// The store to edit. Defaults to [RssiScaleStore.instance]; tests inject.
  final RssiScaleStore? store;

  /// Screen title.
  static const String kTitle = 'Signal Bands';

  /// The plain framing at the top of the screen.
  static const String kIntro =
      "These are the signal (RSSI) bands every grade in the app uses. The "
      "defaults are Keith Parsons' own. There is no industry consensus on "
      'RSSI bands, so set them to match your own design targets.';

  /// Field labels, strongest band first.
  static const List<String> kFieldLabels = <String>[
    'Excellent: this reading and stronger',
    'Good: down to',
    'Fair: down to',
    'Poor: down to',
  ];

  static const String kSaveLabel = 'Save';
  static const String kResetLabel = "Reset to Keith Parsons' defaults";
  static const String kSavedMessage = 'Signal bands saved';
  static const String kResetMessage =
      "Signal bands reset to Keith Parsons' defaults";

  @override
  State<SignalBandsSettingsScreen> createState() =>
      _SignalBandsSettingsScreenState();
}

class _SignalBandsSettingsScreenState extends State<SignalBandsSettingsScreen> {
  late final RssiScaleStore _store = widget.store ?? RssiScaleStore.instance;
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = <TextEditingController>[
      for (final int b in _store.value.boundaries)
        TextEditingController(text: '$b'),
    ];
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<int?> get _typed => <int?>[
    for (final TextEditingController c in _controllers)
      RssiScale.parseDbm(c.text),
  ];

  void _fill(RssiScale scale) {
    for (int i = 0; i < 4; i++) {
      _controllers[i].text = '${scale.boundaries[i]}';
    }
  }

  Future<void> _save() async {
    final RssiScale? scale = RssiScale.tryFrom(_typed);
    if (scale == null) return;
    await _store.save(scale);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text(SignalBandsSettingsScreen.kSavedMessage)),
    );
  }

  Future<void> _reset() async {
    await _store.reset();
    if (!mounted) return;
    setState(() => _fill(RssiScale.defaults));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text(SignalBandsSettingsScreen.kResetMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final List<int?> typed = _typed;
    final Map<RssiBoundary, String> errors = RssiScale.validate(typed);
    final RssiScale? preview = RssiScale.tryFrom(typed);
    final bool changed = preview != null && preview != _store.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text(SignalBandsSettingsScreen.kTitle),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenEdgeMobile),
              children: <Widget>[
                Text(
                  SignalBandsSettingsScreen.kIntro,
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (int i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: TextField(
                      key: ValueKey<String>('signal-band-field-$i'),
                      controller: _controllers[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp('[-\u22120-9]'),
                        ),
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(
                        labelText: SignalBandsSettingsScreen.kFieldLabels[i],
                        suffixText: 'dBm',
                        errorText: errors[RssiBoundary.values[i]],
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                Text(
                  'Unusable: anything weaker than Poor.',
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                _Preview(scale: preview),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: <Widget>[
                    FilledButton(
                      onPressed: changed ? _save : null,
                      child: const Text(SignalBandsSettingsScreen.kSaveLabel),
                    ),
                    OutlinedButton(
                      onPressed: _reset,
                      child: const Text(SignalBandsSettingsScreen.kResetLabel),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Keith Parsons' defaults: ${RssiScale.defaults.summary}.",
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The five bands as they would be saved, or a note while a field is wrong.
class _Preview extends StatelessWidget {
  const _Preview({required this.scale});

  final RssiScale? scale;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RssiScale? s = scale;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: s == null
          ? Text(
              'Fix the fields above to see the bands.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final RssiBand b in s.bands)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            b.label,
                            style: (text.bodyLarge ?? const TextStyle())
                                .copyWith(
                                  color: SignalThresholdsScreen.gradeColor(
                                    colors,
                                    _tier(b),
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        Text(
                          b.displayRange,
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  static SignalGrade _tier(RssiBand b) =>
      SignalThresholdsScreen.signalGradeForQuality(b.grade);
}
