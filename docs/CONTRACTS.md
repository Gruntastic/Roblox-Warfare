# Call of Roblox: Architecture & Interface Contracts

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
`deployed`, `equippedSlot`, `equippedWeaponId`, `ads`, `sprinting`.
Signals: `MatchStateChanged`, `ProfileChanged`, `AmmoChanged(slot, info)`, `KillFeed`,
`HitConfirm`, `DamageTaken`, `XPGain`, `MatchResults`, `Notify(text, kind)`,
`DeployedChanged(bool)`, `WeaponChanged(slot, weaponId)`, `AdsChanged(bool)`, `Fired(weaponId)`.

## Remotes (src/shared/Net.luau, payloads in src/shared/Types.luau)
Client -> server: `Fire(shotId, slot, origin, direction)`, `Reload(slot)`, `Equip(slot)`,
`SetLoadout(index, {primary, secondary})`, `SelectLoadout(index)`, `SetStance(stance)`,
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
