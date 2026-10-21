# Known issues

Date: 2026-10-20. Severity: **Blocker** (must fix or clear before launch), **Minor** (polish),
**Note** (expected behaviour or a tooling detail).

| # | Severity | Issue | Status |
|---|---|---|---|
| 1 | Blocker | Title "Blox Ops": confirm the closeness of "Blox Ops" to "Black Ops" (see LAUNCH_READINESS) | Owner |
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
| 16 | Note | One server runs one mode at a time. A player who picks a mode the queue did not choose waits for a later match (or switches to ANY). Cross-server matchmaking would be a follow-up | By design |
| 17 | Minor | Toolbox sounds (AR, SMG, shotgun, pistol, suppressed, distant, dry fire, shell load, bolt, kill, hurt, impacts) are free community uploads whose licence cannot be verified; replace with the owner's licensed SFX when available. Equip, ADS, melee, footstep, UI and objective sounds are still empty | Open |
| 18 | Blocker | The staging hangar, squad UI, gear fit on R15 bodies and procedural operator poses were written without a Studio run (no Studio in the build environment) | Needs a Studio playtest |
| 19 | Minor | ForgeGUI art was published without a visual check (previews could not be opened from the build environment). Check every image in docs/ASSETS.md, especially the AI-drawn wordmark text | Owner |
| 20 | Minor | Five ForgeGUI jobs ended "outcome unknown" (Gunsmith icon, Talon shirt, Arctic shirt and pants, NightOps shirt); those slots use code-drawn or colour fallbacks | Open |
| 21 | Note | Operator animations are procedural because ForgeGUI cannot make R15 animations; gear is part-built, not mesh | By design |
