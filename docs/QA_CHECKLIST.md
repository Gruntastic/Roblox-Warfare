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
- [ ] Right mouse aims down sights; the crosshair hides
- [ ] Shift sprints and blocks firing; C crouches
- [ ] Speed hacking (WalkSpeed raised from the client console) is rubber-banded back

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
| 2026-10-20 | 8a766db | Claude (Studio via MCP, 1 client) | Items marked ✓ | Pass, after 4 fixes |
