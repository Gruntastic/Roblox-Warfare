# Weapon and gameplay SFX list

The game has no audio yet. This is what it needs, in priority order. Each line is one sound slot.
Once the sounds are uploaded, put their asset ids in `src/shared/Config/Audio.luau` (one entry per
slot below, all 0 for now); the game plays them automatically and skips any slot left at 0.
Playback is in `src/client/Controllers/SoundController.luau`. Already wired: all of sections 1–3
(gunshots, handling, hits, impacts by surface; other players' shots use `Shot.Distant`). Sections
4–6 have slots reserved but are not hooked up yet.

**Uploading:** Creator Dashboard → Development Items → Audio → Upload (or Studio's Asset Manager).
Use mono `.ogg` or `.wav` files under 7 seconds for SFX. Make the audio public or owned by the same
account or group as the game, otherwise it will not play in live servers. Commercial-licence
libraries are fine; keep the licence on file.

## 1. Gunshots: highest priority (one per weapon class, 8 + 1 suppressed)

The 26 weapons share sounds by class, with a small random pitch shift per weapon, so 9 files cover
everything. Each needs a close (first-person) version. A distant tail is optional but adds a lot.

| Slot | Used by | What to pick |
|---|---|---|
| `Shot.AssaultRifle` | VK-7, KT-9, SW-3, HL-4, BX-2, TR-6 | Punchy 5.56/7.62 rifle crack, short tail |
| `Shot.SMG` | 5 SMGs (MR-5, ZP-9, CW-4, MN-8, …) | Lighter, snappier 9mm auto |
| `Shot.LMG` | 3 LMGs | Heavier rifle with more low end |
| `Shot.Marksman` | 2 DMRs | Sharp semi-auto rifle, more reverb than the AR |
| `Shot.Sniper` | 3 snipers | Big bolt-action boom with a long tail |
| `Shot.Shotgun` | 3 shotguns | 12-gauge blast |
| `Shot.Pistol` | P-12 and 2 other pistols | 9mm / .45 handgun |
| `Shot.MachinePistol` | 1 machine pistol | Light, fast handgun burst |
| `Shot.Suppressed` | any gun with the Suppressor | Thump / "phut" suppressed shot |
| `Shot.Distant` *(optional)* | any shot heard from far away | Distant gunfire crack/echo |

## 2. Weapon handling (shared by all guns)

| Slot | When |
|---|---|
| `Dry` | Trigger pulled on an empty magazine (click) |
| `MagOut` | Reload starts (magazine release) |
| `MagIn` | Magazine seated |
| `BoltRack` | End of a reload from empty (charging handle / slide) |
| `ShellLoad` | Each shell in a shotgun reload |
| `BoltCycle` | Between sniper shots (bolt action) |
| `Equip` | Swapping weapons (cloth rustle + metal) |
| `AdsIn` | Aiming down sights (soft cloth/metal) |
| `Melee` | Melee swing (whoosh) |
| `MeleeHit` | Melee connects |

## 3. Hits and feedback

| Slot | When |
|---|---|
| `HitMarker` | Your shot hits a player (short tick) |
| `HitHeadshot` | Headshot (brighter ping) |
| `KillConfirm` | You get a kill |
| `HurtPlayer` | You take damage |
| `Impact.Concrete`, `Impact.Metal`, `Impact.Wood`, `Impact.Dirt` | Bullet hits the world (3D, at the hit point) |
| `BulletWhiz` | A shot passes close to you |

## 4. Player movement

| Slot | When |
|---|---|
| `Footstep.Hard`, `Footstep.Soft`, `Footstep.Metal` | Walking/sprinting (several variations each if you have them) |
| `Land` | Landing from a fall |
| `Slide` / `Crouch` | Crouching (cloth) |

## 5. Killstreaks and objectives

| Slot | When |
|---|---|
| `Streak.Earned` | A killstreak is ready |
| `Streak.ReconDrone` | Drone hum / ping |
| `Streak.MortarIncoming`, `Streak.Explosion` | Mortar whistle and blast (also Strike Run) |
| `Streak.JetFlyby` | Strike Run pass |
| `Streak.SentryFire` | Sentry gun shots |
| `Streak.Blackout`, `Streak.Jammed` | Static / EMP buzz |
| `Objective.Capture`, `Objective.Lost` | Domination flag taken / lost |
| `Objective.BombPlant`, `Objective.BombTick`, `Objective.BombDefuse` | Search and Destroy |
| `Objective.TagPickup` | Kill Confirmed tag |

## 6. Interface

| Slot | When |
|---|---|
| `UI.Click`, `UI.Hover` | Menu buttons |
| `UI.LevelUp`, `UI.Challenge` | Rank up / challenge complete |
| `UI.MatchStart`, `UI.Victory`, `UI.Defeat` | Countdown end and results |
| `UI.Purchase`, `UI.CrateOpen` | Store |

**Minimum set to make the game feel right:** the 9 gunshots, `Dry`, `MagOut`, `MagIn`, `Equip`,
`HitMarker`, `HitHeadshot`, `KillConfirm`, `HurtPlayer` and one footstep: 17 files.
