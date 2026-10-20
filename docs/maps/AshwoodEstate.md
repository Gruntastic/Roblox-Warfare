# Ashwood Estate

Module: `src/server/Maps/AshwoodEstate.luau` (id `AshwoodEstate`). Tests: `tests/specs/map_ashwoodestate.spec.luau` (shared map contract).

## Concept

Ashwood Estate is a country house standing in its own woods. It is autumn, late in the day: the sun is low and golden, the copper-beech hedges have turned, and the orchard is dropping leaves. The house is shut up for the season, and two teams fight over the grounds:

- **Manor house**: a two-storey brick house with slate roofs in the centre. It is the indoor middle lane. Its double-height great hall has two grand flights of stairs and two galleries that overlook it. The library is in the west wing and the dining room in the east wing. Upstairs are the bedrooms and a long gallery.
- **Gardens**: the north lane. A fountain parterre lies to the west, a copper-beech hedge maze in the centre, and a glass greenhouse to the east.
- **Orchard and stable yard**: the south lane. A stone-walled orchard lies to the west, then a cart track. A carriage house and a fenced paddock lie to the east.
- **Two flanks**: the woodland walk to the north, behind the garden wall, and the kitchen walk to the south, with cold frames, woodpiles and a potting shed.
- **Bases**: Sable holds the **gatehouse court** (west), where the drive enters through the stone gatehouse. Talon holds the **stable court** (east), under the clock arch.

The playable area is about 360 x 260 studs. The inner faces of the boundary walls are at X = +-180 and Z = +-130, and the walls are 26 studs tall. Total part count is 999.

Axes: +X is east and -Z is north (the top of the sketch). All walkable ground has its top at Y 0. The only other floors are the manor's upper floor and galleries, at Y 14. Ground slabs run from Y -4 to 0 and cover the whole footprint. `BoundsMin` = (-184, -4, -134) and `BoundsMax` = (184, 60, 134), the outer faces of the boundary walls. KillY is -30.

Palette: brick and cobblestone walls, limestone and marble dressings, slate roofs, wood-plank floors, grass lawns. Foliage is built from LeafyGrass in copper, orange, red and gold. Tree canopies are non-collidable so nobody can perch in them, but they still block sight and bullets. Greenhouse glass is transparent (0.6) but collidable.

## Top-down layout (not to scale; 1 char is about 6 studs)

```
Z=-130  +------------+------------------------------------------------------------------+------------+
        |            | WOODLAND WALK (N flank)   T   log    T   rock    T    log   T    |            |
        |            ) G1    T    log     T      T     log      T      T    rock   G1   (            |
Z=-112  |            |==== gw ========== gw ============== gw ============= gw ======   |            |
        |            | bed  bed    +-----HEDGE MAZE-----+    +---GREENHOUSE---+         |            |
        |  SABLE     | topi  .-.   |  +--inner ring--+  |    | bench   bench  |         |  TALON     |
        |  GATEHOUSE ) G2   (FTN)  D  D   armillary  D  D    D    (glass)     D  G2     (  STABLE    |
        |  COURT     | topi  '-'   |  +--------------+  |    | bench   bench  |         |  COURT     |
        |            | bed  bed    +---------D----------+    +-------D--------+         |            |
Z=-40   | s     s    |  ~balustrade~   urn   ~portico~   urn   ~balustrade~             |  s     s   |
        |            | tree urn  +-----D-----+----D-----+-----D-----+ bench  tree       |            |
        |[GATEHOUSE] | yew  A    |  LIBRARY  |  GREAT   |  DINING   |       yew         |[CLOCK ARCH]|
Z=0     | s   arch   =G3 STATUE  D  stacks    D  HALL B   D  table    D  STATUE  G3     =arch   s    |
        |            | yew       | (bedrooms |  stairs, | (long     |   C   yew         |            |
        |            | tree urn  +--above)---+-galleries+--gallery)-+  urn   tree       |            |
Z=40    | s     s    |  ~balustrade~   urn   ~portico~   urn   ~balustrade~             |  s     s   |
        |            | +===ORCHARD (stone walls)===+ cart  +-CARRIAGE HOUSE-+ paddock   |            |
        |            ) G4 D  T    T    T    T      | wagon D carriage   hay D fence G4  (            |
        |  s     s   |  |   T    T    T    T       D trough |  hay  carriage | shelter  |  s     s   |
        |            |  |shed T    T    T    T      |       +-------D--------+          |            |
Z=112   |            |==== gw ========== gw ============== gw ============= gw ======   |            |
        |            ) G5  barrow  woodpile  cold frame [SHED] cold frame  woodpile G5  (            |
Z=130   +------------+------------------------------------------------------------------+------------+
        X=-180        -122                              0                              122         180

 |  )  (  estate wall (14 tall) with gaps G1..G5. Each gap is a walled passage (fins); the
          centre gap G3 is the arch of the gatehouse (Sable) or the clock arch (Talon)
 s        team spawn (two columns of five per base, behind spawn-side baffle walls)
 D        doorway or gate (>= 6 wide, >= 9 tall)
 gw       gap in a 9-tall brick garden wall
 T        tree (trunk collides; canopy is above head height and does not)
 A B C    Domination flags
```

## Lanes

| Lane | Band | Range | Character |
|---|---|---|---|
| North: gardens | Z -108..-48 | mid to long | Three distinct rooms. The **parterre** has a raised fountain, 3-tall box-hedge beds, 8-tall topiary columns and stone benches. The **hedge maze** (8-tall copper beech, X -40..40) has an outer ring with one opening per side, offset so there is no straight line through, and an inner ring around an armillary. Spurs turn the ring corridors into a loop with pockets. The **greenhouse** (X 56..104) has a brick plinth, glass walls, doors west, east and south, and 3-tall staging benches inside. |
| Middle: manor house | Z -30..30 (interior) | close to mid | Library (book stacks 10 tall), great hall (settees, columns, rug), dining room (long table, piano). The hall's north and south doors line up across the hall, but the settees break the line at crouch height. The library and dining doors are offset from the hall's partition doors, so there is no line through the whole house. |
| South: orchard and stable yard | Z 46..110 | mid | **Orchard**: 12 trees in a grid inside 8-tall stone walls, with gates on every side, a cider shed and apple crates. **Cart track** (X -14..16): hay wagon, trough and pump, mounting block. **Carriage house** (X 16..70): a big brick room with carriage doors on all four sides, two carriages and hay. **Paddock**: post-and-rail fence and a three-sided field shelter. |
| North flank: woodland walk | Z -130..-112 | close | An 18-wide strip of trees, fallen logs and rocks behind the garden wall. Four gates lead into the gardens. |
| South flank: kitchen walk | Z 112..130 | close | Cold frames, woodpiles, compost bays and water butts. The potting shed blocks the south half at the centre (a 6-wide door through it, a 10-wide passage beside it). Four gates lead into the orchard and the stable yard. |

Cross-connections:

- The terraces (Z -40..40 outside the house) and the belts just inside each estate wall (|X| 100..112) run north to south on both sides.
- The manor has ground-floor doors on every side: north and south into the hall, library and dining room, and west and east from the terraces. Its partitions have one door each, offset north (west) and south (east).
- The garden-to-terrace edge (Z -48..-40) and the terrace-to-orchard edge (Z 40..52) are open except for low balustrade segments, so rotating between lanes is quick.

## Vertical play: the manor upstairs

- **Grand stairs**: two straight flights of 14 steps (1-stud rise, about 1.9-stud run, 7 wide) inside the great hall. The west flight rises south onto the south gallery, and the east flight rises north onto the north gallery.
- **Galleries** (Y 14) run along the hall's north and south walls behind 3.5-tall balustrades. They overlook the hall floor (flag B and hardpoint 1), and their upper windows overlook the gardens and the orchard.
- Each gallery has a 6-wide door at each end into the upper wings, so the upstairs is one loop: south gallery, west bedrooms, north gallery, east long gallery. Holding it means watching two stairs and four doors.
- Counters:
  - The gallery is open to the hall floor below.
  - Every upper window can be shot into from the lanes.
  - Neither stair is far from a ground door.
  - The roof cannot be reached.

Rule of thumb: nothing a player can stand on is within jump reach (about 7 studs) of a ledge they were not meant to reach. The statue plinths and topiary columns are 8 tall, the fountain bowl sits 7.4 above the basin rim, garden walls are 9 and maze hedges 8. Tree canopies are non-collidable. The only perch is the hay wagon in the cart track (6.5), which is exposed from three sides.

## Spawn logic

- **Sable** spawns in the gatehouse court (X -180..-122), and **Talon** in the stable court (X 122..180). The bases are mirror images in shape; only the arch dressing (stone gatehouse versus timber clock arch with cupola) and the courtyard props differ.
- There are 10 team spawns per side, in two columns (|X| = 150 and 167) spread from Z -100 to 108, all facing the map centre. The team centroids are 317 studs apart, and the closest enemy spawn pair is 300 studs apart.
- Each base is closed off by a 14-tall estate wall (cobble base, brick upper) with five exits:
  - G1 to the woodland walk
  - G2 to the gardens
  - G3, the arch, to the terrace drive
  - G4 to the orchard (Sable) or the paddock (Talon)
  - G5 to the kitchen walk
- Every gap is a walled passage 16 studs deep (fins at |X| 112..128; the gatehouse towers serve as G3's sides). A 12-tall baffle on the spawn side (|X| 136..138) blocks the shallow lines that pass through it.
- The contract test casts 72 rays per team spawn at eye height. The longest line within 60 degrees of the enemy base is **88 studs** (ending inside the walled base). No line from a spawn reaches the shared play space.
- **FFA**: 20 spawns, at least 20 studs apart, covering both bases, the woodland walk, parterre, maze, greenhouse, library, dining room, south gallery (Y 14), both terraces, the orchard, cart track, carriage house, paddock and kitchen walk.

## Objectives

All zones are invisible boxes in `Objectives`, 10 tall, with their bottom face on the floor.

**Domination.** Flags A and C are point-symmetric about the hall, and B is on the centre line.

| Flag | Centre (X, Z) | Size | Where |
|---|---|---|---|
| A | (-88, 18) | 18 x 18 | West terrace, south of the statue. Urns, a stone bench and the yew planter give cover. Nearer Sable. |
| B | (0, 0) | 20 x 16 | Great hall floor, between the settees. Overlooked by both galleries. |
| C | (88, -18) | 18 x 18 | East terrace, north of the statue. Nearer Talon. |

**Hardpoint.** Six zones, each a room or a defined structure. Consecutive zones are at least 45 studs apart, and every zone is at least 70 studs from a team spawn.

| Order | Zone | Centre (X, Z) | Size | Hop to next |
|---|---|---|---|---|
| 1 | Great hall | (0, 0) | 28 x 22 | 108 |
| 2 | Greenhouse | (80, -72) | 30 x 22 | 203 |
| 3 | Orchard (between the middle-row trees) | (-56, 78) | 26 x 26 | 162 |
| 4 | Hedge maze, inner ring | (0, -74) | 28 x 16 | 151 |
| 5 | Carriage house | (43, 71) | 28 x 22 | 113 |
| 6 | Library | (-45, 0) | 26 x 24 | 45 (back to 1) |

**Search and Destroy.** `SnDAttackBase` = `"Sable"`. Sable storms the estate through the gatehouse in round 1, and Talon defends. Both sites are on the east side, about 142 studs apart.

| Site | Centre (X, Z) | Size | Where and cover |
|---|---|---|---|
| A | (80, -66) | 14 x 14 | Inside the greenhouse, between the staging benches, the potted citrus trees and the south bench rows. Attackers come in through the west door from the maze, or the south door from the terrace. The glass lets both sides see each other through the walls. |
| B | (43, 71) | 14 x 14 | Inside the carriage house, between the two carriages and the hay stacks. There are doors on all four sides: the cart track (west), the terrace (north, two doors), the paddock (east) and the kitchen walk side (south). |

## Sightline notes

- **Gardens.** The fountain, topiary columns and box-hedge beds cut the parterre into short lines. The maze's outer openings are offset (W at Z -90..-82, E at Z -66..-58), so no line runs through it. The greenhouse is see-through, so its interior is a high-information, low-protection room. Its benches give crouch cover.
- **Manor.** Doors on the outer walls do not line up with the partition doors. The longest interior line is the library's central aisle, from the west door to the partition wall (about 38 studs).
- **Terraces.** A statue stands on each drive axis (Z 0), so the arch-to-west-door line is broken. Yew planters and urns on the belts (|X| 100..108) stop long north-south lines past the arches.
- **Orchard.** Trunks are thin, but crates, the barrow, the shed and the walls keep fights within about 30 to 40 studs. One section in each of the north and east walls is broken down to 3 studs, giving crouch-height firing lanes.
- **Flanks.** Logs and rocks (woodland), woodpiles, cold frames and the potting shed (kitchen walk) give cover every 15 to 25 studs, so end-to-end shots are blocked.

## Design notes

- **Three lanes plus flanks, with distinct materials**: brick and plank indoors, lawn and copper hedge in the north lane, dry grass and cobble in the south lane, leaf litter and packed earth in the flanks.
- **Asymmetric dressing, symmetric timing.** The gardens and the south lane differ in content (the parterre opposes the greenhouse, the orchard opposes the carriage house), but each lane has a comparable structure at a comparable distance from each base. Both S&D sites sit on the defenders' east side.
- **Doorways** are at least 6 x 9 (most are 8 x 10), and **stairs** rise 1 stud per step.
- Part count: **999** (the limit is 2500). Large slabs are used for floors, walls and roofs. Props are a few parts each.
