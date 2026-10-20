--!strict
-- Pure anti-farm and XP award rules.
local XPRules = {}

export type Decay = { { threshold: number, multiplier: number } }

-- killsOnVictim is the number of kills on this victim INCLUDING the current one.
function XPRules.repeatMultiplier(decay: Decay, killsOnVictim: number): number
	local mult = 1
	for _, step in decay do
		if killsOnVictim > step.threshold then
			mult = step.multiplier
		end
	end
	return mult
end

-- Clamps an award so combat XP within a match never exceeds the per-minute ceiling.
-- Returns the amount actually allowed.
function XPRules.capCombat(alreadyAwarded: number, amount: number, matchSeconds: number, perMinute: number): number
	local ceiling = math.max(perMinute, perMinute * (matchSeconds / 60))
	return math.max(0, math.min(amount, ceiling - alreadyAwarded))
end

function XPRules.matchCompletion(cfg: any, secondsPlayed: number, won: boolean, completed: boolean): { { reason: string, amount: number } }
	local out = {}
	local minutes = math.min(secondsPlayed / 60, cfg.MatchMinutesCap)
	local timeXP = math.floor(minutes * cfg.PerMinutePlayed)
	if timeXP > 0 then
		table.insert(out, { reason = "Time Played", amount = timeXP })
	end
	if completed then
		table.insert(out, { reason = "Match Complete", amount = cfg.MatchComplete })
		if won then
			table.insert(out, { reason = "Victory", amount = cfg.MatchWin })
		end
	end
	return out
end

return XPRules
