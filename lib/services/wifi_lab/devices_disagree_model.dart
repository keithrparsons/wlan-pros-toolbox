// Why Two Devices Disagree About Signal: model (Wi-Fi Classroom, 2026-09-26).
//
// Pure Dart, no Flutter imports. Built clean-room per myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/31-devices-disagree.md, from the
// wave 4 research brief row D (Deliverables/2026-09-26-wifi-classroom-wave4-
// research/brief.md). Same config and seed, same numbers.
//
// THE MODEL (a teaching model, and the screen says so):
//
//   True power at the spot, dBm (the same for every device):
//     P = EIRP - FSPL(1 m) - 10 n log10(d)
//   reused from the Roaming Walk engine (RoamWalkConfig.meanRssiAtDistance),
//   so the two tools agree on path loss.
//
//   What device i's antenna receives at sample t, dBm:
//     raw_i(t) = P + offset_i - grip_i - body_i + F_i(t)
//   offset_i: the device's fixed offset (antenna gain and how its chip is
//             calibrated), positive when it reads high. Illustrative.
//   grip_i:   orientation and how the device is held. Illustrative.
//   body_i:   the person's body, when that device has body loss on.
//             Illustrative.
//   F_i(t):   fading, dB relative to the local average, from the Multipath
//             Simulator's Rayleigh scene (ManyPathScene: equal-power
//             reflectors with random phases, direct path blocked). The
//             devices stand side by side, [spacingM] apart, across the
//             direction the fading pattern moves, so each antenna sits at its
//             own point in the field and sees its own fade.
//
//   Time. Nothing in the room is literally drawn moving, but people and doors
//   move, so the fading at a fixed spot changes from moment to moment. That
//   is modeled the standard frozen-field way: the fading pattern slides past
//   the devices at [kDriftMetersPerSample] per sample, [kSamplesPerSecond]
//   samples a second. The drift speed is illustrative.
//
//   What device i reports at sample t:
//     avg_i(t) = 10 log10( mean over the last W_i samples of 10^(raw/10) )
//     reported_i(t) = step_i * round(avg_i(t) / step_i)
//   The average is taken in milliwatts, as a power measurement would be, so
//   a long average settles near P + offset - grip - body. The reporting step
//   is 1 or 2 dB.
//
//   Apply offsets (what a survey tool's per-adapter offset does):
//     corrected_i(t) = reported_i(t) - offset_i
//   The fixed part disappears. Grip, body and fading stay: an offset
//   calibrates the device, not the way it is held or the spot it is in.
//
//   RCPI (802.11k) is shown as a concept only. Its exact scale is not stated
//   as fact (the research brief marks it UNVERIFIED), so nothing here
//   computes an RCPI value.
//
// ASCII only, no em dashes (GL-004). Devices are generic: no vendor or
// product is named anywhere in this tool.

import 'dart:math' as math;

import 'multipath_model.dart';
import 'roaming_walk_engine.dart';

/// Samples per second (a reading every 100 ms).
const int kSamplesPerSecond = 10;

/// Seconds the strip chart shows.
const int kStripSeconds = 6;

/// Samples on the strip chart.
const int kStripSamples = kSamplesPerSecond * kStripSeconds;

/// Longest averaging window, samples.
const int kMaxAveraging = 10;

/// How far the fading pattern slides past the devices per sample, meters
/// (0.1 m/s at 10 samples a second, about a fifth of a wavelength per
/// sample at 5 GHz, so a fade shows as a dip rather than noise).
/// Illustrative.
const double kDriftMetersPerSample = 0.01;

/// Reflectors in the fading scene.
const int kFadingReflectors = 12;

/// Device count limits.
const int kMinDevices = 2;
const int kMaxDevices = 4;

/// Limits for the controls.
const double kMinOffsetDb = -10;
const double kMaxOffsetDb = 10;
const double kMaxGripLossDb = 10;
const double kMaxBodyLossDb = 10;
const double kMinDistanceM = 1;
const double kMaxDistanceM = 50;
const double kMaxSpacingM = 0.30;

/// Illustrative AP transmit power (EIRP), dBm, and path loss exponent.
const double kDdEirpDbm = 14;
const double kDdPathLossExponent = 3.0;

double _log10(double x) => math.log(x) / math.ln10;

/// The three bands. Path loss uses the Roaming Walk band's frequency and the
/// fading uses the Multipath Simulator band's wavelength, so each number
/// matches the tool it comes from.
enum DdBand {
  b24('2.4 GHz', RoamBand.b24, MultipathBand.b24),
  b5('5 GHz', RoamBand.b5, MultipathBand.b55),
  b6('6 GHz', RoamBand.b6, MultipathBand.b65);

  const DdBand(this.label, this.roam, this.fading);

  final String label;
  final RoamBand roam;
  final MultipathBand fading;

  /// Wavelength used for fading, meters.
  double get wavelength => fading.wavelength;
}

/// What kind of device it is. A label only: the numbers are set per device.
enum DeviceKind {
  laptop('Laptop'),
  phone('Phone'),
  tablet('Tablet'),
  surveyAdapter('Survey adapter');

  const DeviceKind(this.label);

  final String label;
}

/// One device's settings. Every default is illustrative.
class DeviceSettings {
  const DeviceSettings({
    required this.kind,
    this.offsetDb = 0,
    this.gripLossDb = 0,
    this.bodyOn = false,
    this.stepDb = 1,
    this.averaging = 1,
  });

  final DeviceKind kind;

  /// Fixed offset, dB; positive reads high. -10 to +10.
  final double offsetDb;

  /// Orientation and grip loss, dB. 0 to 10.
  final double gripLossDb;

  /// True when the person's body sits between the device and the AP.
  final bool bodyOn;

  /// Reporting step, 1 or 2 dB.
  final int stepDb;

  /// Averaging window, 1 to 10 samples.
  final int averaging;

  DeviceSettings copyWith({
    DeviceKind? kind,
    double? offsetDb,
    double? gripLossDb,
    bool? bodyOn,
    int? stepDb,
    int? averaging,
  }) => DeviceSettings(
    kind: kind ?? this.kind,
    offsetDb: (offsetDb ?? this.offsetDb).clamp(kMinOffsetDb, kMaxOffsetDb),
    gripLossDb: (gripLossDb ?? this.gripLossDb).clamp(0.0, kMaxGripLossDb),
    bodyOn: bodyOn ?? this.bodyOn,
    stepDb: (stepDb ?? this.stepDb) == 2 ? 2 : 1,
    averaging: (averaging ?? this.averaging).clamp(1, kMaxAveraging),
  );

  @override
  bool operator ==(Object other) =>
      other is DeviceSettings &&
      other.kind == kind &&
      other.offsetDb == offsetDb &&
      other.gripLossDb == gripLossDb &&
      other.bodyOn == bodyOn &&
      other.stepDb == stepDb &&
      other.averaging == averaging;

  @override
  int get hashCode =>
      Object.hash(kind, offsetDb, gripLossDb, bodyOn, stepDb, averaging);
}

/// The four default devices, A to D. Illustrative values: the spec's example
/// offsets (0, -4, -2, +1) and grips and steps chosen to show each effect.
const List<DeviceSettings> kDefaultDevices = <DeviceSettings>[
  DeviceSettings(kind: DeviceKind.laptop, averaging: 4),
  DeviceSettings(
    kind: DeviceKind.phone,
    offsetDb: -4,
    gripLossDb: 2,
    bodyOn: true,
  ),
  DeviceSettings(
    kind: DeviceKind.tablet,
    offsetDb: -2,
    gripLossDb: 1,
    stepDb: 2,
    averaging: 2,
  ),
  DeviceSettings(kind: DeviceKind.surveyAdapter, offsetDb: 1),
];

/// Letter for device [index] (0 = A).
String deviceLetter(int index) => String.fromCharCode(65 + index);

/// Everything the numbers depend on.
class DdConfig {
  DdConfig({
    this.band = DdBand.b5,
    this.distanceM = 8,
    this.fadingOn = true,
    this.spacingM = 0.10,
    this.bodyLossDb = 3,
    this.deviceCount = kMaxDevices,
    List<DeviceSettings>? devices,
    this.seed = 1,
  }) : devices = List<DeviceSettings>.unmodifiable(devices ?? kDefaultDevices) {
    assert(this.devices.length == kMaxDevices);
    assert(deviceCount >= kMinDevices && deviceCount <= kMaxDevices);
  }

  final DdBand band;

  /// AP to the spot, meters.
  final double distanceM;
  final bool fadingOn;

  /// Distance between neighboring devices, meters.
  final double spacingM;

  /// Loss when a device's body loss is on, dB. Illustrative.
  final double bodyLossDb;

  /// How many of [devices] are in use (the first [deviceCount]).
  final int deviceCount;

  /// All four device slots; only the first [deviceCount] are measured.
  final List<DeviceSettings> devices;
  final int seed;

  DdConfig copyWith({
    DdBand? band,
    double? distanceM,
    bool? fadingOn,
    double? spacingM,
    double? bodyLossDb,
    int? deviceCount,
    List<DeviceSettings>? devices,
    int? seed,
  }) => DdConfig(
    band: band ?? this.band,
    distanceM: (distanceM ?? this.distanceM).clamp(
      kMinDistanceM,
      kMaxDistanceM,
    ),
    fadingOn: fadingOn ?? this.fadingOn,
    spacingM: (spacingM ?? this.spacingM).clamp(0.0, kMaxSpacingM),
    bodyLossDb: (bodyLossDb ?? this.bodyLossDb).clamp(0.0, kMaxBodyLossDb),
    deviceCount: (deviceCount ?? this.deviceCount).clamp(
      kMinDevices,
      kMaxDevices,
    ),
    devices: devices ?? this.devices,
    seed: seed ?? this.seed,
  );

  /// The same config with device [index] replaced.
  DdConfig withDevice(int index, DeviceSettings d) => copyWith(
    devices: <DeviceSettings>[
      for (int i = 0; i < devices.length; i++) i == index ? d : devices[i],
    ],
  );

  List<DeviceSettings> get active => devices.sublist(0, deviceCount);

  @override
  bool operator ==(Object other) =>
      other is DdConfig &&
      other.band == band &&
      other.distanceM == distanceM &&
      other.fadingOn == fadingOn &&
      other.spacingM == spacingM &&
      other.bodyLossDb == bodyLossDb &&
      other.deviceCount == deviceCount &&
      other.seed == seed &&
      _listEq(other.devices, devices);

  @override
  int get hashCode => Object.hash(
    band,
    distanceM,
    fadingOn,
    spacingM,
    bodyLossDb,
    deviceCount,
    seed,
    Object.hashAll(devices),
  );

  static bool _listEq(List<DeviceSettings> a, List<DeviceSettings> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One device's run: every sample on the strip chart.
class DeviceTrace {
  const DeviceTrace({
    required this.settings,
    required this.fadeDb,
    required this.rawDbm,
    required this.reportedDbm,
    required this.bodyLossDb,
  });

  final DeviceSettings settings;

  /// Fading at each strip sample, dB relative to the local average.
  final List<double> fadeDb;

  /// What the antenna received at each strip sample, before averaging and
  /// the reporting step, dBm.
  final List<double> rawDbm;

  /// What the device reported at each strip sample, dBm.
  final List<double> reportedDbm;

  /// Body loss applied to this device, dB (0 when off).
  final double bodyLossDb;

  /// Reported minus this device's offset: what a survey tool shows once the
  /// offset is entered.
  List<double> get correctedDbm => <double>[
    for (final double v in reportedDbm) v - settings.offsetDb,
  ];

  /// The latest reading.
  double get latest => reportedDbm.last;

  /// The latest reading with the offset applied.
  double get latestCorrected => reportedDbm.last - settings.offsetDb;

  /// The fixed part of this device's error, dB: offset - grip - body.
  double get fixedErrorDb =>
      settings.offsetDb - settings.gripLossDb - bodyLossDb;
}

/// The whole run for one config.
class DdResult {
  DdResult._(this.config, this.trueDbm, this.traces);

  factory DdResult.compute(DdConfig config) {
    final double trueDbm = DevicesDisagreeMath.truePowerDbm(
      config.band,
      config.distanceM,
    );
    final List<List<double>> fades = config.fadingOn
        ? DevicesDisagreeMath.fadeTraces(config)
        : <List<double>>[
            for (int i = 0; i < config.deviceCount; i++)
              List<double>.filled(kStripSamples + kMaxAveraging - 1, 0),
          ];
    final List<DeviceTrace> traces = <DeviceTrace>[
      for (int i = 0; i < config.deviceCount; i++)
        DevicesDisagreeMath.trace(
          config.devices[i],
          trueDbm: trueDbm,
          bodyLossDb: config.devices[i].bodyOn ? config.bodyLossDb : 0,
          fadeDb: fades[i],
        ),
    ];
    return DdResult._(config, trueDbm, traces);
  }

  final DdConfig config;

  /// True received power at the spot, dBm.
  final double trueDbm;

  /// One trace per active device, A first.
  final List<DeviceTrace> traces;

  /// Highest minus lowest reading at strip sample [t].
  double spreadAt(int t, {bool corrected = false}) {
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final DeviceTrace d in traces) {
      final double v = d.reportedDbm[t] - (corrected ? d.settings.offsetDb : 0);
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    return hi - lo;
  }

  /// Spread of the latest readings.
  double spreadNow({bool corrected = false}) =>
      spreadAt(kStripSamples - 1, corrected: corrected);

  /// Spread averaged over every sample on the strip.
  double meanSpread({bool corrected = false}) {
    double sum = 0;
    for (int t = 0; t < kStripSamples; t++) {
      sum += spreadAt(t, corrected: corrected);
    }
    return sum / kStripSamples;
  }

  /// Lowest and highest value any trace reaches, dBm (for the chart axis).
  (double, double) range({bool corrected = false}) {
    double lo = trueDbm;
    double hi = trueDbm;
    for (final DeviceTrace d in traces) {
      final double off = corrected ? d.settings.offsetDb : 0;
      for (final double v in d.reportedDbm) {
        lo = math.min(lo, v - off);
        hi = math.max(hi, v - off);
      }
    }
    return (lo, hi);
  }
}

/// The pure functions.
abstract final class DevicesDisagreeMath {
  /// True power at [distanceM] from the AP, dBm, from the Roaming Walk
  /// engine's log-distance model with the illustrative EIRP and exponent.
  static double truePowerDbm(DdBand band, double distanceM) => RoamWalkConfig(
    band: band.roam,
    eirpDbm: kDdEirpDbm,
    pathLossExponent: kDdPathLossExponent,
  ).meanRssiAtDistance(distanceM);

  /// Quantizes [dbm] to a [stepDb] reporting step.
  static double quantize(double dbm, int stepDb) =>
      (dbm / stepDb).roundToDouble() * stepDb;

  /// The mean of [dbm] values taken in milliwatts, back in dBm.
  static double powerMeanDbm(Iterable<double> dbm) {
    double sum = 0;
    int n = 0;
    for (final double v in dbm) {
      sum += math.pow(10, v / 10).toDouble();
      n++;
    }
    return 10 * _log10(sum / n);
  }

  /// Where device [index] of [count] stands across the drift direction,
  /// meters, centered on the spot.
  static double deviceY(int index, int count, double spacingM) =>
      (index - (count - 1) / 2) * spacingM;

  /// Normalized fading power at point ([x], [y]) of [scene], dB: the
  /// Multipath engine's sum of path contributions, over the local mean
  /// power, exactly as ManyPathScene.normalizedPower does on its own track
  /// but at any point beside it.
  static double fadeDbAt(
    ManyPathScene scene,
    double x,
    double y,
    MultipathBand band,
  ) {
    Complex sum = Complex.zero;
    double mean = 0;
    for (final Scatterer s in scene.scatterers) {
      final double dx = s.x - x;
      final double dy = s.y - y;
      final double r = s.txLeg + math.sqrt(dx * dx + dy * dy);
      sum =
          sum +
          MultipathMath.contribution(
            MultipathPath(length: r, coefficient: s.coefficient),
            band.k,
          );
      mean += s.coefficient.abs2 / (r * r);
    }
    if (mean == 0) return 0;
    return MultipathMath.powerRatioToDb(sum.abs2 / mean);
  }

  /// The fading scene for [seed]: the Multipath Simulator's Rayleigh scene
  /// with its reflectors at large-hall distances, so the devices never stand
  /// near one reflector and the sum stays a sum of many.
  static ManyPathScene scene(int seed) => ManyPathScene.generate(
    seed: seed,
    count: kFadingReflectors,
    environment: ScatterEnvironment.hall,
  );

  /// Fading, dB, for each active device at every sample, warm-up included
  /// (kStripSamples + kMaxAveraging - 1 samples, oldest first).
  static List<List<double>> fadeTraces(DdConfig c) {
    final ManyPathScene s = scene(c.seed);
    const int n = kStripSamples + kMaxAveraging - 1;
    final double x0 = s.trackLength / 2 - (n - 1) * kDriftMetersPerSample / 2;
    return <List<double>>[
      for (int i = 0; i < c.deviceCount; i++)
        <double>[
          for (int t = 0; t < n; t++)
            fadeDbAt(
              s,
              x0 + t * kDriftMetersPerSample,
              deviceY(i, c.deviceCount, c.spacingM),
              c.band.fading,
            ),
        ],
    ];
  }

  /// One device's strip from its full fade list (warm-up included).
  static DeviceTrace trace(
    DeviceSettings d, {
    required double trueDbm,
    required double bodyLossDb,
    required List<double> fadeDb,
  }) {
    const int warm = kMaxAveraging - 1;
    final double fixed = trueDbm + d.offsetDb - d.gripLossDb - bodyLossDb;
    final List<double> raw = <double>[for (final double f in fadeDb) fixed + f];
    final List<double> reported = <double>[
      for (int t = warm; t < raw.length; t++)
        quantize(
          powerMeanDbm(raw.sublist(t - d.averaging + 1, t + 1)),
          d.stepDb,
        ),
    ];
    return DeviceTrace(
      settings: d,
      fadeDb: fadeDb.sublist(warm),
      rawDbm: raw.sublist(warm),
      reportedDbm: reported,
      bodyLossDb: bodyLossDb,
    );
  }

  /// Pearson correlation of two equal-length series (fade comparison).
  static double correlation(List<double> a, List<double> b) {
    assert(a.length == b.length);
    final int n = a.length;
    double ma = 0;
    double mb = 0;
    for (int i = 0; i < n; i++) {
      ma += a[i];
      mb += b[i];
    }
    ma /= n;
    mb /= n;
    double sab = 0;
    double saa = 0;
    double sbb = 0;
    for (int i = 0; i < n; i++) {
      sab += (a[i] - ma) * (b[i] - mb);
      saa += (a[i] - ma) * (a[i] - ma);
      sbb += (b[i] - mb) * (b[i] - mb);
    }
    if (saa == 0 || sbb == 0) return 1;
    return sab / math.sqrt(saa * sbb);
  }
}
