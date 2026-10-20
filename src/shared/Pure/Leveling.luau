--!strict
-- Pure level/XP math shared by account and weapon progression.
export type Curve = { base: number, step: number }
export type LevelState = { level: number, xp: number } -- xp = progress inside the current level

local Leveling = {}

function Leveling.needed(curve: Curve, level: number): number
	return curve.base + curve.step * (level - 1)
end

function Leveling.totalToReach(curve: Curve, level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Leveling.needed(curve, l)
	end
	return total
end

-- Returns the new state and number of levels gained. At max level xp is clamped to 0.
function Leveling.add(state: LevelState, amount: number, curve: Curve, maxLevel: number): (LevelState, number)
	assert(amount >= 0, "negative xp")
	local level, xp = state.level, state.xp + math.floor(amount)
	local gained = 0
	while level < maxLevel and xp >= Leveling.needed(curve, level) do
		xp -= Leveling.needed(curve, level)
		level += 1
		gained += 1
	end
	if level >= maxLevel then
		level, xp = maxLevel, 0
	end
	return { level = level, xp = xp }, gained
end

function Leveling.progress(state: LevelState, curve: Curve, maxLevel: number): { level: number, xp: number, needed: number }
	local needed = if state.level >= maxLevel then 0 else Leveling.needed(curve, state.level)
	return { level = state.level, xp = state.xp, needed = needed }
end

return Leveling
