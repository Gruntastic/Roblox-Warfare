# Roblox Blox Ops: Architecture & Interface Contracts

Source of truth for cross-team boundaries. Change a contract here first, then the code.

## Layout (Rojo: default.project.json)
| Path | Instance | Owner |
|---|---|---|
| src/shared/Config/* | ReplicatedStorage.Shared.Config | Lead (Combat/Progression data) |
| src/shared/Pure/* | ReplicatedStorage.Shared.Pure | Lead. Pure, dependency-free, Lune-testable. No `game` access. |
| src/shared/Net.luau, Types.luau | ReplicatedStorage.Shared | Lead. Remote names + payload types. |
| src/server/** | ServerScriptService.Server | Lead (Combat/Multiplayer/Progression) |
| src/server/Maps/<MapId>.luau | ServerScriptService.Server.Maps | Maps & Environment |
| src/client/init.client.luau, ClientState.luau | StarterPlayerScripts.Client | Lead |
| src/client/Controllers/* | StarterPlayerScripts.Client.Controllers | Lead (Combat: weapons, movement, camera) |
| src/client/UI/* | StarterPlayerScripts.Client.UI | UI/UX |
| tests/specs/*.spec.luau | Lune tests | each owner tests their own modules |

## Client module contract
Every ModuleScript in `Client/Controllers` and `Client/UI` is required by `init.client.luau`
and may export `init()` (connect signals; must not yield) and `start()` (spawned).
Modules talk to each other ONLY through `ClientState` signals/fields and `Net` remotes.

`ClientState` (src/client/ClientState.luau) fields: `matchState`, `profile`, `ammo[slot]`,
`deployed`, `equippedSlot`, `equippedWeaponId`, `ads`, `sprinting`, `objective` (latest ObjectivePayload),
`interacting` (Interact held; written by UI/Objectives).
Signals: `MatchStateChanged`, `ProfileChanged`, `AmmoChanged(slot, info)`, `KillFeed`,
`HitConfirm`, `DamageTaken`, `XPGain`, `MatchResults`, `Notify(text, kind)`,
`DeployedChanged(bool)`, `WeaponChanged(slot, weaponId)`, `AdsChanged(bool)`, `Fired(weaponId)`,
`ObjectiveChanged(payload)`, `ObjectiveEvent(kind, data)`.
Spectating (S&D) is signalled by the LocalPlayer attribute `COR_Spectating`, set by UI/Objectives and
read by CameraController.

## Remotes (src/shared/Net.luau, payloads in src/shared/Types.luau)
Client -> server: `Fire(shotId, slot, origin, direction)`, `Reload(slot)`, `Equip(slot)`, `Melee()`,
`SetLoadout(index, {primary, secondary, primaryAttachments, secondaryAttachments})`, `SelectLoadout(index)`,
`VoteMap(mapId)`, `RequestDeploy()`. Function: `GetProfile() -> ProfileSummary`.
Server -> client: `MatchState`, `KillFeed`, `HitConfirm`, `DamageTaken`, `AmmoState(slot, mag, reserve, reloading)`,
`XPGain`, `ProfileSync`, `MatchResults`, `Tracer(shooterUserId, origin, hitPos)`, `Notify(text, kind)`.

All client -> server remotes are validated (types, ranges, rate limits) on the server.
The client never reports damage, hits, XP, ammo counts or unlocks; it only reports intent.

## Match flow (server MatchService)
`Lobby` (no characters; loadout + map vote; countdown once minPlayers present)
-> `Countdown` (characters spawned, frozen) -> `Playing` (respawns after delay; score limit / time limit)
-> `Results` (results screen, XP awarded) -> `Lobby`.
Players joining during `Playing` stay in the lobby UI until they press Deploy (`RequestDeploy`).

## Map contract (src/server/Maps/<MapId>.luau)
```lua
return {
  id = "DustlineTerminal", displayName = "Dustline Terminal",
  lighting = { ClockTime = 15.5, Brightness = 2.2, ... }, -- Lighting properties applied by server
  atmosphere = { Density = 0.3, ... }?, -- optional Atmosphere properties
  build = function(): Model end, -- returns an UNPARENTED Model named "Map"
}
```
The built Model contains:
- `Geometry` Folder: anchored parts (CanQuery true so bullets collide). Keep total parts under ~2000.
- `Spawns` Folder: anchored Parts, Transparency 1, CanCollide/CanQuery/CanTouch false, size (2,1,2).
  Attribute `Team` = "Sable" | "Talon" for team spawns (>= 8 each), attribute `FFA` = true for FFA spawns (>= 12).
  LookVector faces into the play space. Positioned so a character placed at CFrame + (0,3,0) stands on the floor.
- `LobbyCamera` Part (transparent, anchored, CanQuery false): overview CFrame used by the lobby camera.
- Model attribute `KillY` (number): characters below this Y are killed.
- Optional `Objectives` Folder (later modes) with Parts named by objective, attribute `Mode`.
`build()` must work both in Studio edit mode and on the server, and must not require other project modules.

## Weapons and attachments (Phase 3)
- `src/shared/Config/Weapons.luau`: `WeaponDef` (see its exported types). Ids are short uppercase
  strings (`VK7`). Each weapon declares `anchors` (optic, muzzle, underbarrel?, magazine, leftHand),
  `sightOffset` (iron-sight eye point), `attachmentSlots` and `attachmentUnlocks` (attachment id ->
  weapon level). `unlockLevel` is the account level that unlocks the weapon.
- `src/shared/Config/Attachments.luau`: `AttachmentDef`. Slots: `Optic`, `Muzzle`, `Barrel`,
  `Underbarrel`, `Magazine`, at most one per slot. Modifiers are multipliers. Attachments are only
  ever earned by weapon level: none are sold or random.
- Attachment model parts are authored relative to the slot anchor:
  - Optic → `anchors.optic`.
  - Underbarrel → `anchors.underbarrel`.
  - Magazine → `anchors.magazine`, replacing the weapon part named `Magazine`.
  - Barrel → `anchors.muzzle`.
  - Muzzle → `anchors.muzzle`, moved forward by the equipped barrel's `muzzleExtend`.
- `src/shared/Pure/WeaponStats.luau`:
  - `validate(def, selection, weaponLevel, catalog)` is used by the server on `SetLoadout`.
  - `sanitize(...)` is used on profile load.
  - `resolve(def, selection, catalog) -> Effective` gives the stats both sides use; the server is
    authoritative.
  - `ratings(effective)` gives 0..100 values for UI bars.
- `src/shared/Pure/Pellets.luau`: a fixed shotgun pellet pattern shared by client and server. The
  client sends one aim direction.
- `WeaponModel.build(def, opts)` takes `opts.attachments` (a selection). It adds an Attachment named
  `Sight` at the effective `sightOffset`, which ADS aligns to, and an Attachment named `Muzzle`.
- Burst weapons: `rpm` is the rate inside a burst. The client enforces `burst.delay`; the server
  enforces `rpm` and ammo.

## Modes and objectives (Phase 4)

Mode tuning lives in `src/shared/Config/Modes.luau` (`TDM`, `FFA`, `DOM`, `SND`, `HP`, `KC`). Each map
supports every mode through its `Objectives` folder (`docs/MAP_CONTRACT.md`).

### Lobby vote
`MatchState.options` holds `VoteOption`s (map + mode pairings) while in the Lobby. The client votes
with `VoteMap(optionId)`. `MatchState.votes` is keyed by option id. The server plays the option with
the most votes; on a tie, the first listed option wins.

### Objective state (server -> client)
- `ObjectiveState(ObjectivePayload)` is sent whenever the objective changes, at most about 5 per
  second, and to each player when they join. It is mirrored in `ClientState.objective` and
  `ClientState.ObjectiveChanged`. `kind = "None"` for TDM and FFA.
- `ObjectiveEvent(kind, data)` is for one-off announcements, mirrored in `ClientState.ObjectiveEvent`.
  Team ids are `"Sable"` / `"Talon"`, and user ids are numbers.

| kind | data | When |
|---|---|---|
| `ZoneCaptured` | `{ id, team }` | Domination flag captured |
| `HardpointMoved` | `{ id }` | a new hardpoint goes live (also at first activation) |
| `BombPickedUp` | `{ userId }` | an attacker takes the bomb |
| `BombDropped` | `{ position }` | the carrier died or left |
| `BombPlanted` | `{ site, userId }` | |
| `BombDefused` | `{ userId }` | |
| `BombDetonated` | `{ site }` | |
| `RoundStart` | `{ number, attackers }` | S&D round countdown begins (players are frozen) |
| `RoundLive` | `{ number }` | S&D round unfreezes |
| `RoundEnd` | `{ winner, reason }` | reason: `Elimination`, `Detonated`, `Defused`, `Time` |
| `SidesSwapped` | `{}` | S&D halftime |
| `TagConfirmed` | `{ userId, victimUserId }` | Kill Confirmed: enemy tag collected (+1 team score) |
| `TagDenied` | `{ userId, victimUserId }` | Kill Confirmed: friendly tag recovered |

### Server-made world objects
The server creates these, so every client sees them:
- `workspace.DogTags`: a Folder of anchored, non-colliding Parts named `Tag`, with attributes `Team`
  (the victim's team) and `VictimUserId`. The server picks a tag up when a living player's root is
  within 4 studs. Clients may decorate tags, for example a billboard coloured by friend or foe, but
  must not move them.
- `workspace.Bomb`: while dropped or planted, an anchored Part named `Bomb`, with attribute `State`
  (`"Dropped"` | `"Planted"`). While carried, a small non-colliding part named `CarriedBomb` is welded
  to the carrier's UpperTorso / Torso.

### Interact (S&D plant and defuse)
The client sends `Interact(true)` when the interact input is pressed (E, ButtonX, or the touch
button) and `Interact(false)` on release or when the character dies. The server decides what that
means:
- Plant: the bomb carrier, an attacker, standing in a site.
- Defuse: a defender within 6 studs of the planted bomb.
The action completes only if the player stays alive, in range and holding for the whole duration.
Moving more than 3 studs from where they started cancels it. Progress is visible to everyone in
`ObjectivePayload.bomb.actionUserId / actionKind / actionEndsAt`.

### Free-for-All
`MatchState.teamMode = false`, `teams = {}`, and players have no team. `scoreLimit` counts one
player's kills. `PlayerLine.score` is the scoreboard score; the race is decided by `kills`.
`MatchResults.winnerUserId` is the top player (nil on a tie).

### Respawns in S&D
There are no respawns during a round: dead players stay dead until the next round's countdown, when
everyone is respawned frozen at their side's spawns. The client should spectate a living teammate
while dead and `ClientState.objective.round.live` is true, and show who is alive per team.
