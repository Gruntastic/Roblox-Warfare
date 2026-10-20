# Red Mesa

Module: `src/server/Maps/RedMesa.luau` (id `RedMesa`). Tests: `tests/specs/map_redmesa.spec.luau`.

## Concept

Red Mesa is a working copper-and-iron mining outpost cut into a red-rock canyon. It is midday: the sun is high and hard, shadows are short, and the sandstone glows. It is the large, long-range map of the rotation. Open terraces and a long main street reward rifles, while the buildings, the dry wash and the tunnel give close-range players their own routes.

- **Stepped mesa terraces**: four floor levels joined by stairs and wedge cart ramps. These are the dry wash (Y -8), the street and camp (Y 0), the ore terrace (Y 6) and the ridge path (Y 12).
- **Ore terrace**: the north lane. A crusher house sits in the centre, with an elevated ore conveyor running out to an ore loader on each side.
- **Trestle bridge**: a timber trestle carries the main street over the dry wash. You can fight on the deck or walk under it in the wash.
- **Bunkhouse and mess hall**: two walk-through timber buildings between the street and the lower camp.
- **Rock-cut tunnel**: the south flank, a shored mine adit with zig-zag rock baffles at each end.

The playable area is about 420 x 300 studs. The inner faces of the canyon walls are at X = +-210 and Z = +-150. KillY is -40, and `BoundsMin`/`BoundsMax` are (-214, -10, -154) / (214, 64, 154). The total part count is 1039.

Axes: +X is east and -Z is north (the top of the sketch). The layout is mirror-symmetric across X = 0. Only cosmetic details differ, such as building colours and which side has the powder magazine.

## Top-down layout (not to scale; 1 char is about 6 studs across, 1 row about 10 studs)

```
 Z=-150 +====================================================================+
        |##################### CLIFF FACE (unreachable) ######################|
 Z=-140 |  RIDGE PATH y12   ^h      ^h     ^h  [SHACK]  ^h     ^h      ^h      |
 Z=-122 |##stairs#####/ramp######stairs#####+--D---D--+####stairs####ramp\####|
        |  |    tim     ore   barrels      | CRUSHER  |     barrels  ore  tim |
        | T|   [LOADER]=====CONVEYOR=======D  HOUSE   D=======CONVEYOR=[LOADER]
        | E|   (cribs)   leg  leg  leg     |  (HP3)   |   leg  leg  (BOMB A)  |
        | R)  carts  [shed]  timbers  carts+----D-----+carts timbers [shed]   (|
 Z=-60  |__|__stairs____ramp___stairs_______  ~WASH~  ______stairs__ramp__stairs__|
        |  |     [ASSAY]   boulder  #st          #st      boulder  [FUEL]    |
        | s|)    [OFFICE]  [TOWER]           ~~            [TOWER] [DEPOT]  (|s |
        | s|)  wagon  (FLAG A)  timbers  ===BRIDGE===  timbers  (FLAG C) wagon(|s |
        | s|)  bench  crates     boulder  (FLAG B/HP1)  boulder   crates bench (|s |
 Z=22   |  |)   timbers   +------D--BUNKHOUSE--D-+ ~~ +-D--MESS HALL--D------+(|  |
        | s|)  crates     D  bunks  (HP2)  bunks D ~~ D bunks (HP4) bunks D  (|s |
 Z=56   | s|)  barrels    +------D--------D------+ ~~ +------D--------D------+(|s |
        | s|)   wagon=====spur=====wagon           ~~      wagon=====spur=====wagon (|s |
        |  |)  timbers [TOOL YARD] tent  boulder  #st  boulder tent [MAGAZINE] (|  |
        | s|)  boulder [ vault  ]       crate     ~~(HP5) crate     [(BOMB B)]  (|s |
 Z=124  |  |___D_______________D________________##________________D________D___|  |
        |  >tunnel>|| carts  shoring  carts   collapse   carts  shoring  carts ||<tunnel<|
 Z=150  +====================================================================+
       X=-210  -174 -165               -14  0  14                165  174   210

  ^h  hoodoo (rock column)          ~~   dry wash, floor Y -8 (X -14..14, Z -60..124)
  #st stairs into the wash          D    doorway (>= 6 wide, >= 9 tall)
  |)  base rampart (16 tall) with gaps; the outer baffle walls stand in front of the street and south gaps
  s   team spawn (Sable west, Talon east)       TER  base terrace rampart with one gap
```

## Lanes

| Lane | Band | Range | Character |
|---|---|---|---|
| North: ore terrace (Y 6) | Z -122..-60 | long to mid | A wide sandstone shelf. The crusher house in the centre can be walked through on both axes. The conveyor (belt at Y 17) runs overhead on legs out to the two ore loaders. Ore carts, timber stacks, boulders and two small tool sheds give cover every 15 to 25 studs along X. |
| Middle: main street and trestle bridge (Y 0) | Z -60..22 | long | The longest lane. The assay office (west) and fuel depot (east) are small walk-through buildings. Water towers, wagons, timber stacks and boulders break up the street. The 16-wide trestle bridge is the only level crossing of the wash. |
| South: lower camp (Y 0) | Z 56..124 | mid | Ore wagons on a spur line, canvas tents, the walled tool yard (west) and powder magazine (east). The wash is crossed here by bank stairs (Z 76..92). |
| North flank: ridge path (Y 12) | Z -140..-122 | mid to close | An 18-wide ledge under the cliff. Hoodoos alternate sides of the path every 30 to 45 studs, and a lookout shack sits in the centre (doors on the west and east sides, a window looking south over the ore terrace). |
| South flank: rock-cut tunnel (Y 0) | Z 128..150 | close | A roofed adit (ceiling Y 12) with timber shoring every 24 studs. Doors at X +-100 and +-30 open into the lower camp. Zig-zag rock baffles near each mouth stop end-to-end shots. |
| Centre connector: dry wash (Y -8) | X -14..14 | close | A sunken north-south channel. It passes under the bridge between the trestle bents (8-wide walkways, 6 studs of headroom). Bank stairs at Z -56..-40 and Z 76..92 join it to the street and the camp. |

Cross-connections let players rotate between lanes:

- **Street to ore terrace:** stairs at X +-40 and +-140, and a wedge cart ramp at X +-80 (all at Z -60..-44).
- **Ore terrace to ridge:** stairs at X +-80 and +-185, and a wedge ramp at X +-130.
- **Street to lower camp:** through the bunkhouse and mess hall (doors on all four sides), or through the alleys at X +-14..40 and +-100..165.
- **Lower camp to tunnel:** four doors in the tunnel's north wall.
- **Wash:** links the north end of the street, the bridge underpass and the lower camp.

## Levels and climbing

- **Every level stands on the ground.** The bedrock slab (Y -10..-8) covers the whole footprint. The ridge and the ore terrace are each one solid block from Y -8 up to their top, and the street, camp and tunnel floors are solid blocks from Y -8 to Y 0. There is no void anywhere.
- **Stairs** are built with 1-stud rises: 6 steps between the street and the terrace and between the terrace and the ridge, and 8 steps into the wash.
- **Wedge ramps** are 6 high over 16 run, about 21 degrees.
- **Doorways** are 8 wide and 10 tall. The shack doors are 8 x 9.5.

## Power positions and counters

1. **Ridge path (Y 12).**
   - **What it gives:** a view down over the whole ore terrace.
   - **Counters:** it is a narrow ledge. The hoodoos block long shots along it, so holding it means fighting at close range. It can be reached from five points: two stairs and a ramp per side, plus the base stairs. The terrace below can shoot back up into it.
2. **Crusher house (HP3).**
   - **What it gives:** the centre of the north lane. Four doors and two small windows per side.
   - **Counters:** the doors face all four directions, so a team holding it gets flanked from the ridge stairs and from the street stairs at X +-40.
3. **Trestle bridge (Flag B, HP1).**
   - **What it gives:** the middle-lane crossing.
   - **Counters:** the deck has only 3.5-stud rails as cover. Players in the wash below can push up the bank stairs, or shoot up through the gaps around the bents. The bridge is exposed to both water towers and to the bunkhouse and mess hall windows.
4. **Bunkhouse and mess hall (HP2, HP4).**
   - **What they give:** walk-through cover between the middle and south lanes.
   - **Counters:** each has 8 doors and window bands on both long walls. Bunks and tables give crouch cover only.
5. **Ore loaders.** The bin sits on legs above the terrace and can't be climbed. Players fight underneath it among the timber cribs.

## Spawn logic

- **Sable** spawns in the west yard (X -210..-174) and **Talon** in the east yard (X 174..210). There are 10 team spawns per side in two columns (|X| 186 and 200) from Z -40 to 86. All of them face the map centre.
- The team centroids are 386 studs apart. The closest pair of enemy spawns is 372 apart.
- **The base rampart** is a 16-tall rock wall at |X| 170..174 that runs from the terrace face (Z -60) to the south wall. It has three 10-wide gaps:
  - street (Z -20..-10)
  - lower camp (Z 80..90)
  - tunnel (Z 134..144)
- **Outer baffles:** in front of the street and camp gaps stand 14-tall rock walls at |X| 158..161 (Z -40..10 and Z 62..108). A straight shot through a gap hits the baffle. The tunnel gap is shielded by the tunnel's own zig-zag baffles.
- **Base terrace:** the part of the ore terrace above each yard is closed off by a 12-tall terrace rampart with one gap (Z -96..-86), and a parapet runs along its edge above the spawn yard. Stairs connect the yard to the base terrace, and the base terrace to the ridge.
- **Longest team-spawn sightline:** the contract test casts eye-level rays within 60 degrees of the enemy base. The longest is 68 studs, from (-200, 0.5, 26) through the street gap onto the baffle.
- **FFA spawns:** there are 22, spread over every zone and every level:
  - both base yards and base terraces
  - the ore terrace (4) and the ridge (2)
  - the street (4) and the wash (1)
  - the lower camp (4) and the tunnel (3)

  They are pairwise at least 20 apart. The layout spec checks that each of the four levels has at least one.

## Objectives

| Mode | Zone | Position (floor) | Size | Notes |
|---|---|---|---|---|
| Domination | Flag A | (-112, 0, -6) street west | 18 x 18 | wagon, crates and timbers around it |
| Domination | Flag B | (0, 0, 0) on the bridge deck | 18 x 14 | equidistant from both bases |
| Domination | Flag C | (112, 0, -6) street east | 18 x 18 | mirror of A |
| Hardpoint 1 | Trestle bridge | (0, 0, 0) | 24 x 16 | |
| Hardpoint 2 | Bunkhouse | (-70, 0.2, 40) | 26 x 18 | interior aisle |
| Hardpoint 3 | Crusher house | (0, 6, -93) | 22 x 20 | interior, machine against the north wall |
| Hardpoint 4 | Mess hall | (70, 0.2, 40) | 26 x 18 | interior aisle |
| Hardpoint 5 | Wash bend | (0, -7.9, 104) | 18 x 22 | under the south bank stairs |
| S&D (Talon defends) | Bomb A | (112, 6, -88) under the east ore loader | 14 x 14 | cribs, ore cart, boulder |
| S&D (Talon defends) | Bomb B | (110, 0, 96) in the powder magazine yard | 14 x 14 | 8-tall stone walls, vault, crates and barrels |

- **Hardpoint rotation:** bridge, bunkhouse, crusher, mess hall, wash. Each hop is at least 80 studs and crosses a lane, so the teams keep rotating between levels.
- **S&D:** `SnDAttackBase` is `"Sable"`, so Sable attacks first from the west, and both sites are on the Talon (east) side.

## Look and lighting

- **Lighting:** ClockTime 12.6, Brightness 3.2, ShadowSoftness 0.15. Hard midday light with warm ambient.
- **Atmosphere:** thin dusty haze (Density 0.24). Fog starts at 400 studs, so nothing hides players.
- **Materials:** Sandstone for the terraces and stone walls, Rock for the canyon and ramparts, Ground for the street and camp, rusted CorrodedMetal for the crusher, conveyor and roofs, WoodPlanks and Wood for the bridge, bunkhouse and shoring.
- **Lobby camera:** from the south-east, over the mess hall. It frames the trestle bridge with the crusher house and conveyor behind it.

## Sightline notes

- **Street:** the longest open lines run east-west along the street. The water towers, wagons, timber stacks and the two street buildings break any standing-height line into 40 to 70-stud pieces. The bridge rails give crouch cover only, by design.
- **Ore terrace:** the crusher house blocks the centre of the terrace, so the two halves only see each other through its doors or around its north and south sides.
- **Ridge:** the hoodoos are staggered so the ridge never has a clean line of more than about 45 studs.
- **Dry wash:** the wash is 184 long. Boulders, the driftwood and the trestle bents stop shots from end to end.
