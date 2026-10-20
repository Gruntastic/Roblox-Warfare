# Status report: Phases 1–2 (vertical slice)

Last updated: 2026-10-20. Commit `8a766db` and later.

This report separates what was **executed with evidence** from what is **written but not yet exercised**.
Nothing below is claimed as tested unless it was run.

## Summary

The vertical slice is playable end to end in Roblox Studio with one client:
lobby with loadouts and map vote → 5 s frozen countdown → Team Deathmatch on Dustline Terminal →
results screen with XP breakdown → back to lobby, with XP carried over.

Player-vs-player combat (hits, damage, kills, assists) has **not** been exercised in Studio, because
the Studio tooling available here runs a single client. It is covered by unit tests of the pure logic
only. Multi-client testing is the top open QA item.

## Verified by execution

### Automated (Lune, `lune run tests/run.luau`)

60 tests, 60 passed. Coverage: leveling curves, damage falloff and hit zones, weapon state machine
(token-bucket fire rate, jitter tolerance, reload, equip), OBB hitbox rays, profile schema migration
and sanitising, session lock, match rules and team picking, Dustline Terminal map contract
(spawn counts, KillY, bounds).

Static checks: `luau-lsp analyze` in strict mode over all of `src/` reports no errors.

### Studio playtest (single client, unpublished place)

| Area | Result | Evidence |
|---|---|---|
| Server boot, service init order | Pass | Console: `[CallOfRoblox] server started`, no script errors |
| DataStore fallback when unpublished | Pass | Console warning plus the red in-lobby banner; profiles marked temporary |
| Phase loop Lobby → Countdown → Playing → Results → Lobby | Pass, twice | Console phase log |
| Spawn on team base, frozen during countdown, unfrozen at start | Pass | Server state read, Frozen attribute |
| First-person viewmodel (VK-7) | Pass | `docs/qa/phase2/02-hud.jpg` |
| Firing reaches the server; server-authoritative ammo syncs back | Pass | 14 Fire events from a 1 s hold (VK-7 rate); AmmoState received |
| No shots sent during the countdown (after fix) | Pass, weak | 0 Fire events while frozen; click timing not independently confirmed |
| Death by falling below KillY, then respawn after 3 s | Pass | Died after 0.1 s, respawned after 3.4 s at a Sable spawn |
| Death screen and kill feed | Pass | `docs/qa/phase2/03-death-killfeed.jpg` |
| HUD: health, ammo, compass, team scores, timer | Pass | `02-hud.jpg` |
| Lobby: loadouts, editor, rank, map vote, operator list | Pass | `01-lobby.jpg` |
| Results: outcome, team scores, player stats, XP breakdown, animated rank bar | Pass | `04-results.jpg` (Draw, 1 death, +517 XP) |
| XP persists across matches within the session; lobby rank refreshes | Pass (after fix) | `05-lobby-after-match.jpg` shows 514/1000 |
| Studio scripts identical to the repo | Pass | `tools/studio_verify.py`: 39 scripts, 0 mismatched |

### Defects found in the playtest and fixed

1. Lobby operator list was empty before teams were assigned (only "+1 unassigned"). Fixed.
2. Clicking during the countdown showed a muzzle flash and decremented the local magazine
   (the server correctly rejected the shot). Client now gates firing on the Playing phase.
3. Lobby rank bar did not update after match-end XP (no profile sync). Fixed.
4. Teams and scores from the finished match carried into the next lobby. Fixed.

## Written but not yet exercised

- **Player-vs-player combat**: lag-compensated hit registration, damage and headshots, kill credit,
  assists, kill XP, anti-farm decay, the per-minute XP cap, spawn protection, team-kill prevention.
- **DataStore persistence**: session locking, autosave, BindToClose, retries and v1→v2 migration
  against real DataStores. Needs a published place with Studio API access enabled.
- ADS, reload animation, weapon switching, melee, sprint and crouch were not checked visually in this
  session.
- MovementGuard speed rubber-banding has not been triggered.
- The third-person world weapon, as seen by other players.
- Map vote with more than one map (only Dustline Terminal exists).
- Late-join DEPLOY button flow.
- Touch, gamepad and small-screen layouts.
- Performance with 12 players.

## Known issues and notes

- Studio prints `rbxassetid://203785492 … Asset type does not match` three times at play start. That
  id does not appear anywhere in `src/`. It is likely from Studio or core scripts; to be confirmed.
- The HUD stays visible under the death screen overlay. This is acceptable for now; revisit in polish.
- Results with a single player always show DRAW (0–0), which is correct behaviour.
- The game title "Call of Roblox" still needs the trademark and policy review called for in the brief
  before any public release.
- Studio sync is done through MCP scripts, not the Rojo plugin. `tools/studio_patch.py` sends only
  changed hunks with checksum verification, and `tools/studio_verify.py` audits the whole tree.

## Needs the owner

1. **Publish the place and enable Studio API access** (Game Settings → Security), so DataStore
   persistence can be tested for real.
2. **Connect a GitHub repository** so the source tree is pushed and not only held in the session
   container. A git bundle is mirrored to the project files in the meantime.
3. **Run one two-player test**, either Studio Test → Clients and Servers with 2 players, or a
   private server, to clear the combat items above. `docs/QA_CHECKLIST.md` lists the steps.
