--!strict
-- Pure cosmetic ownership and equip validation, plus prestige rules. Ownership is derived from
-- progress (weapon kills / headshots, lifetime stats, prestige reached) or from an inventory entry
-- "<Kind>:<id>" (reserved for items obtained another way, e.g. the Phase 6 store).
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)

local CosmeticRules = {}

export type Kind = "Camo" | "Title" | "Emblem"
export type Equipped = { title: string, emblem: string?, camos: { [string]: string } }

local function inInventory(profile: any, kind: string, id: string): boolean
	local inv = profile.inventory
	return type(inv) == "table" and type(inv[kind .. ":" .. id]) == "number" and inv[kind .. ":" .. id] > 0
end

function CosmeticRules.ownsCamo(profile: any, weaponId: string, camoId: string): boolean
	local def = Cosmetics.camoById[camoId]
	if not def then
		return false
	end
	if inInventory(profile, "Camo", camoId) then
		return true
	end
	local w = profile.weapons and profile.weapons[weaponId]
	local kills = if w then w.kills or 0 else 0
	local headshots = if w then w.headshots or 0 else 0
	return kills >= def.kills and headshots >= (def.headshots or 0)
end

function CosmeticRules.ownsTitle(profile: any, titleId: string): boolean
	local def = Cosmetics.titleById[titleId]
	if not def then
		return false
	end
	if not def.stat or inInventory(profile, "Title", titleId) then
		return true
	end
	local stats = profile.stats or {}
	return (stats[def.stat] or 0) >= (def.value or 0)
end

function CosmeticRules.ownsEmblem(profile: any, emblemId: string): boolean
	local def = Cosmetics.emblemById[emblemId]
	if not def then
		return false
	end
	return (profile.account and profile.account.prestige or 0) >= def.prestige or inInventory(profile, "Emblem", emblemId)
end

-- Everything a profile owns, for the client: camos per weapon id in `weaponIds`.
function CosmeticRules.owned(profile: any, weaponIds: { string }): { titles: { string }, emblems: { string }, camos: { [string]: { string } } }
	local out = { titles = {}, emblems = {}, camos = {} }
	for _, t in Cosmetics.titles do
		if CosmeticRules.ownsTitle(profile, t.id) then
			table.insert(out.titles, t.id)
		end
	end
	for _, e in Cosmetics.emblems do
		if CosmeticRules.ownsEmblem(profile, e.id) then
			table.insert(out.emblems, e.id)
		end
	end
	for _, weaponId in weaponIds do
		local list = {}
		for _, c in Cosmetics.camos do
			if CosmeticRules.ownsCamo(profile, weaponId, c.id) then
				table.insert(list, c.id)
			end
		end
		out.camos[weaponId] = list
	end
	return out
end

-- The equipped set with anything no longer owned (or malformed) replaced by defaults.
function CosmeticRules.sanitizeEquipped(profile: any, equipped: any): Equipped
	local out: Equipped = { title = Cosmetics.DefaultTitle, emblem = nil, camos = {} }
	if type(equipped) ~= "table" then
		return out
	end
	if type(equipped.title) == "string" and CosmeticRules.ownsTitle(profile, equipped.title) then
		out.title = equipped.title
	end
	if type(equipped.emblem) == "string" and CosmeticRules.ownsEmblem(profile, equipped.emblem) then
		out.emblem = equipped.emblem
	end
	if type(equipped.camos) == "table" then
		for weaponId, camoId in equipped.camos do
			if type(weaponId) == "string" and type(camoId) == "string" and camoId ~= Cosmetics.DefaultCamo and CosmeticRules.ownsCamo(profile, weaponId, camoId) then
				out.camos[weaponId] = camoId
			end
		end
	end
	return out
end

local function result(ok: boolean): (boolean, string?)
	if ok then
		return true, nil
	end
	return false, "locked"
end

-- Returns (ok, reason) for an equip request. Emblem "" unequips; camo "Factory" is the default.
function CosmeticRules.canEquip(profile: any, kind: any, id: any, weaponId: any): (boolean, string?)
	if type(id) ~= "string" or #id > 32 then
		return false, "shape"
	end
	if kind == "Camo" then
		if type(weaponId) ~= "string" or #weaponId > 32 then
			return false, "shape"
		end
		if id == Cosmetics.DefaultCamo then
			return true, nil
		end
		return result(CosmeticRules.ownsCamo(profile, weaponId, id))
	elseif kind == "Title" then
		return result(CosmeticRules.ownsTitle(profile, id))
	elseif kind == "Emblem" then
		if id == "" then
			return true, nil
		end
		return result(CosmeticRules.ownsEmblem(profile, id))
	end
	return false, "kind"
end

-- Prestige: available at the maximum account level, up to the maximum prestige. Prestiging sets
-- the account back to level 1 and keeps everything else (weapons, attachments, perks, streaks,
-- cosmetics stay unlocked once a player has prestiged).
function CosmeticRules.canPrestige(profile: any, maxLevel: number, maxPrestige: number): boolean
	return profile.account.level >= maxLevel and profile.account.prestige < maxPrestige
end

function CosmeticRules.applyPrestige(profile: any)
	profile.account.prestige += 1
	profile.account.level = 1
	profile.account.xp = 0
end

return CosmeticRules
