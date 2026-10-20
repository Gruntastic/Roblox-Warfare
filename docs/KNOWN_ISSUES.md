# Known issues

Date: 2026-10-20. Severity: **Blocker** (must fix or clear before launch), **Minor** (polish),
**Note** (expected behaviour or a tooling detail).

| # | Severity | Issue | Status |
|---|---|---|---|
| 1 | Blocker | New title "Roblox Blox Ops": confirm use of "Roblox" in the name against Roblox brand guidelines, and the closeness of "Blox Ops" to "Black Ops" (see LAUNCH_READINESS) | Owner |
| 2 | Blocker | DataStore persistence has never run for real (unpublished place, in-memory fallback) | Owner: publish and enable API access |
| 3 | Blocker | Robux purchase never run end to end (Founder Pack product 3720442629 is now configured) | Owner: one test purchase on the published game |
| 4 | Blocker | Multiplayer combat, objectives contested by both teams, killstreaks and perks in fights are untested | Needs a 2+ player session |
| 5 | Minor | Touch controls tested only through the Studio QA hook. Real finger taps are untested | Needs a phone or the device emulator |
| 6 | Minor | Gamepad bindings exist but have not been tried on a physical controller | Needs a controller |
| 7 | Minor | Gunsmith damage ratings look low for rifles because the scale runs to sniper damage | Open |
| 8 | Minor | The HUD stays visible under the death screen overlay | Open |
| 9 | Minor | The lobby operator list can show a player's old rank briefly, until the next roster refresh | Open |
| 10 | Minor | The Gunsmith preview starts at a fixed angle, so it is sometimes edge-on | Open |
| 11 | Minor | A loadout changed outside the editor keeps showing the old draft until the slot is reselected (normal play does not hit this) | Open |
| 12 | Note | Studio prints `rbxassetid://203785492 … Asset type does not match` at play start. The id is not in `src/` (Studio/core) | Not ours |
| 13 | Note | Studio's 3D view went white for a few minutes during one playtest and recovered on its own | Studio/display |
| 14 | Note | During Blackout the S&D plant/defuse prompt stays on screen on purpose, so the objective stays playable | By design |
| 15 | Note | A solo match shows DRAW (team modes) or "No outright winner" (FFA) | By design |
