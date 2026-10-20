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
MatchRules.POINTS = {
	Kill = 100,
	Assist = 50,
	Headshot = 20,
	Capture = 200,
	HardpointHold = 50, -- every 5 s alone in the live hardpoint
	TagConfirm = 50,
	TagDeny = 50,
	Plant = 300,
	Defuse = 300,
}

-- Join queue (mode select). A pick is a mode id or "Any".
MatchRules.ANY = "Any"

-- Whether a player queued with `pick` plays a match of `modeId`.
function MatchRules.queueAccepts(pick: string?, modeId: string): boolean
	return pick ~= nil and (pick == MatchRules.ANY or pick == modeId)
end

-- The mode the next match should be: the specific mode picked by the most queued players. Ties go
-- to the mode that comes first in the rotation after `lastModeId`. nil when nobody picked a
-- specific mode (all "Any"), so the lobby vote decides.
function MatchRules.pickQueuedMode(picks: { string }, rotation: { string }, lastModeId: string?): string?
	local counts: { [string]: number } = {}
	for _, p in picks do
		if p ~= MatchRules.ANY and table.find(rotation, p) then
			counts[p] = (counts[p] or 0) + 1
		end
	end
	local start = (if lastModeId then table.find(rotation, lastModeId) else nil) or 0
	local best, bestCount = nil, 0
	for i = 1, #rotation do
		local id = rotation[(start + i - 1) % #rotation + 1]
		local c = counts[id] or 0
		if c > bestCount then
			best, bestCount = id, c
		end
	end
	return best
end

-- Free-for-All: the player id with the most kills, or nil on a tie (or nobody).
function MatchRules.ffaWinner(kills: { [number]: number }): number?
	local best, bestKills, tied = nil, -math.huge, false
	for id, k in kills do
		if k > bestKills then
			best, bestKills, tied = id, k, false
		elseif k == bestKills then
			tied = true
		end
	end
	-- a tie, or a match nobody scored in (e.g. one player alone), has no winner
	if tied or bestKills < 1 then
		return nil
	end
	return best
end

return MatchRules
