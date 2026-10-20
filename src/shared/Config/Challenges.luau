--!strict
-- Daily challenges. Each player gets `DailyCount` challenges per UTC day, picked deterministically
-- from the pool by (userId, day) in Pure/ChallengeRules.luau: the same player sees the same three
-- all day, on every server. Rewards are fixed account XP (never random, never paid).
--
-- Progress events (ChallengeRules.Event.kind):
--   "kill"      { class = weapon class or "Melee" / "Streak", headshot = boolean }
--   "assist", "win", "match", "capture", "plant", "defuse", "tag", "streakEarned"
--   "hardpointSecond" (one per second held)
export type ChallengeDef = {
	id: string,
	text: string, -- "%d" is replaced by the target
	event: string, -- the event kind counted
	class: string?, -- kill events only: weapon class that counts (nil = any non-streak kill)
	headshot: boolean?, -- kill events only: only headshot kills count
	target: number,
	xp: number,
}

local pool: { ChallengeDef } = {
	{ id = "Kills", text = "Get %d kills", event = "kill", target = 15, xp = 1000 },
	{ id = "Headshots", text = "Get %d headshot kills", event = "kill", headshot = true, target = 5, xp = 1500 },
	{ id = "RifleKills", text = "Get %d kills with assault rifles", event = "kill", class = "AssaultRifle", target = 10, xp = 1200 },
	{ id = "SMGKills", text = "Get %d kills with SMGs", event = "kill", class = "SMG", target = 10, xp = 1200 },
	{ id = "SniperKills", text = "Get %d kills with sniper rifles", event = "kill", class = "Sniper", target = 5, xp = 1500 },
	{ id = "ShotgunKills", text = "Get %d kills with shotguns", event = "kill", class = "Shotgun", target = 8, xp = 1200 },
	{ id = "LMGKills", text = "Get %d kills with LMGs", event = "kill", class = "LMG", target = 8, xp = 1200 },
	{ id = "PistolKills", text = "Get %d kills with pistols", event = "kill", class = "Pistol", target = 5, xp = 1500 },
	{ id = "MeleeKills", text = "Get %d melee kills", event = "kill", class = "Melee", target = 2, xp = 1500 },
	{ id = "Assists", text = "Get %d assists", event = "assist", target = 5, xp = 1000 },
	{ id = "Wins", text = "Win %d matches", event = "win", target = 2, xp = 2000 },
	{ id = "Matches", text = "Finish %d matches", event = "match", target = 3, xp = 1500 },
	{ id = "Captures", text = "Capture %d Domination flags", event = "capture", target = 4, xp = 1500 },
	{ id = "Hardpoint", text = "Hold a hardpoint for %d seconds", event = "hardpointSecond", target = 60, xp = 1500 },
	{ id = "Plants", text = "Plant %d bombs in Search and Destroy", event = "plant", target = 2, xp = 2000 },
	{ id = "Tags", text = "Collect %d tags in Kill Confirmed", event = "tag", target = 10, xp = 1500 },
	{ id = "Streaks", text = "Earn %d killstreaks", event = "streakEarned", target = 3, xp = 1500 },
}

local Challenges = {
	pool = pool,
	byId = {} :: { [string]: ChallengeDef },
	DailyCount = 3,
	-- days are counted from the Unix epoch in UTC: day = floor(os.time() / 86400)
	SecondsPerDay = 86400,
}
for _, def in pool do
	Challenges.byId[def.id] = def
end

return Challenges
