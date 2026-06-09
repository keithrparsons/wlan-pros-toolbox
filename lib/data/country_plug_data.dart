// Country -> Power Plug lookup data + search.
//
// Inverts the per-type International Power Plugs page (type letter -> country)
// into a country -> plug-type lookup, so a traveler/installer can type a
// country name and see the plug type letter(s) plus the residential voltage and
// frequency they will encounter.
//
// Data provenance (GL-005): Pax's verified build-ready dataset,
// Deliverables/2026-06-08-country-plug-lookup/COUNTRY-PLUG-DATA.md (~205
// countries and territories). The type-letter -> national-standard mapping it
// rests on was verified High in the prior power-and-cooling research brief
// (Topic 5). Voltage shown is the residential single-phase figure; frequency is
// 50 or 60 Hz (a few territories run a real 50/60 or dual-voltage split, carried
// verbatim because they are genuine, not transcription errors: Japan 100V 50/60,
// Brazil 127/220V, Philippines 230V/60Hz).
//
// Pure offline data + a synchronous search function. No network, no subprocess,
// no platform dependency (GL-008 does not apply: nothing is fetched or shelled
// out to). Glyph / copy rules (GL-004): ASCII hyphen-minus only, never an em
// dash; US spelling; the middot separator in display strings is a real Unicode
// "MIDDLE DOT" used only for visual separation, not punctuation.

import 'package:flutter/foundation.dart';

/// One country/territory and the plug types, voltage, and frequency a traveler
/// or installer will encounter there. Immutable compile-time data.
@immutable
class CountryPlug {
  const CountryPlug({
    required this.country,
    required this.types,
    required this.voltage,
    required this.frequency,
    this.aliases = const <String>[],
  });

  /// Canonical display name, e.g. `Germany`, `United States`.
  final String country;

  /// IEC World Plugs type letters in use, e.g. `['C', 'F']`. Always at least
  /// one entry; a multi-type country lists ALL its letters in source order.
  final List<String> types;

  /// Residential single-phase voltage label, e.g. `230V`, `120V`, `127/220V`.
  final String voltage;

  /// Mains frequency label, e.g. `50Hz`, `60Hz`, `50/60Hz`.
  final String frequency;

  /// Alternate spellings / common names / abbreviations that should match this
  /// country in search, e.g. `['USA', 'US', 'America']` for the United States.
  /// Case-insensitive at match time.
  final List<String> aliases;

  /// The type letters joined for display, e.g. `Type C, F`.
  String get typeLabel =>
      'Type ${types.join(', ')}';

  /// The voltage/frequency suffix for display, e.g. `230V/50Hz`.
  String get powerLabel => '$voltage/$frequency';
}

/// The full country -> plug lookup table. ~205 entries, sourced verbatim from
/// the Pax dataset. Public-const for testing and for the screen to render.
const List<CountryPlug> kCountryPlugs = <CountryPlug>[
  CountryPlug(country: 'Afghanistan', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Albania', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Algeria', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'American Samoa', types: <String>['A', 'B', 'I'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Andorra', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Angola', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Anguilla', types: <String>['A', 'B'], voltage: '110/120V', frequency: '60Hz'),
  CountryPlug(country: 'Antigua and Barbuda', types: <String>['A', 'B'], voltage: '230V', frequency: '60Hz'),
  CountryPlug(country: 'Argentina', types: <String>['C', 'I'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Armenia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Aruba', types: <String>['A', 'B', 'F'], voltage: '127V', frequency: '60Hz'),
  CountryPlug(country: 'Australia', types: <String>['I'], voltage: '230V', frequency: '50Hz', aliases: <String>['Oz']),
  CountryPlug(country: 'Austria', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Azerbaijan', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Bahamas', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Bahrain', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Bangladesh', types: <String>['A', 'C', 'D', 'G'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Barbados', types: <String>['A', 'B'], voltage: '115V', frequency: '50Hz'),
  CountryPlug(country: 'Belarus', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Belgium', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Belize', types: <String>['A', 'B', 'G'], voltage: '110/220V', frequency: '60Hz'),
  CountryPlug(country: 'Benin', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Bermuda', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Bhutan', types: <String>['C', 'D', 'F', 'G', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Bolivia', types: <String>['A', 'B', 'C'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Bonaire / Sint Eustatius / Saba', types: <String>['A', 'B'], voltage: '127V', frequency: '50Hz'),
  CountryPlug(country: 'Bosnia and Herzegovina', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Botswana', types: <String>['D', 'G', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Brazil', types: <String>['C', 'N'], voltage: '127/220V', frequency: '60Hz'),
  CountryPlug(country: 'British Virgin Islands', types: <String>['A', 'B'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Brunei', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Bulgaria', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Burkina Faso', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Burundi', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Cambodia', types: <String>['A', 'C', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Cameroon', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Canada', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Cape Verde', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Cayman Islands', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Central African Republic', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Chad', types: <String>['C', 'D', 'E', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Chile', types: <String>['C', 'F', 'L'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'China', types: <String>['A', 'I'], voltage: '220V', frequency: '50Hz', aliases: <String>['PRC']),
  CountryPlug(country: 'Colombia', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Comoros', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Congo, Republic of the', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Congo, Dem. Rep. of the', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz', aliases: <String>['DRC', 'Zaire']),
  CountryPlug(country: 'Cook Islands', types: <String>['I'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Costa Rica', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: "Cote d'Ivoire", types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz', aliases: <String>['Ivory Coast']),
  CountryPlug(country: 'Croatia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Cuba', types: <String>['A', 'B', 'C', 'L'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Curacao', types: <String>['A', 'B', 'F'], voltage: '127V', frequency: '50Hz'),
  CountryPlug(country: 'Cyprus', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Czechia', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz', aliases: <String>['Czech Republic']),
  CountryPlug(country: 'Denmark', types: <String>['C', 'E', 'F', 'K'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Djibouti', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Dominica', types: <String>['D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Dominican Republic', types: <String>['A', 'B', 'C'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Ecuador', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Egypt', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'El Salvador', types: <String>['A', 'B'], voltage: '115V', frequency: '60Hz'),
  CountryPlug(country: 'Equatorial Guinea', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Eritrea', types: <String>['C', 'L'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Estonia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Eswatini (Swaziland)', types: <String>['M'], voltage: '230V', frequency: '50Hz', aliases: <String>['Swaziland']),
  CountryPlug(country: 'Ethiopia', types: <String>['C', 'E', 'F', 'L'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Falkland Islands', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Faroe Islands', types: <String>['C', 'E', 'F', 'K'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Fiji', types: <String>['I'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Finland', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'France', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'French Guiana', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'French Polynesia', types: <String>['A', 'B', 'C', 'E', 'F'], voltage: '110/220V', frequency: '60/50Hz', aliases: <String>['Tahiti']),
  CountryPlug(country: 'Gabon', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Gambia', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Georgia', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Germany', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz', aliases: <String>['Deutschland']),
  CountryPlug(country: 'Ghana', types: <String>['D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Gibraltar', types: <String>['C', 'G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Greece', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Greenland', types: <String>['C', 'E', 'F', 'K'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Grenada', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Guadeloupe', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Guam', types: <String>['A', 'B'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Guatemala', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Guernsey', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Guinea', types: <String>['C', 'F', 'K'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Guinea-Bissau', types: <String>['C', 'E', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Guyana', types: <String>['A', 'B', 'D', 'G'], voltage: '240V', frequency: '60Hz'),
  CountryPlug(country: 'Haiti', types: <String>['A', 'B'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Honduras', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Hong Kong', types: <String>['G', 'D', 'M'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Hungary', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Iceland', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'India', types: <String>['C', 'D', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Indonesia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Iran', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Iraq', types: <String>['C', 'D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Ireland', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Isle of Man', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Israel', types: <String>['C', 'H'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Italy', types: <String>['C', 'F', 'L'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Jamaica', types: <String>['A', 'B'], voltage: '110V', frequency: '50Hz'),
  CountryPlug(country: 'Japan', types: <String>['A', 'B'], voltage: '100V', frequency: '50/60Hz'),
  CountryPlug(country: 'Jersey', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Jordan', types: <String>['B', 'C', 'D', 'F', 'G', 'J'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Kazakhstan', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Kenya', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Kiribati', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Kosovo', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Kuwait', types: <String>['C', 'G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Kyrgyzstan', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Laos', types: <String>['A', 'B', 'C', 'E', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Latvia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Lebanon', types: <String>['A', 'B', 'C', 'D', 'G'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Lesotho', types: <String>['M'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Liberia', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Libya', types: <String>['C', 'F', 'L'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Liechtenstein', types: <String>['C', 'J'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Lithuania', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Luxembourg', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Macau', types: <String>['G', 'D', 'M'], voltage: '230V', frequency: '50Hz', aliases: <String>['Macao']),
  CountryPlug(country: 'Madagascar', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Malawi', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Malaysia', types: <String>['C', 'G', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Maldives', types: <String>['D', 'G', 'J', 'K', 'L'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Mali', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Malta', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Martinique', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Mauritania', types: <String>['C', 'E', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Mauritius', types: <String>['C', 'E', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Mexico', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Micronesia (Fed. States)', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Moldova', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Monaco', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Mongolia', types: <String>['C', 'E', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Montenegro', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Montserrat', types: <String>['A', 'B'], voltage: '230V', frequency: '60Hz'),
  CountryPlug(country: 'Morocco', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Mozambique', types: <String>['C', 'F', 'M'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Myanmar', types: <String>['A', 'C', 'D', 'F', 'G', 'I'], voltage: '230V', frequency: '50Hz', aliases: <String>['Burma']),
  CountryPlug(country: 'Namibia', types: <String>['D', 'M'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Nauru', types: <String>['I'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Nepal', types: <String>['C', 'D', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Netherlands', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz', aliases: <String>['Holland']),
  CountryPlug(country: 'New Caledonia', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'New Zealand', types: <String>['I'], voltage: '230V', frequency: '50Hz', aliases: <String>['NZ', 'Aotearoa']),
  CountryPlug(country: 'Nicaragua', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Niger', types: <String>['A', 'B', 'C', 'D', 'E', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Nigeria', types: <String>['D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Niue', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'North Korea', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz', aliases: <String>['DPRK']),
  CountryPlug(country: 'North Macedonia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz', aliases: <String>['Macedonia']),
  CountryPlug(country: 'Norway', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Oman', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Pakistan', types: <String>['C', 'D', 'G', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Palau', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Palestine', types: <String>['C', 'H'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Panama', types: <String>['A', 'B'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Papua New Guinea', types: <String>['I'], voltage: '240V', frequency: '50Hz', aliases: <String>['PNG']),
  CountryPlug(country: 'Paraguay', types: <String>['A', 'B', 'C', 'N'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Peru', types: <String>['A', 'B', 'C'], voltage: '220V', frequency: '60Hz'),
  CountryPlug(country: 'Philippines', types: <String>['A', 'B', 'C'], voltage: '230V', frequency: '60Hz'),
  CountryPlug(country: 'Pitcairn Islands', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Poland', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Portugal', types: <String>['C', 'E', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Puerto Rico', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Qatar', types: <String>['D', 'F', 'G', 'L'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Reunion', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Romania', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Russia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz', aliases: <String>['Russian Federation']),
  CountryPlug(country: 'Rwanda', types: <String>['C', 'E', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Saint Helena / Ascension / Tristan da Cunha', types: <String>['G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Saint Kitts and Nevis', types: <String>['A', 'B', 'D', 'G'], voltage: '230V', frequency: '60Hz'),
  CountryPlug(country: 'Saint Lucia', types: <String>['A', 'B', 'G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Saint Martin (French)', types: <String>['C', 'E'], voltage: '220V', frequency: '60Hz'),
  CountryPlug(country: 'Sint Maarten (Dutch)', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Saint Pierre and Miquelon', types: <String>['C', 'E', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Saint Vincent and the Grenadines', types: <String>['A', 'B', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Samoa', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'San Marino', types: <String>['C', 'F', 'L'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Sao Tome and Principe', types: <String>['C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Saudi Arabia', types: <String>['A', 'B', 'F', 'G'], voltage: '230V', frequency: '60Hz'),
  CountryPlug(country: 'Senegal', types: <String>['C', 'D', 'E', 'K'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Serbia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Seychelles', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Sierra Leone', types: <String>['D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Singapore', types: <String>['C', 'G', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Slovakia', types: <String>['C', 'E', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Slovenia', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Solomon Islands', types: <String>['I', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Somalia', types: <String>['C', 'G'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'South Africa', types: <String>['C', 'M', 'N'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'South Korea', types: <String>['C', 'F'], voltage: '220V', frequency: '60Hz', aliases: <String>['Korea', 'Republic of Korea']),
  CountryPlug(country: 'Spain', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Sri Lanka', types: <String>['D', 'G', 'M'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Sudan', types: <String>['C', 'D', 'F', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Suriname', types: <String>['C', 'F'], voltage: '127/220V', frequency: '60Hz'),
  CountryPlug(country: 'Sweden', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Switzerland', types: <String>['C', 'J'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Syria', types: <String>['C', 'E', 'L'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Taiwan', types: <String>['A', 'B'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Tajikistan', types: <String>['C', 'F', 'I'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Tanzania', types: <String>['D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Thailand', types: <String>['A', 'B', 'C', 'O'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Timor-Leste', types: <String>['C', 'E', 'F', 'I'], voltage: '220V', frequency: '50Hz', aliases: <String>['East Timor']),
  CountryPlug(country: 'Togo', types: <String>['C', 'E'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Tonga', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Trinidad and Tobago', types: <String>['A', 'B'], voltage: '115V', frequency: '60Hz'),
  CountryPlug(country: 'Tunisia', types: <String>['C', 'E'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Turkey', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz', aliases: <String>['Turkiye']),
  CountryPlug(country: 'Turkmenistan', types: <String>['B', 'C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Tuvalu', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Uganda', types: <String>['G'], voltage: '240V', frequency: '50Hz'),
  CountryPlug(country: 'Ukraine', types: <String>['C', 'F'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'United Arab Emirates', types: <String>['G'], voltage: '230V', frequency: '50Hz', aliases: <String>['UAE', 'Emirates', 'Dubai', 'Abu Dhabi']),
  CountryPlug(country: 'United Kingdom', types: <String>['G'], voltage: '230V', frequency: '50Hz', aliases: <String>['UK', 'Britain', 'Great Britain', 'England', 'Scotland', 'Wales', 'GB']),
  CountryPlug(country: 'United States', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz', aliases: <String>['USA', 'US', 'America', 'United States of America', 'U.S.', 'U.S.A.']),
  CountryPlug(country: 'Uruguay', types: <String>['C', 'F', 'I', 'L'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'US Virgin Islands', types: <String>['A', 'B'], voltage: '110V', frequency: '60Hz'),
  CountryPlug(country: 'Uzbekistan', types: <String>['C', 'E', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Vanuatu', types: <String>['I'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Venezuela', types: <String>['A', 'B'], voltage: '120V', frequency: '60Hz'),
  CountryPlug(country: 'Vietnam', types: <String>['A', 'B', 'C', 'F'], voltage: '220V', frequency: '50Hz'),
  CountryPlug(country: 'Yemen', types: <String>['A', 'D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Zambia', types: <String>['C', 'D', 'G'], voltage: '230V', frequency: '50Hz'),
  CountryPlug(country: 'Zimbabwe', types: <String>['D', 'G'], voltage: '220V', frequency: '50Hz'),
];

/// Searches [kCountryPlugs] for entries matching [query], case-insensitively,
/// against the canonical country name AND every alias.
///
/// Matching rules:
///  - An empty/whitespace-only query returns an empty list (the screen shows its
///    own idle/empty prompt rather than dumping all ~205 rows).
///  - A query is matched as a case-insensitive substring of the country name or
///    any alias. So `germ` finds Germany; `usa`, `us`, and `united states` all
///    find the United States; `holland` finds the Netherlands.
///  - Results are ranked: exact name/alias matches first, then prefix matches,
///    then substring matches; ties broken alphabetically by country name. This
///    keeps `us` from burying the United States under "Belarus", "Cyprus", etc.
List<CountryPlug> searchCountryPlugs(String query) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return const <CountryPlug>[];

  final List<_Ranked> ranked = <_Ranked>[];
  for (final CountryPlug entry in kCountryPlugs) {
    final int rank = _matchRank(entry, q);
    if (rank >= 0) ranked.add(_Ranked(entry, rank));
  }

  ranked.sort((_Ranked a, _Ranked b) {
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    return a.entry.country.toLowerCase().compareTo(b.entry.country.toLowerCase());
  });

  return ranked.map((_Ranked r) => r.entry).toList(growable: false);
}

/// Returns the best (lowest) match rank for [entry] against the normalized
/// query [q], or -1 if no field matches. 0 = exact, 1 = prefix, 2 = substring.
int _matchRank(CountryPlug entry, String q) {
  int best = -1;
  for (final String candidate in <String>[entry.country, ...entry.aliases]) {
    final String c = candidate.toLowerCase();
    int rank;
    if (c == q) {
      rank = 0;
    } else if (c.startsWith(q)) {
      rank = 1;
    } else if (c.contains(q)) {
      rank = 2;
    } else {
      continue;
    }
    if (best == -1 || rank < best) best = rank;
  }
  return best;
}

/// Internal ranking pair for the search sort.
@immutable
class _Ranked {
  const _Ranked(this.entry, this.rank);
  final CountryPlug entry;
  final int rank;
}
