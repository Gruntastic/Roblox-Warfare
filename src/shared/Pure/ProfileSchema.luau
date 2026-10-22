--!strict
-- Persistent profile schema, defaults, migration and sanitation. Pure.
local ProfileSchema = {}

-- Kept in step with Config/Perks.Defaults and Config/Killstreaks.Defaults (checked by the specs);
-- copied here so the schema stays free of requires.
local DEFAULT_PERKS = { "Fleetfoot", "Quickhands", "SecondWind" }
local DEFAULT_STREAKS = { "ReconDrone", "MortarBarrage" }
ProfileSchema.DEFAULT_PERKS = DEFAULT_PERKS
ProfileSchema.DEFAULT_STREAKS = DEFAULT_STREAKS

ProfileSchema.VERSION = 5

export type WeaponProgress = { level: number, xp: number, kills: number, headshots: number }
export type Loadout = {
	name: string,
	primary: string,
	secondary: string,
	primaryAttachments: { [string]: string }, -- attachment slot -> attachment id
	secondaryAttachments: { [string]: string },
	perks: { string }, -- one id per tier (1..3); validity/unlocks are checked by PerkRules on use
	streaks: { string }, -- up to three killstreak ids; checked by StreakRules on use
}
export type ChallengeEntry = { id: string, progress: number, done: boolean }
export type Equipped = { title: string, emblem: string?, gear: string?, camos: { [string]: string } }
export type Profile = {
	version: number,
	account: { level: number, xp: number, prestige: number },
	weapons: { [string]: WeaponProgress },
	stats: {
		kills: number,
		deaths: number,
		matches: number,
		wins: number,
		headshots: number,
		assists: number,
		captures: number,
		plants: number,
		defuses: number,
		tags: number, -- Kill Confirmed tags collected (confirms and denies)
		dailies: number, -- daily challenges completed
		cratesOpened: number,
	},
	loadouts: { Loadout },
	selectedLoadout: number,
	challenges: { day: number, daily: { ChallengeEntry } },
	equipped: Equipped,
	inventory: { [string]: number }, -- "<Kind>:<id>" -> count: store cosmetics (1) and unopened crates ("Crate:<id>")
	processedReceipts: { [string]: number }, -- Robux purchaseId -> unix time it was granted
	wallet: { credits: number }, -- earned by play only (Config/Store.luau)
	dailyCrateDay: number, -- UTC day the all-dailies crate was last given
	createdAt: number,
	lastSeen: number,
}

function ProfileSchema.default(now: number, loadoutSlots: number): Profile
	local loadouts = {}
	for i = 1, loadoutSlots do
		loadouts[i] = {
			name = "Loadout " .. i,
			primary = "VK7",
			secondary = "P12",
			primaryAttachments = {},
			secondaryAttachments = {},
			perks = table.clone(DEFAULT_PERKS),
			streaks = table.clone(DEFAULT_STREAKS),
		}
	end
	return {
		version = ProfileSchema.VERSION,
		account = { level = 1, xp = 0, prestige = 0 },
		weapons = {},
		stats = { kills = 0, deaths = 0, matches = 0, wins = 0, headshots = 0, assists = 0, captures = 0, plants = 0, defuses = 0, tags = 0, dailies = 0, cratesOpened = 0 },
		loadouts = loadouts,
		selectedLoadout = 1,
		challenges = { day = 0, daily = {} },
		equipped = { title = "Recruit", emblem = nil, camos = {} },
		inventory = {},
		processedReceipts = {},
		wallet = { credits = 0 },
		dailyCrateDay = 0,
		createdAt = now,
		lastSeen = now,
	}
end

-- Ordered migrations: MIGRATIONS[n] upgrades a version-n profile to version n+1.
local MIGRATIONS: { [number]: (any) -> any } = {
	-- v1 stored account progress as flat fields `level`/`xp` and had no loadouts.
	[1] = function(old)
		local new = {
			version = 2,
			account = { level = old.level or 1, xp = old.xp or 0, prestige = old.prestige or 0 },
			weapons = old.weapons or {},
			stats = old.stats or {},
			loadouts = {},
			selectedLoadout = 1,
			inventory = old.inventory or {},
			processedReceipts = old.processedReceipts or {},
			createdAt = old.createdAt or 0,
			lastSeen = old.lastSeen or 0,
		}
		return new
	end,
	-- v3 added per-weapon attachment selections to loadouts (empty for existing loadouts).
	[2] = function(old)
		old.version = 3
		if type(old.loadouts) == "table" then
			for _, l in old.loadouts do
				if type(l) == "table" then
					l.primaryAttachments = {}
					l.secondaryAttachments = {}
				end
			end
		end
		return old
	end,
	-- v4 (Phase 5) added perks and killstreaks to loadouts, per-weapon headshots, more lifetime
	-- stats, daily challenges and equipped cosmetics. Missing fields are filled by `migrate`.
	[3] = function(old)
		old.version = 4
		if type(old.loadouts) == "table" then
			for _, l in old.loadouts do
				if type(l) == "table" then
					l.perks = table.clone(DEFAULT_PERKS)
					l.streaks = table.clone(DEFAULT_STREAKS)
				end
			end
		end
		return old
	end,
	-- v5 (Phase 6) added the credit wallet, crates opened and the daily crate marker. Filled with
	-- defaults by `migrate`.
	[4] = function(old)
		old.version = 5
		return old
	end,
}

-- Shape-only check of an attachment selection: at most five string -> string entries. Whether the
-- ids are real, compatible and unlocked is checked by WeaponStats on the server.
local function attachmentMap(v: any): { [string]: string }
	local out = {}
	if type(v) ~= "table" then
		return out
	end
	local n = 0
	for slot, id in v do
		if type(slot) == "string" and type(id) == "string" and #slot <= 16 and #id <= 32 then
			n += 1
			if n > 5 then
				break
			end
			out[slot] = id
		end
	end
	return out
end
ProfileSchema.attachmentMap = attachmentMap

-- Shape-only check of a short list of ids (perks, streaks): strings of sane length, in order.
local function stringList(v: any, max: number): { string }?
	if type(v) ~= "table" then
		return nil
	end
	local out = {}
	for i = 1, max do
		local id = v[i]
		if type(id) ~= "string" or #id > 32 then
			break
		end
		out[i] = id
	end
	return out
end

local function num(v: any, default: number, min: number?, max: number?): number
	if type(v) ~= "number" or v ~= v then
		return default
	end
	if min and v < min then
		return min
	end
	if max and v > max then
		return max
	end
	return v
end

-- Upgrades and repairs any stored value into a valid current-version profile.
-- `validWeapons` is the set of known weapon ids; unknown loadout entries fall back to defaults.
function ProfileSchema.migrate(data: any, now: number, loadoutSlots: number, validWeapons: { [string]: string }): (Profile, boolean)
	if type(data) ~= "table" then
		return ProfileSchema.default(now, loadoutSlots), true
	end
	local changed = false
	local version = num(data.version, 1)
	if version > ProfileSchema.VERSION then
		error(("profile version %d is newer than server version %d"):format(version, ProfileSchema.VERSION))
	end
	while version < ProfileSchema.VERSION do
		data = MIGRATIONS[version](data)
		version = data.version
		changed = true
	end

	local d = ProfileSchema.default(now, loadoutSlots)
	local acct = type(data.account) == "table" and data.account or {}
	d.account = { level = num(acct.level, 1, 1, 70), xp = num(acct.xp, 0, 0), prestige = num(acct.prestige, 0, 0, 10) }
	if type(data.weapons) == "table" then
		for id, w in data.weapons do
			if type(id) == "string" and type(w) == "table" then
				d.weapons[id] = { level = num(w.level, 1, 1, 30), xp = num(w.xp, 0, 0), kills = num(w.kills, 0, 0), headshots = num(w.headshots, 0, 0) }
			end
		end
	end
	local stats = type(data.stats) == "table" and data.stats or {}
	for key in d.stats do
		d.stats[key] = num(stats[key], 0, 0)
	end
	if type(data.loadouts) == "table" then
		for i = 1, loadoutSlots do
			local l = data.loadouts[i]
			if type(l) == "table" then
				local primary = if validWeapons[l.primary] == "Primary" then l.primary else d.loadouts[i].primary
				local secondary = if validWeapons[l.secondary] == "Secondary" then l.secondary else d.loadouts[i].secondary
				local name = if type(l.name) == "string" then string.sub(l.name, 1, 24) else d.loadouts[i].name
				d.loadouts[i] = {
					name = name,
					primary = primary,
					secondary = secondary,
					-- a changed weapon invalidates its attachments
					primaryAttachments = if primary == l.primary then attachmentMap(l.primaryAttachments) else {},
					secondaryAttachments = if secondary == l.secondary then attachmentMap(l.secondaryAttachments) else {},
					perks = stringList(l.perks, 3) or d.loadouts[i].perks,
					streaks = stringList(l.streaks, 3) or d.loadouts[i].streaks,
				}
			end
		end
	end
	d.selectedLoadout = math.floor(num(data.selectedLoadout, 1, 1, loadoutSlots))
	local ch = data.challenges
	if type(ch) == "table" and type(ch.daily) == "table" then
		local daily = {}
		for i = 1, 5 do
			local e = ch.daily[i]
			if type(e) ~= "table" or type(e.id) ~= "string" or #e.id > 32 then
				break
			end
			daily[i] = { id = e.id, progress = num(e.progress, 0, 0), done = e.done == true }
		end
		d.challenges = { day = math.floor(num(ch.day, 0, 0)), daily = daily }
	end
	local eq = data.equipped
	if type(eq) == "table" then
		-- shape only; ownership is re-checked by CosmeticRules.sanitizeEquipped on use
		d.equipped.title = if type(eq.title) == "string" and #eq.title <= 32 then eq.title else d.equipped.title
		d.equipped.emblem = if type(eq.emblem) == "string" and #eq.emblem <= 32 then eq.emblem else nil
		d.equipped.gear = if type(eq.gear) == "string" and #eq.gear <= 32 then eq.gear else nil
		if type(eq.camos) == "table" then
			for weaponId, camoId in eq.camos do
				if type(weaponId) == "string" and type(camoId) == "string" and #weaponId <= 32 and #camoId <= 32 then
					d.equipped.camos[weaponId] = camoId
				end
			end
		end
	end
	if type(data.inventory) == "table" then
		for key, n in data.inventory do
			if type(key) == "string" and #key <= 64 and type(n) == "number" and n == n and n >= 1 then
				d.inventory[key] = math.min(math.floor(n), 1000)
			end
		end
	end
	if type(data.processedReceipts) == "table" then
		for id, t in data.processedReceipts do
			if type(id) == "string" and #id <= 128 and type(t) == "number" and t == t then
				d.processedReceipts[id] = t
			end
		end
	end
	local wallet = type(data.wallet) == "table" and data.wallet or {}
	d.wallet = { credits = math.floor(num(wallet.credits, 0, 0, 1000000)) }
	d.dailyCrateDay = math.floor(num(data.dailyCrateDay, 0, 0))
	d.createdAt = num(data.createdAt, now)
	d.lastSeen = num(data.lastSeen, now)
	return d, changed
end

return ProfileSchema
