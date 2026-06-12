// Time Zones reference data — compile-time const, source of truth for the
// data-driven Time Zones screen (Tier-1, Pass 2b 2026-06-12).
//
// Two native tables sit beneath the embedded world-map plate:
//   A. World UTC offset rail (anchor cities per one-hour offset band).
//   B. United States time zones (standard / daylight abbreviations + notes).
//
// All offsets are STANDARD TIME (no DST) — the stable reference. Where a region
// observes daylight saving, the local clock runs one hour ahead of the listed
// offset during the DST window; this is stated on-screen.
//
// Source: modernized from Keith's "International Time Zones" laminated
// reference; offsets reconciled against the current IANA tz database city
// groupings.

/// One UTC-offset band: the offset label and its anchor cities.
class UtcOffset {
  const UtcOffset(this.offset, this.cities);

  /// Offset label, e.g. `UTC +9` or `UTC +5:30`.
  final String offset;

  /// Anchor cities for the band.
  final String cities;
}

/// The world UTC offset rail (standard time).
const List<UtcOffset> kUtcOffsets = <UtcOffset>[
  UtcOffset('UTC -12', 'Baker Island'),
  UtcOffset('UTC -11', 'Pago Pago, Niue'),
  UtcOffset('UTC -10', 'Honolulu, Tahiti'),
  UtcOffset('UTC -9', 'Anchorage'),
  UtcOffset('UTC -8', 'Los Angeles, Vancouver'),
  UtcOffset('UTC -7', 'Denver, Phoenix'),
  UtcOffset('UTC -6', 'Chicago, Mexico City'),
  UtcOffset('UTC -5', 'New York, Toronto, Lima'),
  UtcOffset('UTC -4', 'Halifax, Caracas, Santiago'),
  UtcOffset('UTC -3', 'Sao Paulo, Buenos Aires'),
  UtcOffset('UTC -2', 'South Georgia, Fernando de Noronha'),
  UtcOffset('UTC -1', 'Azores, Cape Verde'),
  UtcOffset('UTC 0', 'London, Lisbon, Accra'),
  UtcOffset('UTC +1', 'Paris, Berlin, Lagos'),
  UtcOffset('UTC +2', 'Cairo, Athens, Cape Town'),
  UtcOffset('UTC +3', 'Moscow, Nairobi, Riyadh'),
  UtcOffset('UTC +4', 'Dubai, Baku'),
  UtcOffset('UTC +5', 'Karachi, Tashkent'),
  UtcOffset('UTC +5:30', 'Mumbai, Delhi, Colombo'),
  UtcOffset('UTC +6', 'Dhaka, Almaty'),
  UtcOffset('UTC +7', 'Bangkok, Jakarta, Hanoi'),
  UtcOffset('UTC +8', 'Beijing, Singapore, Perth'),
  UtcOffset('UTC +9', 'Tokyo, Seoul'),
  UtcOffset('UTC +9:30', 'Adelaide, Darwin'),
  UtcOffset('UTC +10', 'Sydney, Brisbane, Guam'),
  UtcOffset('UTC +11', 'Noumea, Solomon Islands'),
  UtcOffset('UTC +12', 'Auckland, Fiji'),
  UtcOffset('UTC +13', 'Samoa, Tonga'),
];

/// Footnote for the offset rail (half-hour / 45-minute outliers).
const String kUtcOffsetsNote =
    'Half-hour offsets (India UTC +5:30, central Australia UTC +9:30) and a few '
    '45-minute offsets (Nepal +5:45, Chatham +12:45) exist; the 45-minute cases '
    'are left off the rail for legibility.';

/// One US time zone row.
class UsTimeZone {
  const UsTimeZone({
    required this.zone,
    required this.abbr,
    required this.offset,
    required this.daylight,
    required this.cities,
  });

  /// Zone name, e.g. `Eastern`.
  final String zone;

  /// Standard / daylight abbreviations, e.g. `EST / EDT`.
  final String abbr;

  /// Standard-time offset, e.g. `UTC -5`.
  final String offset;

  /// Daylight-saving note.
  final String daylight;

  /// Anchor cities.
  final String cities;
}

/// United States time zones.
const List<UsTimeZone> kUsTimeZones = <UsTimeZone>[
  UsTimeZone(
    zone: 'Hawaii-Aleutian',
    abbr: 'HST / HDT',
    offset: 'UTC -10',
    daylight: 'Not observed in most of Hawaii (HDT only in the Aleutians)',
    cities: 'Honolulu',
  ),
  UsTimeZone(
    zone: 'Alaska',
    abbr: 'AKST / AKDT',
    offset: 'UTC -9',
    daylight: 'Observed',
    cities: 'Anchorage, Juneau',
  ),
  UsTimeZone(
    zone: 'Pacific',
    abbr: 'PST / PDT',
    offset: 'UTC -8',
    daylight: 'Observed',
    cities: 'Los Angeles, Seattle',
  ),
  UsTimeZone(
    zone: 'Mountain',
    abbr: 'MST / MDT',
    offset: 'UTC -7',
    daylight: 'Observed (most of Arizona stays on MST year-round)',
    cities: 'Denver, Phoenix',
  ),
  UsTimeZone(
    zone: 'Central',
    abbr: 'CST / CDT',
    offset: 'UTC -6',
    daylight: 'Observed',
    cities: 'Chicago, Dallas, Houston',
  ),
  UsTimeZone(
    zone: 'Eastern',
    abbr: 'EST / EDT',
    offset: 'UTC -5',
    daylight: 'Observed',
    cities: 'New York, Atlanta, Miami',
  ),
];

/// The standard-time / DST framing note carried on-screen.
const String kTimeZonesDstNote =
    'Offsets shown are standard time. When a region is on daylight saving, its '
    'local clock runs one hour ahead of the listed offset. In the US that window '
    'runs from the second Sunday in March to the first Sunday in November.';
