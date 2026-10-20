# Dustline Terminal

Module: `src/server/Maps/DustlineTerminal.luau` (id `DustlineTerminal`). Tests: `tests/specs/map_dustline.spec.luau`.

## Concept

Dustline Terminal is a regional bus and rail interchange at the edge of the desert, abandoned for years. It is late afternoon: warm low sun, haze, sand drifting through a rusted roof. The map is medium sized and built for 6v6 Team Deathmatch, with a mix of indoor and outdoor fighting:

- **Terminal hall**: a tiled ticket hall, the indoor middle lane.
- **Loading yard**: a parking and freight area to the north, the outdoor long-range lane.
- **Platforms and bus bays**: to the south, a mid-range lane full of vehicles you can walk through.
- **Two flanks**: a north alley behind a wall of shipping containers, and a south service tunnel.
- **Control office**: a two-storey building in the centre. It is the map's main vertical power position.

The playable area is about 360 x 260 studs. The inner faces of the boundary walls are at X = +-180 and Z = +-128. The walls are 30 studs tall. Total part count is about 890 (889 with the base slab).

Axes: +X is east and -Z is north (the top of the sketch). The ground is at Y 0 everywhere except the sunken track bed (Y -3) and the office upper floor (Y 13). KillY is -40.

The track bed reaches lower than the other ground pieces, so a thin continuous base slab (Y -8..-7) runs under the whole footprint. It is the bottom of the ground: the model attributes are `BoundsMin` = (-184, -8, -132) and `BoundsMax` = (184, 40, 132), the outer faces of the boundary walls. Existing floors were not moved.

## Top-down layout (not to scale; 1 char is about 6 studs)

```
 Z=-128 +----------+-----------------------------------------------------------+----------+
        |          |  NORTH ALLEY (flank)   . dumpster .  pallets  . dumpster  |          |
        |          |   [CNT==][CNT==]  [CNT==]   [CNT==]   [CNT==]  (2-high)   |          |
        |  SABLE   |)  G1  car    car  car  .  car   car    car   car    G1  (|  TALON   |
        |  DEPOT   |    ~~      bar      @taxi      bar       ~~               |  FREIGHT |
        |          |  lamp  car/   bar      booth     bar   \car    lamp       |  GATE    |
        | s  s  |  |            ramp/[========DOCK y4========]  crates         |  |  s  s |
 Z=-50  |          |  plaza +=====D=======================================D====+ plaza    |
        | s  s  |  |  phone |  shop  col     +----------+     col  shop   |phone |  s  s |
        |          |)  G2   D  counter  benches|TICKET OFF|benches counter  D   G2  (|      |
        |          |        | col     col     +----------+     col     col |       |   |
        | s  s  |  |        D  trolley        [PYLON+benches]   trolley    D       |  s  s |
 Z=21   |          |  planter+=====D===========+--OFFICE--+==========D=====+planter|  |
        | s  s  |  | lockers  vend  vend  /stairs| 2 storey |stairs\  vend  vend lockers|  s s |
        |          |)  G3  bench news   cart     +----D-----+   cart   news bench  G3  (|      |
        |          |  lamp - - - - - - PLATFORM A EDGE - - - - - - - - - lamp |          |
 Z=60   | s  s  |  |#steps#  [handcar]  [==TRAIN CAR walk-thru==] [FLATCAR] #steps#|  s  s |
 Z=74   |          |  - - - - - - - - PLATFORM B (canopy y15) - - - - - - - |          |
        |          |    post  advert  bench  post  advert  bench  post        |          |
 Z=92   | s  s  |  |)  G4 bar  [BUS walk-thru]   bar [island] bar   [BUS walk-thru] bar G4 (|  s s |
 Z=113  |          +=====D==========D=============D==============D=========D=====+          |
        |  tunnel >  ||  SERVICE TUNNEL  ||   valve  crates  valve  ||       ||   < tunnel  |
 Z=128  +----------+-----------------------------------------------------------+----------+
       X=-180    -122  -100                    0                     100   122          180

 |  )  (  screen wall (14 tall) with gaps G1..G4; each gap is a fenced corridor (fins)
 |       spawn-side baffle wall behind every gap      s  team spawn
 D       doorway (>= 6 wide, >= 9 tall)               [CNT==] double-stacked container (18 tall)
 ||      tunnel zig-zag baffles                       ~~ / car  derelict cars,  bar  jersey barrier
```

## Lanes

| Lane | Band | Range | Character |
|---|---|---|---|
| North: loading yard | Z -108..-50 | long to mid | Open asphalt broken up by parked cars, jersey barriers, a taxi booth in the centre and a raised loading dock (Y 4) against the hall. Cover is every 15 to 25 studs along any east-west crossing. |
| Middle: terminal hall | Z -48..19 (interior) | close to mid | The hall is split into west and east halves by the ticket office block (Z -40..-6) and the departures pylon (Z 0..12). They are joined by three passages: north (8 wide), centre (6 wide) and south (7 wide, in front of the office door). Columns, counters with glass, benches and shops give cover inside each half. |
| South: platforms and bus bays | Z 21..113 | mid | Platform A, the sunken track bed, Platform B and the bus bays. You can walk through the passenger car on the tracks and both buses (doors on both sides, open windows). |
| North flank: alley | Z -128..-116 | close | A 12-wide alley behind 18-tall container stacks. It has entrances at both ends and through the gaps between the stacks. |
| South flank: service tunnel | Z 115..128 | close | A roofed tunnel (ceiling Y 12) with mouths opening straight into each spawn and doors to the bus bays at X -70, 0 and +70. Zig-zag baffles near each end stop end-to-end shots. |

Cross-connections let players rotate between lanes:

- The plazas at X +-100..122 run north to south along each side.
- The hall has side doors at Z -36 and Z 8, and north and south doors at X +-61 and X +-65.
- The office ground floor is a walk-through between the hall and Platform A.
- The track bed can be crossed through the train car's bridge plates, through the stairs at X +-100, or by jumping across.
- The tunnel's centre door opens into the bus-bay island.

## Power positions and counters

1. **Control office, upper floor (Y 13).**
   - **What it gives:** big south windows (sill at Y 16.5) overlook Platform A, the train car and Platform B. A window through the hall's south wall (Y 15.5..19) looks down into the southern half of the hall. Consoles and map tables give crouch cover.
   - **Counters:**
     - Two entrances: exterior stairs on the west and east sides, each with a 7-wide door at the top. A team holding the room has to watch both.
     - The window band can be shot into from the platforms, from the train-car windows and from the hall.
     - The ground floor below is a separate room. Holding it cuts off the stairs' approach.
     - The roof (Y 23) cannot be reached.
2. **Loading dock (Y 4).**
   - **What it gives:** a raised view over the whole yard.
   - **Counters:**
     - The dock is open on three sides, with only crates and a forklift for cover.
     - You can climb it by the stairs at each end, by the forklift ramp, or by jumping from the yard.
     - The hall's north doors at X +-61 sit right beside it.
3. **Train car.** A long, protected corridor through the centre of the south lane.
   - **Counters:**
     - The doors on both sides line up with the bridge plates, so grenades and shots can come in from both platforms.
     - The open windows let players on the platforms (who stand 3.4 studs higher than the bed) shoot down into it.
     - The flatcar is a second crossing point to the east.
4. **Ticket office and departures pylon.**
   - **What they give:** the hall's centre. Whoever holds the passages controls rotations between the hall's halves.
   - **Counters:**
     - The three passages are each short, so they are easy to flash or flank.
     - The office ground floor gives a back door into the south passage.

Rule of thumb used throughout: every strong spot has at least two ways in, at least one of them from a different height or angle, and no spot can be reached that was not designed to be. The container stacks are 18 tall. Booths, newsstands and vending machines are under 8 tall, and nothing tall enough to climb from sits next to them.

## Spawn logic

- **Sable** spawns in the west depot (X -180..-122) and **Talon** at the east freight gate (X 122..180). The layout is mirror-symmetric across X = 0, which keeps it fair. Only cosmetic colours differ between the two sides.
- There are 10 team spawns per side, in two columns (|X| = 150 and 167) spread from Z -100 to 108, all facing the map centre. The team centroids are about 317 studs apart, and the closest enemy spawn pair is 300 studs apart.
- Each base is closed off by a 14-tall screen wall with four exits:
  - G1 to the yard
  - G2 to the plaza and hall side doors
  - G3 to Platform A
  - G4 to the bus bays
  - The tunnel mouth acts as a fifth exit.
- Every gap is a short fenced corridor 16 studs deep (fins at |X| 112..128). Only shallow-angle lines can pass through it. A baffle wall on the spawn side (|X| 136..138) blocks those shallow lines, so no team spawn has an eye-level line into the shared play space. The spec checks this by casting 144 rays from each team spawn. The worst case is about 22 studs, into the tunnel mouth.
- There are 16 FFA spawns spread over every zone (depots, alley, yard, both hall halves, Platform A, office ground floor, Platform B, bus bays and tunnel). They are at least 20 studs apart from each other.
- Spawn parts sit on the floor (centre at Y 0.5), so CFrame + (0,3,0) stands a character on the ground.

## Objectives

All objective zones are invisible boxes in the `Objectives` folder, 10 studs tall, with their bottom face on the floor they sit on (see `docs/MAP_CONTRACT.md`). The layout is mirror-symmetric, so every placement below is either on the centre line or mirrored.

**Domination (flags).** The team-spawn centroids are at X -158.5 and +158.5.

| Flag | Centre (X, Z) | Size | Where |
|---|---|---|---|
| A | (-60, -22) | 18 x 18 | West hall half, between the west ticket counter, the waiting benches and the column pair. Nearer Sable. |
| B | (0, 46) | 20 x 14 | Platform A, right outside the office's south door. Overlooked by the office's upper windows and the train car. |
| C | (60, -22) | 18 x 18 | East hall half, mirror of A. Nearer Talon. |

**Hardpoint.** Five zones, rotating through all three lanes. Each hop is at least 88 studs, and every zone is more than 100 studs from a team spawn.

| Order | Zone | Centre (X, Z), floor Y | Size | Hop to next |
|---|---|---|---|---|
| 1 | Ticket hall centre (passage between the ticket office and the pylon) | (0, -3), 0 | 28 x 16 | 112 |
| 2 | West bus bays (between the west bus and the bay island) | (-40, 102), 0 | 26 x 18 | 165 |
| 3 | Loading dock deck | (0, -58), 4 | 26 x 16 | 88 |
| 4 | Control office ground floor | (0, 30), 0 | 24 x 16 | 96 |
| 5 | Service tunnel, east of the centre door | (30, 121), 0 | 24 x 16 | 128 (back to 1) |

**Search and Destroy.** `SnDAttackBase` = `"Sable"`: Sable attacks from the west depot in round 1, and Talon defends the east. Both bomb sites are on the east side.

| Site | Centre (X, Z) | Size | Where and cover |
|---|---|---|---|
| A | (66, -68) | 14 x 14 | East loading yard. The parked car at (48, -78), the jersey barrier at X 75..85, the pallets by the hall's north-east door and the dock's east stairs give cover. |
| B | (42, 102) | 14 x 14 | East bus bays, between the bay island and the east bus. The barriers at X 29..39, the island planter and the walk-through bus give cover. |

The sites are about 170 studs apart. Attackers reach A through the yard or the north alley, and B through the bus bays or the service tunnel. Defenders rotate between them through the east plaza or the east half of the hall.

## Sightline notes

- The longest open lines are east-west across the yard. Rows of parked cars, barriers and the centre taxi booth break any line longer than about 60 to 80 studs at standing eye height. Crouching behind cover always works.
- Inside the hall, the side doors (Z -40..-32 and 4..12) are lined up with the ticket office and the pylon. Shots from door to door are blocked, and the hall plays as two connected rooms.
- Along Platform A, the office block and the newsstands cut the platform into thirds.
- The track bed is 3 studs lower than the platforms. That gives a "trench" lane where players are partly hidden from the platforms but exposed to the office windows.
- In the tunnel, the zig-zag baffles at |X| 98..108 stop shots from one end to the other. The centre valve units and crates keep fights within about 40 studs.
- The belts in front of the spawn gaps (|X| 100..122) contain a phone booth, a planter and a bank of lockers. These stop long north-south lines past the gaps.

## Design principles drawn from classic arena-FPS maps (own analysis)

- **Three lanes plus flanks.** Every fight should offer a choice between at least two routes. Fast shooters reward momentum, so routes have to connect often. Without that, players get stuck pushing a single choke point.
- **Spawns that are protected but not hidden.** Spawns should not see into the action, and the action should not see into spawns. Exits are fenced corridors with baffles, not open doorways. This stops spawn-killing without walling off a team.
- **Stairs as a cost.** Height wins fights, so every elevated position costs a predictable climb and has a second entrance. The office has two stairs. The dock has two stairs and a ramp.
- **Readable silhouettes.** Each zone has its own material and colour: tile hall, asphalt yard, pebble track bed, rusted roofs, teal and red accents. Players should always know where they are at a glance and be able to call positions ("dock", "car", "pylon", "tunnel").
- **Cover cadence.** Any open crossing has something to break line of sight every 15 to 25 studs. Crouch-height cover (cars, barriers, benches) differs from full cover (booths, pylons, containers), so players learn which cover stops what.
- **Movement over memorisation.** Shapes are kept simple and flat: no ledges to snag on, steps of 1 stud or less, and doors at least 6 x 9. Movement is the skill being tested, not navigation.
