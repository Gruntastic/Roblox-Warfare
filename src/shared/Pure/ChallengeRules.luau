--!strict
-- Pure daily-challenge logic. The daily set is a deterministic function of (userId, UTC day), so
-- it is the same on every server and cannot be re-rolled. Progress lives in the profile and the
-- reward is fixed XP granted by the server when a challenge completes.
local Challenges = require(script.Parent.Parent.Config.Challenges)

local ChallengeRules = {}

export type Entry = { id: string, progress: number, done: boolean }
export type State = { day: number, daily: { Entry } }
export type Event = { kind: string, class: string?, headshot: boolean?, amount: number? }

-- Weapon classes that count as another class for challenges.
local CLASS_GROUP: { [string]: string } = { MachinePistol = "Pistol" }

local MODULUS = 2147483647

function ChallengeRules.day(now: number): number
	return math.floor(now / Challenges.SecondsPerDay)
end

-- Seconds until the next UTC day starts.
function ChallengeRules.secondsLeft(now: number): number
	return Challenges.SecondsPerDay - (now % Challenges.SecondsPerDay)
end

-- The ids of the daily challenges for a player on a day. Deterministic, distinct, pool order
-- independent of call history (a Park-Miller generator seeded from the inputs).
function ChallengeRules.dailyFor(userId: number, day: number): { string }
	local seed = ((math.abs(userId) % 1000003) * 7919 + (day % 1000003) * 104729 + 12345) % MODULUS
	if seed == 0 then
		seed = 1
	end
	local function nextInt(n: number): number
		seed = (seed * 48271) % MODULUS
		return seed % n
	end
	-- warm up so close seeds diverge
	for _ = 1, 4 do
		nextInt(2)
	end
	local ids = {}
	for i, def in Challenges.pool do
		ids[i] = def.id
	end
	local out = {}
	for i = 1, math.min(Challenges.DailyCount, #ids) do
		local j = i + nextInt(#ids - i + 1)
		ids[i], ids[j] = ids[j], ids[i]
		out[i] = ids[i]
	end
	return out
end

-- Brings a stored state to `now`: a new day replaces the set and clears progress. Returns true
-- when it changed. Unknown or malformed entries are rebuilt.
function ChallengeRules.refresh(state: State, userId: number, now: number): boolean
	local today = ChallengeRules.day(now)
	local valid = state.day == today and type(state.daily) == "table" and #state.daily == Challenges.DailyCount
	if valid then
		for _, e in state.daily do
			if type(e) ~= "table" or not Challenges.byId[e.id] then
				valid = false
				break
			end
		end
	end
	if valid then
		return false
	end
	state.day = today
	state.daily = {}
	for i, id in ChallengeRules.dailyFor(userId, today) do
		state.daily[i] = { id = id, progress = 0, done = false }
	end
	return true
end

-- How much an event advances a challenge (0 when it does not count).
function ChallengeRules.amount(def: Challenges.ChallengeDef, event: Event): number
	if event.kind ~= def.event then
		return 0
	end
	if def.event == "kill" then
		local class = if event.class then CLASS_GROUP[event.class] or event.class else nil
		if class == "Streak" then
			return 0 -- killstreak kills never count toward challenges
		end
		if def.class and def.class ~= class then
			return 0
		end
		if def.headshot and not event.headshot then
			return 0
		end
	end
	local n = event.amount or 1
	return if n > 0 then n else 0
end

-- Applies an event. Returns the definitions completed by it, in order.
function ChallengeRules.record(state: State, event: Event): { Challenges.ChallengeDef }
	local completed = {}
	for _, e in state.daily do
		local def = Challenges.byId[e.id]
		if def and not e.done then
			local n = ChallengeRules.amount(def, event)
			if n > 0 then
				e.progress = math.min(def.target, e.progress + n)
				if e.progress >= def.target then
					e.done = true
					table.insert(completed, def)
				end
			end
		end
	end
	return completed
end

function ChallengeRules.text(def: Challenges.ChallengeDef): string
	return (string.gsub(def.text, "%%d", tostring(def.target)))
end

return ChallengeRules
