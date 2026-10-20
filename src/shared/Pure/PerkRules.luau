--!strict
-- Pure perk logic: unlock checks, loadout validation, combined effects and how they modify a
-- weapon's effective stats. The server is authoritative; the client mirrors it for feel and UI.
local Perks = require(script.Parent.Parent.Config.Perks)
local WeaponStats = require(script.Parent.WeaponStats)

local PerkRules = {}

export type Combined = {
	moveSpeed: number,
	reloadTime: number,
	reserveAmmo: number,
	hipSpread: number,
	adsTime: number,
	regenDelay: number,
	streakDiscount: number,
	scavenger: boolean,
	tracker: boolean,
	ghost: boolean,
	objectiveTime: number,
	streakDamage: number,
}

-- Everything earned by account level is kept once a player has prestiged at least once.
function PerkRules.isUnlocked(unlockLevel: number, level: number, prestige: number): boolean
	return prestige > 0 or level >= unlockLevel
end

-- Returns (ok, reason). A perk selection is exactly three ids, one per tier, in tier order.
function PerkRules.validate(perks: any, level: number, prestige: number): (boolean, string?)
	if type(perks) ~= "table" then
		return false, "shape"
	end
	for tier = 1, 3 do
		local id = perks[tier]
		local def = if type(id) == "string" then Perks.byId[id] else nil
		if not def then
			return false, "unknown"
		end
		if def.tier ~= tier then
			return false, "tier"
		end
		if not PerkRules.isUnlocked(def.unlockLevel, level, prestige) then
			return false, "locked"
		end
	end
	local count = 0
	for _ in perks do
		count += 1
	end
	if count ~= 3 then
		return false, "shape"
	end
	return true, nil
end

-- A valid selection built from whatever is stored: bad or locked entries fall back to defaults.
function PerkRules.sanitize(perks: any, level: number, prestige: number): { string }
	local out = table.clone(Perks.Defaults)
	if type(perks) ~= "table" then
		return out
	end
	for tier = 1, 3 do
		local id = perks[tier]
		local def = if type(id) == "string" then Perks.byId[id] else nil
		if def and def.tier == tier and PerkRules.isUnlocked(def.unlockLevel, level, prestige) then
			out[tier] = id
		end
	end
	return out
end

-- Combined effect of a (sanitized) selection. Multipliers multiply, flags OR, discounts add.
function PerkRules.combine(perks: { string }): Combined
	local c: Combined = {
		moveSpeed = 1,
		reloadTime = 1,
		reserveAmmo = 1,
		hipSpread = 1,
		adsTime = 1,
		regenDelay = 1,
		streakDiscount = 0,
		scavenger = false,
		tracker = false,
		ghost = false,
		objectiveTime = 1,
		streakDamage = 1,
	}
	for _, id in perks do
		local def = Perks.byId[id]
		if def then
			local e = def.effects
			c.moveSpeed *= e.moveSpeed or 1
			c.reloadTime *= e.reloadTime or 1
			c.reserveAmmo *= e.reserveAmmo or 1
			c.hipSpread *= e.hipSpread or 1
			c.adsTime *= e.adsTime or 1
			c.regenDelay *= e.regenDelay or 1
			c.streakDiscount += e.streakDiscount or 0
			c.scavenger = c.scavenger or e.scavenger == true
			c.tracker = c.tracker or e.tracker == true
			c.ghost = c.ghost or e.ghost == true
			c.objectiveTime *= e.objectiveTime or 1
			c.streakDamage *= e.streakDamage or 1
		end
	end
	return c
end

-- A copy of a weapon's effective stats with the perks applied. Never mutates the input.
function PerkRules.applyToWeapon(stats: WeaponStats.Effective, c: Combined): WeaponStats.Effective
	local out = table.clone(stats)
	out.spread = table.clone(stats.spread)
	out.reloadTime = stats.reloadTime * c.reloadTime
	out.reloadEmptyTime = stats.reloadEmptyTime * c.reloadTime
	out.reserveAmmo = math.floor(stats.reserveAmmo * c.reserveAmmo + 0.5)
	out.spread.hip = stats.spread.hip * c.hipSpread
	out.adsTime = stats.adsTime * c.adsTime
	return out
end

return PerkRules
