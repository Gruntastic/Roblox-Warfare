--!strict
-- Progression tuning. Pure data; the math lives in Pure/Leveling.luau.
local Progression = {
	MaxAccountLevel = 70,
	MaxPrestige = 10,
	MaxWeaponLevel = 30,

	-- XP required to go from level L to L+1 is Base + Step * (L - 1)
	AccountCurve = { base = 1000, step = 150 },
	WeaponCurve = { base = 600, step = 90 },

	AccountXP = {
		Kill = 100,
		Headshot = 25, -- bonus on top of Kill
		Assist = 50,
		MatchComplete = 500,
		MatchWin = 300,
		PerMinutePlayed = 40, -- prorated, capped by MatchMinutesCap
		MatchMinutesCap = 12,
		-- objective awards (scoreboard points are in Pure/MatchRules POINTS)
		Capture = 150, -- Domination flag, each capturer present
		HardpointHold = 25, -- every 5 s alone in the live hardpoint
		TagConfirm = 50, -- Kill Confirmed
		TagDeny = 50,
		Plant = 200, -- S&D
		Defuse = 250,
		RoundWin = 100, -- S&D, every member of the winning side
	},
	WeaponXP = {
		Kill = 100,
		Headshot = 30,
		Assist = 30,
	},

	-- Anti-farm: repeated kills on the same victim within one match decay.
	-- kills beyond `threshold` against one victim are multiplied by `multiplier`.
	RepeatVictimDecay = {
		{ threshold = 8, multiplier = 0.5 },
		{ threshold = 15, multiplier = 0.2 },
		{ threshold = 25, multiplier = 0 },
	},
	-- Hard ceiling on combat XP per player per minute of match time (suspicious-rate guard).
	MaxCombatXPPerMinute = 3500,
	-- Ceiling on objective XP per player per minute of match time (the modes pace it already).
	MaxObjectiveXPPerMinute = 1500,

	-- Item unlocks by account level (vertical slice ships with everything at level 1).
	Unlocks = {
		Weapons = { VK7 = 1, P12 = 1 },
	},

	DefaultLoadoutSlots = 5,
}

return Progression
