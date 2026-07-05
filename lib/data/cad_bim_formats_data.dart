// CAD and BIM Formats - typed const datasets for the read-only field/trade
// reference screen (Field & Trade Reference set, 2026-07-05).
//
// Every string is rendered VERBATIM from Penn's voice-gated copy
// (Deliverables/2026-07-05-field-trade-reference/content/07-cad-bim-formats.md,
// SOP-020 PASS): the format decode table, the Level of Development ladder, the
// CAD-to-Wi-Fi-design workflow, the boundary statement, and the framing prose.
// No copy is rewritten here - the screen only lays it out. This entry is
// text-reference (no decoder plate); a plate can be added later.
//
// GL-005 / truthfulness: the seven-format decode table, the six LOD levels, and
// the three import steps are the load-bearing facts, so the widget test asserts
// the anchor rows (DWG/IFC/RVT, LOD 300/350, the scale-calibration step)
// against these consts so a future edit cannot silently drift a value away from
// Penn's approved copy.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; format and LOD designators shown in DM Mono (AppMonoText.inlineCode).

/// Stable catalog tool id - backs the route, the help entry, and the tests.
/// Permanent.
const String kCadBimFormatsToolId = 'cad-bim-formats';

/// One row of the CAD/BIM format decode table. [format] is the file-format
/// designator (e.g. `DWG`); [whatItIs] is what the format actually is;
/// [authoredBy] is the tool that authors or reads it.
class CadFormatRow {
  const CadFormatRow({
    required this.format,
    required this.whatItIs,
    required this.authoredBy,
  });

  /// The file-format designator, e.g. `DWG` or `NWD / NWC`.
  final String format;

  /// What the format actually is.
  final String whatItIs;

  /// Who authors or reads it.
  final String authoredBy;
}

/// The seven-format decode table, verbatim from the copy.
const List<CadFormatRow> kCadFormats = <CadFormatRow>[
  CadFormatRow(
    format: 'DWG',
    whatItIs:
        'Autodesk\'s native CAD format; the de-facto interchange for 2D '
        'drawings',
    authoredBy: 'AutoCAD; read by many tools',
  ),
  CadFormatRow(
    format: 'DXF',
    whatItIs:
        'Autodesk\'s open drawing-interchange format; near-universal import',
    authoredBy: 'Almost every CAD tool',
  ),
  CadFormatRow(
    format: 'DGN',
    whatItIs:
        'Bentley MicroStation\'s native format; common on large civil and '
        'infrastructure',
    authoredBy: 'MicroStation',
  ),
  CadFormatRow(
    format: 'IFC',
    whatItIs:
        'Industry Foundation Classes: the vendor-neutral, ISO-standardized '
        'open BIM format from buildingSMART',
    authoredBy: 'Any IFC-compliant BIM app',
  ),
  CadFormatRow(
    format: 'RVT',
    whatItIs: 'Autodesk Revit\'s native BIM model (parametric 3D plus data)',
    authoredBy: 'Revit (natively)',
  ),
  CadFormatRow(
    format: 'NWD / NWC',
    whatItIs:
        'Autodesk Navisworks: NWC is a lightweight cache, NWD a coordinated '
        'snapshot merging many models for review and clash detection',
    authoredBy: 'Navisworks (free Freedom viewer opens NWD)',
  ),
  CadFormatRow(
    format: 'COBie',
    whatItIs:
        'Construction-Operations Building information exchange: structured, '
        'non-graphic asset data for facility handover',
    authoredBy: 'Excel or FM systems',
  ),
];

/// One Level of Development rung. [level] is the LOD designator (e.g.
/// `LOD 300`); [meaning] is how much of the model to trust at that rung.
class LodLevel {
  const LodLevel({required this.level, required this.meaning});

  /// The LOD designator, e.g. `LOD 350`.
  final String level;

  /// What that rung means for trust.
  final String meaning;
}

/// The six LOD rungs, verbatim from the copy.
const List<LodLevel> kLodLevels = <LodLevel>[
  LodLevel(level: 'LOD 100', meaning: 'conceptual. A symbol or mass, existence only.'),
  LodLevel(level: 'LOD 200', meaning: 'approximate geometry.'),
  LodLevel(
    level: 'LOD 300',
    meaning: 'accurate, dimensioned geometry in the correct position.',
  ),
  LodLevel(
    level: 'LOD 350',
    meaning:
        'LOD 300 plus connections to other elements (the trade-coordination '
        'level).',
  ),
  LodLevel(level: 'LOD 400', meaning: 'fabrication and installation-ready.'),
  LodLevel(level: 'LOD 500', meaning: 'field-verified as-built.'),
];

/// The three CAD-to-Wi-Fi-design import steps, verbatim from the copy.
const List<String> kCadImportSteps = <String>[
  'Import the CAD or PDF. Ekahau reads DWG and DXF directly and takes PDF, '
      'PNG, and JPG as images. On a CAD import it reads the file\'s layers and '
      'lets you pick which to keep, and its wall-outlining step converts CAD '
      'wall layers into wall lines.',
  'Calibrate the scale on a known distance. You draw a line over something of '
      'known length (a doorway, a hallway) and enter the real measurement. Get '
      'this wrong and every distance, coverage prediction, and attenuation '
      'value downstream is wrong. This is the single step that matters most.',
  'Assign or derive wall materials, then run the coverage prediction.',
];

// ─────────────────────────── framing prose (verbatim) ───────────────────────

/// The italic lead: what CAD/BIM formats are and where the reference stops.
const String kCadBimLead =
    'What the building files an architect hands you actually are, and how they '
    'flow into a Wi-Fi design tool. The Toolbox explains these formats. It '
    'does not open, render, or convert them. That is a different and much '
    'larger product category, and this reference stays on the explaining side '
    'of that line.';

/// "Why it matters" note under the LOD ladder, verbatim.
const String kLodWhyMatters =
    'Why it matters: an LOD 100 to 200 model is a massing study, so do not '
    'derive wall attenuation or mounting detail from it. LOD 300 and up is '
    'dimensionally trustworthy. LOI (Level of Information) is the '
    'data-completeness sibling of LOD (geometry versus data).';

/// Lead-in to the CAD-to-Wi-Fi-design import steps, verbatim.
const String kCadImportIntro =
    'The major Wi-Fi design tools (Ekahau, Hamina, iBwave) follow the same '
    'pattern:';

/// The practical-prep note under the import steps, verbatim.
const String kCadImportPrep =
    'Practical prep: clean the CAD layers before import. Strip furniture, '
    'dimensions, and title blocks; keep walls, doors, and structure. Knowing '
    'the layer scheme (structured codes like A-WALL, A-DOOR, E-LITE) lets you '
    'tell the architect exactly which layers to send instead of receiving an '
    'unusable 80-layer dump.';

/// The boundary statement (rendered as an info band), verbatim.
const String kCadBoundary =
    'The Toolbox explains DWG, IFC, RVT, and the rest, and how they reach '
    'Ekahau, Hamina, and iBwave. It is not a CAD or BIM viewer, converter, or '
    'editor.';

/// "Why a WLAN pro cares" paragraph, verbatim.
const String kCadBimWlanCares =
    'You receive these files on every design job, and the difference between a '
    'clean import and a wasted afternoon is knowing what the format is, what '
    'LOD you were handed, which layers to ask for, and that scale calibration '
    'is the step that makes or breaks the whole design.';

/// The defer footer (rendered as an info band). Verbatim.
const String kCadBimDeferNote =
    'Reference only. Confirm file handling, model reliability, and '
    'responsibility with the architect of record and your design-tool '
    'documentation.';
