# Manual QA checklist

Run these in Studio with **Test → Clients and Servers → 2 players** unless noted. Record the
pass/fail result, build commit and date in the table at the bottom. Items marked ✓ were executed for
Phase 2 (see `REPORT.md`); everything else is open.

## Boot and lobby
- [x] Server starts with no script errors in Output
- [x] Unpublished place: red "progress saving unavailable" banner shows
- [ ] Published place: no banner; `[DataService]` loads real profiles
- [x] Lobby lists every connected player with rank
- [x] Loadout slots render; the active slot is marked
- [ ] Change the primary or secondary in the editor → SAVE → "SAVED", and the slot text updates
- [ ] Selecting another slot makes it ACTIVE; the next spawn uses that loadout
- [ ] Map vote increments the count for both clients

## Match flow
- [x] Countdown: players spawn on their own team base, frozen, and cannot fire
- [x] Playing: movement unlocks and the timer counts down from 10:00
- [ ] Two players are placed on opposite teams
- [ ] A late joiner during Playing sees the lobby with DEPLOY, and DEPLOY spawns them
- [x] Match end → Results → Lobby; teams and scores reset
- [ ] Reaching the score limit (75) ends the match with VICTORY for the winners and DEFEAT for the losers

## Combat (needs 2 players)
- [ ] Body shot: hit marker on the shooter, damage indicator and health drop on the victim
- [ ] Headshot: amber hit marker, higher damage, HEADSHOT in the kill feed
- [ ] Kill: feed entry shows killer, weapon and victim in team colours; the victim sees "KILLED BY …"
- [ ] Assist: a third player who damaged the victim receives +50
- [ ] Spawn protection: no damage within 2 s of spawning
- [ ] Shooting a teammate deals no damage
- [ ] Shooting through a wall deals no damage
- [ ] At about 150 ms latency (Studio network simulation), shots on moving targets still register
- [ ] Melee (V) at close range deals 135 damage, with a 0.9 s cooldown
- [x] Falling below the map kills the player and they respawn after 3 s

## Weapons and movement
- [x] Fire rate matches the config (about 14 rounds/s for the VK-7)
- [x] Server ammo is authoritative (HUD matches AmmoState)
- [ ] R reloads; the HUD shows RELOADING; you cannot fire mid-reload
- [ ] 1/2, mouse wheel or gamepad Y switches weapons; the HUD weapon name updates
- [x] Right mouse aims down sights; the crosshair hides
- [ ] Shift sprints and blocks firing; C crouches
- [ ] Speed hacking (WalkSpeed raised from the client console) is rubber-banded back

## Attachments and Gunsmith (Phase 3)
Tip: in Studio, `workspace:SetAttribute("QA_GrantLevels", 30)` unlocks everything and
`workspace:SetAttribute("QA_HoldLobby", true)` keeps the lobby open while you test.
- [x] Locked weapons show "UNLOCKS AT LEVEL N"
- [ ] Clicking a locked weapon does not select it
- [x] GUNSMITH opens on the selected weapon; slot list matches the weapon's slots
- [x] Equipping an attachment updates the stat bars, deltas and details (mag, reload, ADS, range)
- [x] DONE saves (lobby shows SAVED and "+N" on the summary); BACK discards; RESET clears
- [ ] Backspace and gamepad B close the Gunsmith; Escape opens the Roblox menu as usual
- [ ] Locked attachments show their unlock level and cannot be equipped
- [x] Attachments are visible on the viewmodel after spawning
- [x] Red dot, holo and scout scope draw their reticle centred in the glass while aiming
- [x] Suppressed weapons show no muzzle flash
- [ ] Suppressed weapons: enemies see no tracer, teammates do (needs 2 players)
- [x] Sniper ADS shows the scope overlay and hides the viewmodel
- [x] Burst weapons fire exactly 3 rounds per click
- [ ] Shotgun pellets spread in the same pattern on client and server; a close hit kills in one shot
- [x] HUD ammo counts down each shot
- [ ] After a reload the HUD matches the server count
- [x] Extended magazines raise the server magazine size (HUD shows the new size after spawning)
- [x] Server rejects unknown attachments and attachments the weapon has no slot for

## Maps and modes (Phase 4)
- [x] Lobby shows three map + mode cards; a vote marks the card, counts it, and updates the header
- [x] QA_Mode / QA_Map / QA_EndMatch switch the next match in Studio
- [x] Kill Confirmed: a tag drops on death; your own team's tag is denied (+50, no team point)
- [ ] Kill Confirmed: an enemy's tag is confirmed (+1 team point) (needs 2 players)
- [x] Domination: standing alone on a flag captures it and the team scores every 5 s
- [ ] Domination: both teams on a flag freezes it (contested); capturing an enemy flag drains it first
- [x] Hardpoint: goes live after 10 s, scores 1/s, +25 every 5 s, rotates after 60 s
- [x] Search and Destroy: hold E on a site to plant (+200); the detonation wins the round; next round starts
- [ ] Search and Destroy: defuse, elimination win, side swap after round 3, spectating while dead (needs 2+ players)
- [x] Free-for-All: own-score header and placing podium on results
- [x] A new life starts looking where the spawn faces
- [x] Each map loads with its lighting: Iron Borough (night), Breakwater, Red Mesa, Ashwood Estate, Frost Relay
- [ ] Walk every map end to end looking for stuck spots and gaps

## Progression and persistence (published place)
- [x] Match complete and time played XP are granted; the results breakdown matches
- [x] The lobby rank bar reflects XP after returning from Results
- [ ] Kill XP toast "+100 KILL" appears
- [ ] Leave and rejoin: XP, level and loadouts persist
- [ ] Join on a second server while still in the first: the session lock prevents a double load
- [ ] Shut down the server: BindToClose saves (check on rejoin)

## Devices
- [ ] Touch-only device emulator: UI is readable; SCORES button shown
- [ ] Gamepad: fire, ADS, reload and switch are bound
- [ ] 1280×720 and 4K window sizes: no clipped panels

## Run log
| Date | Commit | Tester | Scope | Result |
|---|---|---|---|---|
| 2026-10-20 | 8a766db | Claude (Studio via MCP, 1 client) | Phase 2 items marked ✓ | Pass, after 4 fixes |
| 2026-10-20 | Phase 3 playtest commit | Claude (Studio via MCP, 1 client) | Phase 3 items marked ✓ | Pass, after 4 fixes |
| 2026-10-20 | 6ddafa8 → 13e75e8 | Claude (Studio via MCP, 1 client) | Phase 4 items marked ✓ | Pass, after 3 fixes |
