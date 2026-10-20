# Map contract (Phase 4)

Every map is one ModuleScript at `src/server/Maps/<MapId>.luau`. It must support all six modes:
Team Deathmatch, Free-for-All, Domination, Search and Destroy, Hardpoint and Kill Confirmed.
Every map has a spec at `tests/specs/map_<name>.spec.luau` that calls
`tests/lib/MapContract.luau`, plus a design doc at `docs/maps/<MapId>.md`.

All maps are original designs. Do not copy or trace layouts, names or landmarks from any existing
game. Inspiration from real-world places and architecture is fine.

## Module exports

```lua
return {
  id = "FrostRelay",                -- equals the file name and the entry in Config/Modes Match.Maps
  displayName = "Frost Relay",
  lighting = { ... },               -- only valid Lighting properties (see the spec's allow-list)
  atmosphere = { ... },             -- only valid Atmosphere properties
  build = function(): Model end,    -- returns an UNPARENTED Model named "Map"
}
```

`build()` may only use `Instance.new`, `Vector3`, `CFrame`, `Color3`, `Enum`, `NumberSequence`,
`ColorSequence`, `BrickColor` and `math`. It must not require other modules or touch `game`, so the
same code runs on the server, in Studio edit mode and under Lune.

## Model children and attributes

| Child / attribute | Rules |
|---|---|
| `Geometry` Folder | Every BasePart anchored and `CanQuery = true` (bullets must hit it). Total BaseParts 300 to 2500. |
| `Spawns` Folder | Spawn parts, see below. |
| `Objectives` Folder | Objective zone parts, see below. |
| `LobbyCamera` Part | Transparent, anchored, `CanQuery = false`. Its CFrame is the lobby overview shot. |
| attribute `KillY` | number below the lowest floor (characters below it die). |
| attribute `BoundsMin`, `BoundsMax` | Vector3: the playable box. All geometry must sit within it (2 studs tolerance). `BoundsMin.Y` is the bottom of the ground: collidable ground parts reaching down to it must cover every point of the footprint, so there is never a hole to the void (water is a shallow floor, not a pit). |
| attribute `SnDAttackBase` | `"Sable"` or `"Talon"`: the base whose team spawns attackers use in round 1 of S&D. |

## Spawns

- Parts, `Transparency 1`, anchored, `CanCollide / CanQuery / CanTouch = false`, size exactly (2, 1, 2).
- A character is placed at `CFrame + (0, 3, 0)`, so the part's centre sits 0.5 above the floor top.
- `LookVector` is horizontal and faces into the map, with at least 8 studs of open space ahead at eye level.
- Team spawns: attribute `Team = "Sable"` (at least 8) and `Team = "Talon"` (at least 8). They are
  clustered at opposite ends. The two team centroids are at least 150 studs apart, and no Talon spawn
  is within 100 studs of a Sable spawn (smaller maps: at least 60% of the bounds' longer side).
- FFA spawns: attribute `FFA = true`, at least 16, spread over the whole map, pairwise at least 20 apart.
- No team spawn has an unobstructed eye-level (Y + 4.5) horizontal sightline longer than 120 studs in
  any direction within 60 degrees of the enemy base. Shield spawns with walls, buildings or terrain.
- Every spawn has a collidable floor directly under it, and nothing solid in a 2 x 5.4 x 2 box above it.

## Objectives

Each objective is an invisible box part in the `Objectives` folder:
`Transparency 1`, anchored, `CanCollide / CanQuery / CanTouch = false`.
The part's box is the zone. A player counts as inside when their HumanoidRootPart's position is in
the box. Rotation is allowed only about +Y. The bottom face sits on the floor (within 0.5 stud) and
`Size.Y` is at least 8.

| Kind (attribute `Kind`) | Other attributes | Count | Placement |
|---|---|---|---|
| `Flag` | `Label` = `"A"`, `"B"`, `"C"` | exactly 3 | A nearer the Sable base, C nearer the Talon base, B near the middle (the difference between its distances to the two team-spawn centroids is at most 25% of their separation). Zones are 14 to 22 studs across. |
| `Hardpoint` | `Order` = 1..N | 4 to 6 | Rotate in Order. Consecutive zones at least 40 studs apart. None within 40 studs of a team spawn. Zones are 16 to 30 studs across, and ideally each is a room or a defined structure. |
| `BombSite` | `Label` = `"A"`, `"B"` | exactly 2 | Both nearer the defenders' base (the base opposite `SnDAttackBase`) than the attackers'. Sites at least 50 studs apart. Zones are 10 to 16 studs across. Each has cover. |

The zone centre must have a collidable floor under it and no solid part at the character position
(the same check as spawns), so the objective can always be stood on.

## Lobby camera, lighting and look

- The lobby camera should frame the map's signature landmark.
- Original art direction per map. Use materials and colours, not imported meshes or decals.
- Keep `GlobalShadows` on. Avoid fog that hides players inside 250 studs.

## Size and performance

- Recommended playable areas: small 240 x 180, medium 360 x 260 (Dustline), large 420 x 300.
- Under 2500 BaseParts. Prefer large parts over many small ones. No unanchored parts.
- No scripts, sounds or external asset ids inside the map.

## Clarifications
- Zones of different kinds may overlap (for example Flag B and Hardpoint 1 on the same bridge):
  only one mode runs at a time.
- Hardpoint spacing is checked between consecutive zones in rotation order, including last to first.
- Sightline and cover rules are only partly automated (horizontal rays, opaque parts). Elevated
  positions overlooking a spawn must be blocked by design (parapets, walls), and are reviewed in Studio.
