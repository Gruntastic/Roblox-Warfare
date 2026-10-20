--!strict
-- Pure team balancing and spawn scoring.
local Teams = {}

-- Picks the team with the fewest players; ties broken by lower score, then list order.
function Teams.pick(teamIds: { string }, counts: { [string]: number }, scores: { [string]: number }?): string
	local best = teamIds[1]
	for i = 2, #teamIds do
		local id = teamIds[i]
		local c, bc = counts[id] or 0, counts[best] or 0
		if c < bc or (c == bc and scores and (scores[id] or 0) < (scores[best] or 0)) then
			best = id
		end
	end
	return best
end

-- Scores spawn candidates: prefer far from enemies, mildly prefer near teammates.
-- `blocked(i)` lets the caller veto a spawn (e.g. an enemy has line of sight).
function Teams.chooseSpawn(spawns: { Vector3 }, enemies: { Vector3 }, friends: { Vector3 }, blocked: ((number) -> boolean)?): number?
	local bestIndex, bestScore = nil, -math.huge
	for i, pos in spawns do
		local minEnemy = 500
		for _, e in enemies do
			minEnemy = math.min(minEnemy, (e - pos).Magnitude)
		end
		local nearFriend = 0
		for _, f in friends do
			if (f - pos).Magnitude < 60 then
				nearFriend += 1
			end
		end
		local score = minEnemy + math.min(nearFriend, 3) * 8
		if minEnemy < 25 then
			score -= 1000
		end
		if blocked and blocked(i) then
			score -= 500
		end
		if score > bestScore then
			bestIndex, bestScore = i, score
		end
	end
	return bestIndex
end

return Teams
