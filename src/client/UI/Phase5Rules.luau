--!strict
-- Pure helpers for the Phase 5 client UI (perks, killstreaks, challenges, cosmetics). Helper
-- module only: exports no init/start. It requires nothing; callers pass catalogue entries and
-- payloads in, so the Lune specs (tests/specs/phase5_ui.spec.luau) can load it directly.

local Phase5Rules = {}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

function Phase5Rules.roman(n: number): string
	return ROMAN[n] or tostring(n)
end

-- Perk defs grouped by tier (1..3), each tier sorted by unlock level then name.
function Phase5Rules.perkTiers(list: { any }): { { any } }
	local tiers: { { any } } = { {}, {}, {} }
	for _, def in list do
		local t = tiers[def.tier]
		if t then
			table.insert(t, def)
		end
	end
	for _, t in tiers do
		table.sort(t, function(a, b)
			if a.unlockLevel ~= b.unlockLevel then
				return a.unlockLevel < b.unlockLevel
			end
			return a.name < b.name
		end)
	end
	return tiers
end

-- Sum of streak discounts (Hardline) over a perk selection.
function Phase5Rules.streakDiscount(perks: { string }, perkById: { [string]: any }): number
	local d = 0
	for _, id in perks do
		local def = perkById[id]
		if def and def.effects and type(def.effects.streakDiscount) == "number" then
			d += def.effects.streakDiscount
		end
	end
	return d
end

-- Toggles a streak in a selection: removes it if present, otherwise adds it when there is room.
-- The result is ordered by `costOf` (cheapest first, ties by id) so keys 5/6/7 rise with cost.
-- Returns (newList, changed). Never mutates the input.
function Phase5Rules.toggleStreak(list: { string }, id: string, max: number, costOf: (string) -> number): ({ string }, boolean)
	local out = table.clone(list)
	local i = table.find(out, id)
	if i then
		table.remove(out, i)
		return out, true
	end
	if #out >= max then
		return out, false
	end
	table.insert(out, id)
	table.sort(out, function(a, b)
		local ca, cb = costOf(a), costOf(b)
		if ca ~= cb then
			return ca < cb
		end
		return a < b
	end)
	return out, true
end

export type Requirement = { text: string, progress: string, alpha: number }

-- Unlock requirement of a camo for one weapon's progress ({ kills, headshots } or nil).
-- "75 KILLS" / "42/75"; the mastery camo: "300 KILLS +100 HEADSHOTS" / "300/300 · 12/100".
-- Where a store cosmetic comes from, for locked cards (nil for items earned by play).
local SOURCE_TEXT: { [string]: string } = { shop = "STORE", crate = "SUPPLY CRATE", premium = "FOUNDER PACK" }
function Phase5Rules.sourceText(source: string?): string?
	return if source then SOURCE_TEXT[source] or "STORE" else nil
end

function Phase5Rules.camoRequirement(camo: any, weapon: any): Requirement
	if camo.source then
		return { text = Phase5Rules.sourceText(camo.source) :: string, progress = "", alpha = 0 }
	end
	local kills = if weapon and type(weapon.kills) == "number" then weapon.kills else 0
	local heads = if weapon and type(weapon.headshots) == "number" then weapon.headshots else 0
	local needK = camo.kills or 0
	local needH = camo.headshots
	if needK <= 0 and not needH then
		return { text = "DEFAULT", progress = "", alpha = 1 }
	end
	local text = string.format("%d KILLS", needK)
	local progress = string.format("%d/%d", math.min(kills, needK), needK)
	local alpha = if needK > 0 then math.clamp(kills / needK, 0, 1) else 1
	if needH and needH > 0 then
		text ..= string.format(" +%d HEADSHOTS", needH)
		progress ..= string.format(" · %d/%d", math.min(heads, needH), needH)
		alpha = (alpha + math.clamp(heads / needH, 0, 1)) / 2
	end
	return { text = text, progress = progress, alpha = alpha }
end

local STAT_NAMES: { [string]: string } = {
	kills = "KILLS",
	headshots = "HEADSHOT KILLS",
	wins = "WINS",
	captures = "FLAG CAPTURES",
	plants = "BOMB PLANTS",
	defuses = "DEFUSES",
	tags = "TAGS",
	dailies = "DAILY CHALLENGES",
	assists = "ASSISTS",
	matches = "MATCHES",
}

-- Unlock requirement of a title for the lifetime stats in a ProfileSummary.
function Phase5Rules.titleRequirement(title: any, stats: any): Requirement
	if title.source then
		return { text = Phase5Rules.sourceText(title.source) :: string, progress = Phase5Rules.sourceText(title.source) :: string, alpha = 0 }
	end
	if not title.stat then
		return { text = "OWNED BY EVERYONE", progress = "", alpha = 1 }
	end
	local need = title.value or 0
	local have = if type(stats) == "table" and type(stats[title.stat]) == "number" then stats[title.stat] else 0
	return {
		text = string.format("%d %s", need, STAT_NAMES[title.stat] or string.upper(title.stat)),
		progress = string.format("%d/%d", math.min(have, need), need),
		alpha = if need > 0 then math.clamp(have / need, 0, 1) else 1,
	}
end

-- "5H 12M", "12M 30S", "45S"; never negative.
function Phase5Rules.countdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m, sec = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then
		return string.format("%dH %02dM", h, m)
	elseif m > 0 then
		return string.format("%dM %02dS", m, sec)
	end
	return string.format("%dS", sec)
end

-- Whether a team-wide streak effect (Jammed, Blackout) hits the local player. `effectTeam` is the
-- victim team; in Free-for-All it is nil and everyone except the owner is a victim.
function Phase5Rules.isVictim(effectTeam: string?, ownerUserId: number?, myTeam: string?, myUserId: number): boolean
	if type(effectTeam) == "string" then
		return effectTeam == myTeam
	end
	return ownerUserId ~= myUserId
end

-- Whether an activation by (team, owner) is friendly to the local player.
function Phase5Rules.isFriendly(team: string?, ownerUserId: number?, myTeam: string?, myUserId: number): boolean
	if ownerUserId == myUserId then
		return true
	end
	return type(team) == "string" and team == myTeam
end

export type TrayEntry = { id: string, cost: number, ready: number, key: number, progress: number, newest: boolean }

-- Tray view of a StreakStatePayload: one entry per equipped streak (loadout order) with how many
-- of it are ready, the 5/6/7 key index, kill progress towards it this life (0..1) and whether it
-- is the most recently earned ready one (what gamepad D-pad up uses).
function Phase5Rules.tray(state: any): { TrayEntry }
	local out: { TrayEntry } = {}
	if type(state) ~= "table" or type(state.equipped) ~= "table" then
		return out
	end
	local ready = if type(state.ready) == "table" then state.ready else {}
	local newest = ready[#ready]
	local count = if type(state.count) == "number" then state.count else 0
	for i, e in state.equipped do
		if type(e) == "table" and type(e.id) == "string" then
			local n = 0
			for _, r in ready do
				if r == e.id then
					n += 1
				end
			end
			local cost = if type(e.cost) == "number" and e.cost > 0 then e.cost else 1
			table.insert(out, {
				id = e.id,
				cost = cost,
				ready = n,
				key = i,
				progress = math.clamp(count / cost, 0, 1),
				newest = newest == e.id,
			})
		end
	end
	return out
end

-- The streak keys 5/6/7 (index 1..3) would use, or nil when that slot is not ready.
function Phase5Rules.pickByIndex(state: any, index: number): string?
	if type(state) ~= "table" or type(state.equipped) ~= "table" or type(state.ready) ~= "table" then
		return nil
	end
	local e = state.equipped[index]
	if type(e) == "table" and table.find(state.ready, e.id) then
		return e.id
	end
	return nil
end

-- The most recently earned ready streak (gamepad D-pad up), or nil.
function Phase5Rules.pickNewest(state: any): string?
	if type(state) ~= "table" or type(state.ready) ~= "table" then
		return nil
	end
	local id = state.ready[#state.ready]
	return if type(id) == "string" then id else nil
end

-- Emblem id to show for a player: their equipped one, or nil.
function Phase5Rules.lineEmblem(line: any): string?
	local e = if type(line) == "table" then line.emblem else nil
	return if type(e) == "string" and e ~= "" then e else nil
end

-- Emblem id that represents a prestige level (clamped to the catalogue size), or nil at 0.
function Phase5Rules.prestigeEmblem(prestige: number?, maxEmblems: number): string?
	if type(prestige) ~= "number" or prestige <= 0 then
		return nil
	end
	return "Prestige" .. tostring(math.clamp(math.floor(prestige), 1, maxEmblems))
end

-- Challenge text with its target substituted ("Get %d kills" -> "Get 15 kills").
function Phase5Rules.challengeText(text: string, target: number): string
	if string.find(text, "%d", 1, true) then
		return (string.gsub(text, "%%d", tostring(target)))
	end
	return text
end

return Phase5Rules
