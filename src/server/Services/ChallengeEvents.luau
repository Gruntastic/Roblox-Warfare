--!strict
-- Pure helpers for the Phase 5 meta layer: which challenge event a kill or an objective award
-- reports, which lifetime stat an event bumps, and the Studio QA helpers. No requires, so the
-- Lune specs can load it; callers pass the catalogues in.
local ChallengeEvents = {}

export type Event = { kind: string, class: string?, headshot: boolean?, amount: number? }

-- Seconds of hold behind one "Hardpoint" objective award (Modes/Hardpoint HOLD_AWARD_SECONDS).
ChallengeEvents.HARDPOINT_SECONDS_PER_AWARD = 5

local STREAK_PREFIX = "Streak:"

-- Objective award reason (as passed to ctx.award) -> the challenge event it reports.
local OBJECTIVE_EVENTS: { [string]: Event } = {
	["Capture"] = { kind = "capture" },
	["Bomb Planted"] = { kind = "plant" },
	["Bomb Defused"] = { kind = "defuse" },
	["Kill Confirmed"] = { kind = "tag" },
	["Kill Denied"] = { kind = "tag" },
	["Hardpoint"] = { kind = "hardpointSecond", amount = ChallengeEvents.HARDPOINT_SECONDS_PER_AWARD },
}

-- Event kind -> lifetime stat it adds to. Kills, headshots, matches and wins are counted where
-- they happen (ProgressionService.onKill / endMatch), so they are not listed here.
local EVENT_STATS: { [string]: string } = {
	assist = "assists",
	capture = "captures",
	plant = "plants",
	defuse = "defuses",
	tag = "tags",
}
ChallengeEvents.EVENT_STATS = EVENT_STATS

function ChallengeEvents.isStreakKill(weaponId: string?): boolean
	return weaponId ~= nil and string.sub(weaponId, 1, #STREAK_PREFIX) == STREAK_PREFIX
end

-- The class a kill reports: the weapon's class, "Melee", "Streak" for killstreak kills, or nil
-- for anything unknown (which still counts toward class-free kill challenges).
function ChallengeEvents.killClass(weaponId: string?, weapons: { [string]: any }): string?
	if weaponId == nil then
		return nil
	elseif ChallengeEvents.isStreakKill(weaponId) then
		return "Streak"
	elseif weaponId == "Melee" then
		return "Melee"
	end
	local def = weapons[weaponId]
	return if def then def.class else nil
end

function ChallengeEvents.killEvent(weaponId: string?, headshot: boolean, weapons: { [string]: any }): Event
	return { kind = "kill", class = ChallengeEvents.killClass(weaponId, weapons), headshot = headshot }
end

-- A fresh event for an objective award reason, or nil when the reason reports nothing.
function ChallengeEvents.objectiveEvent(reason: string): Event?
	local e = OBJECTIVE_EVENTS[reason]
	return if e then table.clone(e) else nil
end

-- Adds an event to the lifetime stats it counts toward. Returns true when a stat changed.
function ChallengeEvents.applyStats(stats: { [string]: number }, event: Event): boolean
	local key = EVENT_STATS[event.kind]
	if not key then
		return false
	end
	local n = event.amount or 1
	if type(n) ~= "number" or n ~= n or n <= 0 then
		return false
	end
	stats[key] = (stats[key] or 0) + n
	return true
end

-- QA: an event that completes a challenge definition from `progress` in one go.
function ChallengeEvents.completionEvent(def: { event: string, class: string?, headshot: boolean?, target: number }, progress: number): Event
	return { kind = def.event, class = def.class, headshot = def.headshot, amount = math.max(1, def.target - progress) }
end

-- QA: raises every lifetime stat to at least `n`, and every listed weapon's kills to at least `n`
-- and headshots to at least floor(n / 3). Never lowers anything.
function ChallengeEvents.raiseStats(profile: any, n: number, weaponIds: { string })
	n = math.max(0, math.floor(n))
	for key, value in profile.stats do
		profile.stats[key] = math.max(value, n)
	end
	local hs = math.floor(n / 3)
	for _, id in weaponIds do
		local w = profile.weapons[id]
		if not w then
			w = { level = 1, xp = 0, kills = 0, headshots = 0 }
			profile.weapons[id] = w
		end
		w.kills = math.max(w.kills or 0, n)
		w.headshots = math.max(w.headshots or 0, hs)
	end
end

return ChallengeEvents
