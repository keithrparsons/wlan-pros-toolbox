// MSI / Planet and NSMA WG16.99.050 pattern files for the Wi-Fi Lab
// "Antenna Pattern" tool (antenna-pattern): read them into PatternCuts, and
// write our own fixtures from a known pattern. Pure Dart.
//
// CLEAN-ROOM (2026-09-25): grammar and conventions from myPKA
// Deliverables/2026-09-25-antenna-simulator-research/brief.md §1a and §1b
// only. No vendor pattern file is bundled; every example this tool offers is
// generated here from a closed-form model.
//
// THE PARSER BUG TO DESIGN AGAINST (brief §1): the two formats use opposite
// conventions for the vertical direction and for the data sign.
//   MSI   vertical 0 = horizon, 90 = DOWN, 270 = up; values are LOSS, positive
//         (a minus sign is not written); GAIN with no unit is dBd.
//   NSMA  elevation positive UP; DBR data are NEGATIVE (dB relative to peak);
//         GUNITS says what the gain and data units are.
// Both land in the MSI form of PatternCuts (loss >= 0, MSI angles).
//
// NSMA AZIMUTH DIRECTION: the brief does not state it. It is read here as
// counterclockwise seen from above, the usual spherical convention that
// Annex A.2's geometry (zenith at elevation +90) implies. This is INFERRED,
// and it only matters for a horizontal cut that is not left-right symmetric.

import 'dart:math' as math;

import 'antenna_pattern_math.dart';

enum PatternFormat {
  msi('MSI / Planet'),
  nsma('NSMA WG16.99.050');

  const PatternFormat(this.label);
  final String label;
}

class PatternParseException implements Exception {
  const PatternParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A pattern file, read.
class ParsedPattern {
  const ParsedPattern({
    required this.format,
    required this.cuts,
    required this.gainAsWritten,
    required this.warnings,
    this.name,
    this.make,
    this.frequencyMhz,
    this.tilt,
    this.polarization,
  });

  final PatternFormat format;
  final PatternCuts cuts;

  /// The gain line as the file states it, e.g. "0.00 dBd (no unit, so dBd)".
  final String gainAsWritten;
  final List<String> warnings;
  final String? name;
  final String? make;
  final double? frequencyMhz;
  final String? tilt;
  final String? polarization;

  double get gainDbi => cuts.peakGainDbi;
}

/// Reads either format, telling them apart by NSMA's `KEY:,value` lines.
ParsedPattern parsePatternText(String text) {
  final bool nsma = RegExp(
    r'^\s*(REVNUM|ANTMAN|PATCUT|GUNITS|NUPOIN)\s*:',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(text);
  return nsma ? parseNsma(text) : parseMsi(text);
}

// ── Resampling ─────────────────────────────────────────────────────────────

/// Resamples (angle, value) points on a circle to 360 values at 1° steps by
/// linear interpolation, wrapping at 360.
List<double> _resampleCircle(List<(double, double)> points) {
  final Map<double, double> byAngle = <double, double>{};
  for (final (double a, double v) in points) {
    byAngle[((a % 360) + 360) % 360] = v; // a later duplicate wins
  }
  final List<double> angles = byAngle.keys.toList()..sort();
  final int n = angles.length;
  final List<double> out = List<double>.filled(360, 0);
  int hi = 0;
  for (int d = 0; d < 360; d++) {
    final double x = d.toDouble();
    while (hi < n && angles[hi] < x) {
      hi++;
    }
    if (hi < n && angles[hi] == x) {
      out[d] = byAngle[x]!;
      continue;
    }
    final double a1 = hi < n ? angles[hi] : angles[0] + 360;
    final double v1 = byAngle[hi < n ? angles[hi] : angles[0]]!;
    final double a0 = hi > 0 ? angles[hi - 1] : angles[n - 1] - 360;
    final double v0 = byAngle[hi > 0 ? angles[hi - 1] : angles[n - 1]]!;
    final double f = (x - a0) / (a1 - a0);
    out[d] = v0 + (v1 - v0) * f;
  }
  return out;
}

double? _num(String s) => double.tryParse(s.trim());

String _fmt(double v, [int places = 2]) {
  final String s = v.toStringAsFixed(places);
  return s.startsWith('-') && double.parse(s) == 0 ? s.substring(1) : s;
}

// ── MSI ────────────────────────────────────────────────────────────────────

const Set<String> _msiKnownKeys = <String>{
  'NAME',
  'MAKE',
  'FREQUENCY',
  'H_WIDTH',
  'V_WIDTH',
  'FRONT_TO_BACK',
  'GAIN',
  'TILT',
  'ELECTRICAL_TILT',
  'MECHANICAL_TILT',
  'POLARIZATION',
  'COMMENT',
  'HORIZONTAL',
  'VERTICAL',
};

ParsedPattern parseMsi(String text) {
  final List<String> lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final List<String> warnings = <String>[];
  String? name, make, tilt, polarization;
  double? freq;
  double? gain;
  bool gainIsDbi = false;
  String gainWritten = '';
  final Map<String, List<(double, double)>> sections =
      <String, List<(double, double)>>{};
  final Map<String, int?> declared = <String, int?>{};
  int unknownKeys = 0;
  bool sawNegative = false;

  int i = 0;
  while (i < lines.length) {
    final String line = lines[i].trim();
    i++;
    if (line.isEmpty) continue;
    final List<String> tok = line.split(RegExp(r'\s+'));
    final String key = tok.first.toUpperCase();
    final String rest = line.substring(tok.first.length).trim();
    if (key == 'HORIZONTAL' || key == 'VERTICAL') {
      declared[key] = tok.length > 1 ? int.tryParse(tok[1]) : null;
      final List<(double, double)> pts = <(double, double)>[];
      while (i < lines.length) {
        final String d = lines[i].trim();
        if (d.isEmpty) {
          i++;
          continue;
        }
        final List<String> dt = d.split(RegExp(r'[\s,;]+'));
        final double? a = dt.isNotEmpty ? _num(dt[0]) : null;
        final double? v = dt.length > 1 ? _num(dt[1]) : null;
        if (a == null || v == null) break;
        if (v < 0) sawNegative = true;
        pts.add((a, v.abs()));
        i++;
      }
      sections[key] = pts;
      continue;
    }
    // A key must start with a letter; the rest are vendor extensions (mixed
    // case is allowed and ignored).
    if (!RegExp(r'^[A-Za-z]').hasMatch(key)) {
      throw PatternParseException(
        'Line $i does not start with a key: "$line". An MSI file is a list '
        'of KEY value lines, then HORIZONTAL and VERTICAL sections.',
      );
    }
    switch (key) {
      case 'NAME':
        name = rest;
      case 'MAKE':
        make = rest;
      case 'FREQUENCY':
        freq = tok.length > 1 ? _num(tok[1]) : null;
      case 'GAIN':
        gain = tok.length > 1 ? _num(tok[1]) : null;
        final String unit = tok.length > 2 ? tok[2].toLowerCase() : '';
        gainIsDbi = unit == 'dbi';
        if (gain != null) {
          gainWritten = unit.isEmpty
              ? '${_fmt(gain)} (no unit, so dBd)'
              : '${_fmt(gain)} ${gainIsDbi ? 'dBi' : 'dBd'}';
        }
      case 'TILT':
      case 'ELECTRICAL_TILT':
      case 'MECHANICAL_TILT':
        tilt = key == 'TILT' ? rest : '${key.toLowerCase()} $rest';
      case 'POLARIZATION':
        polarization = rest;
      default:
        if (!_msiKnownKeys.contains(key)) unknownKeys++;
    }
  }

  for (final String s in <String>['HORIZONTAL', 'VERTICAL']) {
    final List<(double, double)>? pts = sections[s];
    if (pts == null) {
      throw PatternParseException(
        'No $s section found. An MSI file needs both a HORIZONTAL and a '
        'VERTICAL section.',
      );
    }
    if (pts.length < 4) {
      throw PatternParseException(
        'The $s section has ${pts.length} points; it needs at least 4.',
      );
    }
    final int? d = declared[s];
    if (d != null && d != pts.length) {
      warnings.add(
        '$s says $d points and holds ${pts.length}. Read the '
        '${pts.length} that are there.',
      );
    }
  }
  if (gain == null) {
    warnings.add('No GAIN line. Assumed 0 dBd (2.15 dBi).');
    gain = 0;
    gainWritten = 'none stated, assumed 0 dBd';
  }
  if (sawNegative) {
    warnings.add(
      'Some values carry a minus sign. MSI values are loss below the peak '
      'and are written without one, so they were read as losses.',
    );
  }
  if (unknownKeys > 0) {
    warnings.add(
      '$unknownKeys unrecognized key${unknownKeys == 1 ? '' : 's'} '
      'ignored (vendor extensions are allowed).',
    );
  }
  final double gainDbi = gainIsDbi ? gain : dbdToDbi(gain);
  final List<double> h = _resampleCircle(sections['HORIZONTAL']!);
  final List<double> v = _resampleCircle(sections['VERTICAL']!);
  return ParsedPattern(
    format: PatternFormat.msi,
    cuts: _normalized(h, v, gainDbi, warnings),
    gainAsWritten: gainWritten,
    warnings: warnings,
    name: name,
    make: make,
    frequencyMhz: freq,
    tilt: tilt,
    polarization: polarization,
  );
}

/// Shifts both cuts so the lowest loss is 0 dB: MSI promises loss relative
/// to the peak, and a file that breaks the promise gets a warning.
PatternCuts _normalized(
  List<double> h,
  List<double> v,
  double gainDbi,
  List<String> warnings,
) {
  final double lo = math.min(h.reduce(math.min), v.reduce(math.min));
  if (lo.abs() > 0.05) {
    warnings.add(
      'Neither cut reaches 0 dB loss (lowest ${_fmt(lo)} dB); shifted so the '
      'best direction is the stated gain.',
    );
  }
  return PatternCuts(
    horizontalLossDb: <double>[for (final double x in h) x - lo],
    verticalLossDb: <double>[for (final double x in v) x - lo],
    peakGainDbi: gainDbi,
  );
}

/// Writes an MSI file from [cuts]. With [gainInDbd] the GAIN line carries no
/// unit, exercising the MSI default.
String writeMsi(
  PatternCuts cuts, {
  required String name,
  double frequencyMhz = 2450,
  bool gainInDbd = true,
  String tilt = 'NONE',
  String comment =
      'Generated by the WLAN Pros Toolbox from a closed-form '
      'model. The exact 3D pattern is known.',
}) {
  final double? hw = cuts.horizontalBeamwidthDeg;
  final double? vw = cuts.verticalBeamwidthDeg;
  final List<double> h = cuts.horizontalLossDb;
  final StringBuffer b = StringBuffer()
    ..writeln('NAME $name')
    ..writeln('MAKE WLAN Pros Toolbox (generated)')
    ..writeln('FREQUENCY ${_fmt(frequencyMhz, 0)}')
    ..writeln('H_WIDTH ${hw == null ? 360 : _fmt(hw, 1)}')
    ..writeln('V_WIDTH ${vw == null ? 360 : _fmt(vw, 1)}')
    ..writeln('FRONT_TO_BACK ${_fmt(h[180] - h[0])}')
    ..writeln(
      gainInDbd
          ? 'GAIN ${_fmt(dbiToDbd(cuts.peakGainDbi))}'
          : 'GAIN ${_fmt(cuts.peakGainDbi)} dBi',
    )
    ..writeln('TILT $tilt')
    ..writeln('POLARIZATION VERTICAL')
    ..writeln('COMMENT $comment')
    ..writeln('HORIZONTAL 360');
  for (int a = 0; a < 360; a++) {
    b.writeln('$a ${_fmt(h[a])}');
  }
  b.writeln('VERTICAL 360');
  for (int a = 0; a < 360; a++) {
    b.writeln('$a ${_fmt(cuts.verticalLossDb[a])}');
  }
  return b.toString();
}

// ── NSMA ───────────────────────────────────────────────────────────────────

class _NsmaCut {
  _NsmaCut(this.kind);
  final String kind;
  String? polarization;
  int? declared;
  final List<(double, double)> points = <(double, double)>[];
}

ParsedPattern parseNsma(String text) {
  final List<String> warnings = <String>[];
  final Map<String, List<String>> fields = <String, List<String>>{};
  final List<_NsmaCut> cuts = <_NsmaCut>[];
  _NsmaCut? current;
  for (final String raw in text.replaceAll('\r', '\n').split('\n')) {
    final int bang = raw.indexOf('!');
    final String line = (bang >= 0 ? raw.substring(0, bang) : raw).trim();
    if (line.isEmpty) continue;
    final int colon = line.indexOf(':');
    if (colon > 0 && RegExp(r'^[A-Za-z]').hasMatch(line)) {
      final String key = line.substring(0, colon).trim().toUpperCase();
      final List<String> values = line
          .substring(colon + 1)
          .split(',')
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      switch (key) {
        case 'PATCUT':
          current = _NsmaCut(values.isEmpty ? '' : values.first.toUpperCase());
          cuts.add(current);
        case 'POLARI':
          current?.polarization = values.isEmpty ? null : values.first;
        case 'NUPOIN':
          current?.declared = values.isEmpty ? null : int.tryParse(values[0]);
        default:
          fields[key] = values;
      }
      continue;
    }
    final List<String> parts = line.split(RegExp(r'[,\s]+'));
    final double? a = parts.isNotEmpty ? _num(parts[0]) : null;
    final double? v = parts.length > 1 ? _num(parts[1]) : null;
    if (a == null || v == null) {
      throw PatternParseException(
        'Could not read "$line". NSMA data lines are angle,value.',
      );
    }
    if (current == null) {
      throw const PatternParseException(
        'Data before any PATCUT line. Each cut starts with PATCUT:,AZ or '
        'PATCUT:,EL.',
      );
    }
    current.points.add((a, v));
  }

  // Units: GUNITS:,<gain unit>/<data unit>.
  final String gunits = (fields['GUNITS'] ?? <String>['DBI/DBR']).join(',');
  final List<String> u = gunits.toUpperCase().split('/');
  final String gainUnit = u.first.trim();
  final String dataUnit = u.length > 1 ? u[1].trim() : 'DBR';
  final double? mdgain = (fields['MDGAIN'] ?? const <String>[]).isEmpty
      ? null
      : _num(fields['MDGAIN']!.first);
  if (mdgain == null) warnings.add('No MDGAIN line. Assumed 0 dBi.');
  final double gainDbi = gainUnit == 'DBD'
      ? dbdToDbi(mdgain ?? 0)
      : (mdgain ?? 0);

  _NsmaCut? pick(Set<String> kinds) {
    final List<_NsmaCut> of = cuts
        .where((_NsmaCut c) => kinds.contains(c.kind))
        .toList();
    if (of.isEmpty) return null;
    // Prefer a co-polar cut (V/V, H/H) over a cross-polar one.
    for (final _NsmaCut c in of) {
      final List<String> p = (c.polarization ?? '').toUpperCase().split('/');
      if (p.length == 2 && p[0] == p[1]) return c;
    }
    return of.first;
  }

  final _NsmaCut? az = pick(<String>{'AZ', 'H'});
  final _NsmaCut? el = pick(<String>{'EL', 'V'});
  if (az == null || el == null) {
    throw const PatternParseException(
      'An NSMA file needs an azimuth cut (PATCUT:,AZ or H) and an elevation '
      'cut (PATCUT:,EL or V).',
    );
  }
  for (final _NsmaCut c in <_NsmaCut>[az, el]) {
    if (c.points.length < 4) {
      throw PatternParseException(
        'The ${c.kind} cut has ${c.points.length} points; it needs at least 4.',
      );
    }
    if (c.declared != null && c.declared != c.points.length) {
      warnings.add(
        'The ${c.kind} cut says NUPOIN ${c.declared} and holds '
        '${c.points.length}. Read the ${c.points.length} that are there.',
      );
    }
  }

  double toLoss(double value) => switch (dataUnit) {
    'DBR' => -value,
    'DBI' => gainDbi - value,
    'DBD' => gainDbi - dbdToDbi(value),
    'LIN' => value <= 0 ? kGridFloorDb : -20 * math.log(value) / math.ln10,
    _ => -value,
  };
  if (!<String>{'DBR', 'DBI', 'DBD', 'LIN'}.contains(dataUnit)) {
    warnings.add('Unknown data unit "$dataUnit"; read as DBR.');
  }

  // NSMA elevation is positive UP; MSI vertical is positive DOWN: v = −e.
  // NSMA azimuth is read counterclockwise (see header); MSI is clockwise.
  final List<double> h = _resampleCircle(<(double, double)>[
    for (final (double a, double v) in az.points) (-a, toLoss(v)),
  ]);
  final List<double> v = _resampleCircle(<(double, double)>[
    for (final (double e, double x) in el.points) (-e, toLoss(x)),
  ]);
  final List<String> name = <String>[
    ...?fields['ANTMAN'],
    ...?fields['MODNUM'],
  ];
  final double? lo = (fields['LOWFRQ'] ?? const <String>[]).isEmpty
      ? null
      : _num(fields['LOWFRQ']!.first);
  final double? hi = (fields['HGHFRQ'] ?? const <String>[]).isEmpty
      ? null
      : _num(fields['HGHFRQ']!.first);
  return ParsedPattern(
    format: PatternFormat.nsma,
    cuts: _normalized(h, v, gainDbi, warnings),
    gainAsWritten:
        '${_fmt(mdgain ?? 0)} ${gainUnit == 'DBD' ? 'dBd' : 'dBi'}'
        ' (GUNITS $gunits)',
    warnings: warnings,
    name: name.isEmpty ? null : name.join(' '),
    make: fields['ANTMAN']?.join(' '),
    frequencyMhz: lo != null && hi != null ? (lo + hi) / 2 : lo ?? hi,
    tilt: fields['ELTILT']?.join(' '),
    polarization: el.polarization,
  );
}

/// Writes an NSMA WG16.99.050 file (DBI gain, DBR data, AZ and EL cuts,
/// −180..179) from [cuts].
String writeNsma(
  PatternCuts cuts, {
  required String model,
  double lowMhz = 2400,
  double highMhz = 2500,
  double electricalTiltDeg = 0,
}) {
  final StringBuffer b = StringBuffer()
    ..writeln('REVNUM:,NSMA WG16.99.050')
    ..writeln('REVDAT:,19990520')
    ..writeln('ANTMAN:,WLAN Pros Toolbox (generated)')
    ..writeln('MODNUM:,$model')
    ..writeln('LOWFRQ:,${_fmt(lowMhz, 0)}')
    ..writeln('HGHFRQ:,${_fmt(highMhz, 0)}')
    ..writeln('GUNITS:,DBI/DBR')
    ..writeln('MDGAIN:,${_fmt(cuts.peakGainDbi)}')
    ..writeln('ELTILT:,${_fmt(electricalTiltDeg, 1)}')
    ..writeln('PATTYP:,Typical')
    ..writeln('NOFREQ:,1')
    ..writeln('PATFRE:,${_fmt((lowMhz + highMhz) / 2, 0)}')
    ..writeln('NUMCUT:,2')
    ..writeln('PATCUT:,AZ')
    ..writeln('POLARI:,V/V')
    ..writeln('NUPOIN:,360')
    ..writeln('FSTLST:,-180,179');
  // Counterclockwise azimuth a is MSI azimuth −a.
  for (int a = -180; a < 180; a++) {
    final int msi = ((-a) % 360 + 360) % 360;
    b.writeln('$a,${_fmt(-cuts.horizontalLossDb[msi])}');
  }
  b
    ..writeln('PATCUT:,EL')
    ..writeln('POLARI:,V/V')
    ..writeln('NUPOIN:,360')
    ..writeln('FSTLST:,-180,179');
  // Elevation e (positive up) is MSI vertical −e.
  for (int e = -180; e < 180; e++) {
    final int msi = ((-e) % 360 + 360) % 360;
    b.writeln('$e,${_fmt(-cuts.verticalLossDb[msi])}');
  }
  b.writeln('ENDFIL:,EOF');
  return b.toString();
}
