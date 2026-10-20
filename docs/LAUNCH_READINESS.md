# Launch readiness (Phase 8)

Date: 2026-10-20. Commit: see `git log` (this file was added in the Phase 8 commit).

**Verdict: not ready for a public launch yet.** The game is feature-complete for Phases 1–7 and
passes its automated tests and single-client Studio playtests. But several launch blockers can only
be cleared by the owner or by a session with more than one player. None of them is a known code
defect. They are things that have not been exercised yet.

## Evidence that exists

| Area | Evidence |
|---|---|
| Unit specs | 305 pass, 0 fail (`lune run tests/run.luau`), covering damage, hitboxes, leveling, weapon stats, all six map contracts, objectives, perks, streaks, challenges, cosmetics, the store and profile migrations v1→v5 |
| Types | `luau-lsp analyze` in strict mode: 0 errors |
| Studio playtests (1 client) | One per phase, with screenshots in `docs/qa/phase4` to `phase7` and a run log in `docs/QA_CHECKLIST.md`. Every mode was played on at least one map; lobby, Gunsmith, Barracks, prestige, store and touch controls were all exercised |
| Server authority | All 15 client→server remotes are handled on the server with type, range and rate checks: Fire, Reload, Equip, Melee, SetLoadout, SelectLoadout, VoteMap, Interact, RequestDeploy, ActivateStreak, Prestige, EquipCosmetic, BuyItem, OpenCrate, plus GetProfile. Damage, ammo, XP, unlocks, inventory, credits, crates and purchases are decided only on the server |
| Data safety | Session-locked DataStore profiles, retries with backoff, autosave, BindToClose, versioned migrations (v1→v5). There is an in-memory fallback, with an on-screen warning, when DataStores are unavailable |
| Monetisation policy | Cosmetic only. Credits and crates are earned only by play. Robux buys fixed bundles through an idempotent ProcessReceipt that acknowledges only after a save. Nothing paid is random. PolicyService is read per player |
| Assets | No Toolbox or third-party scripts or models. Everything is built from code in `src/` |
| Population | No bots or fake players. Lobbies show only real players |

## Launch blockers (owner)

1. **Title and branding review.** "Call of Roblox" closely echoes an existing franchise name. The
   brief asked for a trademark and policy review before release. A rename is the safe default.
   The name is only used in UI text and docs, so a rename is cheap.
2. **Publish the place and enable Studio access to API services.** DataStore persistence (save,
   rejoin, session lock across servers, BindToClose) has only run in its in-memory fallback.
3. **Create the Founder Pack developer product** and set its id in `src/shared/Config/Store.luau`.
   Then make one test purchase in a private server. Also check that it is granted once, including
   after a rejoin mid-purchase.
4. **Experience questionnaire / content maturity** on the Creator Dashboard. The game has realistic
   firearms combat and no blood, so it should be answered accordingly.

## Launch blockers (needs 2+ players)

Run `docs/QA_CHECKLIST.md` items marked "needs 2 players" in Studio (Test → Clients and Servers,
2–4 players) or a private server:
- Hits, kills, assists, kill feed and damage indicators between players
- Kill Confirmed confirms, contested Domination and Hardpoint zones
- Search and Destroy defuse, elimination, side swap and spectating
- Earning and calling in every killstreak, the sentry health bar, Blackout and Counter-Recon
- Perk effects in a fight
- Camos visible on other players' weapons

## Should do before launch (not blockers)

- Try the touch controls on a real phone (or the Studio device emulator) and on a physical gamepad.
- Load test with 12 players for server frame time and remote traffic.
- See `docs/KNOWN_ISSUES.md` for the polish list.

## How to verify again

```
lune run tests/run.luau
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=<roblox defs> src
```
Then follow `docs/QA_CHECKLIST.md`. Studio QA hooks only work in Studio and only on unsaved
(temporary) profiles: QA_HoldLobby, QA_EndMatch, QA_Mode, QA_Map, QA_GrantLevels, QA_GrantStats,
QA_CompleteChallenges, QA_GrantCredits, QA_GrantCrates, QA_ForceTouch and QA_TouchTap. Clear them
before saving the place.
