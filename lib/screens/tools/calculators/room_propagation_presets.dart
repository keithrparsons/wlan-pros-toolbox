// The four floor plans the Room Propagation simulator opens with (spec:
// open office, drywall offices, concrete corridor, glass meeting room).
//
// Coordinates in meters from the plan's top-left corner, y pointing down the
// screen. Materials and thicknesses come from the same ITU-R P.2040 list as Wi-Fi
// Through a Wall; each wall is one solid slab of that material. A real office
// wall has studs and a cavity, which this model does not describe.

import '../../../services/wifi_lab/room_propagation_model.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';

/// One starting plan.
class RoomPreset {
  const RoomPreset({
    required this.label,
    required this.lesson,
    required this.widthM,
    required this.heightM,
    required this.walls,
    required this.ap,
    required this.client,
  });

  final String label;

  /// What to look for, one sentence.
  final String lesson;

  final double widthM;
  final double heightM;
  final List<RoomWall> walls;
  final P2 ap;
  final P2 client;
}

/// Largest plan the tool accepts (spec: about 20 m x 15 m).
const double kPlanMaxWidthM = 20;
const double kPlanMaxHeightM = 15;

RoomWall _w(
  double x1,
  double y1,
  double x2,
  double y2,
  WallMaterial m,
  double mm, [
  List<double> doorsAt = const <double>[],
]) => RoomWall(
  a: P2(x1, y1),
  b: P2(x2, y2),
  material: m,
  thicknessMm: mm,
  doors: <DoorGap>[for (final double d in doorsAt) DoorGap(centerM: d)],
);

const WallMaterial _concrete = WallMaterial.concrete;
const WallMaterial _drywall = WallMaterial.plasterboard;
const WallMaterial _glass = WallMaterial.glass;
const WallMaterial _metal = WallMaterial.metal;

List<RoomWall> _perimeter(
  double w,
  double h, {
  WallMaterial bottom = _concrete,
  double bottomMm = 200,
}) => <RoomWall>[
  _w(0, 0, w, 0, _concrete, 200),
  _w(w, 0, w, h, _concrete, 200),
  _w(w, h, 0, h, bottom, bottomMm),
  _w(0, h, 0, 0, _concrete, 200),
];

final List<RoomPreset> kRoomPresets = <RoomPreset>[
  RoomPreset(
    label: 'Drywall offices',
    lesson:
        'Four offices off an open area. Drywall passes most of the signal, so '
        'a doorway here matters far less than one in concrete.',
    widthM: 20,
    heightM: 12,
    walls: <RoomWall>[
      ..._perimeter(20, 12),
      _w(0, 5, 20, 5, _drywall, 13, <double>[3.5, 8.5, 13.5, 18.5]),
      _w(5, 0, 5, 5, _drywall, 13),
      _w(10, 0, 10, 5, _drywall, 13),
      _w(15, 0, 15, 5, _drywall, 13),
    ],
    ap: const P2(9, 8.5),
    client: const P2(17.5, 2),
  ),
  RoomPreset(
    label: 'Concrete corridor',
    lesson:
        'Rooms off a concrete corridor. The doorways carry the signal in, '
        'and it bends past each jamb into the room.',
    widthM: 20,
    heightM: 10,
    walls: <RoomWall>[
      ..._perimeter(20, 10),
      _w(0, 4, 20, 4, _concrete, 150, <double>[4, 12]),
      _w(0, 6.5, 20, 6.5, _concrete, 150, <double>[7, 16]),
      _w(8, 0, 8, 4, _concrete, 150),
      _w(16, 0, 16, 4, _concrete, 150),
      _w(12, 6.5, 12, 10, _concrete, 150),
    ],
    ap: const P2(2, 5.25),
    client: const P2(13.5, 2),
  ),
  RoomPreset(
    label: 'Open office',
    lesson:
        'One big room with a row of metal cabinets. Behind the cabinets '
        'the only signal is what bends around their ends or bounces in.',
    widthM: 20,
    heightM: 12,
    walls: <RoomWall>[
      ..._perimeter(20, 12, bottom: _glass, bottomMm: 10),
      _w(7, 7, 11, 7, _metal, 20),
    ],
    ap: const P2(5, 3.5),
    client: const P2(11, 10),
  ),
  RoomPreset(
    label: 'Glass meeting room',
    lesson:
        'A glass meeting room in an open floor. Thin glass passes most of '
        'the signal, and this 10 mm pane loses less on channels 100 and 117 '
        'than on channel 6.',
    widthM: 16,
    heightM: 10,
    walls: <RoomWall>[
      ..._perimeter(16, 10),
      _w(8, 2, 13, 2, _glass, 10),
      _w(13, 2, 13, 7, _glass, 10),
      _w(13, 7, 8, 7, _glass, 10),
      _w(8, 7, 8, 2, _glass, 10, <double>[1.5]),
    ],
    ap: const P2(3, 5),
    client: const P2(11, 4.5),
  ),
];
