# Iron Borough

Module: `src/server/Maps/IronBorough.luau` (id `IronBorough`). Tests: `tests/specs/map_ironborough.spec.luau`.

## Concept

Iron Borough is one rain-soaked city block in an old industrial district, at night. A commuter train has stopped on the brick viaduct over the main street, its windows lit. Below it, wet asphalt and slate reflect the warm sodium lamps and the neon shop signs. This is the close-quarters map: small to medium sized, dense, and full of doors.

- **Shop row**: a two-storey brick terrace with walk-through shops (hardware store, diner, pawn shop, record shop). The flats above are solid. A covered arcade runs through the middle.
- **Iron Street**: the main road under the rail viaduct. Brick piers every 22 studs give the street a steady cover rhythm.
- **Park square**: railings, hedges, trees and a bandstand in the centre. Two brick sheds sit on either side: the print works (west) and the tram substation (east).
- **Back alleys**: a network behind the shops, with two cross alleys and the arcade cutting through to the street.
- **Underpass**: a tiled pedestrian subway under the goods-line embankment along the south edge.

The playable area is about 256 x 196 studs. The inner faces of the boundary are at X = +-128 and Z = +-98. Total part count is 1174.

Axes: +X is east and -Z is north (the top of the sketch). The ground is at Y 0 everywhere except the underpass (floor Y -10, ceiling Y -1) and the bandstand platform (Y 1, a single 1-stud step). Every ground slab reaches down to Y -14 (`BoundsMin.Y`). KillY is -40. Bounds are (-132, -14, -102) to (132, 60, 102).

## Top-down layout (not to scale; 1 char is about 4 studs)

```
 Z=-98 +------+-----------------------------------------------------------------+------+
       |      |)G1 dump  pallets  BACK ALLEY  dump  crate | dump     dump  bin  G1(|      |
 Z=-82 | s  s |  +--D---+--D---+--D---+ X +--D---+=ARC=+--D---+ X +--D---+--D---+--D--+ | s  s |
       |      |  D HARDW D DINER D PAWN | X | RECORDS | A | RECORDS| X | PAWN D DINER D HARDW D|      |
       | s  s |  |  1    |       | HP1  | X |         | R |        | X | HP3  | BOMB A|      | | s  s |
 Z=-50 |      |  +--D---+--D---+--D---+   +--D------+ C +---D----+   +--D---+--D---+--D--+ |      |
       | s  s |svc  shelter   lamp   car   lamp     kiosk  kiosk   lamp  car    lamp  shelter svc| s  s |
       |      |)G2 [P]  [P]   A  [P]  [P]  [P] HP5 [P]  [P]  [P]  C   [P]  [P]  G2(|      |
       | s  s |   van  car   barrier ===== VIADUCT deck y18 (train above) ===== barrier car van |s  s|
 Z=-6  |      |  phone  bench  +----gate----railings----gate----+  bench  phone |      |
       | s  s |  +-PRINT-WORKS-+ | hedge  tree   hedge  tree   | +-SUBSTATION-+ | s  s |
       |      |)G3 D presses   D gate  [  BANDSTAND B/HP2  ]  gate D transf BOMB B D G3(|  |
       | s  s |  | rolls  type  | | hedge  tree   hedge  tree   | | switchgear | | s  s |
 Z=56  |      |  +------D-------+ +-------gate-----------------+ +------D------+ |      |
       | s  s |  grit   van  phone   car  planter |st| planter  car  phone  van   grit | s  s |
 Z=76  |      |)G4 #cut#  ===== EMBANKMENT (12 tall) over UNDERPASS y-10 ===== #cut#  G4(|  |
       |      |    stairs  baffle   col   col   HP4   col   col   baffle  stairs     |      |
 Z=98  +------+-----------------------------------------------------------------+------+
      X=-128 -106   -96          -52 -44            0            44  52          96   106  128

 )  (  yard wall (16 tall) with gaps G1..G4       s  team spawn      [P]  viaduct pier (5 x 8)
 D     doorway (>= 6 wide, >= 9.5 tall)           X  cross alley     ARC  covered arcade
 svc   service lane (|X| 96..106)                 st stairwell down to the underpass (1-stud steps)
```

## Lanes

| Lane | Band | Range | Character |
|---|---|---|---|
| North: shop row | Z -82..-50 | close | Eight shops in three blocks. Each shop has a 8-wide front door, a 6-wide back door and display windows. Neighbouring shops connect through 7-wide party-wall doors, so you can walk from the service lane to a cross alley indoors. Counters and booths are crouch cover, and shelving and fridges are full cover. |
| Middle: Iron Street | Z -50..-6 | mid | Pavements and a two-lane road under the viaduct. Ten brick piers at X +-11, 33, 55, 77, 99 line the centre of the road. Parked cars and vans, roadworks barriers, two kiosks, bus shelters and phone boxes fill the kerbs. The longest standing line is from one pier to the next car. |
| South: park and sheds | Z -6..62 | close to mid | The park (X -44..44) has railings on a brick plinth with gates on all four sides, four L-shaped hedges (4 tall), trees, benches and the bandstand. The print works and the substation (X +-52..96) each have five doors, including one to the service lane, and are full of presses, paper rolls, transformers and switchgear. |
| North flank: back alleys | Z -98..-82 | close | A 16-wide alley behind the shops, with dumpsters alternating sides every 20 to 30 studs. The cross alleys at X +-33 and the arcade at X 0 cut through to the street. Fire escapes start at Y 12 and are out of reach. |
| South flank: underpass | Z 78..94 (Y -10) | close | A tiled subway, 9 tall, under a 12-tall embankment. A centre column line, crates and fuse boxes give cover, and zig-zag baffles at X +-70 and +-78 sit near each end. Open-air cuttings with 10 one-stud steps climb to the yard gaps at each end. A 14-wide stairwell at X 0 drops into it from Canal Row and the park's south gate. |

Cross-connections let players rotate between lanes:

- The service lanes (|X| 96..106) run the full height of the map just inside each yard wall.
- The side streets (|X| 44..52) run between the park and the sheds.
- The cross alleys and arcade join the back alley to the street.
- The park gates line up with the street crossing (north) and the underpass stairwell (south).

## Power positions and counters

The roofs, the viaduct deck and the embankment are all out of reach. This map has no high ground; control comes from rooms and doorways.

1. **Pawn shops (Hardpoint 1 and 3).** These are corner rooms with four doors: front, back, a party-wall door and a side door to the cross alley. Glass cases line the walls.
   - **Counters:** every door faces a different lane, so holders cannot watch them all.
2. **Bandstand (Flag B, Hardpoint 2).** One step up, with six slim columns and an open view of all four park gates.
   - **Counters:** the hedges and trees give approaches from every quadrant. The roof gives no protection from the sides.
3. **Underpass centre (Hardpoint 4).**
   - **Counters:** there are three ways in: the two end cuttings and the centre stairwell. Grenades bounce well in the tiled corridor.
4. **Under the viaduct (Hardpoint 5).** The space between the two centre piers.
   - **Counters:** it is open to both pavements, the kiosks and the arcade mouth.

## Spawn logic

- **Sable** spawns in the west yard (X -128..-108) and **Talon** in the east yard (X 108..128). The layout is mirror-symmetric across X = 0, except for shop signage colours and car colours.
- There are 11 team spawns per side, in two columns (|X| = 120 and 125.5) spread from Z -84 to 86, all facing the map centre. The team centroids are about 245 studs apart. The closest enemy spawn pair is 240 studs apart.
- Each yard is closed off by a 16-tall brick wall at |X| 106..108, under the viaduct deck. It has four gaps:
  - G1, the back alley (Z -94..-84)
  - G2, the street (Z -38..-26). The end viaduct pier stands right outside it.
  - G3, the shed doors (Z 24..34)
  - G4, the underpass cutting (Z 80..92)
- A 12-tall loading-bay screen (|X| 113..116) stands behind each gap, 6 studs wider than the gap on each side. The longest eye-level sightline from a team spawn toward the enemy (within 60 degrees) is **82.0 studs**, measured by the contract test.
- There are 18 FFA spawns: both yards, the alleys, shops in every block, the street, the service lane, the park, both sheds, Canal Row and the underpass. They are at least 20 studs apart from each other.

## Objectives

| Mode | Zone | Where | Size (X x Z) | Floor Y |
|---|---|---|---|---|
| Domination | Flag A | west street between piers (-66, -28) | 16 x 16 | 0 |
| Domination | Flag B | bandstand (0, 28) | 18 x 18 | 1 |
| Domination | Flag C | east street between piers (66, -28) | 16 x 16 | 0 |
| Hardpoint | 1 | west pawn shop (-46, -66) | 18 x 24 | 0 |
| Hardpoint | 2 | bandstand (0, 28) | 20 x 20 | 1 |
| Hardpoint | 3 | east pawn shop (46, -66) | 18 x 24 | 0 |
| Hardpoint | 4 | underpass centre (0, 86) | 22 x 16 | -10 |
| Hardpoint | 5 | viaduct arches, centre of the street (0, -28) | 20 x 16 | 0 |
| S&D | Bomb A | east diner (66, -67): counter, booths, fridge | 14 x 14 | 0 |
| S&D | Bomb B | tram substation (74, 29): transformers, cable drum, cabinets | 14 x 14 | 0 |

- **Hardpoint rotation:** west shop, then the park, then the east shop, then the underpass, then the street. Every hop is at least 59 studs, and every zone is at least 74 studs from a team spawn.
- **Search and Destroy:** `SnDAttackBase = "Sable"`. Sable attacks from the west in round 1, so both sites are on the Talon side. They are about 96 studs apart.

## Sightline notes

- **Iron Street:** the piers sit every 22 studs along the centre line. The parked cars on both kerbs are staggered against them, so no standing line runs more than about 45 studs along a pavement.
- **Shop row:** the shop rows' party walls only line up at their doorways (Z -70..-63). A shot through four shops needs all three doors open in line, at a 7-stud angle window.
- **Park:** the hedges and the bandstand block the diagonals. The railings are see-through but do not stop movement.
- **Canal Row:** the stairwell parapets, planters, a parked car, phone boxes and a van give a piece of cover every 15 to 20 studs. The stairwell splits the strip at X 0.
- **Underpass:** the column line and the end baffles keep fights within about 30 studs.

## Art direction

Brick (red, soot-dark), wet Asphalt and Slate (with slight reflectance), Cobblestone alleys, iron-green lamp posts and viaduct girders. Warm sodium lamps (PointLights) line every pavement and the underpass. Pink, teal, amber and red neon shop signs, lit flat windows and the train's amber band supply colour. The lighting runs at ClockTime 0.5 with Brightness 2, Ambient (122,118,132), OutdoorAmbient (132,132,152) and ExposureCompensation 0.6, so players stay readable. Fog runs from 260 to 1000, and a rain haze sits in the atmosphere (Density 0.28, Haze 2). Puddles are thin reflective plates. The lobby camera looks from over the print works north-east at the viaduct and its stopped train.
