// Rolling time-series capture for Wi-Fi Live mode (TICKET-01).
//
// A fixed-capacity ring of the streamed RF fields we chart and grade: RSSI,
// SNR, Tx rate, Rx rate. The screen pushes one [ConnectedAp] per streamed
// sample; this keeps the last [capacity] samples per field, oldest→newest, so
// the sparklines and trend grading read a stable window without the widget
// hand-managing four parallel lists.
//
// Honesty (GL-005): a field absent from a sample is stored as `null`, never as
// 0 — the sparkline draws a gap and the grade reads "Unavailable". We never
// back-fill a missing reading.

import 'connected_ap.dart';

/// A fixed-capacity rolling window of the four charted RF fields.
class WifiTimeSeries {
  WifiTimeSeries({this.capacity = defaultCapacity})
      : assert(capacity > 0, 'capacity must be positive');

  /// Default rolling-window length. ~60 samples ≈ one minute at the looping
  /// Shortcut's ~1s cadence (TICKET-01 spike target ~1–2s).
  static const int defaultCapacity = 60;

  /// Maximum number of samples retained per field.
  final int capacity;

  final List<double?> _rssi = <double?>[];
  final List<double?> _snr = <double?>[];
  final List<double?> _txRate = <double?>[];
  final List<double?> _rxRate = <double?>[];

  /// RSSI window (dBm), oldest→newest. Unmodifiable view.
  List<double?> get rssi => List<double?>.unmodifiable(_rssi);

  /// SNR window (dB), oldest→newest. Unmodifiable view.
  List<double?> get snr => List<double?>.unmodifiable(_snr);

  /// Tx-rate window (Mbps), oldest→newest. Unmodifiable view.
  List<double?> get txRate => List<double?>.unmodifiable(_txRate);

  /// Rx-rate window (Mbps), oldest→newest. Unmodifiable view.
  List<double?> get rxRate => List<double?>.unmodifiable(_rxRate);

  /// Number of samples currently held (all four windows share this length).
  int get length => _rssi.length;

  /// True until the first sample lands.
  bool get isEmpty => _rssi.isEmpty;

  /// Appends one sample from a streamed [ConnectedAp], evicting the oldest when
  /// at [capacity]. Each field is stored as-is (null when the sample omitted
  /// it) so gaps stay honest.
  void add(ConnectedAp ap) {
    _push(_rssi, ap.rssiDbm?.toDouble());
    _push(_snr, ap.snrDb?.toDouble());
    _push(_txRate, ap.txRateMbps);
    _push(_rxRate, ap.rxRateMbps);
  }

  /// Clears every window (used when Live monitoring stops and restarts so a new
  /// session does not chart stale samples from the previous one).
  void clear() {
    _rssi.clear();
    _snr.clear();
    _txRate.clear();
    _rxRate.clear();
  }

  void _push(List<double?> window, double? value) {
    window.add(value);
    if (window.length > capacity) window.removeAt(0);
  }
}
