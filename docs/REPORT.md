# Status report: Phases 1–3

Last updated: 2026-10-20. Phase 2 evidence: commit `8a766db`. Phase 3 evidence: the Phase 3 playtest commit and later.

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

## Phase 3: weapons, attachments, Gunsmith

### What shipped
- 26 weapons (22 primaries in six classes, four secondaries) and 18 attachments across five slots.
  See `docs/WEAPONS.md` for the full table.
- `WeaponStats.resolve` applies attachments to a weapon definition. The server validates and
  sanitises every loadout against the weapon's slots and the player's weapon level, so attachment
  stats are server-authoritative like everything else.
- Gunsmith screen with a 3D preview, slot list, option cards with pro and con chips, stat bars with
  deltas, and a details panel. DONE saves, BACK discards, RESET clears.
- Attachment-aware viewmodels and world models, shotgun pellet patterns (deterministic on client
  and server), burst fire, a built-in sniper scope overlay, and optic reticles.

### Automated
100 tests, 100 passed (`lune run tests/run.luau`). New coverage: roster contracts for all 26
weapons, attachment resolution and validation, magazine rounding, pellet determinism, and optic
reticles. `luau-lsp analyze` (strict) is clean over `src/`.

### Studio playtest (single client)

| Area | Result | Evidence |
|---|---|---|
| Class-grouped weapon picker with unlock gating | Pass | `qa/phase3/02-lobby-saved.jpg` (TR-6 locked at 42) |
| Gunsmith: equip four attachments, live stat deltas | Pass | `qa/phase3/01-gunsmith-vk7.jpg` (mag 45, reload 2.42 s, ADS 304 ms) |
| Gunsmith DONE saves through the server; summary shows "+4" | Pass | `02-lobby-saved.jpg` ("SAVED") |
| RESET clears all slots; BACK closes without saving | Pass | UI state read after each click |
| Attachments on the first-person viewmodel | Pass | `03-viewmodel-attachments.jpg` |
| Extended magazine changes server ammo (45 / 180) | Pass | HUD after spawn, fed by server AmmoState |
| Holo and red-dot reticles centred in the glass while aiming (after fix) | Pass | `05-holo-reticle.jpg`, `09-reddot-burst-ammo.jpg` |
| Suppressed fire: no muzzle flash; impacts render | Pass | `06-suppressed-fire.jpg`; no flash objects on the viewmodel |
| Sniper scope overlay, viewmodel hidden, no optic reticle on top | Pass | `07-sniper-scope.jpg` |
| SW-3 burst: one click fires exactly 3 rounds | Pass | HUD 30 → 27 after a single click |
| Server rejects an unknown attachment and an optic on a sniper | Pass | Two "Invalid attachments" notices |
| SetLoadout rate limit drops rapid repeats | Pass | 4 of 5 back-to-back saves dropped silently |
| Studio scripts identical to the repo | Pass | `studio_verify.py`: 43 scripts, 0 mismatched |

### Defects found in the Phase 3 playtest and fixed
1. Optics had no reticle; the `reticle` field in the attachment config was never drawn. The HUD now
   draws a dot, holo ring or chevron at the point of aim, fading in over the second half of ADS.
   Before and after: `04-reddot-before-fix.jpg`, `05-holo-reticle.jpg`.
2. The HUD ammo counter only changed on server syncs (empty mag, reload, rejected shot), so it sat
   at the full count while firing. The client now shows its predicted count each shot; the server
   remains authoritative and corrects it on every sync. This was also present in Phase 2.
3. Escape is reserved by the Roblox system menu. Pressing it opened that menu, which then swallowed
   clicks on the Gunsmith. Backspace (and gamepad B) now go back; the hint text says so.
4. Lobby text showed faintly through the Gunsmith preview. The backdrop is now opaque.
5. QuickMag on small sniper magazines rounded back up to the full size. Reductions now always cost
   at least one round.

### Studio-only QA hooks
Both only work in Studio. `QA_GrantLevels` also requires temporary (unpublished) profiles.
- `workspace:SetAttribute("QA_GrantLevels", 30)` raises the account and every weapon to that level.
- `workspace:SetAttribute("QA_HoldLobby", true)` keeps the lobby countdown from running out; set it
  to nil to let the match start.

## Written but not yet exercised

- **Player-vs-player combat**: lag-compensated hit registration, damage and headshots, kill credit,
  assists, kill XP, anti-farm decay, the per-minute XP cap, spawn protection, team-kill prevention.
- **DataStore persistence**: session locking, autosave, BindToClose, retries and v1→v2 migration
  against real DataStores. Needs a published place with Studio API access enabled.
- Reload animation, weapon switching, melee, sprint and crouch have not been checked visually.
- Attachment effects on damage and range against a real target (needs two players).
- Pistol, LMG, marksman and SMG viewmodels other than the ones named above were not inspected one by one.
- Gunsmith on touch and gamepad.
- MovementGuard speed rubber-banding has not been triggered.
- The third-person world weapon, as seen by other players.
- Map vote with more than one map (only Dustline Terminal exists).
- Late-join DEPLOY button flow.
- Touch, gamepad and small-screen layouts.
- Performance with 12 players.

## Known issues and notes

- Studio prints `rbxassetid://203785492 … Asset type does not match` three times at play start. That
  id does not appear anywhere in `src/`. It is likely from Studio or core scripts; to be confirmed.
- Weapon damage ratings in the Gunsmith look low for rifles (VK-7 shows 14/100) because the scale
  runs to sniper damage. Rescaling per class is a polish item.
- The Gunsmith preview starts at a fixed angle and auto-spins, so some screenshots catch it edge-on.
- If a loadout is changed outside the editor (for example by a test script), the editor keeps the
  older draft and shows UNSAVED CHANGES until the slot is reselected. Normal play does not hit this.
- Studio patching: `tools/studio_patch.py` moves its base forward when it writes a patch. If the
  patch is then not applied, reset that file in `studio_base` from git before generating again.
- The HUD stays visible under the death screen overlay. This is acceptable for now; revisit in polish.
- Results with a single player always show DRAW (0–0), which is correct behaviour.
- The game title "Call of Roblox" still needs the trademark and policy review called for in the brief
  before any public release.
- Studio sync is done through MCP scripts, not the Rojo plugin. `tools/studio_patch.py` sends only
  changed hunks with checksum verification, and `tools/studio_verify.py` audits the whole tree.

## Needs the owner

1. **Publish the place and enable Studio API access** (Game Settings → Security), so DataStore
   persistence can be tested for real.
2. ~~Connect a GitHub repository~~ Done: https://github.com/Gruntastic/roblox-warfare (`main`).
3. **Run one two-player test**, either Studio Test → Clients and Servers with 2 players, or a
   private server, to clear the combat items above. `docs/QA_CHECKLIST.md` lists the steps.
