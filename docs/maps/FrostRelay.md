# Frost Relay

Module: `src/server/Maps/FrostRelay.luau` (id `FrostRelay`). Tests: `tests/specs/map_frostrelay.spec.luau`.

## Concept

Frost Relay is a radio-relay station high in the mountains, snowed in and running on its last generator. It is dusk: a low peach sun behind the ridge, blue shadows on the snow, and the red-and-white lattice mast blinking over everything. The map is medium sized and built for 6v6, with a mix of open ice, a fenced compound and close vehicle-yard fights:

- **Relay compound**: the middle lane. It has a two-storey operations block, the lattice mast on its pad, and two radio cabins.
- **Frozen reservoir**: the north lane. The ice is a walkable floor 3 studs below the shore. A pump house stands in the middle, with ice-locked barges and fishing huts around it.
- **Motor pool**: the south lane. A walk-through vehicle shed (two snowcats inside) sits between two bunded fuel depots.
- **Two flanks**: the dam gallery, a roofed concrete walkway along the north cliff with windows over the ice, and the pipeline trench, a sunken trench along the south edge under timber snow sheds.
- **Snow berms**: wedge-shaped drifts that split the compound from the motor pool and give crouch cover.

The playable area is about 356 x 256 studs. The inner faces of the rock boundary are at X = +-178 and Z = +-128. Total part count is 949.

Axes: +X is east and -Z is north (the top of the sketch). The ground is at Y 0 everywhere except four places: the ice (Y -3), the pipeline trench (Y -3), the mast pad (Y 0.6) and the operations block upper floor (Y 13). Every ground slab reaches down to Y -6 (`BoundsMin.Y`). KillY is -40. Bounds are (-182, -6, -132) to (182, 96, 132).

## Top-down layout (not to scale; 1 char is about 6 studs)

```
 Z=-128 +-----------+----------------------------------------------------------+-----------+
        |           |> DAM GALLERY (roof y11) |baf  pump  [sw]   pump  baf|  <|           |
        |           |==win==D=====win===win===D===win===win===D====win=====|   |           |
 Z=-112 |  SABLE    |)G1 ~~~~~~~~~~~~ shore steps (y0 -> ice y-3) ~~~~~~~~~ G1(|  TALON    |
        |  WEST     |   ^ridge   [hut]   ^  [==BARGE==]  +-PUMP-+  [==BARGE==]  [hut]   ^    |  EAST     |
        |  CAMP     |)G2  ICE y-3   ^       drums      D HOUSE D       ^    ICE   G2(|  CAMP     |
        | H  s   s  |     [hut]  ^drift   ^ridge       +------+  ridge^   [hut]  ^  |  s   s  H |
 Z=-57  |           |  ---mesh fence---D---------------D---------------D---mesh---  |           |
        | H  s   s  |  drum [CABIN]  /st|  OPS BLOCK (2 storey)  |st\  [CABIN] drum | s   s  H |
        |           |  gate  case     /st| D(N)           D(S)  |st\    case  gate  |           |
        |           |)G3   A           bar   [MAST PAD + mast] B  bar        C   G3(|           |
        | H  s   s  |  gate [GENSET]  case       cabinets          case [GENSET] gate | s   s  H |
 Z=26   |           |  ~~berm~~      ~~berm~~       ~~berm~~      ~~berm~~      |           |
        | H  s   s  | berm  lamp     D  [ VEHICLE SHED  ]  D     lamp   berm   | s   s  H |
        |           |)G4 [DEPOT bund] D  snowcat  snowcat D [bund DEPOT]  G4(|           |
        |           |  plough  tanks |  gantry  workbench |  tanks  plough   |           |
        | H  s   s  |  drums  berm         ~~berm~~         berm   drums     | s   s  H |
 Z=108  |           |)G5 #st# shed###valve#st#==PIPELINE TRENCH y-3==#st#valve###shed #st# G5(|  |
 Z=128  +-----------+----------------------------------------------------------+-----------+
       X=-178     -126   -100            -24     0     24             100    126         178

 )  (  blast wall (14 tall) with gaps G1..G5      H  barracks hut behind each gap (baffle)
 D     doorway (>= 6 wide, >= 9 tall)             s  team spawn          st  1-stud stairs
 A B C flags                                      ^  ice ridge / drift   bar concrete barrier
```

## Lanes

| Lane | Band | Range | Character |
|---|---|---|---|
| North: frozen reservoir | Z -106..-64 (ice, Y -3) | long to mid | Open ice broken up by the pump house in the centre, two ice-locked barges (hull 4 tall, wheelhouse on the outer end), glacier pressure ridges, snow drifts and fishing huts. Cover every 15 to 25 studs along any east-west crossing. Three-step shore stairs run along the whole north and south shores and both ends, so you can step on and off the ice anywhere. |
| Middle: relay compound | Z -57..26 | mid to close | A fenced yard (concrete). The operations block (X -24..24) and the mast pad (X -12..12) split it into west and east yards. Each yard has a radio cabin, a generator shed, cable drums, equipment cases and barriers. The mesh fence is see-through and gated at X -60, 0 and +60 (north) and at Z -20 and +6 (west and east). |
| South: motor pool | Z 34..104 | mid to close | The vehicle shed (X -32..32) has 16-wide roller doors at both ends and doors on both long sides. Inside are two snowcats and a gantry. The fuel depots (X +-62..100) have 3-tall bund walls with a gap on every side, two horizontal tanks on saddles and pump units in between. Snow berms and parked plough trucks fill the gaps. |
| North flank: dam gallery | Z -128..-114 | close | A roofed concrete walkway (ceiling Y 11). Doors at X -90, 0 and +90 lead onto the shore, and windows (sill Y 4) look over the ice. Pump motors and switchgear sit against the dam face. Zig-zag baffles at X +-104 and +-114 stop end-to-end shots. |
| South flank: pipeline trench | Z 108..124 (Y -3) | close | A sunken trench. The pipeline along the south side is crouch cover. Valve pits at X +-94, +-80 and +-30 zig-zag the trench. Stairs lead out at both ends and at X -50, 0 and +50, and two timber snow sheds (roof Y 9, out of reach) cover parts of it. |

Cross-connections let players rotate between lanes:

- Within each camp, the corridor between the blast wall and the huts connects all five gaps.
- From the compound, the north fence gaps lead to the ice. The fence gaps at Z -20 and +6 lead to the side areas between the compound and the camps.
- The berm line has gaps at X 0, +-60 and +-100.
- The trench's mid stairs come up beside the shed's south door and the depots.
- The gallery doors open straight onto the shore stairs.

## Power positions and counters

1. **Operations block, upper floor (Y 13).**
   - **What it gives:** big north windows over the whole reservoir, and big south windows over the mast pad and Flag B.
   - **Counters:**
     - Two entrances only: the exterior stairs on the west and east sides, each rising 13 one-stud steps north to a landing and a 6-wide door. A team holding the room has to watch both.
     - The windows (Y 15.5..20.5) can be shot into from the ice, the barge decks and the compound.
     - The ground floor is a separate room with north and south doors. Holding it puts you under both stair approaches.
     - The roof (Y 24) cannot be reached.
2. **Barge decks (Y 1).**
   - **What they give:** 4 studs of height over the ice, with a wheelhouse to hide behind.
   - **Counters:**
     - The decks are exposed to the gallery windows and the ops block.
     - You reach them by jumping from the ice, so pushing onto them is slow.
3. **Vehicle shed.** It controls the south lane.
   - **Counters:**
     - Five doors: two 16-wide roller doors and three side doors.
     - Snowcats give mid-room cover.
     - The high windows are for light only (sill Y 11).
4. **Mast pad.**
   - **What it gives:** the centre of the map, Flag B.
   - **Counters:**
     - The lowest bay of the mast is open, and cabinets at the pad corners give cover.
     - The ops block's south windows overlook it.
     - The barriers at X +-18..24 and the cases at X +-36 give approaches from both yards.

## Spawn logic

- **Sable** spawns in the west camp (X -178..-126) and **Talon** in the east camp (X 126..178). The layout is mirror-symmetric across X = 0. Only accent colours and camp dressing differ (Sable: supply tent and snowmobiles; Talon: helipad and fuel bladder).
- There are 12 team spawns per side, in two columns (|X| = 148 and 166) spread from Z -100 to 92, all facing the map centre. The team centroids are about 314 studs apart. The closest enemy spawn pair is about 296 studs apart.
- Each camp is closed off by a 14-tall blast wall at |X| 126..128 with five gaps:
  - G1, the gallery mouth (Z -128..-114)
  - G2, the ice (Z -96..-84)
  - G3, the compound (Z -22..-10)
  - G4, the motor pool (Z 54..66)
  - G5, the trench (Z 110..122)
- A barracks hut (|X| 134..142, 10 tall) stands behind every gap, 8 studs wider than the gap on each side. Any line through a gap toward a spawn column is caught by the hut. The longest eye-level sightline from a team spawn toward the enemy (within 60 degrees) is **87.9 studs**, measured by the contract test.
- There are 19 FFA spawns: camps, gallery, ice, both compound yards, the ops block on both floors, the motor pool, the shed, the depots and the trench. They are at least 20 studs apart from each other.

## Objectives

| Mode | Zone | Where | Size (X x Z) | Floor Y |
|---|---|---|---|---|
| Domination | Flag A | west compound yard (-72, -12) | 18 x 18 | 0 |
| Domination | Flag B | mast pad (0, 6) | 18 x 18 | 0.6 |
| Domination | Flag C | east compound yard (72, -12) | 18 x 18 | 0 |
| Hardpoint | 1 | operations block ground floor (0, -37) | 22 x 20 | 0 |
| Hardpoint | 2 | vehicle shed (0, 64) | 26 x 20 | 0 |
| Hardpoint | 3 | pump house on the ice (0, -85) | 18 x 16 | -3 |
| Hardpoint | 4 | west fuel depot (-81, 68) | 20 x 16 | 0 |
| Hardpoint | 5 | east fuel depot (81, 68) | 20 x 16 | 0 |
| S&D | Bomb A | east radio cabin (60, -34): rack, desk, bench | 12 x 12 | 0 |
| S&D | Bomb B | east fuel depot (81, 68): tanks, pump units, bund wall | 14 x 12 | 0 |

- **Hardpoint rotation:** centre, then south, then north, then the west and east depots. Every hop is at least 100 studs, and every zone is at least 65 studs from a team spawn.
- **Search and Destroy:** `SnDAttackBase = "Sable"`. Sable attacks from the west in round 1, so both sites are on the Talon side. They are about 103 studs apart.

## Sightline notes

- The longest open lines run east-west across the ice. The pump house, the barge wheelhouses and the ridges at X +-22..26 and +-72 break any standing line at about 50 to 70 studs. Low drifts and the sled are crouch-only cover.
- The compound's long north-south line is broken by the ops block and the mast pad. The cabins and generator sheds block the east-west lines along the yards.
- The motor pool's east-west line runs straight through the shed's end doors. The snowcats sit off-axis, and the plough trucks and berms at |X| 108..112 stop the line short of the camp gaps.
- Gallery and trench lines are capped by their zig-zag baffles and valve pits.

## Art direction

The palette is Snow, Ice, Glacier, Concrete, Metal and Slate. Warm accents come from red-and-white mast bands, orange equipment and drums, and warm sodium lamps against the blue dusk. Lighting runs at ClockTime 17.7 with a warm top colour shift and a blue bottom. Fog starts at 320 and ends at 1500. A light atmosphere haze (Density 0.3, Haze 1.6) reads as snowfall in the air. The lobby camera looks from the south-west over the shed roof at the mast, the ops block and the ice behind.
