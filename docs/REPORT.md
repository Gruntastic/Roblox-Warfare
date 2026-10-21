# Status report: Phases 1–8

Last updated: 2026-10-20. Phase 2 evidence: commit `8a766db`. Phase 3 evidence: the Phase 3 playtest commit and later. Phase 4 evidence: commit `13e75e8`. Phase 5 evidence: commit `e334c3d` and the Phase 5 report commit (screenshots in `docs/qa/phase5`).

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
| Server boot, service init order | Pass | Console: `[CallOfRoblox] server started` (now `[BloxOps]`), no script errors |
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

## Phase 4: maps and modes

### What shipped
- Six maps: Dustline Terminal (now with objectives), Frost Relay, Iron Borough, Red Mesa, Breakwater
  and Ashwood Estate. Every map is built from code and checked by one shared contract
  (`docs/MAP_CONTRACT.md`, `tests/lib/MapContract.luau`): bounds, no holes, spawn spacing and sight
  lines, objective placement for every mode.
- Six modes: Team Deathmatch, Free-for-All, Domination, Search and Destroy, Hardpoint and Kill
  Confirmed. Objective scoring, plant/defuse, round flow and tag pickup all run on the server;
  objective XP goes through the same ledger and per-minute cap as kill XP.
- The lobby offers three map + mode pairings to vote on; the HUD shows flags, the hardpoint, the
  bomb state and FFA standings.

### Automated
232 tests pass (`lune run tests/run.luau`), type check clean (`luau-lsp analyze`, 0 errors).

### Studio playtest (single client, commits `6ddafa8` then `13e75e8`)
Studio was synced from GitHub at the commit with `tools/studio_fetch.py` (every file checksum-checked;
HttpEnabled restored to off afterwards). Screenshots are in `docs/qa/phase4/`.
- Lobby vote: three cards render; clicking one marks it, shows 1 VOTE, and the header switches to
  that pairing (Iron Borough / Kill Confirmed) (01, 02).
- Kill Confirmed, Iron Borough: dying drops a team-coloured tag on the floor; walking over your own
  team's tag removes it, scores no team point, and pays "Kill Denied +50" on the results (04).
- Domination, Breakwater: standing on Flag B captures it (HUD B turns blue) and the team score ticks
  every 5 s (3, then 15, then 17).
- Search and Destroy, Iron Borough: "You have the bomb" banner; holding E on site A plants it
  (+200, "Bomb planted at A", 40 s timer); the detonation wins round 1 and round 2 starts with the
  bomb re-issued and the round pips at 1–0 (05, 06).
- Hardpoint, Ashwood Estate: goes live after 10 s; holding it shows SECURED, scores 1/s and pays +25
  every 5 s; after 60 s it moves and shows UNCLAIMED with the next timer (10, 12).
- Free-for-All, Red Mesa: "YOU / NO RIVALS" header, first to 30, 1ST PLACE podium on results (08, 09).
- Team Deathmatch, Frost Relay: HUD and spawn verified after the fixes below (13).
- Respawn: after dying while facing south, the new life starts facing the spawn direction (camera
  and character both +X).

### Defects found in the Phase 4 playtest and fixed
1. After spawning, the camera kept its old yaw, so the first-person character turned to face it,
   often a wall. The camera now takes the spawn's facing once per life (03).
2. Eight team spawns per side on three maps faced a wall, screen or post 4–6 studs away (Iron
   Borough corners, Frost Relay front row, Dustline centre). They were moved, and the map contract
   now requires 8 studs of open space ahead of every team spawn (11, 13).
3. A lone player in Free-for-All was awarded Victory XP with 0 kills. There is now no FFA winner
   unless someone has a kill (and still none on a tie).

### Studio-only QA hooks
All of these only work in Studio. `QA_GrantLevels` also requires temporary (unpublished) profiles.
- `workspace:SetAttribute("QA_GrantLevels", 30)` raises the account and every weapon to that level.
- `workspace:SetAttribute("QA_HoldLobby", true)` keeps the lobby countdown from running out; set it
  to nil to let the match start.
- `workspace:SetAttribute("QA_EndMatch", true)` ends the current match now.
- `workspace:SetAttribute("QA_Mode", "SND")` and `("QA_Map", "FrostRelay")` force the next match.
  Clear them again before saving the place.

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
- Kill Confirmed: an enemy picking up a tag (confirm). Only deny was possible solo.
- Search and Destroy: defusing, elimination wins, the side swap after round 3, the final round,
  and spectating a teammate while dead. Solo play only reaches attack-side planting.
- Domination and Hardpoint with both teams in a zone (contested), and captures from an enemy flag.
- The objective XP per-minute cap under real play.
- Breakwater, Red Mesa and Ashwood Estate were seen in one mode each; not every map was walked fully.
- Late-join DEPLOY button flow.
- Touch, gamepad and small-screen layouts.
- Performance with 12 players.

## Phase 5: perks, killstreaks, challenges, prestige, cosmetics

Built against `docs/PHASE5_CONTRACT.md`: 12 perks in three tiers, 6 killstreaks (Recon Drone,
Counter-Recon, Mortar Barrage, Sentry Gun, Strike Run, Blackout), 3 deterministic daily
challenges from a pool of 17, 6 camos, 11 titles, 10 prestige emblems, and profile schema v4 with a
v3→v4 migration. Everything that changes gameplay unlocks by level only; cosmetic ownership is
derived from play. Nothing is random-for-reward and nothing is paid.

Executed with evidence: 289 unit specs pass (54 new for Phase 5) and the type check is clean. In the
Studio playtest (1 client) the loadout tabs, Barracks, challenge completion, title unlocks and
equip, prestige with confirmation, and the in-match streak tray all worked (`docs/qa/phase5`).
One defect was fixed: Red Mesa team spawns faced the rampart wall 12 studs away; they now face the
nearest rampart gap.

Not yet exercised: earning and using killstreaks, perk effects in a fight, sentries, Blackout and
camos on models all need kills, so they wait for a two-player session.

## Phase 6: compliant store

Policy (`src/shared/Config/Store.luau`, enforced by `Pure/StoreRules.luau` and specs):
- Everything in the store is cosmetic. Gameplay items stay level-unlocked only.
- Credits are earned by play only (match complete +100, win +50, each daily challenge +150) and are
  never sold for Robux, so no Robux ever reaches a random outcome, directly or through a currency.
- Supply crates are earned by play only (each level-up or prestige, and once a day for finishing all
  three dailies). Odds are shown before opening, and a crate never gives an item you already own.
  Because nothing paid is random, no regional or age gating of paid random items is needed; the
  server still reads PolicyService (`ArePaidRandomItemsRestricted`, unknown = restricted) and shows it
  in the store state, so any future paid random item has the flag ready.
- Robux buys fixed, named bundles (developer products). `ProcessReceipt` is idempotent: the grant and
  the PurchaseId are written to the profile together, and the purchase is acknowledged only after the
  profile is saved. A retried receipt is acknowledged without granting twice. Unknown products are
  left unprocessed. Receipt ids are kept 120 days.
- Profile schema v5 adds the wallet and crate stats, with a v4→v5 migration and stricter inventory
  sanitising.

Executed with evidence: 305 unit specs pass (16 new for Phase 6) and the type check is clean. In
Studio the shop purchase, crate opening with odds and duplicate protection, the premium COMING SOON
state and the PolicyService lookup all worked (`docs/qa/phase6`). No defects were found.

Not yet exercised: a real Robux purchase (needs a developer product on the published game), and
credits and crates earned through real matches.

## Phase 7: polish, mobile and controller

- Touch controls (`src/client/UI/TouchControls.luau`): FIRE (two, one per thumb), AIM (toggle),
  RELOAD, SWAP, MELEE, CROUCH (toggle) and SPRINT (toggle), laid out in the Theme's scaled canvas
  above the streak tray. They drive the same controller code as mouse and gamepad, so the server
  sees identical requests. Movement and look use Roblox's default thumbstick and camera drag.
- Blackout now also hides the objective strip (the plant / defuse prompt stays usable).
- Sentry Guns show a health bar.
- Ashwood Estate's Great Hall is lit (chandelier and fireplace lights).

Executed with evidence: 305 specs pass, type check clean. In Studio with QA_ForceTouch the controls
showed, the first layout overlapped the streak tray and was fixed, and AIM, CROUCH, SWAP and FIRE
worked through the QA_TouchTap hook (a first-person locked mouse cannot press GUI buttons, so real
touches still need a phone or the device emulator). The Great Hall is visibly lit (`docs/qa/phase7`).

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
- Results with a single player always show DRAW (0–0), which is correct behaviour. In FFA a lone
  player now sees 1ST PLACE with "No outright winner" and gets no Victory XP.
- During the Phase 4 playtest Studio stopped drawing the 3D view for a few minutes (white screen,
  HUD still drawn; exposure changes had no effect). It recovered on its own and happened on two
  maps, so it is treated as a Studio/display issue on the test machine, not a game bug (07).
- The game was renamed to "Blox Ops" (2026-10-20). The title check is in LAUNCH_READINESS.
- Studio sync is done through MCP scripts, not the Rojo plugin. `tools/studio_patch.py` sends only
  changed hunks with checksum verification, and `tools/studio_verify.py` audits the whole tree.

- The lobby operator list shows a player's old rank until the next roster refresh.

## Needs the owner

1. **Publish the place and enable Studio API access** (Game Settings → Security), so DataStore
   persistence can be tested for real.
2. ~~Connect a GitHub repository~~ Done: https://github.com/Gruntastic/roblox-warfare (`main`).
3. **Run one two-player test**, either Studio Test → Clients and Servers with 2 players, or a
   private server, to clear the combat items above. `docs/QA_CHECKLIST.md` lists the steps.
4. **Create the Founder Pack developer product** on the published game and put its id in
   `src/shared/Config/Store.luau` (`productId`). Until then the bundle shows COMING SOON.

## Phase 8: testing and launch readiness

See `docs/LAUNCH_READINESS.md` (verdict and blockers) and `docs/KNOWN_ISSUES.md`.

## Phase 9: Blox Ops revamp

- Renamed to **Blox Ops** (internal `COR_` identifiers kept).
- **Staging screen**: the lobby is now a 3D hangar with the player in the centre and five squad
  slots showing teammates' animated, geared avatars. Empty slots have INVITE buttons (server players
  or a Roblox friend invite). The left nav opens Loadouts, Gunsmith, Perks, Killstreaks, Operator and
  Barracks. QUEUE opens mode select; SHOP opens the store on the Loot Crates tab.
- **Squads**: `PartyService` (invite, accept, leave, kick). The leader's mode pick queues the squad.
- **Military gear**: eight gear sets (helmet with NVG, plate carrier with pouches, packs, belts, knee
  pads, team armband). Ranger is the default, Woodland and Urban unlock at levels 10 and 25,
  Desert Recon costs 3,000 credits, and four sets come from the new Gear Crate (earned every 5 levels;
  crates are still earned only, never sold).
- **Animations**: procedural operator poses (rifle carry, sprint, aim pitch synced to other clients,
  idle staging poses) and geared viewmodel arms.
- **Art**: 34 ForgeGUI images published to Roblox (docs/ASSETS.md); five jobs did not finish.
- Not run in Studio yet: see KNOWN_ISSUES 18–21.
