# Breakwater

Module: `src/server/Maps/Breakwater.luau` (id `Breakwater`). Tests: `tests/specs/map_breakwater.spec.luau`.

## Concept

Breakwater is a small harbour container port on an overcast morning: flat grey light, sea haze, wet concrete and bright stacked containers. It is a medium map. It mixes the alley fights of a container yard with one strong vertical position and an open, wet south flank:

- **Container yard**: the middle lane. Four rows of single and double stacks form three east-west alleys, with cross-gaps every 8 to 10 studs.
- **Gantry crane**: a rubber-tyred gantry straddles the centre of the yard. Two stairs, one per side, climb to a mid-height catwalk (Y 14) with a cross span over the central alley.
- **Fish market**: the north lane. A brick market hall with stall counters and a sawtooth roof, flanked by a cold store (west) and a net loft (east).
- **Harbourmaster office**: a two-storey brick office on the quay apron (the south lane). It has a south balcony reached by exterior stairs at both ends.
- **Pier and harbour water**: the south flank. A plank pier runs along the shallow harbour, joined to the quay by gangways. The water is a walkable floor 1.5 studs below the quay, not a pit.

The playable area is about 360 x 260 studs. The inner faces of the boundary walls are at X = +-180 and Z = +-130. KillY is -40, and `BoundsMin`/`BoundsMax` are (-184, -8, -134) / (184, 50, 134). The total part count is 1261.

Axes: +X is east and -Z is north (the top of the sketch). The layout is mirror-symmetric across X = 0. Only colours differ: the west store is a white cold store and the east one a timber net loft, with the same footprint and doors.

## Top-down layout (not to scale; 1 char is about 6 studs across, 1 row about 9 studs)

```
 Z=-130 +====================== WAREHOUSE WALL (24 tall) =======================+
        |  RAIL SIDING (flank)  [flatcar]     [flatcar]   [flatcar]     [flatcar] |
 Z=-116 | s|) [CNT==][CNT==]  [CNT==][CNT==]  [CNT=][=CNT]  [CNT==][CNT==] [CNT=](|  |
 Z=-108 |  |  pallets  truck-yard   +---D-------FISH MARKET-------D---+   pallets |  |
        |  |) +-COLD--+    light    | stalls   stalls  |  stalls stalls| +NET---+ (|  |
        | B|) D STORE |  totes      D  col  ice  (HP2)  ice  col       D | LOFT D (| B|
        |  |) | (HP3) |   tower     | stalls   stalls  |  stalls stalls| |(HP5) | (|  |
        |  |) +--D----+             +===DD=====DDD======DD=============+ +--D---+ (|  |
 Z=-46  |  | truck  forklift pallet  totes  [ICE]  totes  pallet forklift  truck |  |
        | s|) [CNT==][CNT==]  [CNT==][CNT=]  .  [CNT=][CNT==]  [CNT==][CNT==]   (|s |
        | s|)  cage   crate   genset   #E-STAIRS#->|LEG     LEG|    cage   crate (|s |
        | s|) [CNT=]  [CNT==][CNT=] [CNT|=catwalk=|CNT] [CNT=][CNT==]  [CNT=]   (|s |
        | s|)--(FLAG A) bin  tractor  barrier (FLAG B / HP1) barrier tractor bin (FLAG C)--(|s |
        | s|) [CNT=]  [CNT==][CNT=] [CNT|=catwalk=|CNT] [CNT=][CNT==]  [CNT=]   (|s |
        | s|)  genset crate  cage  <-#W-STAIRS#  |LEG     LEG|   genset crate cage (|s |
 Z=34   |  |) [CNT==][CNT==]  [CNT==][CNT=]     [CNT=][CNT==]  [CNT==][CNT==]   (|  |
        |  |)  ice    reefer  [REEFER]   +--D--HARBOURMASTER--D--+  [REEFER] reefer (|  |
        |  |)  plant  pallet  forklift   D   (HP4)  ground fl.   D  forklift  pallet (|  |
        | s|)  reefer  light  ==stairs==/=====BALCONY y13=====\==stairs==  light (| s|
 Z=88   |__|__o____o____o____o___#st__||_____________||_____________||__#st__o____o__|__|
        |  |) ~~ boat ~~  ~skiff~  ~~  ||   ~skiff~   ||    ~~  ~skiff~  ~~ boat ~~ (|  |
        |==|)======================== PIER (deck Y 0) =====================(BOMB B)===(|==|
        |  |) ~~ #st ~~ [hut] ~~ boat ~~ #st ~ boat ~ #st ~~ boat ~~ [hut] ~~ #st ~~ (|  |
 Z=130  +=========== BREAKWATER (armour blocks + sea wall) =======================+
       X=-180  -144 -122                     0                     122  144     180

  |)  (|  double-stacked container rampart (|X| 136..144) with gaps; B = outer baffles
  [CNT==] container row (single or double stack)    D  doorway (>= 6 wide, >= 9 tall)
  ~~  harbour water, walkable floor at Y -1.5      ||  gangway   #st  steps out of the water
  o   bollard                                       s  team spawn (Sable west, Talon east)
```

## Lanes

| Lane | Band | Range | Character |
|---|---|---|---|
| North: fish market | Z -108..-46 | close to mid | The market hall (X -50..50) is an interior lane. It has three big roller-door openings on the south side, doors north and on both ends, two rows of stall counters, ice tables and columns. The cold store and net loft are walk-through side rooms. Box trucks, a forklift, pallets and fish totes fill the yards around them. |
| Middle: container yard | Z -46..34 | close to mid | Three alleys: alley 1 (Z -38..-24), the central alley (Z -16..4) and alley 3 (Z 12..26). They are separated by container rows with cross-gaps every 20 to 30 studs. The gantry crane straddles the centre. Its catwalk (Y 14) overlooks all three alleys. |
| South: quay apron | Z 34..88 | mid | Reefers, pallets, light towers and forklifts around the harbourmaster office. The office ground floor is a walk-through from the yard to the quay. Its balcony overlooks the pier and the water. |
| North flank: rail siding | Z -130..-116 | close | A 14-wide lane behind a double-stacked container wall. Low flatcars carry crates and tarps for chest-high cover. Gaps in the container wall at X 0, +-50 and +-100 lead into the market yards. |
| South flank: pier and harbour | Z 88..130 | mid to long | A 12-wide pier (deck Y 0) runs the whole width, with gangways to the quay at X 0 and +-44. Players can also drop into the shallow water (Y -1.5) and wade. Boats, bait huts on piles and the armour blocks of the breakwater give cover. Steps lead out of the water onto the pier and the quay. |

Rotations:

- The yard alleys open north into the market front yard and south onto the quay apron through the gaps in the outer rows.
- The office links the central alley, through the gap behind row S, to the quay and the balcony.
- The gangways and the water steps tie the pier to the quay.

## Gantry crane and climbing

- **Structure:** legs at (|X| 12, Z -36) and (|X| 12, Z 24), girders at Y 26..28, an operator cab and a trolley above the centre.
- **Catwalks:** they run along |X| 8..14 from Z -32 to 20, joined by a cross span over the central alley at Z -10..-2. All have 3.5-tall rails.
- **Stairs:** both are 14 steps of 1-stud rise and 2-stud run.
  - West stair: in alley 3, rising east from X -42 to the west catwalk at Z 14..20.
  - East stair: in alley 1, rising west from X 42 to the east catwalk at Z -32..-26.
- **Rows under the catwalks:** the centre containers of rows M1 and M2 are single stacks (top Y 9), so the catwalk clears them. A player can drop from the catwalk onto those container tops as a risky shortcut.
- **Office:** the exterior stairs (13 steps of 1-stud rise) climb from the quay at X +-48 to the balcony (Y 13). Two upper doors open from the balcony into the office.
- **Water:** steps out of the water rise 0.75 per step. The pier and quay sit 1.5 above the water.
- **Doorways:** at least 8 x 10 everywhere except the bait huts (6 x 9).

## Power positions and counters

1. **Gantry catwalk (Y 14).**
   - **What it gives:** sees down all three alleys.
   - **Counters:**
     - The rails are the only cover, plus one cabinet per side.
     - Each side has a single stair, and both stairs are long and exposed.
     - Nothing reachable sits above it (the double stacks top out at an unreachable Y 18), but the office upper windows and the market front yard can see the catwalk ends.
2. **Harbourmaster office, upper floor and balcony (Y 13).**
   - **What it gives:** watches the pier, the gangways and the quay apron. The north windows look into alley 3.
   - **Counters:** two stairs (west and east ends of the balcony). The windows can be shot into from the yard and from the pier. The ground floor below is a separate walk-through room.
3. **Fish market centre (HP2).**
   - **What it gives:** the indoor heart of the north lane.
   - **Counters:** seven entrances. The stall counters are crouch cover only.
4. **Pier.**
   - **What it gives:** long east-west lines over the harbour.
   - **Counters:** players in the water are partly hidden below the deck edge (the deck is 1.5 higher), and the bait huts and boats break the line every 30 to 40 studs.

## Spawn logic

- **Bases:** Sable spawns at the west gate (X -180..-144) and Talon at the east gate (X 144..180). There are 10 team spawns per side in two columns (|X| 152 and 166), from Z -48 to 54, all facing the map centre.
- **Distances:** the team centroids are 318 studs apart. The closest pair of enemy spawns is 304 apart.
- **The base rampart** is a double stack of containers (18 tall) at |X| 136..144, running from the warehouse wall to the sea wall. Over the water it stands on the harbour floor. It has five gaps:
  - rail siding (Z -126..-118)
  - fish market yard (Z -80..-70)
  - central alley (Z -6..4)
  - quay apron (Z 56..66)
  - pier (Z 100..112)
- **Outer baffles:** single containers (9 tall) at |X| 122..130 stand 6 studs in front of the three land-lane gaps (Z -92..-58, -18..16 and 44..78). A shot through a gap at any angle within 60 degrees of the enemy base hits a baffle. The siding and pier gaps sit too far north and south of the spawn columns to give a line into them.
- **Longest team-spawn sightline:** the contract test casts eye-level rays within 60 degrees of the enemy base. The longest is 56 studs, from (-166, 0.55, 30).
- **FFA spawns:** there are 21, spread over:
  - both base yards
  - the rail siding (3)
  - the market hall, cold store and net loft (4)
  - the container yard (4) and the catwalk (1)
  - the apron and office (3)
  - the pier (2) and the water (2)

  They are pairwise at least 20 apart.

## Objectives

| Mode | Zone | Position (floor) | Size | Notes |
|---|---|---|---|---|
| Domination | Flag A | (-90, 0.05, -6) central alley west | 18 x 18 | twistlock bins, tractor, crates |
| Domination | Flag B | (0, 0.05, -6) under the gantry cross span | 18 x 18 | watched from the catwalk |
| Domination | Flag C | (90, 0.05, -6) central alley east | 18 x 18 | mirror of A |
| Hardpoint 1 | Gantry yard | (0, 0.05, -6) | 24 x 18 | |
| Hardpoint 2 | Fish market hall | (0, 0, -80) | 24 x 20 | interior |
| Hardpoint 3 | Cold store | (-86, 0, -83) | 20 x 18 | interior |
| Hardpoint 4 | Harbourmaster office | (0, 0, 60) | 24 x 18 | ground floor |
| Hardpoint 5 | Net loft | (86, 0, -83) | 20 x 18 | interior |
| S&D (Talon defends) | Bomb A | (86, 0, -83) in the net loft | 14 x 14 | net piles, mending bench, two doors |
| S&D (Talon defends) | Bomb B | (91, 0, 106) on the east pier fuel dock | 14 x 10 | fuel pump, drums, attackable from the water |

- **Hardpoint rotation:** yard, market, cold store, office, net loft. Each hop is at least 74 studs.
- **S&D:** `SnDAttackBase` is `"Sable"`, so Sable attacks first from the west, and both sites are on the Talon (east) side.

## Look and lighting

- **Lighting:** ClockTime 8.2, Brightness 1.7, ShadowSoftness 0.8. Low-contrast overcast light with a cool blue-grey ambient.
- **Atmosphere:** sea haze (Density 0.36, Haze 2.2, no glare). Fog starts at 300 studs.
- **Colours:** grey-blue concrete, asphalt and steel, with saturated containers (red, blue, yellow, green, orange, white, teal) and a yellow crane, so positions are easy to call ("yellow stack", "blue baffle").
- **Water:** tinted Glass (transparency 0.35) over a dark seabed. The Glass is collidable, so you can walk on it.
- **Lobby camera:** from above the south-east quay. It frames the gantry crane over the container yard, with the market hall behind.

## Sightline notes

- **Central alley:** this is the long east-west line. Twistlock bins, concrete barriers, gensets, terminal tractors and crates alternate sides every 12 to 25 studs. No standing line runs from one baffle to the other.
- **Alleys 1 and 3:** the stair runs, cages and gensets break these up.
- **Market hall:** the ice tables and columns sit between the end doors, so you can't shoot through the hall from door to door.
- **Pier:** the pier is the longest open line on the map. The bait huts, net piles and fuel dock break the deck, while the water beside it is the low, slow alternative route.
