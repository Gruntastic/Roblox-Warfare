# Phase 5 contract: perks, killstreaks, challenges, prestige, cosmetics

This is the interface the Phase 5 work is built against. The shared pieces already exist and are
tested: the catalogues (`src/shared/Config/Perks.luau`, `Killstreaks.luau`, `Challenges.luau`,
`Cosmetics.luau`), the pure rules (`src/shared/Pure/PerkRules.luau`, `StreakRules.luau`,
`ChallengeRules.luau`, `CosmeticRules.luau`), profile schema v4 (`Pure/ProfileSchema.luau`), the
types (`src/shared/Types.luau`, Phase 5 section) and the remotes (`src/shared/Net.luau`).
Specs: `tests/specs/phase5_rules.spec.luau`, `tests/specs/profile.spec.luau`.

Ground rules from the brief, which apply to every part:
- Damage, ammo, XP, inventory and unlocks are decided on the server. The client only asks and mirrors.
- Gameplay-changing items (perks, killstreaks) are earned by account level only. Nothing is random
  and nothing is paid. Cosmetics are earned by play (ownership is derived, see below).
- Validate every remote argument's type, range and rate. Never trust a client position or target.

## Perks

A loadout has `perks = { tier1Id, tier2Id, tier3Id }`. `PerkRules.sanitize` always gives three valid,
unlocked ids. `ProgressionService.currentLoadout(player).perks` is the sanitized list a player spawns
with, and `PerkRules.combine(perks)` gives the combined effects:

| Effect | Where it applies |
|---|---|
| `moveSpeed` | Client `MovementController` multiplies walk and sprint speed. `MovementGuard` tolerance must still allow it. |
| `reloadTime`, `reserveAmmo`, `hipSpread`, `adsTime` | `PerkRules.applyToWeapon(stats, combined)` on the server's per-slot effective stats at spawn (reload timing and reserve are authoritative). The client `WeaponController` mirrors the same call for feel. |
| `regenDelay` | Server health regeneration delay for that player. |
| `scavenger` | On a kill, the killer's weapons each gain one magazine of reserve (capped at their max reserve); send `AmmoState`. |
| `tracker` | When the player damages an enemy, fire `Mark(victimUserId, Perks.TRACKER_SECONDS)` to the attacker. |
| `ghost` | Left out of enemy Recon Drone pings. Enemy sentries need `ghostLockOn` seconds of sight instead of `lockOn`. |
| `objectiveTime` | Multiplies that player's S&D plant and defuse durations. |
| `streakDamage` | Multiplies damage the player takes from enemy killstreaks. |
| `streakDiscount` | Passed to `StreakRules` (Hardline). |

## Killstreaks

A loadout has `streaks = { id, ... }` (0 to 3). Server state per player per match is a
`StreakRules.State`. Rules (all in `StreakRules`):
- A kill counts unless it was made by a killstreak (`byStreak`). Kills made by a killstreak use the
  weapon id `"Streak:<StreakId>"` (for example `"Streak:MortarBarrage"`).
- Each streak is earned when the life's count reaches its cost (once per life). Dying resets the
  count and keeps earned rewards. Match start clears everything.
- On earning: `StreakEvent("Earned", { streakId })` to the owner, `StreakState` to the owner, and
  `ProgressionService.recordEvent(player, { kind = "streakEarned" })`.

Activation: client fires `ActivateStreak(id, aimDirection?)`. The server checks: the match is
Playing, the player is alive and deployed, the id is in their `ready` list, they are not under an
enemy Blackout, rate limit 1 per 0.5 s. Targeted streaks aim from the server's head position along
`aimDirection` (must be a finite vector of length 0.5..1.5; normalise it). Raycast against map
geometry only, up to `params.maxRange`. With no hit, take the point at max range and drop it to the
ground with a downward ray. Then `StreakRules.take`, `StreakState` to the owner, and
`StreakEvent("Activated", { streakId, ownerUserId, ownerName, team })` to everyone.

Damage from killstreaks goes through `CombatService.applyDamage(victim, owner, amount,
"Streak:<id>", false, fromPos)`: no friendly fire, no self damage, the target's `streakDamage`
applies, and an explosion only hurts a player whose torso it can see (one raycast against map
geometry), so cover and roofs protect.

| Streak | Behaviour |
|---|---|
| Recon Drone | For `duration` s, every `pingInterval` s send `Ping({ targets, expiresAt })` to the owner's team (FFA: the owner only). Targets are living enemies without Ghost Signal. Suppressed while the owner's team is under an enemy Counter-Recon or Blackout. |
| Counter-Recon | For `duration` s the enemy team's Recon Drones send nothing and their compass is jammed. `StreakEvent("Jammed", { team = victimTeam, endsAt })` to everyone; `StreakEvent("EffectEnded", { streakId, team })` at the end. |
| Mortar Barrage | `StreakEvent("Incoming", { streakId, team, positions, radius, impactAt })` to everyone at activation (each shell's landing point = aim point + random scatter within `scatter`). Shells land `warning` s later, `interval` s apart. Each landing: `StreakEvent("Impact", { streakId, position, radius })` to everyone, then radial damage `damage * (1 - d / radius)`. |
| Sentry Gun | Placed `placeDistance` studs in front of the owner on the floor (raycast down; refuse if there is no floor or the spot is blocked, and give the reward back). It is a server Model in `workspace.Streaks` with attributes `Team`, `OwnerUserId`, `Health`. It turns to and fires at the nearest visible enemy within `range` after a lock-on time, at `rpm`, for `damage` per hit (hitscan with a short tracer via the existing `Tracer` event). Enemies can shoot it: it has `health`. It is removed after `duration` s, when destroyed, or when the owner leaves. |
| Strike Run | Like the mortar: `Incoming` with all `blasts` positions in a line from the aim point along the horizontal aim direction, `spacing` apart; impacts `interval` s apart after `warning` s. |
| Blackout | For `duration` s the enemy team cannot activate killstreaks, their Recon Drones send nothing, and their HUD is knocked out (client). `StreakEvent("Blackout", { team = victimTeam, endsAt })` to everyone, `EffectEnded` at the end. |

In FFA "enemy team" means every other player. Active effects, sentries and pending shells are cleared
when the match ends. Streaks work in every mode, including S&D (the count resets every death).

`StreakState` (to the owner) is a `Types.StreakStatePayload`; send it on spawn, kill, death, earn
and use.

Client controls: keys 5, 6 and 7 use the 1st, 2nd and 3rd equipped streak when it is ready.
Gamepad D-pad up uses the most recently earned ready streak. On touch, tapping a ready streak in
the tray uses it. Targeted streaks send the camera's look direction.

## Daily challenges and lifetime stats

`ProgressionService.recordEvent(player, event)` is the single entry point. `ChallengeService.init()`
replaces the stub with the real implementation, which:
1. Brings `profile.challenges` to today (`ChallengeRules.refresh`).
2. Updates lifetime stats: `kill` → `stats.kills` is already counted by `onKill`, plus per-weapon
   `headshots` and `stats.headshots` on headshot kills; `assist` → `stats.assists`;
   `capture` → `stats.captures`; `plant` → `stats.plants`; `defuse` → `stats.defuses`;
   `tag` → `stats.tags`.
3. Applies `ChallengeRules.record`. For each completed challenge: grant `def.xp` account XP (reason
   `"Daily Challenge"`; it is not subject to the combat or objective per-minute caps), add 1 to
   `stats.dailies`, `Notify("Challenge complete: <text>  +<xp> XP", "Challenge")`.
4. Marks the profile dirty and syncs the summary when anything changed.

Who reports what:
| Event | Reported from |
|---|---|
| `kill` (`class` = weapon class, `"Melee"` or `"Streak"`; `headshot`) | `ProgressionService.onKill` |
| `assist` | `ProgressionService.onAssist` |
| `match`, `win` | `ProgressionService.endMatch` (completed matches) |
| `capture`, `plant`, `defuse`, `tag`, `hardpointSecond` | `ProgressionService.onObjective` by reason: "Capture", "Bomb Planted", "Bomb Defused", "Kill Confirmed" or "Kill Denied" (`tag`), "Hardpoint" (`hardpointSecond` with `amount = 5`) |
| `streakEarned` | `KillstreakService` |

Streak kills give account XP and count as kills in stats, but give no weapon XP and never count
toward challenges (`ChallengeRules` ignores class `"Streak"`).

## Prestige

`Prestige(confirm)`: `confirm` must be exactly `"PRESTIGE"`. Allowed when
`CosmeticRules.canPrestige(profile, MaxAccountLevel, MaxPrestige)`; rate limited. Applies
`CosmeticRules.applyPrestige`, saves immediately (`DataService.saveNow`), notifies
`"Prestige <n> reached"` with kind `"LevelUp"` and syncs. Weapons, attachments, perks, killstreaks
and cosmetics stay unlocked after a first prestige (`PerkRules.isUnlocked` and
`isWeaponUnlocked` both treat `prestige > 0` as unlocked). The reward is the prestige emblem.

## Cosmetics

Ownership is derived (`CosmeticRules.owns*`), so earning needs no writes. `EquipCosmetic(kind, id,
weaponId?)` checks `CosmeticRules.canEquip`, stores it in `profile.equipped` (camo `"Factory"`
removes the weapon's entry; emblem `""` unequips) and syncs. Rate limit 4 per second.

`ProgressionService.cosmeticsFor(player)` returns the sanitized equipped set:
- `MatchService` puts `title` and `emblem` on every `PlayerLine`.
- The server's third-person weapon model and the client viewmodel are built with
  `WeaponModel.build(def, { ..., camo = equipped.camos[weaponId] })` (or `WeaponModel.applyCamo`).

## Ownership of files for Phase 5 work

| Area | Files |
|---|---|
| Gameplay (perk effects, killstreaks, camo on models) | `src/server/Services/KillstreakService.luau`, `CombatService.luau`, `MatchService.luau`, `MovementGuard.luau`, `src/server/Modes/SearchAndDestroy.luau`, `src/client/Controllers/WeaponController.luau`, `MovementController.luau`, `Effects.luau` |
| Meta (challenges, stats, prestige, equips) | `src/server/Services/ChallengeService.luau`, `ProgressionService.luau`, `DataService.luau` |
| Client UI | everything in `src/client/UI/`, `src/client/ClientState.luau`, new files in `src/client/Controllers/` |
| Shared (fixed; ask before changing) | `src/shared/**`, `docs/PHASE5_CONTRACT.md` |
