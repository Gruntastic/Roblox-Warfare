--!strict
-- Persistent profile schema, defaults, migration and sanitation. Pure.
local ProfileSchema = {}

ProfileSchema.VERSION = 2

export type WeaponProgress = { level: number, xp: number, kills: number }
export type Profile = {
	version: number,
	account: { level: number, xp: number, prestige: number },
	weapons: { [string]: WeaponProgress },
	stats: { kills: number, deaths: number, matches: number, wins: number, headshots: number },
	loadouts: { { name: string, primary: string, secondary: string } },
	selectedLoadout: number,
	inventory: { [string]: number }, -- cosmetics (Phase 5)
	processedReceipts: { [string]: number }, -- purchaseId -> unix time (Phase 6)
	createdAt: number,
	lastSeen: number,
}

function ProfileSchema.default(now: number, loadoutSlots: number): Profile
	local loadouts = {}
	for i = 1, loadoutSlots do
		loadouts[i] = { name = "Loadout " .. i, primary = "VK7", secondary = "P12" }
	end
	return {
		version = ProfileSchema.VERSION,
		account = { level = 1, xp = 0, prestige = 0 },
		weapons = {},
		stats = { kills = 0, deaths = 0, matches = 0, wins = 0, headshots = 0 },
		loadouts = loadouts,
		selectedLoadout = 1,
		inventory = {},
		processedReceipts = {},
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
}

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
				d.weapons[id] = { level = num(w.level, 1, 1, 30), xp = num(w.xp, 0, 0), kills = num(w.kills, 0, 0) }
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
				d.loadouts[i] = { name = name, primary = primary, secondary = secondary }
			end
		end
	end
	d.selectedLoadout = math.floor(num(data.selectedLoadout, 1, 1, loadoutSlots))
	if type(data.inventory) == "table" then
		d.inventory = data.inventory
	end
	if type(data.processedReceipts) == "table" then
		d.processedReceipts = data.processedReceipts
	end
	d.createdAt = num(data.createdAt, now)
	d.lastSeen = num(data.lastSeen, now)
	return d, changed
end

return ProfileSchema
