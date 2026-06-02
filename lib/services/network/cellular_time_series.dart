// Rolling time-series capture for Cellular Information Live mode (TICKET-05).
//
// A fixed-capacity ring of the one cellular field that trends meaningfully:
// signal bars (0..4). Carrier / radio technology / country / roaming are
// categorical, not time-series, so they are shown as their current live value
// only — not charted. The screen pushes one [CellularInfo] per streamed sample;
// this keeps the last [capacity] bars readings, oldest->newest, for the small
// bars-history sparkline.
//
// Honesty (GL-005): a sample with no bars is stored as `null`, never as 0 — the
// sparkline draws a gap rather than a fabricated zero-bar reading. Bars are the
// coarse iOS status-bar 0..4 scale and are NEVER dBm/RSRP/RSRQ.

import 'cellular_info.dart';

/// A fixed-capacity rolling window of the signal-bars reading (0..4).
class CellularTimeSeries {
  CellularTimeSeries({this.capacity = defaultCapacity})
      : assert(capacity > 0, 'capacity must be positive');

  /// Default rolling-window length. ~60 samples at the recursive Shortcut's
  /// ~1s cadence, matching [WifiTimeSeries.defaultCapacity].
  static const int defaultCapacity = 60;

  /// Maximum number of samples retained.
  final int capacity;

  final List<double?> _bars = <double?>[];

  /// Signal-bars window (0..4 as doubles for the sparkline), oldest->newest.
  /// Unmodifiable view.
  List<double?> get bars => List<double?>.unmodifiable(_bars);

  /// Number of samples currently held.
  int get length => _bars.length;

  /// True until the first sample lands.
  bool get isEmpty => _bars.isEmpty;

  /// Appends one sample from a streamed [CellularInfo], evicting the oldest when
  /// at [capacity]. A null signalBars is stored as null (a gap), never as 0.
  void add(CellularInfo info) {
    _bars.add(info.signalBars?.toDouble());
    if (_bars.length > capacity) _bars.removeAt(0);
  }

  /// Clears the window (used when Live monitoring stops and restarts so a new
  /// session does not chart stale samples from the previous one).
  void clear() => _bars.clear();
}
