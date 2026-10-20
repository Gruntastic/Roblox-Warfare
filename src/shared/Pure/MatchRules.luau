--!strict
-- Pure end-of-match rules shared by modes.
local MatchRules = {}

-- Returns the leading team id, or nil on a tie.
function MatchRules.winner(scores: { [string]: number }): string?
	local best, bestScore, tied = nil, -math.huge, false
	for id, score in scores do
		if score > bestScore then
			best, bestScore, tied = id, score, false
		elseif score == bestScore then
			tied = true
		end
	end
	if tied then
		return nil
	end
	return best
end

-- Returns (over, reason) where reason is "score" | "time" | nil.
function MatchRules.isOver(scoreLimit: number, scores: { [string]: number }, now: number, endsAt: number): (boolean, string?)
	for _, score in scores do
		if score >= scoreLimit then
			return true, "score"
		end
	end
	if endsAt > 0 and now >= endsAt then
		return true, "time"
	end
	return false, nil
end

-- Per-player scoreboard points.
MatchRules.POINTS = { Kill = 100, Assist = 50, Headshot = 20 }

return MatchRules
