# Call of Roblox (working title)

An original, fast-paced multiplayer first-person shooter for Roblox. Working title is subject to
a trademark and Roblox policy review before release. All code, geometry and branding in this
repository are original; no third-party game assets, maps, sounds, logos or code are used.

## Status
Phase 2 vertical slice: one original map (Dustline Terminal), two original weapons (VK-7 Vanguard
assault rifle, P-12 Warden pistol), Team Deathmatch, lobby with loadouts and map vote, HUD,
account XP + weapon XP, session-locked DataStore persistence. See `docs/REPORT.md` for what was
verified versus what is still untested.

## Layout
```
default.project.json   Rojo project (ReplicatedStorage.Shared, ServerScriptService.Server, StarterPlayerScripts.Client)
src/shared/Config      Data-driven tuning: weapons, progression, modes
src/shared/Pure        Dependency-free gameplay logic (damage, hitboxes, weapon state, XP, profiles, locks); unit tested
src/shared/Net.luau    Remote contract; Types.luau payload types
src/server/Services    DataService, ProgressionService, CombatService, MatchService, MovementGuard
src/server/Maps        One module per map (procedural, data-driven geometry)
src/client             ClientState store, Controllers (weapons, movement, camera, effects), UI
tests/                 Lune test runner + specs
tools/studio_sync.py   Mirrors the source tree into a live Studio session when Rojo live-sync is unavailable
docs/                  Contracts, map design notes, QA checklist, phase reports
```

## Building
Requires [Rojo](https://rojo.space) 7.4+ and [Lune](https://lune-org.github.io/docs) 0.8+.
```
rojo build default.project.json -o CallOfRoblox.rbxl   # place file
rojo serve                                            # live-sync with the Rojo Studio plugin
lune run tests/run.luau                               # unit tests
```
Static analysis: `rojo sourcemap default.project.json -o sourcemap.json` then
`luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src`.

## Persistence setup (requires your Roblox account)
DataStores only work in a **published** place. In Studio: File > Publish to Roblox, then
Game Settings > Security > enable "Enable Studio Access to API Services". Without this the server
falls back to clearly-flagged temporary profiles and shows a warning banner; nothing is saved.

## Controls (PC / controller)
Move WASD, Sprint Shift / L3, Crouch C or Ctrl / B, Jump Space / A, Fire LMB / R2, Aim RMB / L2,
Reload R / X, Swap 1, 2, wheel / Y, Melee V / R3, Scoreboard Tab.
