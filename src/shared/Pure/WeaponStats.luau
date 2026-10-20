--!strict
-- Pure attachment math: resolves a weapon definition plus equipped attachments into the effective
-- stats used by both the server (authoritative) and the client (feel, UI). Catalogues are passed
-- in, so this module has no requires and is testable on its own.
local WeaponStats = {}

export type Selection = { [string]: string } -- attachment slot -> attachment id

-- The gameplay-relevant subset of a WeaponDef after attachments are applied.
export type Effective = {
	id: string,
	class: string,
	fireMode: string,
	rpm: number,
	burst: { count: number, delay: number }?,
	pellets: number?,
	pelletSpread: number?,
	damage: { close: number, far: number, closeRange: number, farRange: number, maxRange: number },
	headMultiplier: number,
	limbMultiplier: number,
	magSize: number,
	reserveAmmo: number,
	reloadTime: number,
	reloadEmptyTime: number,
	equipTime: number,
	adsTime: number,
	moveSpeedMultiplier: number,
	adsMoveSpeedMultiplier: number,
	spread: { hip: number, ads: number, movingMultiplier: number },
	recoil: { vertical: number, horizontal: number, recovery: number, adsMultiplier: number },
	adsFov: number,
	scoped: boolean, -- built-in magnified scope (ADS shows a scope overlay)
	suppressed: boolean,
	muzzleOffset: CFrame,
	sightOffset: CFrame, -- eye point for ADS, relative to the grip origin
	attachments: Selection,
}

-- Maximum one attachment per slot is implied by the Selection shape.
WeaponStats.SLOTS = { "Optic", "Muzzle", "Barrel", "Underbarrel", "Magazine" }

local function m(mods: any, key: string): number
	local v = mods[key]
	return if type(v) == "number" then v else 1
end

-- Returns (ok, reason). Rejects unknown ids, wrong slots, incompatible classes and anything the
-- weapon has not unlocked at `weaponLevel`.
function WeaponStats.validate(def: any, selection: any, weaponLevel: number, catalog: { [string]: any }): (boolean, string?)
	if type(selection) ~= "table" then
		return false, "selection"
	end
	local count = 0
	for slot, id in selection do
		count += 1
		if count > #WeaponStats.SLOTS then
			return false, "toomany"
		end
		if type(slot) ~= "string" or type(id) ~= "string" then
			return false, "types"
		end
		if not table.find(def.attachmentSlots, slot) then
			return false, "slot"
		end
		local att = catalog[id]
		if not att or att.slot ~= slot then
			return false, "attachment"
		end
		if not table.find(att.classes, def.class) then
			return false, "class"
		end
		local unlockAt = def.attachmentUnlocks[id]
		if unlockAt == nil then
			return false, "notoffered"
		end
		if weaponLevel < unlockAt then
			return false, "locked"
		end
	end
	return true, nil
end

-- Drops anything invalid (used when loading stored loadouts after a content change).
function WeaponStats.sanitize(def: any, selection: any, weaponLevel: number, catalog: { [string]: any }): Selection
	local clean: Selection = {}
	if type(selection) ~= "table" then
		return clean
	end
	for _, slot in WeaponStats.SLOTS do
		local id = selection[slot]
		if type(id) == "string" then
			local single = { [slot] = id }
			if WeaponStats.validate(def, single, weaponLevel, catalog) then
				clean[slot] = id
			end
		end
	end
	return clean
end

-- Applies attachments in a fixed slot order so the result never depends on table iteration order.
-- Assumes `selection` has been validated; unknown ids are ignored.
function WeaponStats.resolve(def: any, selection: Selection?, catalog: { [string]: any }): Effective
	local damage = table.clone(def.damage)
	local spread = table.clone(def.spread)
	local recoil = table.clone(def.recoil)
	local e: Effective = {
		id = def.id,
		class = def.class,
		fireMode = def.fireMode,
		rpm = def.rpm,
		burst = def.burst,
		pellets = def.pellets,
		pelletSpread = def.pelletSpread,
		damage = damage,
		headMultiplier = def.headMultiplier,
		limbMultiplier = def.limbMultiplier,
		magSize = def.magSize,
		reserveAmmo = def.reserveAmmo,
		reloadTime = def.reloadTime,
		reloadEmptyTime = def.reloadEmptyTime,
		equipTime = def.equipTime,
		adsTime = def.adsTime,
		moveSpeedMultiplier = def.moveSpeedMultiplier,
		adsMoveSpeedMultiplier = def.adsMoveSpeedMultiplier,
		spread = spread,
		recoil = recoil,
		adsFov = if def.scope then def.scope.fov else def.adsFov,
		scoped = def.scope ~= nil,
		suppressed = false,
		muzzleOffset = def.muzzleOffset,
		sightOffset = def.sightOffset,
		attachments = {},
	}
	if not selection then
		return e
	end
	local magMult, muzzleExtend = 1, 0
	for _, slot in WeaponStats.SLOTS do
		local id = selection[slot]
		local att = if id then catalog[id] else nil
		if att and att.slot == slot then
			e.attachments[slot] = id :: string
			local mods = att.modifiers
			damage.close *= m(mods, "damage")
			damage.far *= m(mods, "damage")
			local range = m(mods, "range")
			damage.closeRange *= range
			damage.farRange *= range
			damage.maxRange *= range
			e.rpm *= m(mods, "rpm")
			magMult *= m(mods, "magSize")
			e.reloadTime *= m(mods, "reload")
			e.reloadEmptyTime *= m(mods, "reload")
			e.adsTime *= m(mods, "adsTime")
			e.equipTime *= m(mods, "equipTime")
			e.moveSpeedMultiplier *= m(mods, "moveSpeed")
			e.adsMoveSpeedMultiplier *= m(mods, "adsMoveSpeed")
			spread.hip *= m(mods, "hipSpread")
			spread.ads *= m(mods, "adsSpread")
			recoil.vertical *= m(mods, "recoilVertical")
			recoil.horizontal *= m(mods, "recoilHorizontal")
			if att.suppressed then
				e.suppressed = true
			end
			if att.muzzleExtend then
				muzzleExtend += att.muzzleExtend
			end
			-- A magnified scope is part of the weapon; optics only replace iron sights.
			if att.optic and not def.scope then
				e.adsFov = att.optic.fov
				e.sightOffset = CFrame.new((def.anchors.optic :: CFrame).Position + Vector3.new(0, att.optic.sightHeight, 0))
			end
		end
	end
	if magMult ~= 1 then
		local newMag = math.max(1, math.floor(def.magSize * magMult + 0.5))
		e.reserveAmmo = math.floor(def.reserveAmmo * newMag / def.magSize + 0.5)
		e.magSize = newMag
	end
	if muzzleExtend ~= 0 then
		e.muzzleOffset = def.muzzleOffset * CFrame.new(0, 0, -muzzleExtend)
	end
	return e
end

-- 0..100 ratings for UI stat bars. Bounds are fixed so bars compare across weapons.
local function scale(v: number, lo: number, hi: number): number
	return math.floor(math.clamp((v - lo) / (hi - lo), 0, 1) * 100 + 0.5)
end

export type Ratings = { damage: number, range: number, fireRate: number, accuracy: number, mobility: number, control: number }

function WeaponStats.ratings(e: Effective): Ratings
	local perShot = e.damage.close * (e.pellets or 1)
	local mobility = (e.moveSpeedMultiplier * 0.6 + (1 / math.max(e.adsTime, 0.05)) * 0.02 + (1 / math.max(e.equipTime, 0.05)) * 0.02)
	return {
		damage = scale(perShot, 15, 120),
		range = scale(e.damage.farRange, 20, 400),
		fireRate = scale(e.rpm, 40, 1100),
		accuracy = 100 - scale(e.spread.hip * 0.5 + e.spread.ads * 8, 0.5, 6),
		mobility = scale(mobility, 0.6, 1.0),
		control = 100 - scale(e.recoil.vertical + e.recoil.horizontal * 1.5, 0.2, 3.5),
	}
end

return WeaponStats
