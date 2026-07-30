// SD and microSD cards — typed const datasets for the read-only "decode the
// markings" reference screen (Quick Reference / Vendor & Hardware).
//
// SOLE DATA SOURCE (GL-005): Pax's clean-room research brief
// Deliverables/2026-07-25-battery-sd-reference/FINDINGS.md, Part 2. Every
// number below traces to that file, which pulled the class tables, the bus
// speeds, the contact-row detail, and the Application Performance Class figures
// from the SD Physical Layer Simplified Specification v6.00 PDF with section
// and page cited, because the SD Association publishes its own class tables
// only as images.
//
// The brief's explicit DO-NOT-PRINT list is honored:
//   * The SD Association contradicts itself on the SD Express maximum (its web
//     table says 3940 MB/s, its own SD 9.1 white paper says 3938). This page
//     prints "~3.9 GB/s" and does not pick a side.
//
// The load-bearing insight the page exists to deliver: only ONE class mark
// measures two things. C, U, and V each set a minimum sustained SEQUENTIAL
// WRITE floor and nothing else. A1 and A2 set that same floor (10 MB/s, the
// same for both) AND add RANDOM 4 KB IOPS. A V90 card can be poor at booting a
// Pi and an A2 card can drop frames, and neither fact is visible from the
// headline MB/s figure on the label.
//
// CORRECTED 2026-07-27. This block said the marks measure "TWO orthogonal
// things" and that A1/A2 measure IOPS alone. Both were wrong, and the data at
// the foot of this file was already right, so the file contradicted itself.
// Pinned: SD Part 1 Physical Layer Simplified Specification v6.00 (10 Apr
// 2017), Sec 4.16.1.1 and 4.16.1.2, p.150. The A-class floor is measured as
// PSSw (Sec 4.16.3.3) rather than Pw (Sec 4.13.1.3), so an A2 card is NOT
// thereby V10-certified even though the guaranteed number is the same.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash or en dash;
// US spelling; "Wi-Fi" never "WiFi"; no marketing words.

/// Stable catalog tool id — backs the route, the help entry, the hero graphic
/// slot, and the tests. Permanent.
const String kSdCardsToolId = 'sd-cards';

// ─────────────────────────────── framing lead ───────────────────────────────

/// The lead. Conclusion first.
const String kSdLead =
    'A card face carries up to seven independent marks, and only one of them '
    'measures two things. The Speed Class, UHS Speed Class, and Video Speed '
    'Class marks each set a minimum sustained SEQUENTIAL write floor and '
    'nothing else. The Application Performance Class marks set that same floor, '
    '10 MB/s for both A1 and A2, and add a guarantee the others never make: '
    'RANDOM 4 KB IOPS. That is why a V90 card can be slower than an A2 card at '
    'booting a Pi, and why an A2 card can drop frames the V90 handles.';

/// One of the seven marks the screen decodes, in the order they are worth
/// reading. The numbering is the callout order on the hero card-face graphic.
class SdCardMark {
  const SdCardMark({
    required this.number,
    required this.mark,
    required this.measures,
  });

  /// Callout number on the card-face graphic, 1 through 7.
  final int number;

  /// What the mark is called.
  final String mark;

  /// What it measures, in one line.
  final String measures;
}

/// The seven marks, in reading order.
const List<SdCardMark> kSdCardMarks = <SdCardMark>[
  SdCardMark(
    number: 1,
    mark: 'Capacity standard (SD, SDHC, SDXC, SDUC)',
    measures:
        'A compatibility gate and a filesystem contract, not a speed. Read this '
        'first.',
  ),
  SdCardMark(
    number: 2,
    mark: 'Printed capacity (32GB, 128GB, and so on)',
    measures: 'How much it holds. It does not tell you which standard applies.',
  ),
  SdCardMark(
    number: 3,
    mark: 'Bus interface (I, II, III, EX)',
    measures: 'The ceiling. No class mark can exceed the bus it runs on.',
  ),
  SdCardMark(
    number: 4,
    mark: 'Speed Class (C2, C4, C6, C10)',
    measures:
        'Minimum sustained sequential write, in MB/s. Legacy, and optional.',
  ),
  SdCardMark(
    number: 5,
    mark: 'UHS Speed Class (U1, U3)',
    measures:
        'Minimum sustained sequential write. The number is the MB/s floor '
        'divided by 10.',
  ),
  SdCardMark(
    number: 6,
    mark: 'Video Speed Class (V6 to V90)',
    measures:
        'Minimum sustained sequential write. The V number IS the MB/s floor.',
  ),
  SdCardMark(
    number: 7,
    mark: 'Application Performance Class (A1, A2)',
    measures: 'Random 4 KB IOPS, plus a 10 MB/s sustained sequential write '
        'floor. The only mark that guarantees both.',
  ),
];

/// The eighth thing on the face, which is not a class at all.
const String kMarketingReadCaution =
    'The big number on the front, the "up to 170 MB/s" figure, is a maximum '
    'sequential READ. No class regulates it and nothing guarantees it. The class '
    'marks are the only floors on the card, so read them and ignore the headline.';

// ───────────────── 1. capacity standard = filesystem contract ───────────────

/// One capacity standard and the filesystem the spec pairs with it.
class SdCapacityStandard {
  const SdCapacityStandard({
    required this.mark,
    required this.capacity,
    required this.filesystem,
  });

  /// The mark on the face, e.g. `SDXC`.
  final String mark;

  /// The capacity band, e.g. `32 GB to 2 TB`.
  final String capacity;

  /// The filesystem the standard specifies.
  final String filesystem;
}

/// The capacity ladder. The filesystem column is the one that actually bites.
const List<SdCapacityStandard> kSdCapacityStandards = <SdCapacityStandard>[
  SdCapacityStandard(
    mark: 'SD (SDSC)',
    capacity: 'Up to 2 GB',
    filesystem: 'FAT12 / FAT16',
  ),
  SdCapacityStandard(
    mark: 'SDHC',
    capacity: '2 GB to 32 GB',
    filesystem: 'FAT32',
  ),
  SdCapacityStandard(
    mark: 'SDXC',
    capacity: '32 GB to 2 TB',
    filesystem: 'exFAT',
  ),
  SdCapacityStandard(
    mark: 'SDUC',
    capacity: '2 TB to 128 TB',
    filesystem: 'exFAT',
  ),
];

/// Why the filesystem column is the load-bearing one.
const String kFilesystemContract =
    'A host that supports SDHC but not SDXC does not fail on capacity. It fails '
    'on exFAT. Reformatting an SDXC card as FAT32 makes it mount and makes it '
    'work, and it also puts the card outside the specification, which is where '
    '"it works but it occasionally drops frames" comes from.';

// ────────────────────────── 2. bus interface ────────────────────────────────

/// One bus interface and its ceiling.
class SdBusInterface {
  const SdBusInterface({
    required this.mark,
    required this.name,
    required this.ceiling,
  });

  /// What appears on the face, e.g. `II`.
  final String mark;

  /// Bus name, e.g. `UHS-II`.
  final String name;

  /// Interface ceiling, e.g. `312 MB/s`.
  final String ceiling;
}

/// Bus interfaces, slowest to fastest.
const List<SdBusInterface> kSdBusInterfaces = <SdBusInterface>[
  SdBusInterface(mark: 'I', name: 'UHS-I', ceiling: '104 MB/s'),
  SdBusInterface(mark: 'II', name: 'UHS-II', ceiling: '312 MB/s'),
  SdBusInterface(mark: 'III', name: 'UHS-III', ceiling: '624 MB/s'),
  SdBusInterface(
    mark: 'EX',
    name: 'SD Express',
    ceiling: 'Up to ~3.9 GB/s over PCIe / NVMe',
  ),
];

/// Why the SD Express number carries a tilde. The SD Association's own two
/// publications disagree, so the page rounds rather than picking a side.
const String kSdExpressCaution =
    'The SD Express maximum is given here as ~3.9 GB/s on purpose. The SD '
    'Association web table and its own SD 9.1 white paper publish two different '
    'figures for the same thing, so there is no single number worth quoting.';

/// What the second row of pins physically is. SD Physical Layer Simplified
/// Specification v6.00, sections 3.7.1 and 3.7.2, Tables 3-1 and 3-3.
const String kSecondPinRow =
    'A standard SD card has 9 contacts in one row. UHS-II adds pins 10 through '
    '17 in a second row, carrying two differential lanes plus a second supply at '
    '1.70 V to 1.95 V. It also repurposes pins 7 and 8 of the FIRST row as '
    'RCLK+ and RCLK-. The card is electrically a different device depending on '
    'the mode it negotiates.';

/// Why a UHS-II card in a laptop reader is often no faster.
const String kUhsIiInUhsISlot =
    'A UHS-II card in a UHS-I slot simply runs UHS-I. The second row does '
    'nothing. That is why a fast card in a laptop reader frequently measures no '
    'faster than the cheap one.';

/// The mis-marking to catch.
const String kV60RequiresUhsIi =
    'V60 and V90 require UHS-II. A card marked V60 that shows only a Roman I on '
    'the face is marked wrongly, and the mark it got wrong is the one you were '
    'paying for.';

// ─────────────────────── 3. sustained-write classes ─────────────────────────

/// One sustained-write class mark.
class SdSpeedClass {
  const SdSpeedClass({
    required this.mark,
    required this.floor,
    required this.note,
  });

  /// The mark family, e.g. `U1 / U3`.
  final String mark;

  /// The minimum sustained sequential write it guarantees.
  final String floor;

  /// What else you need to know about it.
  final String note;
}

/// The three sustained-write class families. All three measure the same thing.
const List<SdSpeedClass> kSdSpeedClasses = <SdSpeedClass>[
  SdSpeedClass(
    mark: 'C2 / C4 / C6 / C10',
    floor: '2 / 4 / 6 / 10 MB/s',
    note:
        'Speed Class. Legacy, and optional. A C10 mark is not a modern statement '
        'about a card.',
  ),
  SdSpeedClass(
    mark: 'U1 / U3',
    floor: '10 / 30 MB/s',
    note:
        'UHS Speed Class. There is no U2; the number is the MB/s floor divided '
        'by 10.',
  ),
  SdSpeedClass(
    mark: 'V6 / V10 / V30',
    floor: '6 / 10 / 30 MB/s',
    note: 'Video Speed Class. Runs on High Speed or UHS-I.',
  ),
  SdSpeedClass(
    mark: 'V60 / V90',
    floor: '60 / 90 MB/s',
    note: 'Video Speed Class. Requires UHS-II. Check for the Roman II.',
  ),
];

/// The one mark that reads directly.
const String kVNumberReadsDirectly =
    'The V number IS the MB/s floor. It is the only mark on the card that reads '
    'directly without a conversion.';

/// Why the same number appears under three different letters.
const String kRedundantMarks =
    '30 MB/s appears twice, as U3 and V30. 10 MB/s appears four times, as C10, '
    'U1, V10, and the A-class floor. The redundancy is historical: each host '
    'generation learned a different mark, and the SD Association kept the old '
    'ones legible rather than retiring them.';

/// All three families are optional, which changes how you read a bare card.
const String kClassesAreOptional =
    'All three sustained-write class families are OPTIONAL for cards. An '
    'unmarked card is not necessarily a slow card, and a marked one is '
    'only telling you the floors the vendor chose to certify.';

// ───────────────── 4. Application Performance Class (IOPS) ──────────────────

/// One Application Performance Class row. SD Physical Layer Simplified
/// Specification v6.00, section 4.16.1, p. 150.
class SdAppPerformanceClass {
  const SdAppPerformanceClass({
    required this.mark,
    required this.randomRead,
    required this.randomWrite,
    required this.sustainedWrite,
  });

  /// `A1` or `A2`.
  final String mark;

  /// Minimum random read, in IOPS.
  final String randomRead;

  /// Minimum random write, in IOPS.
  final String randomWrite;

  /// Minimum sustained sequential write, which is the same for both.
  final String sustainedWrite;
}

/// The two A-class rows, quoted from the spec.
const List<SdAppPerformanceClass> kSdAppClasses = <SdAppPerformanceClass>[
  SdAppPerformanceClass(
    mark: 'A1',
    randomRead: '1500 IOPS',
    randomWrite: '500 IOPS',
    sustainedWrite: '10 MB/s',
  ),
  SdAppPerformanceClass(
    mark: 'A2',
    randomRead: '4000 IOPS',
    randomWrite: '2000 IOPS',
    sustainedWrite: '10 MB/s',
  ),
];

/// The single most valuable caveat on the page.
const String kA2NeedsCommandQueuing =
    'A2 only delivers A2 performance if the HOST implements Command Queuing. '
    'The spec conditions the WHOLE A2 assurance, IOPS and sustained write alike, '
    'on using the Command Queue scheme with cache enabled, and it requires an A2 card to fall back to A1 behavior '
    'when those are disabled. That fallback is by design, not a fault. It is '
    'also why real-world Raspberry Pi benchmarks have repeatedly failed to show '
    'A2 beating A1: the host stack did not support Command Queuing. Retail '
    'marketing prints A2 unconditionally.';

/// The second caveat, which costs the same people the same money.
const String kA2IsNotAVideoCard =
    'A1 and A2 both pin their sustained-write floor at 10 MB/s, so an A2 card is '
    'guaranteed no better than V10 NUMBER at sustained write unless it '
    'separately carries a V mark, and it is not thereby a V10 card: the two '
    'floors are measured by different tests.  An A2 card with no V30 is not a 4K video card. The '
    'reverse holds too: V90 says nothing at all about IOPS, so booting a Pi from '
    'a V90 card with no A mark is a gamble.';

// ──────────────────────── 5. reading order for a buyer ──────────────────────

/// One step of the buying read, in order.
class SdReadingStep {
  const SdReadingStep({required this.step, required this.what});

  /// What to read, e.g. `Capacity standard`.
  final String step;

  /// Why, in one line.
  final String what;
}

/// The four-step read.
const List<SdReadingStep> kSdReadingOrder = <SdReadingStep>[
  SdReadingStep(
    step: '1. Capacity standard',
    what:
        'A compatibility gate and a filesystem contract, not a performance '
        'number. If the host cannot mount exFAT, nothing else matters.',
  ),
  SdReadingStep(
    step: '2. Bus interface',
    what: 'The ceiling. No class mark can exceed the bus.',
  ),
  SdReadingStep(
    step: '3. The one class that matches the job',
    what:
        'V marks for recording or capture. A marks for running an operating '
        'system. Reading the wrong one is how people buy the wrong card.',
  ),
  SdReadingStep(
    step: '4. Ignore the headline MB/s',
    what:
        'It is an unregulated maximum sequential read. The class marks are the '
        'only floors on the card.',
  ),
];

// ───────────────────────── 6. selection by job ──────────────────────────────

/// One job, and what actually governs the card choice for it.
class SdJobSelection {
  const SdJobSelection({
    required this.job,
    required this.governs,
    required this.read,
    required this.ignore,
  });

  /// The job, e.g. `Pi / WLAN Pi boot and OS`.
  final String job;

  /// What actually governs performance for this job.
  final String governs;

  /// Which mark to read.
  final String read;

  /// Which mark is noise for this job.
  final String ignore;
}

/// Selection by job, with the reasoning rather than just the answer.
const List<SdJobSelection> kSdJobSelections = <SdJobSelection>[
  SdJobSelection(
    job: 'Pi or WLAN Pi boot and OS',
    governs:
        'Thousands of scattered 4 KB operations: package installs, logs, '
        'SQLite, swap. Random IOPS.',
    read: 'A1 as the safe default. A2 only if the host does Command Queuing.',
    ignore: 'V class entirely',
  ),
  SdJobSelection(
    job: 'Continuous packet capture',
    governs:
        'One long unbroken sequential write. The failure mode is dropped '
        'frames.',
    read:
        'V30 minimum. V60 or V90 if the capture rate justifies it and the host '
        'is UHS-II.',
    ignore: 'A class',
  ),
  SdJobSelection(
    job: '4K video',
    governs:
        '4K60 at 100 to 200 Mbps works out to 12.5 to 25 MB/s, so V30 has '
        'headroom.',
    read: 'V30, or V60 for high-bitrate work.',
    ignore: 'The read figure',
  ),
  SdJobSelection(
    job: 'Continuous logging',
    governs: 'Total data written across the life of the card.',
    read: 'Endurance rating, plus V30.',
    ignore: 'Everything else',
  ),
];

// ───────────────────────────── 7. endurance ─────────────────────────────────

/// The measurement problem, stated plainly.
const String kEnduranceProblem =
    'Endurance on a consumer card is quoted in HOURS at an unstated bitrate, and '
    'the hours shrink if you record 4K. SanDisk High Endurance quotes 2,500 h '
    'for the 32 GB card and 40,000 h for the 512 GB card, footnoted "Full HD '
    'video only; total hours less for 4K UHD." Samsung quotes hours the same '
    'way. Two cards both labeled high endurance can differ by 4x at the same '
    'capacity with no way to compare them.';

/// The number that would be comparable, and who publishes it.
const String kEnduranceTbw =
    'TBW, terabytes written, is the only endurance figure that compares across '
    'vendors, and consumer vendors mostly do not publish it. Industrial cards '
    'do. If endurance matters to the deployment, buy from the '
    'catalog that publishes TBW.';

// ──────────────────────────── 8. counterfeits ───────────────────────────────

/// How a counterfeit card is built.
const String kCounterfeitMechanism =
    'A counterfeit card is real flash with reprogrammed controller firmware that '
    'reports a larger capacity than the flash holds. Past the real '
    'capacity it does one of two things.';

/// One counterfeit failure mode.
class CounterfeitBehavior {
  const CounterfeitBehavior({required this.name, required this.what});

  /// The failure mode name, e.g. `Limbo`.
  final String name;

  /// What the card does.
  final String what;
}

/// The two failure modes past the real capacity.
const List<CounterfeitBehavior> kCounterfeitBehaviors = <CounterfeitBehavior>[
  CounterfeitBehavior(
    name: 'Limbo',
    what:
        'Writes are silently discarded and the files read back as zeros. '
        'Nothing errors at write time, which makes this the dangerous one: you '
        'find out when you go looking for the capture.',
  ),
  CounterfeitBehavior(
    name: 'Wraparound',
    what:
        'Writes overwrite the start of the card, corrupting the filesystem and '
        'the data already there.',
  ),
];

/// Why the obvious test does not work.
const String kCounterfeitAntiPattern =
    'A counterfeit passes every quick test. It mounts, it reports the right '
    'size, and it copies a few files back correctly. "I copied some photos and '
    'they opened, so it is fine" cannot detect a limbo fake by construction, '
    'because the fake only misbehaves past the capacity you did not fill.';

/// The only test that works.
const String kCounterfeitTest =
    'The only method that works is to fill the card completely with known data '
    'and read every byte back. Use h2testw on Windows, or f3write and f3read on '
    'macOS and Linux. f3probe runs a fast destructive check when you would '
    'rather not wait for a full fill.';

// ─────────────────────── 9. the write-protect notch ─────────────────────────

/// The notch, and the fact that surprises people.
const String kWriteProtectNotch =
    'The write-protect notch on a full-size SD card is not enforced by the card. '
    'The switch slides a plastic tab past a microswitch in the HOST, and the '
    'host decides whether to honor it. The card cannot see the switch position '
    'and cannot refuse a write on its own. microSD has no notch at all.';
