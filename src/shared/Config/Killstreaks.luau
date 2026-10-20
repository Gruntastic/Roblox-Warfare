--!strict
-- Killstreak catalogue. A loadout equips up to three. Kills in one life (without dying) earn them;
-- kills made BY a killstreak never count toward the next one. Earned rewards are kept until used
-- or the match ends (dying does not lose them). All effects run on the server.
export type StreakDef = {
	id: string,
	name: string,
	kills: number, -- consecutive kills needed (before perk discounts)
	unlockLevel: number,
	description: string,
	targeted: boolean, -- activation needs an aim point (validated on the server)
	duration: number?, -- seconds the effect lasts, where it lasts
	-- tuning, read by the server implementation
	params: { [string]: number },
}

local list: { StreakDef } = {
	{
		id = "ReconDrone",
		name = "Recon Drone",
		kills = 3,
		unlockLevel = 1,
		description = "Pings every enemy on your team's compass every 2 seconds for 30 seconds.",
		targeted = false,
		duration = 30,
		params = { pingInterval = 2 },
	},
	{
		id = "CounterRecon",
		name = "Counter-Recon",
		kills = 4,
		unlockLevel = 6,
		description = "Jams the enemy compass and cancels their Recon Drones for 30 seconds.",
		targeted = false,
		duration = 30,
		params = {},
	},
	{
		id = "MortarBarrage",
		name = "Mortar Barrage",
		kills = 5,
		unlockLevel = 1,
		description = "Three mortar shells land where you aim, after a 3 second warning.",
		targeted = true,
		params = { shells = 3, warning = 3, interval = 1.2, radius = 14, damage = 150, scatter = 6, maxRange = 400 },
	},
	{
		id = "SentryGun",
		name = "Sentry Gun",
		kills = 6,
		unlockLevel = 14,
		description = "Deploys an automated turret in front of you for 45 seconds.",
		targeted = false,
		duration = 45,
		params = { range = 90, damage = 16, rpm = 400, health = 300, lockOn = 0.6, ghostLockOn = 1.6, placeDistance = 4 },
	},
	{
		id = "StrikeRun",
		name = "Strike Run",
		kills = 8,
		unlockLevel = 22,
		description = "A line of six blasts sweeps along your aim, starting at the aim point.",
		targeted = true,
		params = { blasts = 6, spacing = 14, warning = 3, interval = 0.25, radius = 12, damage = 200, maxRange = 400 },
	},
	{
		id = "Blackout",
		name = "Blackout",
		kills = 11,
		unlockLevel = 32,
		description = "Knocks out every enemy HUD and grounds their killstreaks for 40 seconds.",
		targeted = false,
		duration = 40,
		params = {},
	},
}

local Killstreaks = {
	list = list,
	byId = {} :: { [string]: StreakDef },
	Defaults = { "ReconDrone", "MortarBarrage" }, -- a new loadout's streaks (both level 1)
	MaxEquipped = 3,
	MinKills = 2, -- floor after perk discounts
}
for _, def in list do
	Killstreaks.byId[def.id] = def
end

return Killstreaks
