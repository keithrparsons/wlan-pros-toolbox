// State for the Wi-Fi Classroom MIMO and Beamforming simulator (mimo-beamforming).
//
// One ChangeNotifier holds every input, so the two halves of the screen stay
// independent widgets: MimoStage (the pictures) and MimoControls (inputs and
// readouts) both listen to it. The phone layout stacks them; a presenter
// layout can put them side by side without either knowing about the other.
//
// All physics lives in lib/services/wifi_lab/mimo_beamforming_model.dart.
// This file only holds the inputs, asks the model, and formats numbers.

import 'package:flutter/foundation.dart';

import '../../../services/wifi_lab/mimo_beamforming_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kMimoBeamformingToolId = 'mimo-beamforming';

/// AP chain choices (8 is the optional large AP).
const List<int> kApChainOptions = <int>[1, 2, 3, 4, 8];

/// Client and sniffer chain choices.
const List<int> kClientChainOptions = <int>[1, 2, 3, 4];

/// Sounding interval choices, milliseconds.
const List<double> kSoundingIntervalsMs = <double>[2, 5, 10, 20, 50, 100, 200];

/// Client and sniffer angle limit, degrees either side of straight ahead.
const double kMaxAngleDeg = 80;

/// How far one presenter key press steers the client, degrees.
const double kClientAngleKeyStepDeg = 5;

class MimoController extends ChangeNotifier {
  MimoController({
    int apChains = 4,
    int clientChains = 2,
    LinkDirection initialDirection = LinkDirection.downlink,
  }) : _ap = apChains,
       _client = clientChains,
       _direction = initialDirection,
       _initialAp = apChains,
       _initialClient = clientChains,
       _initialDirection = initialDirection;

  final int _initialAp;
  final int _initialClient;
  final LinkDirection _initialDirection;

  int _ap;
  int _client;
  LinkDirection _direction;
  bool _beamforming = true;
  double _clientDeg = 20;
  double _snifferDeg = -35;
  int _snifferChains = 1;
  ChannelWidth _width = ChannelWidth.w80;
  int _intervalIndex = 2; // 10 ms

  // ── Inputs ──────────────────────────────────────────────────────────────

  int get apChains => _ap;
  set apChains(int v) => _set(() => _ap = v.clamp(1, 8));

  int get clientChains => _client;
  set clientChains(int v) => _set(() => _client = v.clamp(1, 4));

  /// The vice versa case: swaps the two chain counts. An 8-chain AP swaps
  /// to a 4-chain client, since clients stop at 4.
  void swapSides() => _set(() {
    final int a = _ap;
    _ap = _client;
    _client = a.clamp(1, 4);
  });

  /// True when a swap would lose the AP's chain count (8 to 4).
  bool get swapClamps => _ap > 4;

  LinkDirection get direction => _direction;
  set direction(LinkDirection v) => _set(() => _direction = v);

  bool get beamforming => _beamforming;
  set beamforming(bool v) => _set(() => _beamforming = v);

  /// Client angle from straight ahead of the AP, degrees.
  double get clientDeg => _clientDeg;
  set clientDeg(double v) =>
      _set(() => _clientDeg = v.clamp(-kMaxAngleDeg, kMaxAngleDeg));

  /// Sniffer angle from straight ahead of the AP, degrees.
  double get snifferDeg => _snifferDeg;
  set snifferDeg(double v) =>
      _set(() => _snifferDeg = v.clamp(-kMaxAngleDeg, kMaxAngleDeg));

  int get snifferChains => _snifferChains;
  set snifferChains(int v) => _set(() => _snifferChains = v.clamp(1, 4));

  ChannelWidth get width => _width;
  set width(ChannelWidth v) => _set(() => _width = v);

  int get intervalIndex => _intervalIndex;
  set intervalIndex(int v) =>
      _set(() => _intervalIndex = v.clamp(0, kSoundingIntervalsMs.length - 1));
  double get intervalMs => kSoundingIntervalsMs[_intervalIndex];

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  /// Back to the link the screen opened on, with every other input at its
  /// default.
  void reset() => _set(() {
    _ap = _initialAp;
    _client = _initialClient;
    _direction = _initialDirection;
    _beamforming = true;
    _clientDeg = 20;
    _snifferDeg = -35;
    _snifferChains = 1;
    _width = ChannelWidth.w80;
    _intervalIndex = 2;
  });

  /// Presenter keys: Up and Down steer the client
  /// [kClientAngleKeyStepDeg] at a time (the main lobe follows it), R
  /// resets. Nothing runs on a clock, so there is no play or step.
  PresenterActions get presenterActions => PresenterActions(
    reset: reset,
    sliderDown: () => clientDeg = _clientDeg - kClientAngleKeyStepDeg,
    sliderUp: () => clientDeg = _clientDeg + kClientAngleKeyStepDeg,
    sliderLabel: 'Client angle',
  );

  // ── Derived ─────────────────────────────────────────────────────────────

  MimoLink linkFor(LinkDirection d) => MimoLink(
    apChains: _ap,
    clientChains: _client,
    direction: d,
    beamforming: _beamforming,
  );

  /// The direction the stage is showing.
  MimoLink get link => linkFor(_direction);
  MimoLink get downlink => linkFor(LinkDirection.downlink);
  MimoLink get uplink => linkFor(LinkDirection.uplink);

  int get streams => link.streams;

  /// The AP can beamform only with 2 or more chains.
  bool get apCanBeamform => _ap >= 2;

  /// Beamforming is on and possible, so sounding happens.
  bool get sounding => _beamforming && apCanBeamform;

  /// The downlink is steered right now (what the pattern shows).
  bool get steered => link.isBeamformed;

  /// The sounding estimate for this AP and client (always downlink: the AP
  /// sounds the client).
  SoundingEstimate get soundingEstimate =>
      SoundingEstimate(nr: _ap, nc: downlink.streams, width: _width);

  /// Sounding share of airtime, 0 when there is no sounding.
  double get soundingShare =>
      sounding ? soundingEstimate.shareOfAirtime(intervalMs) : 0;

  /// Sniffer level against the client's, dB. 0 when nothing is steered.
  double get snifferRelativeDb => steered
      ? MimoMath.patternDb(
          elements: _ap,
          angleDeg: _snifferDeg,
          steerDeg: _clientDeg,
        )
      : 0;

  /// The sniffer separates this direction's streams.
  bool get snifferDecodes =>
      MimoMath.canDecode(receiveChains: _snifferChains, streams: streams);

  // ── Formatting (shared by stage, controls and copy) ─────────────────────

  /// Signed dB with one decimal; below -40 dB reads as a null.
  static String db(double v) {
    if (v < -40) return 'below -40 dB';
    final String s = v.toStringAsFixed(1);
    if (s == '-0.0' || s == '0.0') return '0.0 dB';
    return v > 0 ? '+$s dB' : '$s dB';
  }

  /// An ideal gain: "up to +3.0 dB", or "none" at 0.
  static String gain(double v) =>
      v <= 0 ? 'none' : 'up to +${v.toStringAsFixed(1)} dB';

  static String us(double v) => '${v.toStringAsFixed(0)} µs';

  static String pct(double f) {
    final double p = f * 100;
    return '${p.toStringAsFixed(p < 1 ? 2 : 1)}%';
  }

  static String deg(double v) {
    final int d = v.round();
    return d == 0 ? '0 deg' : (d > 0 ? '$d deg right' : '${-d} deg left');
  }

  static String ms(double v) => '${v.toStringAsFixed(0)} ms';

  static String bytes(int b) =>
      b >= 1000 ? '${(b / 1000).toStringAsFixed(1)} kB' : '$b bytes';

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final MimoLink dl = downlink;
    final MimoLink ul = uplink;
    final StringBuffer b = StringBuffer()
      ..writeln('MIMO and Beamforming')
      ..writeln('AP: $_ap chains, client: $_client chains')
      ..writeln('Streams: ${dl.streams} downlink, ${ul.streams} uplink')
      ..writeln(
        'Downlink transmit beamforming (ideal upper bound): '
        '${gain(dl.idealTxBfGainDb)}',
      )
      ..writeln(
        'Downlink receive combining at the client (ideal upper bound): '
        '${gain(dl.idealCombiningGainDb)}',
      )
      ..writeln(
        'Uplink receive combining at the AP (ideal upper bound): '
        '${gain(ul.idealCombiningGainDb)}',
      );
    if (sounding) {
      final SoundingEstimate s = soundingEstimate;
      b
        ..writeln(
          'Sounding (estimate, ${_width.label}): ${us(s.totalUs)} per '
          'exchange, report ${bytes(s.reportBytes)}',
        )
        ..writeln(
          'Every ${ms(intervalMs)}: ${pct(soundingShare)} of airtime '
          'for one client',
        );
    } else {
      b.writeln('Sounding: none (beamforming off)');
    }
    b
      ..writeln(
        'Sniffer: $_snifferChains chain(s) at ${deg(_snifferDeg)}, '
        '${snifferDecodes ? 'can' : 'cannot'} separate $streams stream(s) '
        '(${_direction.label.toLowerCase()})',
      )
      ..writeln(
        'Sniffer level vs the client: ${db(snifferRelativeDb)}'
        '${steered ? '' : ' (nothing steered)'}',
      )
      ..writeln(
        'Our measurement (one capture, signal-matched): beamformed frames '
        'failed FCS ${CaptureMeasurement.fcsFailBeamformedPct}% vs '
        '${CaptureMeasurement.fcsFailNotBeamformedPct}% not beamformed',
      );
    return b.toString().trimRight();
  }
}
