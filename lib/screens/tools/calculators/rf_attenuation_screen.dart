// RF Attenuation (building materials) calculator.
//
// Estimates total path loss through stacked building materials for a chosen
// Wi-Fi band. Dataset and math mirror the RF Tools PWA reference exactly
// (app.js MATERIALS + calcMaterials, lines 998 and 1090):
//
//   bi = band '2.4' -> 1, '5' -> 2, '6' -> 3   (column index into a material row)
//   per-material loss = m[bi] * qty
//   total = sum of per-material loss over every material with qty > 0
//
// The MATERIALS table below is a verbatim port of the PWA constant: each entry
// is [name, loss@2.4, loss@5, loss@6, note] with dB-per-layer values unchanged.
// Do not edit the loss numbers without first updating the PWA + GL-003.
//
// UI model: the PWA renders all 13 materials as a list of quantity inputs and
// sums them. This screen keeps the same math but uses the App-Mode AppSelect
// (§8.14) to pick a material plus a quantity field, accumulating chosen
// materials into a breakdown list. Total = sum of (per-band loss * qty) across
// every accumulated row, identical to calcMaterials.
//
// Edge cases:
// - No materials added -> total blank ("—"), empty-state hint in breakdown.
// - Quantity empty / 0 / invalid on the add control -> adds nothing (no crash),
//   matching the PWA `parseInt(...) || 0` then `if (qty > 0)` guard.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget class so it is unit-testable against the PWA values.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Wi-Fi band selector, mirroring the PWA mat-band select (2.4 / 5 / 6 GHz).
enum MaterialBand { ghz24, ghz5, ghz6 }

class RfAttenuationScreen extends StatefulWidget {
  const RfAttenuationScreen({super.key});

  // ─── Dataset (verbatim PWA port) ────────────────────────────────────────────
  // app.js MATERIALS: [name, loss@2.4GHz, loss@5GHz, loss@6GHz, note].
  // Typical attenuation in dB per layer.

  /// One building material's per-band attenuation and field note.
  static const List<RfMaterial> materials = <RfMaterial>[
    RfMaterial('Drywall / Plasterboard', 3, 4, 5,
        'Single sheet, most interior walls'),
    RfMaterial('Wood door / hollow partition', 4, 5, 6,
        'Standard interior door'),
    RfMaterial('Cubicle / office panel', 2, 3, 4, 'Fabric or thin material'),
    RfMaterial('Glass — clear single pane', 2, 3, 4, 'Standard window glass'),
    RfMaterial('Glass — low-E / tinted coated', 8, 10, 12,
        'Energy-efficient coated glass'),
    RfMaterial('Brick (4 in / 10 cm)', 8, 12, 15, 'Common exterior wall'),
    RfMaterial('Concrete block / CMU', 10, 13, 15, 'Hollow or solid block'),
    RfMaterial('Concrete — poured (4 in / 10 cm)', 13, 16, 19,
        'Reinforced slab or wall'),
    RfMaterial('Metal door / steel panel', 20, 26, 30, 'Major barrier'),
    RfMaterial('Foil insulation / vapor barrier', 25, 30, 35,
        'Near-total block'),
    RfMaterial('Concrete floor / ceiling', 15, 20, 22, 'Inter-floor path loss'),
    RfMaterial('Wood floor / raised subfloor', 5, 7, 8, 'Residential structure'),
    RfMaterial('Water / wet materials', 6, 9, 11, 'Aquariums, wet concrete, HVAC'),
  ];

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: band->column index, per-material loss, total.

  /// Per-band column index, mirroring the PWA `bi` ternary
  /// (band '2.4' -> 1, '5' -> 2, else 3). Returned 1-based to match the raw
  /// MATERIALS row layout the PWA indexes into.
  static int bandIndex(MaterialBand band) {
    switch (band) {
      case MaterialBand.ghz24:
        return 1;
      case MaterialBand.ghz5:
        return 2;
      case MaterialBand.ghz6:
        return 3;
    }
  }

  /// Single material's attenuation in dB for [band] (PWA `m[bi]`).
  static int lossPerLayer(RfMaterial material, MaterialBand band) {
    switch (band) {
      case MaterialBand.ghz24:
        return material.loss24;
      case MaterialBand.ghz5:
        return material.loss5;
      case MaterialBand.ghz6:
        return material.loss6;
    }
  }

  /// Total loss in dB for a material/quantity map at [band]
  /// (PWA calcMaterials: sum of `m[bi] * qty` for every qty > 0).
  static int totalLoss(Map<RfMaterial, int> quantities, MaterialBand band) {
    int total = 0;
    for (final MapEntry<RfMaterial, int> e in quantities.entries) {
      if (e.value > 0) {
        total += lossPerLayer(e.key, band) * e.value;
      }
    }
    return total;
  }

  @override
  State<RfAttenuationScreen> createState() => _RfAttenuationScreenState();
}

/// Immutable building-material record (PWA MATERIALS row).
class RfMaterial {
  const RfMaterial(
    this.name,
    this.loss24,
    this.loss5,
    this.loss6,
    this.note,
  );

  final String name;
  final int loss24;
  final int loss5;
  final int loss6;
  final String note;
}

class _RfAttenuationScreenState extends State<RfAttenuationScreen> {
  final TextEditingController _qtyCtrl =
      TextEditingController(text: '1');
  final FocusNode _qtyFocus = FocusNode();

  MaterialBand _band = MaterialBand.ghz24;
  RfMaterial _selected = RfAttenuationScreen.materials.first;

  // Accumulated materials -> quantity. Insertion order preserved for breakdown.
  final Map<RfMaterial, int> _quantities = <RfMaterial, int>{};

  // Positive integers only; quantities are whole layers a human types by hand.
  static final List<TextInputFormatter> _unsignedInt = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
  ];

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  /// Add the selected material at the entered quantity. PWA parity: empty /
  /// 0 / invalid quantity adds nothing (`parseInt(...) || 0` then `qty > 0`).
  void _addSelected() {
    final int qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    setState(() {
      _quantities[_selected] = (_quantities[_selected] ?? 0) + qty;
    });
  }

  void _removeMaterial(RfMaterial material) {
    setState(() => _quantities.remove(material));
  }

  void _clearAll() {
    setState(_quantities.clear);
  }

  int get _total => RfAttenuationScreen.totalLoss(_quantities, _band);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RF Attenuation'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
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
                          toolId: 'rf-attenuation', isDesktop: isDesktop),
                      if (ToolAssets.hasGraphic('rf-attenuation'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
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

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bandField(text),
          const SizedBox(height: AppSpacing.sm),
          _materialField(),
          const SizedBox(height: AppSpacing.xs),
          // Per-layer loss for the current band, mirroring the PWA
          // "X dB each" hint under each material row.
          Text(
            '${RfAttenuationScreen.lossPerLayer(_selected, _band)} dB each '
            'at ${_bandLabel(_band)}',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _qtyRow(text, mono),
        ],
      ),
    );
  }

  Widget _bandField(TextTheme text) {
    return LabeledField(
      label: 'Frequency band',
      semanticLabel: 'Frequency band',
      // Full-bleed segmented control: the three band chips share the row width
      // so the toggle never exceeds a phone-width input card (the prior
      // intrinsic-width Row inside an Align overflowed ~31px at 375pt).
      field: _UnitToggle<MaterialBand>(
        value: _band,
        options: const [
          (MaterialBand.ghz24, '2.4 GHz'),
          (MaterialBand.ghz5, '5 GHz'),
          (MaterialBand.ghz6, '6 GHz'),
        ],
        onChanged: (MaterialBand b) => setState(() => _band = b),
      ),
    );
  }

  Widget _materialField() {
    // 13 materials, long labels -> full-width AppSelect (§8.14).
    return LabeledField(
      label: 'Material',
      semanticLabel: 'Building material',
      field: AppSelect<RfMaterial>(
        value: _selected,
        semanticLabel: 'Building material',
        items: RfAttenuationScreen.materials
            .map((RfMaterial m) => (m, m.name))
            .toList(),
        onChanged: (RfMaterial m) => setState(() => _selected = m),
      ),
    );
  }

  Widget _qtyRow(TextTheme text, AppMonoText mono) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LabeledField(
            label: 'Quantity',
            hint: '(layers)',
            semanticLabel: 'Quantity of layers',
            field: TextField(
              controller: _qtyCtrl,
              focusNode: _qtyFocus,
              keyboardType: TextInputType.number,
              inputFormatters: _unsignedInt,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addSelected(),
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(fontSize: 20),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '1'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _AddButton(onPressed: _addSelected),
      ],
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final bool hasRows = _quantities.values.any((int q) => q > 0);

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total loss',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              if (hasRows)
                _ClearButton(onPressed: _clearAll),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                // PWA fmt(total, 0). Blank ("—") until a material is added.
                hasRows ? _total.toString() : '—',
                style: mono.outputXL.copyWith(
                  color: hasRows ? AppColors.primary : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'dB',
                style: text.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _breakdown(text, mono, hasRows),
        ],
      ),
    );
  }

  Widget _breakdown(TextTheme text, AppMonoText mono, bool hasRows) {
    if (!hasRows) {
      // Empty state — mirrors the PWA "Add quantities above to see breakdown."
      return Text(
        'Add a material above to see the breakdown.',
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      );
    }

    final List<Widget> lines = <Widget>[];
    for (final MapEntry<RfMaterial, int> e in _quantities.entries) {
      if (e.value <= 0) continue;
      final int loss =
          RfAttenuationScreen.lossPerLayer(e.key, _band) * e.value;
      lines.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  // PWA breakdown line: "${qty}× ${name}: ${loss} dB".
                  '${e.value}× ${e.key.name}: $loss dB',
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _RemoveButton(
                label: 'Remove ${e.key.name}',
                onPressed: () => _removeMaterial(e.key),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
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
            'Per-layer loss at ${_bandLabel(_band)}',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...RfAttenuationScreen.materials.map((RfMaterial m) {
            final int loss = RfAttenuationScreen.lossPerLayer(m, _band);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      m.name,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '$loss dB',
                      textAlign: TextAlign.right,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Typical dB per layer. Real-world loss varies with thickness, '
            'moisture, and angle of incidence.',
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  static String _bandLabel(MaterialBand band) {
    switch (band) {
      case MaterialBand.ghz24:
        return '2.4 GHz';
      case MaterialBand.ghz5:
        return '5 GHz';
      case MaterialBand.ghz6:
        return '6 GHz';
    }
  }
}

/// Primary "Add" action sized to the §8.3 minimum touch target. Lime fill,
/// charcoal glyph — the primary-button treatment without inventing tokens.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add material',
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onPressed,
          child: const SizedBox(
            height: AppSpacing.minTouchTarget,
            width: AppSpacing.minTouchTarget,
            child: Icon(Icons.add, color: AppColors.secondary),
          ),
        ),
      ),
    );
  }
}

/// Inline "remove this row" affordance in the breakdown list.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onPressed,
        child: const SizedBox(
          height: AppSpacing.minTouchTarget,
          width: AppSpacing.minTouchTarget,
          child: Icon(
            Icons.close,
            size: AppSpacing.sm,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// Text "Clear" action in the result header.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Clear all materials',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 6,
          ),
          child: Text(
            'Clear',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented unit toggle, ported from fspl_screen for the 2–3 option band
/// selector. Holds to the §8.3 minimum touch target and uses ChoiceChip-style
/// selection without inventing new tokens.
class _UnitToggle<T> extends StatelessWidget {
  const _UnitToggle({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      // Each option flexes to an equal share of the row so the segmented
      // control fits any bounded width (phone input card) without overflowing.
      child: Row(
        children: options.map((opt) {
          final bool selected = opt.$1 == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: opt.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onChanged(opt.$1),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.labelLarge?.copyWith(
                      color: selected
                          ? AppColors.secondary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
