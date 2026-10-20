--!strict
-- Pure killstreak bookkeeping for one player in one match. Kills in one life count up; each
-- equipped streak is earned when the count reaches its cost (so at most once per life). Kills
-- made by a killstreak do not count. Earned rewards wait in `ready` until used; dying resets the
-- count but keeps what was earned. The server owns this state.
local Killstreaks = require(script.Parent.Parent.Config.Killstreaks)
local PerkRules = require(script.Parent.PerkRules)

local StreakRules = {}

export type State = {
	count: number, -- kills this life that count toward streaks
	ready: { string }, -- earned, not yet used (oldest first)
}

function StreakRules.newState(): State
	return { count = 0, ready = {} }
end

function StreakRules.cost(id: string, discount: number): number
	local def = Killstreaks.byId[id]
	if not def then
		return math.huge
	end
	return math.max(Killstreaks.MinKills, def.kills - discount)
end

-- Returns (ok, reason). Up to MaxEquipped distinct, known, unlocked streaks. Empty is allowed.
function StreakRules.validate(list: any, level: number, prestige: number): (boolean, string?)
	if type(list) ~= "table" then
		return false, "shape"
	end
	local seen = {}
	local n = 0
	for key, id in list do
		n += 1
		if type(key) ~= "number" or key ~= n or n > Killstreaks.MaxEquipped then
			return false, "shape"
		end
		local def = if type(id) == "string" then Killstreaks.byId[id] else nil
		if not def then
			return false, "unknown"
		end
		if seen[id] then
			return false, "duplicate"
		end
		seen[id] = true
		if not PerkRules.isUnlocked(def.unlockLevel, level, prestige) then
			return false, "locked"
		end
	end
	return true, nil
end

-- The valid subset of a stored list, in order; nil or a non-table gives the defaults.
function StreakRules.sanitize(list: any, level: number, prestige: number): { string }
	if type(list) ~= "table" then
		return table.clone(Killstreaks.Defaults)
	end
	local out, seen = {}, {}
	for i = 1, Killstreaks.MaxEquipped do
		local id = list[i]
		local def = if type(id) == "string" then Killstreaks.byId[id] else nil
		if def and not seen[id] and PerkRules.isUnlocked(def.unlockLevel, level, prestige) then
			seen[id] = true
			table.insert(out, id)
		end
	end
	return out
end

-- Records a kill. Returns the streak ids earned by it (usually none).
function StreakRules.onKill(state: State, equipped: { string }, discount: number, byStreak: boolean): { string }
	if byStreak then
		return {}
	end
	state.count += 1
	local earned = {}
	for _, id in equipped do
		if StreakRules.cost(id, discount) == state.count then
			table.insert(state.ready, id)
			table.insert(earned, id)
		end
	end
	return earned
end

function StreakRules.onDeath(state: State)
	state.count = 0
end

-- Uses one earned reward. Returns false when the player has none of that kind.
function StreakRules.take(state: State, id: string): boolean
	local i = table.find(state.ready, id)
	if not i then
		return false
	end
	table.remove(state.ready, i)
	return true
end

-- The next streak still to earn this life and the kills it needs in total, or nil.
function StreakRules.nextUp(state: State, equipped: { string }, discount: number): (string?, number?)
	local bestId, bestCost = nil, math.huge
	for _, id in equipped do
		local c = StreakRules.cost(id, discount)
		if c > state.count and c < bestCost then
			bestId, bestCost = id, c
		end
	end
	if bestId then
		return bestId, bestCost
	end
	return nil, nil
end

return StreakRules
