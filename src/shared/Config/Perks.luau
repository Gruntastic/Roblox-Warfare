--!strict
-- Perk catalogue. A loadout carries one perk per tier (1, 2, 3). Every perk is earned by account
-- level only (prestige keeps everything unlocked). Effects are plain numbers read by
-- Pure/PerkRules.luau; the server applies them, the client only mirrors them for feel and UI.
export type PerkEffects = {
	moveSpeed: number?, -- multiplier on walk and sprint speed
	reloadTime: number?, -- multiplier on reload times
	reserveAmmo: number?, -- multiplier on reserve ammo
	hipSpread: number?, -- multiplier on hip-fire spread
	adsTime: number?, -- multiplier on aim-down-sights time
	regenDelay: number?, -- multiplier on the delay before health regenerates
	streakDiscount: number?, -- killstreaks need this many fewer kills (never below 2)
	scavenger: boolean?, -- each kill refills one magazine of reserve for both weapons
	tracker: boolean?, -- enemies you damage are marked for you for a few seconds
	ghost: boolean?, -- hidden from enemy Recon Drone pings and from sentry target acquisition
	objectiveTime: number?, -- multiplier on S&D plant / defuse time
	streakDamage: number?, -- multiplier on damage taken from enemy killstreaks
}

export type PerkDef = {
	id: string,
	name: string,
	tier: number, -- 1, 2 or 3
	unlockLevel: number,
	description: string,
	effects: PerkEffects,
}

local list: { PerkDef } = {
	-- Tier 1: movement and tempo
	{ id = "Fleetfoot", name = "Fleetfoot", tier = 1, unlockLevel = 1, description = "Move 8% faster.", effects = { moveSpeed = 1.08 } },
	{ id = "Scavenger", name = "Scavenger", tier = 1, unlockLevel = 5, description = "Each kill refills one magazine of reserve ammo.", effects = { scavenger = true } },
	{ id = "Tracker", name = "Tracker", tier = 1, unlockLevel = 11, description = "Enemies you damage stay marked for 3 seconds.", effects = { tracker = true } },
	{ id = "Hardline", name = "Hardline", tier = 1, unlockLevel = 19, description = "Killstreaks need 1 fewer kill.", effects = { streakDiscount = 1 } },
	-- Tier 2: weapon handling
	{ id = "Quickhands", name = "Quickhands", tier = 2, unlockLevel = 1, description = "Reload 25% faster.", effects = { reloadTime = 0.75 } },
	{ id = "DeepPockets", name = "Deep Pockets", tier = 2, unlockLevel = 7, description = "Carry 50% more reserve ammo.", effects = { reserveAmmo = 1.5 } },
	{ id = "SteadyHand", name = "Steady Hand", tier = 2, unlockLevel = 15, description = "35% tighter hip-fire spread.", effects = { hipSpread = 0.65 } },
	{ id = "SwiftSights", name = "Swift Sights", tier = 2, unlockLevel = 23, description = "Aim down sights 20% faster.", effects = { adsTime = 0.8 } },
	-- Tier 3: survival and intel
	{ id = "SecondWind", name = "Second Wind", tier = 3, unlockLevel = 1, description = "Health starts regenerating 40% sooner.", effects = { regenDelay = 0.6 } },
	{ id = "GhostSignal", name = "Ghost Signal", tier = 3, unlockLevel = 9, description = "Invisible to enemy Recon Drones; sentries are slower to lock on to you.", effects = { ghost = true } },
	{ id = "BombTech", name = "Bomb Tech", tier = 3, unlockLevel = 17, description = "Plant and defuse 40% faster.", effects = { objectiveTime = 0.6 } },
	{ id = "BlastGuard", name = "Blast Guard", tier = 3, unlockLevel = 27, description = "Take 40% less damage from enemy killstreaks.", effects = { streakDamage = 0.6 } },
}

local Perks = {
	list = list,
	byId = {} :: { [string]: PerkDef },
	-- The perks a brand-new loadout starts with (all unlocked at level 1).
	Defaults = { "Fleetfoot", "Quickhands", "SecondWind" },
	TRACKER_SECONDS = 3,
}
for _, def in list do
	Perks.byId[def.id] = def
end

return Perks
