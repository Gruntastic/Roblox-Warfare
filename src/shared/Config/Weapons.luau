--!strict
-- Data-driven weapon definitions. Every gameplay number the server validates lives here.
-- Distances are in studs (1 stud ~= 0.28 m). Damage values assume 100 max health.

export type DamageProfile = {
	close: number, -- damage at or below closeRange
	far: number, -- damage at or beyond farRange (linear falloff between)
	closeRange: number,
	farRange: number,
	maxRange: number, -- shots beyond this distance deal no damage
}

export type ModelPart = {
	name: string,
	shape: "Block" | "Cylinder",
	size: Vector3,
	offset: CFrame, -- relative to the weapon's grip origin
	color: Color3,
	material: Enum.Material,
}

export type WeaponClass = "AssaultRifle" | "SMG" | "LMG" | "Marksman" | "Sniper" | "Shotgun" | "Pistol" | "MachinePistol"
export type AttachmentSlot = "Optic" | "Muzzle" | "Barrel" | "Underbarrel" | "Magazine"

-- Where attachment models mount, relative to the grip origin. Each attachment's model parts are
-- authored relative to its slot's anchor. Muzzle devices mount at `muzzle` (== muzzleOffset).
export type Anchors = {
	optic: CFrame, -- top of the receiver rail, centred; +Y is up
	muzzle: CFrame,
	underbarrel: CFrame?, -- nil when the weapon has no underbarrel rail
	magazine: CFrame, -- mag well; magazine attachments replace the part named "Magazine"
	leftHand: CFrame, -- where the viewmodel's left hand holds the weapon (handguard or grip)
}

export type WeaponDef = {
	id: string,
	displayName: string,
	description: string,
	class: WeaponClass,
	slot: "Primary" | "Secondary",
	fireMode: "Auto" | "Semi" | "Burst",
	rpm: number, -- for Burst: the rate inside a burst
	burst: { count: number, delay: number }?, -- Burst only: rounds per trigger pull, seconds between bursts
	pellets: number?, -- shotguns: pellets per shot; `damage` is per pellet
	pelletSpread: number?, -- shotguns: pellet cone radius in degrees (fixed pattern, see Pure/Pellets)
	damage: DamageProfile,
	headMultiplier: number,
	limbMultiplier: number,
	magSize: number,
	reserveAmmo: number,
	reloadTime: number, -- tactical reload (rounds remaining)
	reloadEmptyTime: number,
	equipTime: number,
	adsTime: number,
	moveSpeedMultiplier: number,
	adsMoveSpeedMultiplier: number,
	spread: { hip: number, ads: number, movingMultiplier: number }, -- degrees
	recoil: { vertical: number, horizontal: number, recovery: number, adsMultiplier: number }, -- degrees per shot
	adsFov: number, -- iron-sight ADS field of view
	scope: { fov: number }?, -- built-in magnified scope (snipers): ADS uses this FOV and a scope overlay
	unlockLevel: number, -- account level that unlocks the weapon
	muzzleOffset: CFrame, -- relative to grip origin
	sightOffset: CFrame, -- iron-sight eye point relative to grip origin (ADS aligns the camera here)
	anchors: Anchors,
	attachmentSlots: { AttachmentSlot }, -- slots this weapon accepts
	attachmentUnlocks: { [string]: number }, -- attachment id -> weapon level that unlocks it
	sounds: { fire: string, reload: string, equip: string },
	model: { ModelPart },
}

-- Muted original palette.
local GUNMETAL = Color3.fromRGB(46, 48, 52)
local POLYMER = Color3.fromRGB(64, 62, 56)
local TAN = Color3.fromRGB(150, 128, 92)
local DARK = Color3.fromRGB(30, 31, 34)
local STEEL = Color3.fromRGB(96, 99, 104)
local OLIVE = Color3.fromRGB(84, 90, 66)
local SLATE = Color3.fromRGB(68, 76, 86)
local RUST = Color3.fromRGB(122, 84, 62)
local SAND = Color3.fromRGB(170, 154, 120)
local BONE = Color3.fromRGB(190, 182, 164)
local WALNUT = Color3.fromRGB(96, 66, 44)
local FOREST = Color3.fromRGB(52, 64, 50)
local PLUM = Color3.fromRGB(80, 64, 74)
local TEAL = Color3.fromRGB(58, 84, 82)
local GLASS = Color3.fromRGB(120, 170, 160)

local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic
local WOOD = Enum.Material.Wood

local V3 = Vector3.new
local CF = CFrame.new
local RAD = math.rad
local CYL = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along -Z (the barrel axis)
local function tilt(deg: number): CFrame
	-- Positive tilts the top of a part back (+Z), so its bottom swings forward.
	return CFrame.Angles(RAD(deg), 0, 0)
end

local function part(name: string, size: Vector3, offset: CFrame, color: Color3?, shape: ("Block" | "Cylinder")?, material: Enum.Material?): ModelPart
	return {
		name = name,
		shape = shape or "Block",
		size = size,
		offset = offset,
		color = color or GUNMETAL,
		material = material or METAL,
	}
end

-- Model builders. They run once when this module loads and return plain data (parts, anchors,
-- muzzle and sight points), so every weapon below stays a plain WeaponDef at runtime.
type Geo = { model: { ModelPart }, anchors: Anchors, muzzle: CFrame, sight: CFrame }

type LongOpts = {
	recFront: number, -- receiver length forward of the grip
	recH: number,
	recW: number?,
	hg: "Slim" | "Quad" | "Round" | "Vented" | "Shroud" | "Pump",
	hgLen: number,
	hgH: number,
	barLen: number, -- exposed barrel ahead of the handguard
	barD: number?,
	device: "Brake" | "Flash" | "Cap" | "None",
	stock: "Fixed" | "Skeleton" | "Wire" | "Thumbhole" | "Bullpup" | "Pad" | "None",
	mag: "Curved" | "Straight" | "Stick" | "Short" | "Box" | "Drum" | "ShellBox" | "Tube",
	magZ: number?, -- mag well distance forward of the grip (negative = behind it, bullpups)
	sights: "Iron" | "Bead" | "Scope",
	underbarrel: boolean,
	bipod: boolean?,
	wood: boolean?, -- furniture is wood instead of polymer
	body: Color3,
	furniture: Color3,
	accent: Color3,
	extras: { ModelPart }?, -- per-weapon details
}

local REC_Y = 0.1 -- receiver centre height
local BORE_Y = 0.12 -- barrel axis height

local function longGun(o: LongOpts): Geo
	local parts: { ModelPart } = {}
	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, shape: ("Block" | "Cylinder")?, material: Enum.Material?)
		table.insert(parts, part(name, size, offset, color, shape, material))
	end
	local furnMat = if o.wood then WOOD else PLASTIC
	local recW = o.recW or 0.22
	local bullpup = o.stock == "Bullpup"
	local recBack = if bullpup then 0.8 else 0.15
	local recTop, recBot = REC_Y + o.recH / 2, REC_Y - o.recH / 2

	-- Receiver
	add("Receiver", V3(recW, o.recH, o.recFront + recBack), CF(0, REC_Y, (recBack - o.recFront) / 2), o.body)
	add("EjectionPort", V3(0.02, 0.08, 0.22), CF(recW / 2 + 0.01, REC_Y + 0.03, if bullpup then 0.3 else -0.35), DARK)
	add("ChargingHandle", V3(0.08, 0.05, 0.08), CF(-(recW / 2 + 0.04), REC_Y + 0.05, -o.recFront + 0.25), o.accent)

	-- Top rail: the optic anchor sits on top of it.
	local railLen = math.min(o.recFront, 1.0)
	local railZ = 0.05 - railLen / 2
	local railTop = recTop + 0.05
	add("Rail", V3(0.1, 0.05, railLen), CF(0, recTop + 0.025, railZ), DARK)

	-- Sights
	local sightY, sightZ
	if o.sights == "Scope" then
		local scopeY = railTop + 0.14
		add("ScopeMountRear", V3(0.08, 0.14, 0.08), CF(0, railTop + 0.07, railZ + 0.25), DARK)
		add("ScopeMountFront", V3(0.08, 0.14, 0.08), CF(0, railTop + 0.07, railZ - 0.25), DARK)
		add("ScopeTube", V3(0.95, 0.11, 0.11), CF(0, scopeY, railZ) * CYL, DARK, "Cylinder")
		add("ScopeObjective", V3(0.25, 0.18, 0.18), CF(0, scopeY, railZ - 0.55) * CYL, DARK, "Cylinder")
		add("ScopeLens", V3(0.01, 0.15, 0.15), CF(0, scopeY, railZ - 0.68) * CYL, GLASS, "Cylinder", Enum.Material.Glass)
		add("ScopeEyepiece", V3(0.18, 0.15, 0.15), CF(0, scopeY, railZ + 0.52) * CYL, DARK, "Cylinder")
		add("ScopeTurret", V3(0.07, 0.08, 0.07), CF(0, scopeY + 0.09, railZ), o.accent)
		sightY, sightZ = scopeY, railZ + 0.76
	else
		local rearH = if o.sights == "Bead" then 0.05 else 0.09
		add("RearSight", V3(0.1, rearH, 0.07), CF(0, railTop + rearH / 2, -0.12), DARK)
		sightY, sightZ = railTop + rearH, 0.08
	end

	-- Handguard
	local hgZc = -(o.recFront + o.hgLen / 2)
	local hgW = recW - 0.02
	local hgY = if o.hg == "Pump" then BORE_Y - 0.12 elseif o.hg == "Shroud" then BORE_Y else REC_Y
	local hgTop, hgBot = hgY + o.hgH / 2, hgY - o.hgH / 2
	if o.hg == "Slim" then
		add("Handguard", V3(hgW, o.hgH, o.hgLen), CF(0, hgY, hgZc), o.furniture, nil, furnMat)
	elseif o.hg == "Quad" then
		add("Handguard", V3(hgW, o.hgH, o.hgLen), CF(0, hgY, hgZc), o.furniture, nil, furnMat)
		add("SideRailL", V3(0.03, 0.05, o.hgLen * 0.8), CF(-hgW / 2 - 0.015, hgY, hgZc), DARK)
		add("SideRailR", V3(0.03, 0.05, o.hgLen * 0.8), CF(hgW / 2 + 0.015, hgY, hgZc), DARK)
		add("BottomRail", V3(0.06, 0.03, o.hgLen * 0.8), CF(0, hgBot - 0.015, hgZc), DARK)
		hgBot -= 0.03
	elseif o.hg == "Round" then
		add("Handguard", V3(o.hgLen, o.hgH, o.hgH), CF(0, hgY, hgZc) * CYL, o.furniture, "Cylinder", furnMat)
		add("HandguardCap", V3(0.05, o.hgH + 0.03, o.hgH + 0.03), CF(0, hgY, hgZc - o.hgLen / 2 + 0.025) * CYL, DARK, "Cylinder")
	elseif o.hg == "Vented" then
		add("Handguard", V3(hgW, o.hgH, o.hgLen), CF(0, hgY, hgZc), o.furniture, nil, furnMat)
		for i = 1, 3 do
			local z = -(o.recFront + o.hgLen * (0.2 + 0.25 * i))
			add("VentL" .. i, V3(0.01, o.hgH * 0.4, 0.1), CF(-hgW / 2 - 0.005, hgY + 0.02, z), DARK)
			add("VentR" .. i, V3(0.01, o.hgH * 0.4, 0.1), CF(hgW / 2 + 0.005, hgY + 0.02, z), DARK)
		end
	elseif o.hg == "Shroud" then
		add("Handguard", V3(o.hgLen, o.hgH, o.hgH), CF(0, hgY, hgZc) * CYL, o.furniture, "Cylinder", furnMat)
		add("ShroudRingA", V3(0.05, o.hgH + 0.03, o.hgH + 0.03), CF(0, hgY, hgZc + o.hgLen * 0.3) * CYL, DARK, "Cylinder")
		add("ShroudRingB", V3(0.05, o.hgH + 0.03, o.hgH + 0.03), CF(0, hgY, hgZc - o.hgLen * 0.3) * CYL, DARK, "Cylinder")
		add("CarryHandle", V3(0.05, 0.05, o.hgLen * 0.4), CF(-o.hgH / 2 - 0.05, hgY + 0.04, hgZc + o.hgLen * 0.2), DARK)
	else -- Pump: a forend wrapped around the tube magazine, under the barrel
		add("Handguard", V3(hgW, o.hgH, o.hgLen), CF(0, hgY, hgZc), o.furniture, nil, furnMat)
		add("PumpRidgeA", V3(hgW + 0.02, o.hgH + 0.02, 0.04), CF(0, hgY, hgZc - o.hgLen * 0.25), o.accent)
		add("PumpRidgeB", V3(hgW + 0.02, o.hgH + 0.02, 0.04), CF(0, hgY, hgZc + o.hgLen * 0.25), o.accent)
	end

	-- Barrel and fixed muzzle device
	local barD = o.barD or 0.07
	local barStart = if o.hg == "Pump" then o.recFront else o.recFront + o.hgLen - 0.05
	local muzzleDist = o.recFront + o.hgLen + o.barLen
	add("Barrel", V3(muzzleDist - barStart, barD, barD), CF(0, BORE_Y, -(barStart + muzzleDist) / 2) * CYL, STEEL, "Cylinder")
	local devLen, devD = 0, 0
	if o.device == "Brake" then
		devLen, devD = 0.18, barD + 0.045
	elseif o.device == "Flash" then
		devLen, devD = 0.16, barD + 0.02
	elseif o.device == "Cap" then
		devLen, devD = 0.06, barD + 0.025
	end
	if devLen > 0 then
		add("MuzzleDevice", V3(devLen, devD, devD), CF(0, BORE_Y, -(muzzleDist + devLen / 2)) * CYL, DARK, "Cylinder")
	end
	local muzzle = CF(0, BORE_Y, -(muzzleDist + devLen))

	-- Front sight post rises to the sight line (on the barrel for pump guns, else the handguard front).
	if o.sights ~= "Scope" then
		local baseTop, fz
		if o.hg == "Pump" then
			baseTop, fz = BORE_Y + barD / 2, -(muzzleDist - 0.06)
		else
			baseTop, fz = hgTop, -(o.recFront + o.hgLen - 0.07)
		end
		local h = (sightY - 0.005) - baseTop
		add("FrontSight", V3(0.04, h, 0.04), CF(0, baseTop + h / 2, fz), DARK)
	end

	-- Magazine (single part named "Magazine"; magazine attachments replace it). The anchor sits
	-- 0.25 studs below the top of the mag well so attachment mags line up on every weapon.
	local magAnchor: CFrame
	if o.mag == "Tube" then
		local tubeLen = o.hgLen + o.barLen * 0.7
		magAnchor = CF(0, BORE_Y - 0.12, -(o.recFront + tubeLen / 2))
		add("Magazine", V3(tubeLen, 0.1, 0.1), magAnchor * CYL, STEEL, "Cylinder")
	else
		local magZ = o.magZ or o.recFront * 0.55
		magAnchor = CF(0, recBot - 0.25, -magZ)
		if o.mag == "Curved" then
			add("Magazine", V3(0.14, 0.5, 0.22), magAnchor * tilt(14), o.accent, nil, PLASTIC)
		elseif o.mag == "Straight" then
			add("Magazine", V3(0.13, 0.48, 0.2), magAnchor * CF(0, 0.01, 0) * tilt(5), o.accent, nil, PLASTIC)
		elseif o.mag == "Stick" then
			add("Magazine", V3(0.11, 0.6, 0.15), magAnchor * CF(0, -0.05, 0) * tilt(4), o.accent, nil, PLASTIC)
		elseif o.mag == "Short" then
			add("Magazine", V3(0.13, 0.26, 0.24), magAnchor * CF(0, 0.12, 0), o.accent, nil, PLASTIC)
		elseif o.mag == "Box" then
			add("Magazine", V3(0.3, 0.34, 0.36), magAnchor * CF(-0.04, 0.08, 0), o.accent, nil, PLASTIC)
		elseif o.mag == "Drum" then
			add("Magazine", V3(0.24, 0.5, 0.5), magAnchor, o.accent, "Cylinder", PLASTIC)
		else -- ShellBox
			add("Magazine", V3(0.18, 0.36, 0.3), magAnchor * CF(0, 0.07, 0) * tilt(6), o.accent, nil, PLASTIC)
		end
	end

	-- Pistol grip and trigger guard
	add("Grip", V3(0.14, 0.38, 0.18), CF(0, -0.17, 0.03) * tilt(-16), o.furniture, nil, furnMat)
	add("TriggerGuard", V3(0.04, 0.05, 0.26), CF(0, -0.1, -0.17), DARK)

	-- Stock
	if o.stock == "Fixed" then
		add("Stock", V3(0.16, 0.28, 0.72), CF(0, 0.04, recBack + 0.36), o.furniture, nil, furnMat)
		add("Buttpad", V3(0.17, 0.32, 0.05), CF(0, 0.03, recBack + 0.745), DARK, nil, PLASTIC)
	elseif o.stock == "Skeleton" then
		add("StockTop", V3(0.07, 0.06, 0.72), CF(0, 0.15, recBack + 0.36), o.furniture, nil, furnMat)
		add("StockBrace", V3(0.07, 0.06, 0.76), CF(0, 0.0, recBack + 0.36) * tilt(10), o.furniture, nil, furnMat)
		add("Buttpad", V3(0.15, 0.34, 0.06), CF(0, 0.06, recBack + 0.74), DARK, nil, PLASTIC)
	elseif o.stock == "Wire" then
		add("StockRodL", V3(0.03, 0.03, 0.58), CF(-0.06, 0.1, recBack + 0.29), DARK)
		add("StockRodR", V3(0.03, 0.03, 0.58), CF(0.06, 0.1, recBack + 0.29), DARK)
		add("Buttpad", V3(0.15, 0.2, 0.04), CF(0, 0.08, recBack + 0.58), DARK, nil, PLASTIC)
	elseif o.stock == "Thumbhole" then
		add("Stock", V3(0.17, 0.34, 0.8), CF(0, -0.01, recBack + 0.4), o.furniture, nil, furnMat)
		add("CheekRest", V3(0.13, 0.08, 0.4), CF(0, 0.2, recBack + 0.38), o.accent, nil, PLASTIC)
		add("Buttpad", V3(0.18, 0.38, 0.06), CF(0, -0.01, recBack + 0.83), DARK, nil, PLASTIC)
	elseif o.stock == "Pad" then
		add("Stock", V3(0.17, 0.26, 0.66), CF(0, 0.0, recBack + 0.33) * tilt(-6), o.furniture, nil, furnMat)
		add("Buttpad", V3(0.18, 0.34, 0.06), CF(0, -0.03, recBack + 0.68), DARK, nil, PLASTIC)
	elseif o.stock == "Bullpup" then
		add("CheekRest", V3(0.14, 0.05, 0.4), CF(0, recTop + 0.025, recBack - 0.3), o.accent, nil, PLASTIC)
		add("Buttpad", V3(recW + 0.02, o.recH + 0.04, 0.05), CF(0, REC_Y, recBack + 0.025), DARK, nil, PLASTIC)
	else
		add("Endcap", V3(recW, o.recH * 0.8, 0.04), CF(0, REC_Y, recBack + 0.02), DARK)
	end

	-- Folded bipod legs under the exposed barrel
	if o.bipod then
		local bz = -(o.recFront + o.hgLen + o.barLen * 0.5)
		add("BipodHinge", V3(0.12, 0.05, 0.08), CF(0, BORE_Y - barD / 2 - 0.025, -(o.recFront + o.hgLen + 0.05)), DARK)
		add("BipodLegL", V3(0.03, 0.03, o.barLen * 0.8), CF(-0.04, BORE_Y - barD / 2 - 0.04, bz), DARK)
		add("BipodLegR", V3(0.03, 0.03, o.barLen * 0.8), CF(0.04, BORE_Y - barD / 2 - 0.04, bz), DARK)
	end

	if o.extras then
		for _, p in o.extras do
			table.insert(parts, p)
		end
	end

	local leftHand = if o.hg == "Pump"
		then CF(0, hgBot - 0.02, hgZc)
		else CF(0, hgBot - 0.04, -(o.recFront + o.hgLen * 0.4))
	return {
		model = parts,
		anchors = {
			optic = CF(0, railTop, railZ),
			muzzle = muzzle,
			underbarrel = if o.underbarrel then CF(0, hgBot, -(o.recFront + o.hgLen * 0.6)) else nil,
			magazine = magAnchor,
			leftHand = leftHand,
		},
		muzzle = muzzle,
		sight = CF(0, sightY, sightZ),
	}
end

type PistolOpts = {
	kind: "Slide" | "Revolver" | "Machine",
	length: number, -- slide length, or barrel length for revolvers
	barrelOut: number?, -- barrel protruding past the slide
	body: Color3,
	frame: Color3,
	grip: Color3,
	wood: boolean?,
	extras: { ModelPart }?,
}

local function handgun(o: PistolOpts): Geo
	local parts: { ModelPart } = {}
	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, shape: ("Block" | "Cylinder")?, material: Enum.Material?)
		table.insert(parts, part(name, size, offset, color, shape, material))
	end
	local gripMat = if o.wood then WOOD else PLASTIC
	local gripCF = CF(0, -0.2, 0.02) * tilt(-12)
	local magAnchor, optic, muzzle, sightY, leftHand
	if o.kind == "Revolver" then
		local lb = o.length
		add("Frame", V3(0.16, 0.24, 0.5), CF(0, 0.1, -0.2), o.body)
		magAnchor = CF(0, 0.11, -0.22)
		add("Magazine", V3(0.3, 0.27, 0.27), magAnchor * CYL, o.frame, "Cylinder")
		add("CylinderPin", V3(0.06, 0.06, 0.06), CF(0, 0.11, -0.4) * CYL, DARK, "Cylinder")
		add("Barrel", V3(lb, 0.09, 0.09), CF(0, 0.18, -(0.45 + lb / 2)) * CYL, o.body, "Cylinder")
		add("BarrelLug", V3(0.08, 0.07, lb), CF(0, 0.12, -(0.45 + lb / 2)), o.body)
		add("Hammer", V3(0.05, 0.08, 0.08), CF(0, 0.22, 0.08) * tilt(-25), DARK)
		add("Grip", V3(0.15, 0.42, 0.22), CF(0, -0.18, 0.06) * tilt(-15), o.grip, nil, gripMat)
		add("TriggerGuard", V3(0.04, 0.05, 0.2), CF(0, -0.08, -0.15), DARK)
		sightY = 0.27
		add("RearSight", V3(0.1, 0.05, 0.04), CF(0, 0.245, -0.02), DARK)
		local fh = (sightY - 0.005) - 0.225
		add("FrontSight", V3(0.03, fh, 0.08), CF(0, 0.225 + fh / 2, -(0.45 + lb - 0.06)), DARK)
		optic = CF(0, 0.22, -0.25)
		muzzle = CF(0, 0.18, -(0.45 + lb))
		leftHand = CF(-0.05, -0.18, 0.08)
	else
		local l = o.length
		local out = o.barrelOut or 0.05
		add("Slide", V3(0.16, 0.18, l), CF(0, 0.15, 0.05 - l / 2), o.body)
		add("SlideSerrations", V3(0.165, 0.1, 0.12), CF(0, 0.15, -0.05), DARK)
		add("Frame", V3(0.15, 0.12, l - 0.15), CF(0, 0.02, 0.04 - (l - 0.15) / 2), o.frame, nil, PLASTIC)
		add("Grip", V3(0.15, 0.45, 0.22), gripCF, o.grip, nil, gripMat)
		add("TriggerGuard", V3(0.04, 0.05, 0.22), CF(0, -0.09, -0.22), DARK)
		add("Barrel", V3(out + 0.05, 0.07, 0.07), CF(0, 0.18, -(l - 0.05) - out / 2 + 0.025) * CYL, STEEL, "Cylinder")
		add("Hammer", V3(0.05, 0.06, 0.05), CF(0, 0.2, 0.08), DARK)
		sightY = 0.29
		add("RearSight", V3(0.12, 0.05, 0.04), CF(0, 0.265, 0.01), DARK)
		add("FrontSight", V3(0.04, 0.05, 0.04), CF(0, 0.265, -(l - 0.1)), DARK)
		magAnchor = CF(0, -0.2, 0.03)
		if o.kind == "Machine" then
			add("Magazine", V3(0.12, 0.72, 0.17), gripCF * CF(0, -0.12, 0), o.frame, nil, PLASTIC)
			leftHand = CF(-0.04, -0.3, 0.06)
		else
			add("Magazine", V3(0.16, 0.05, 0.23), gripCF * CF(0, -0.245, 0), DARK, nil, PLASTIC)
			leftHand = CF(-0.05, -0.2, 0.05)
		end
		optic = CF(0, 0.24, -0.35)
		muzzle = CF(0, 0.18, -(l - 0.05 + out))
	end
	if o.extras then
		for _, p in o.extras do
			table.insert(parts, p)
		end
	end
	return {
		model = parts,
		anchors = { optic = optic, muzzle = muzzle, underbarrel = nil, magazine = magAnchor, leftHand = leftHand },
		muzzle = muzzle,
		sight = CF(0, sightY, 0.15),
	}
end

-- Attachment unlock ladders: ids in unlock order, from weapon level `first` every `step` levels.
local function ladder(ids: { string }, first: number, step: number): { [string]: number }
	local t: { [string]: number } = {}
	for i, id in ids do
		t[id] = math.min(28, first + (i - 1) * step)
	end
	return t
end

local function noSounds(): { fire: string, reload: string, equip: string }
	return { fire = "", reload = "", equip = "" }
end

local ALL_SLOTS: { AttachmentSlot } = { "Optic", "Muzzle", "Barrel", "Underbarrel", "Magazine" }
local function allSlots(): { AttachmentSlot }
	return table.clone(ALL_SLOTS)
end

local AR_LADDER = { "RedDot", "Compensator", "VerticalGrip", "QuickMag", "HoloSight", "Suppressor", "StubBarrel", "ExtendedMag", "AngledGrip", "FlashGuard", "LongBarrel", "ScoutScope", "DrumMag" }
local SMG_LADDER = { "RedDot", "Suppressor", "AngledGrip", "QuickMag", "MicroDot", "Compensator", "StubBarrel", "ExtendedMag", "VerticalGrip", "HoloSight", "FlashGuard", "LongBarrel" }
local LMG_LADDER = { "RedDot", "VerticalGrip", "Compensator", "QuickMag", "HoloSight", "Brace", "FlashGuard", "StubBarrel", "ScoutScope", "Suppressor", "LongBarrel", "AngledGrip" }
local DMR_LADDER = { "RedDot", "Compensator", "VerticalGrip", "QuickMag", "ScoutScope", "Suppressor", "FlutedBarrel", "ExtendedMag", "HoloSight", "FlashGuard", "LongBarrel", "AngledGrip" }
local SNIPER_LADDER = { "FlashGuard", "QuickMag", "Suppressor", "FlutedBarrel", "ExtendedMag", "LongBarrel" }
local PISTOL_LADDER = { "MicroDot", "Compensator", "QuickMag", "Suppressor", "MatchBarrel", "ExtendedMag", "RedDot" }

local function with(list: { string }, extra: { string }): { string }
	local out = table.clone(list)
	for _, id in extra do
		table.insert(out, id)
	end
	return out
end

local function without(list: { string }, drop: { string }): { string }
	local out = {}
	for _, id in list do
		if not table.find(drop, id) then
			table.insert(out, id)
		end
	end
	return out
end

-- Geometry -----------------------------------------------------------------------------------

local G = {
	-- Assault rifles: full stocks, handguards with an underbarrel rail, curved or straight mags.
	VK7 = longGun({ recFront = 1.15, recH = 0.32, hg = "Vented", hgLen = 0.9, hgH = 0.24, barLen = 0.4, device = "Brake", stock = "Fixed", mag = "Curved", sights = "Iron", underbarrel = true, body = GUNMETAL, furniture = TAN, accent = POLYMER }),
	KT9 = longGun({ recFront = 1.0, recH = 0.3, hg = "Quad", hgLen = 0.85, hgH = 0.22, barLen = 0.35, device = "Flash", stock = "Skeleton", mag = "Curved", sights = "Iron", underbarrel = true, body = SLATE, furniture = POLYMER, accent = DARK }),
	SW3 = longGun({ recFront = 1.1, recH = 0.3, hg = "Round", hgLen = 0.8, hgH = 0.22, barLen = 0.45, device = "Brake", stock = "Fixed", mag = "Straight", sights = "Iron", underbarrel = true, body = OLIVE, furniture = BONE, accent = POLYMER,
		extras = { part("FireSelector", V3(0.03, 0.06, 0.06), CF(0.125, 0.0, -0.1), RUST) } }),
	HL4 = longGun({ recFront = 1.2, recH = 0.34, hg = "Slim", hgLen = 1.0, hgH = 0.26, barLen = 0.45, device = "Brake", stock = "Fixed", mag = "Curved", sights = "Iron", underbarrel = true, wood = true, body = GUNMETAL, furniture = WALNUT, accent = DARK,
		extras = { part("GasTube", V3(0.9, 0.05, 0.05), CF(0, 0.26, -1.7) * CYL, STEEL, "Cylinder") } }),
	BX2 = longGun({ recFront = 0.7, recH = 0.34, hg = "Slim", hgLen = 0.7, hgH = 0.26, barLen = 0.4, device = "Flash", stock = "Bullpup", mag = "Curved", magZ = -0.42, sights = "Iron", underbarrel = true, body = SAND, furniture = POLYMER, accent = POLYMER }),
	TR6 = longGun({ recFront = 1.15, recH = 0.3, hg = "Vented", hgLen = 1.05, hgH = 0.22, barLen = 0.5, device = "Cap", stock = "Skeleton", mag = "Straight", sights = "Iron", underbarrel = true, body = FOREST, furniture = POLYMER, accent = DARK }),

	-- SMGs: short receivers, stubby barrels, stick mags, folding or no stocks.
	MR5 = longGun({ recFront = 0.8, recH = 0.28, recW = 0.2, hg = "Slim", hgLen = 0.6, hgH = 0.2, barLen = 0.3, device = "Cap", stock = "Wire", mag = "Stick", magZ = 0.45, sights = "Iron", underbarrel = true, body = POLYMER, furniture = GUNMETAL, accent = DARK }),
	ZP9 = longGun({ recFront = 0.7, recH = 0.3, recW = 0.2, hg = "Quad", hgLen = 0.5, hgH = 0.2, barLen = 0.26, device = "Flash", stock = "Skeleton", mag = "Stick", magZ = 0.3, sights = "Iron", underbarrel = true, body = SLATE, furniture = DARK, accent = POLYMER }),
	CW4 = longGun({ recFront = 0.8, recH = 0.28, recW = 0.2, hg = "Round", hgLen = 0.45, hgH = 0.2, barLen = 0.25, device = "Brake", stock = "Skeleton", mag = "Curved", magZ = 0.45, sights = "Iron", underbarrel = true, body = RUST, furniture = POLYMER, accent = DARK }),
	MN8 = longGun({ recFront = 0.9, recH = 0.3, recW = 0.2, hg = "Vented", hgLen = 0.55, hgH = 0.2, barLen = 0.2, device = "Cap", stock = "Fixed", mag = "Stick", magZ = 0.5, sights = "Iron", underbarrel = true, body = OLIVE, furniture = POLYMER, accent = DARK }),
	GN2 = longGun({ recFront = 0.8, recH = 0.26, recW = 0.2, hg = "Slim", hgLen = 0.55, hgH = 0.18, barLen = 0.2, device = "Cap", stock = "Skeleton", mag = "Stick", magZ = 0.4, sights = "Iron", underbarrel = true, body = PLUM, furniture = DARK, accent = DARK }),

	-- LMGs: thick receivers, box/drum mags, bipods.
	MT1 = longGun({ recFront = 1.2, recH = 0.36, recW = 0.26, hg = "Quad", hgLen = 1.0, hgH = 0.26, barLen = 0.5, barD = 0.08, device = "Flash", stock = "Fixed", mag = "Drum", sights = "Iron", underbarrel = true, bipod = true, body = OLIVE, furniture = POLYMER, accent = DARK }),
	BW5 = longGun({ recFront = 1.3, recH = 0.4, recW = 0.26, hg = "Shroud", hgLen = 1.0, hgH = 0.24, barLen = 0.55, barD = 0.09, device = "Brake", stock = "Pad", mag = "Box", sights = "Iron", underbarrel = true, bipod = true, body = GUNMETAL, furniture = TAN, accent = OLIVE,
		extras = { part("FeedTray", V3(0.12, 0.06, 0.22), CF(-0.16, 0.0, -0.7), DARK) } }),
	RP3 = longGun({ recFront = 1.4, recH = 0.42, recW = 0.28, hg = "Vented", hgLen = 1.1, hgH = 0.28, barLen = 0.6, barD = 0.09, device = "Brake", stock = "Skeleton", mag = "Box", sights = "Iron", underbarrel = true, bipod = true, body = FOREST, furniture = DARK, accent = TAN,
		extras = { part("BarrelHandle", V3(0.05, 0.12, 0.3), CF(0.18, 0.2, -1.6), DARK) } }),

	-- Marksman rifles: long handguards, short box mags, cheek rests.
	LS6 = longGun({ recFront = 1.2, recH = 0.3, hg = "Round", hgLen = 1.1, hgH = 0.2, barLen = 0.55, device = "Flash", stock = "Thumbhole", mag = "Short", sights = "Iron", underbarrel = true, body = SAND, furniture = POLYMER, accent = DARK }),
	RL2 = longGun({ recFront = 1.3, recH = 0.3, hg = "Slim", hgLen = 1.1, hgH = 0.22, barLen = 0.65, device = "Brake", stock = "Fixed", mag = "Short", sights = "Iron", underbarrel = true, wood = true, body = STEEL, furniture = WALNUT, accent = DARK,
		extras = { part("CheekPiece", V3(0.12, 0.06, 0.35), CF(0, 0.2, 0.5), WALNUT, nil, WOOD) } }),

	-- Sniper rifles: built-in scopes, long barrels, no iron sights.
	HR5 = longGun({ recFront = 1.3, recH = 0.3, hg = "Round", hgLen = 1.0, hgH = 0.2, barLen = 0.9, device = "Brake", stock = "Thumbhole", mag = "Short", sights = "Scope", underbarrel = false, body = GUNMETAL, furniture = OLIVE, accent = TAN,
		extras = { part("BoltHandle", V3(0.14, 0.04, 0.04), CF(0.15, 0.18, -0.15), STEEL), part("BoltKnob", V3(0.06, 0.06, 0.06), CF(0.24, 0.18, -0.15), DARK) } }),
	GT8 = longGun({ recFront = 1.15, recH = 0.3, hg = "Slim", hgLen = 0.9, hgH = 0.2, barLen = 0.75, device = "Flash", stock = "Skeleton", mag = "Short", sights = "Scope", underbarrel = false, body = SLATE, furniture = DARK, accent = TEAL }),
	MO1 = longGun({ recFront = 1.4, recH = 0.34, recW = 0.24, hg = "Quad", hgLen = 1.0, hgH = 0.24, barLen = 0.9, barD = 0.09, device = "Brake", stock = "Thumbhole", mag = "Short", sights = "Scope", underbarrel = false, body = DARK, furniture = SAND, accent = RUST }),

	-- Shotguns: pump forend over a tube, semi tube gun, and a box-fed auto.
	HG8 = longGun({ recFront = 0.85, recH = 0.26, hg = "Pump", hgLen = 0.55, hgH = 0.16, barLen = 0.9, barD = 0.09, device = "None", stock = "Pad", mag = "Tube", sights = "Bead", underbarrel = false, wood = true, body = GUNMETAL, furniture = WALNUT, accent = DARK }),
	RV6 = longGun({ recFront = 0.95, recH = 0.28, hg = "Pump", hgLen = 0.7, hgH = 0.17, barLen = 0.75, barD = 0.09, device = "Cap", stock = "Fixed", mag = "Tube", sights = "Bead", underbarrel = false, body = TEAL, furniture = POLYMER, accent = DARK }),
	BL9 = longGun({ recFront = 0.9, recH = 0.34, recW = 0.24, hg = "Quad", hgLen = 0.6, hgH = 0.24, barLen = 0.4, barD = 0.1, device = "Brake", stock = "Fixed", mag = "ShellBox", sights = "Iron", underbarrel = true, body = RUST, furniture = POLYMER, accent = DARK }),

	-- Handguns
	P12 = handgun({ kind = "Slide", length = 0.85, barrelOut = 0.05, body = GUNMETAL, frame = POLYMER, grip = POLYMER }),
	FX3 = handgun({ kind = "Slide", length = 0.8, barrelOut = 0.04, body = SLATE, frame = DARK, grip = DARK,
		extras = { part("SlideCut", V3(0.165, 0.06, 0.25), CF(0, 0.2, -0.45), STEEL) } }),
	OG6 = handgun({ kind = "Revolver", length = 0.6, body = STEEL, frame = GUNMETAL, grip = WALNUT, wood = true }),
	SP3 = handgun({ kind = "Machine", length = 0.75, barrelOut = 0.12, body = DARK, frame = POLYMER, grip = POLYMER,
		extras = { part("FoldedStock", V3(0.03, 0.1, 0.42), CF(0.1, 0.0, -0.15), DARK), part("BarrelPorts", V3(0.09, 0.03, 0.08), CF(0, 0.23, -0.72), STEEL) } }),
}

-- Roster ------------------------------------------------------------------------------------

local Weapons: { [string]: WeaponDef } = {
	-- ASSAULT RIFLES ----------------------------------------------------------------------------
	VK7 = {
		id = "VK7",
		displayName = "VK-7 Vanguard",
		description = "Mid-weight rifle. Reliable all-rounder with a 4-shot close-range kill.",
		class = "AssaultRifle",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 720,
		damage = { close = 30, far = 21, closeRange = 55, farRange = 170, maxRange = 900 },
		headMultiplier = 1.4,
		limbMultiplier = 0.9,
		magSize = 30,
		reserveAmmo = 120,
		reloadTime = 2.1,
		reloadEmptyTime = 2.7,
		equipTime = 0.45,
		adsTime = 0.25,
		moveSpeedMultiplier = 0.95,
		adsMoveSpeedMultiplier = 0.6,
		spread = { hip = 3.2, ads = 0.12, movingMultiplier = 1.6 },
		recoil = { vertical = 0.55, horizontal = 0.22, recovery = 9, adsMultiplier = 0.7 },
		adsFov = 55,
		unlockLevel = 1,
		muzzleOffset = G.VK7.muzzle,
		sightOffset = G.VK7.sight,
		anchors = G.VK7.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(AR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.VK7.model,
	},
	KT9 = {
		id = "KT9",
		displayName = "KT-9 Kestrel",
		description = "Light, fast-cycling rifle that trades long-range punch for handling.",
		class = "AssaultRifle",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 820,
		damage = { close = 25, far = 18, closeRange = 45, farRange = 150, maxRange = 900 },
		headMultiplier = 1.4,
		limbMultiplier = 0.9,
		magSize = 30,
		reserveAmmo = 150,
		reloadTime = 1.9,
		reloadEmptyTime = 2.5,
		equipTime = 0.4,
		adsTime = 0.23,
		moveSpeedMultiplier = 0.96,
		adsMoveSpeedMultiplier = 0.62,
		spread = { hip = 3.0, ads = 0.14, movingMultiplier = 1.55 },
		recoil = { vertical = 0.48, horizontal = 0.26, recovery = 10, adsMultiplier = 0.7 },
		adsFov = 55,
		unlockLevel = 8,
		muzzleOffset = G.KT9.muzzle,
		sightOffset = G.KT9.sight,
		anchors = G.KT9.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(AR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.KT9.model,
	},
	SW3 = {
		id = "SW3",
		displayName = "SW-3 Sparrow",
		description = "Three-round burst rifle that rewards precise, deliberate trigger pulls.",
		class = "AssaultRifle",
		slot = "Primary",
		fireMode = "Burst",
		rpm = 850,
		burst = { count = 3, delay = 0.25 },
		damage = { close = 31, far = 23, closeRange = 60, farRange = 190, maxRange = 900 },
		headMultiplier = 1.5,
		limbMultiplier = 0.9,
		magSize = 30,
		reserveAmmo = 120,
		reloadTime = 2.2,
		reloadEmptyTime = 2.8,
		equipTime = 0.45,
		adsTime = 0.25,
		moveSpeedMultiplier = 0.95,
		adsMoveSpeedMultiplier = 0.6,
		spread = { hip = 3.3, ads = 0.1, movingMultiplier = 1.6 },
		recoil = { vertical = 0.5, horizontal = 0.15, recovery = 10, adsMultiplier = 0.65 },
		adsFov = 55,
		unlockLevel = 14,
		muzzleOffset = G.SW3.muzzle,
		sightOffset = G.SW3.sight,
		anchors = G.SW3.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(AR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.SW3.model,
	},
	HL4 = {
		id = "HL4",
		displayName = "HL-4 Halberd",
		description = "Heavy-calibre rifle with a slow cadence and the hardest-hitting rounds in its class.",
		class = "AssaultRifle",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 600,
		damage = { close = 33, far = 24, closeRange = 60, farRange = 190, maxRange = 900 },
		headMultiplier = 1.4,
		limbMultiplier = 0.9,
		magSize = 25,
		reserveAmmo = 100,
		reloadTime = 2.3,
		reloadEmptyTime = 2.9,
		equipTime = 0.5,
		adsTime = 0.28,
		moveSpeedMultiplier = 0.93,
		adsMoveSpeedMultiplier = 0.58,
		spread = { hip = 3.5, ads = 0.11, movingMultiplier = 1.7 },
		recoil = { vertical = 0.7, horizontal = 0.25, recovery = 8, adsMultiplier = 0.7 },
		adsFov = 55,
		unlockLevel = 22,
		muzzleOffset = G.HL4.muzzle,
		sightOffset = G.HL4.sight,
		anchors = G.HL4.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(AR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.HL4.model,
	},
	BX2 = {
		id = "BX2",
		displayName = "BX-2 Bastion",
		description = "Compact bullpup rifle with full-length barrel performance and a slower reload.",
		class = "AssaultRifle",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 760,
		damage = { close = 28, far = 20, closeRange = 50, farRange = 160, maxRange = 900 },
		headMultiplier = 1.4,
		limbMultiplier = 0.9,
		magSize = 30,
		reserveAmmo = 120,
		reloadTime = 2.4,
		reloadEmptyTime = 3.0,
		equipTime = 0.45,
		adsTime = 0.24,
		moveSpeedMultiplier = 0.95,
		adsMoveSpeedMultiplier = 0.62,
		spread = { hip = 3.1, ads = 0.12, movingMultiplier = 1.6 },
		recoil = { vertical = 0.5, horizontal = 0.3, recovery = 9, adsMultiplier = 0.7 },
		adsFov = 55,
		unlockLevel = 30,
		muzzleOffset = G.BX2.muzzle,
		sightOffset = G.BX2.sight,
		anchors = G.BX2.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(AR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.BX2.model,
	},
	TR6 = {
		id = "TR6",
		displayName = "TR-6 Torrent",
		description = "Long-barrelled rifle with gentle recoil that keeps its damage at range.",
		class = "AssaultRifle",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 680,
		damage = { close = 27, far = 19, closeRange = 65, farRange = 210, maxRange = 950 },
		headMultiplier = 1.45,
		limbMultiplier = 0.9,
		magSize = 32,
		reserveAmmo = 128,
		reloadTime = 2.2,
		reloadEmptyTime = 2.8,
		equipTime = 0.5,
		adsTime = 0.27,
		moveSpeedMultiplier = 0.94,
		adsMoveSpeedMultiplier = 0.6,
		spread = { hip = 3.2, ads = 0.09, movingMultiplier = 1.6 },
		recoil = { vertical = 0.45, horizontal = 0.18, recovery = 10, adsMultiplier = 0.65 },
		adsFov = 55,
		unlockLevel = 42,
		muzzleOffset = G.TR6.muzzle,
		sightOffset = G.TR6.sight,
		anchors = G.TR6.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(AR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.TR6.model,
	},

	-- SMGS --------------------------------------------------------------------------------------
	MR5 = {
		id = "MR5",
		displayName = "MR-5 Mistral",
		description = "Dependable starter SMG with a quick draw and a four-shot kill up close.",
		class = "SMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 850,
		damage = { close = 25, far = 15, closeRange = 22, farRange = 80, maxRange = 450 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 30,
		reserveAmmo = 150,
		reloadTime = 1.8,
		reloadEmptyTime = 2.3,
		equipTime = 0.35,
		adsTime = 0.19,
		moveSpeedMultiplier = 1.0,
		adsMoveSpeedMultiplier = 0.7,
		spread = { hip = 2.4, ads = 0.22, movingMultiplier = 1.3 },
		recoil = { vertical = 0.42, horizontal = 0.3, recovery = 12, adsMultiplier = 0.75 },
		adsFov = 60,
		unlockLevel = 2,
		muzzleOffset = G.MR5.muzzle,
		sightOffset = G.MR5.sight,
		anchors = G.MR5.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(SMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.MR5.model,
	},
	ZP9 = {
		id = "ZP9",
		displayName = "ZP-9 Zephyr",
		description = "Skeleton-stocked room-clearer with a blistering fire rate and fast aim.",
		class = "SMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 950,
		damage = { close = 22, far = 14, closeRange = 18, farRange = 70, maxRange = 400 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 32,
		reserveAmmo = 160,
		reloadTime = 1.9,
		reloadEmptyTime = 2.4,
		equipTime = 0.33,
		adsTime = 0.17,
		moveSpeedMultiplier = 1.02,
		adsMoveSpeedMultiplier = 0.72,
		spread = { hip = 2.3, ads = 0.26, movingMultiplier = 1.25 },
		recoil = { vertical = 0.38, horizontal = 0.34, recovery = 12, adsMultiplier = 0.75 },
		adsFov = 60,
		unlockLevel = 10,
		muzzleOffset = G.ZP9.muzzle,
		sightOffset = G.ZP9.sight,
		anchors = G.ZP9.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(SMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.ZP9.model,
	},
	CW4 = {
		id = "CW4",
		displayName = "CW-4 Cinder",
		description = "Hard-hitting SMG with a smaller magazine and a slower, steadier cadence.",
		class = "SMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 780,
		damage = { close = 26, far = 16, closeRange = 25, farRange = 90, maxRange = 450 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 25,
		reserveAmmo = 125,
		reloadTime = 1.7,
		reloadEmptyTime = 2.2,
		equipTime = 0.35,
		adsTime = 0.2,
		moveSpeedMultiplier = 1.0,
		adsMoveSpeedMultiplier = 0.7,
		spread = { hip = 2.5, ads = 0.2, movingMultiplier = 1.3 },
		recoil = { vertical = 0.5, horizontal = 0.28, recovery = 11, adsMultiplier = 0.75 },
		adsFov = 60,
		unlockLevel = 18,
		muzzleOffset = G.CW4.muzzle,
		sightOffset = G.CW4.sight,
		anchors = G.CW4.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(SMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.CW4.model,
	},
	MN8 = {
		id = "MN8",
		displayName = "MN-8 Marten",
		description = "High-capacity SMG that keeps firing long after others run dry.",
		class = "SMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 900,
		damage = { close = 24, far = 15, closeRange = 24, farRange = 85, maxRange = 450 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 40,
		reserveAmmo = 160,
		reloadTime = 2.1,
		reloadEmptyTime = 2.6,
		equipTime = 0.38,
		adsTime = 0.2,
		moveSpeedMultiplier = 0.99,
		adsMoveSpeedMultiplier = 0.7,
		spread = { hip = 2.4, ads = 0.2, movingMultiplier = 1.3 },
		recoil = { vertical = 0.4, horizontal = 0.28, recovery = 12, adsMultiplier = 0.72 },
		adsFov = 60,
		unlockLevel = 27,
		muzzleOffset = G.MN8.muzzle,
		sightOffset = G.MN8.sight,
		anchors = G.MN8.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(SMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.MN8.model,
	},
	GN2 = {
		id = "GN2",
		displayName = "GN-2 Gnat",
		description = "Featherweight bullet hose: the fastest SMG, and the shortest reach.",
		class = "SMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 1000,
		damage = { close = 21, far = 13, closeRange = 15, farRange = 60, maxRange = 350 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 36,
		reserveAmmo = 180,
		reloadTime = 1.8,
		reloadEmptyTime = 2.2,
		equipTime = 0.3,
		adsTime = 0.16,
		moveSpeedMultiplier = 1.03,
		adsMoveSpeedMultiplier = 0.75,
		spread = { hip = 2.2, ads = 0.3, movingMultiplier = 1.2 },
		recoil = { vertical = 0.36, horizontal = 0.38, recovery = 13, adsMultiplier = 0.78 },
		adsFov = 60,
		unlockLevel = 45,
		muzzleOffset = G.GN2.muzzle,
		sightOffset = G.GN2.sight,
		anchors = G.GN2.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(SMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.GN2.model,
	},

	-- LMGS --------------------------------------------------------------------------------------
	MT1 = {
		id = "MT1",
		displayName = "MT-1 Mattock",
		description = "Drum-fed light machine gun that handles almost like a rifle.",
		class = "LMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 750,
		damage = { close = 27, far = 21, closeRange = 55, farRange = 180, maxRange = 1000 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 75,
		reserveAmmo = 225,
		reloadTime = 4.2,
		reloadEmptyTime = 5.0,
		equipTime = 0.65,
		adsTime = 0.36,
		moveSpeedMultiplier = 0.9,
		adsMoveSpeedMultiplier = 0.5,
		spread = { hip = 4.2, ads = 0.14, movingMultiplier = 1.8 },
		recoil = { vertical = 0.55, horizontal = 0.3, recovery = 8, adsMultiplier = 0.7 },
		adsFov = 55,
		unlockLevel = 4,
		muzzleOffset = G.MT1.muzzle,
		sightOffset = G.MT1.sight,
		anchors = G.MT1.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(with(LMG_LADDER, { "DrumMag" }), 2, 2),
		sounds = noSounds(),
		model = G.MT1.model,
	},
	BW5 = {
		id = "BW5",
		displayName = "BW-5 Bulwark",
		description = "Belt-boxed machine gun built to lock down a lane for a hundred rounds.",
		class = "LMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 650,
		damage = { close = 32, far = 24, closeRange = 60, farRange = 200, maxRange = 1000 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 100,
		reserveAmmo = 200,
		reloadTime = 5.0,
		reloadEmptyTime = 6.0,
		equipTime = 0.7,
		adsTime = 0.42,
		moveSpeedMultiplier = 0.87,
		adsMoveSpeedMultiplier = 0.48,
		spread = { hip = 4.6, ads = 0.13, movingMultiplier = 1.9 },
		recoil = { vertical = 0.7, horizontal = 0.3, recovery = 7, adsMultiplier = 0.65 },
		adsFov = 55,
		unlockLevel = 20,
		muzzleOffset = G.BW5.muzzle,
		sightOffset = G.BW5.sight,
		anchors = G.BW5.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(LMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.BW5.model,
	},
	RP3 = {
		id = "RP3",
		displayName = "RP-3 Rampart",
		description = "Massive 150-round support gun: slow to aim, slower to reload, relentless once set.",
		class = "LMG",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 600,
		damage = { close = 33, far = 25, closeRange = 55, farRange = 190, maxRange = 1000 },
		headMultiplier = 1.35,
		limbMultiplier = 0.9,
		magSize = 150,
		reserveAmmo = 300,
		reloadTime = 6.0,
		reloadEmptyTime = 7.0,
		equipTime = 0.8,
		adsTime = 0.48,
		moveSpeedMultiplier = 0.85,
		adsMoveSpeedMultiplier = 0.45,
		spread = { hip = 5.0, ads = 0.15, movingMultiplier = 2.0 },
		recoil = { vertical = 0.65, horizontal = 0.35, recovery = 7, adsMultiplier = 0.6 },
		adsFov = 55,
		unlockLevel = 34,
		muzzleOffset = G.RP3.muzzle,
		sightOffset = G.RP3.sight,
		anchors = G.RP3.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(LMG_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.RP3.model,
	},

	-- MARKSMAN RIFLES ---------------------------------------------------------------------------
	LS6 = {
		id = "LS6",
		displayName = "LS-6 Longshank",
		description = "Semi-automatic marksman rifle: two body shots up close, three across the map.",
		class = "Marksman",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 300,
		damage = { close = 52, far = 38, closeRange = 70, farRange = 260, maxRange = 1200 },
		headMultiplier = 1.6,
		limbMultiplier = 0.85,
		magSize = 15,
		reserveAmmo = 60,
		reloadTime = 2.4,
		reloadEmptyTime = 3.0,
		equipTime = 0.5,
		adsTime = 0.3,
		moveSpeedMultiplier = 0.93,
		adsMoveSpeedMultiplier = 0.55,
		spread = { hip = 5.0, ads = 0.05, movingMultiplier = 1.8 },
		recoil = { vertical = 1.6, horizontal = 0.35, recovery = 9, adsMultiplier = 0.7 },
		adsFov = 50,
		unlockLevel = 3,
		muzzleOffset = G.LS6.muzzle,
		sightOffset = G.LS6.sight,
		anchors = G.LS6.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(DMR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.LS6.model,
	},
	RL2 = {
		id = "RL2",
		displayName = "RL-2 Ridgeline",
		description = "Slow, heavy-hitting marksman rifle with a wooden stock and a ten-round mag.",
		class = "Marksman",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 200,
		damage = { close = 60, far = 45, closeRange = 90, farRange = 320, maxRange = 1400 },
		headMultiplier = 1.6,
		limbMultiplier = 0.85,
		magSize = 10,
		reserveAmmo = 40,
		reloadTime = 2.6,
		reloadEmptyTime = 3.2,
		equipTime = 0.55,
		adsTime = 0.32,
		moveSpeedMultiplier = 0.92,
		adsMoveSpeedMultiplier = 0.52,
		spread = { hip = 5.5, ads = 0.04, movingMultiplier = 1.9 },
		recoil = { vertical = 2.2, horizontal = 0.4, recovery = 8, adsMultiplier = 0.7 },
		adsFov = 50,
		unlockLevel = 25,
		muzzleOffset = G.RL2.muzzle,
		sightOffset = G.RL2.sight,
		anchors = G.RL2.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder(DMR_LADDER, 2, 2),
		sounds = noSounds(),
		model = G.RL2.model,
	},

	-- SNIPER RIFLES -----------------------------------------------------------------------------
	HR5 = {
		id = "HR5",
		displayName = "HR-5 Heron",
		description = "Scoped sniper rifle that drops a target with one shot to the head or chest.",
		class = "Sniper",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 50,
		damage = { close = 110, far = 100, closeRange = 150, farRange = 400, maxRange = 2000 },
		headMultiplier = 1.5,
		limbMultiplier = 0.85,
		magSize = 5,
		reserveAmmo = 25,
		reloadTime = 3.0,
		reloadEmptyTime = 3.8,
		equipTime = 0.7,
		adsTime = 0.4,
		moveSpeedMultiplier = 0.9,
		adsMoveSpeedMultiplier = 0.4,
		spread = { hip = 8.0, ads = 0.02, movingMultiplier = 2.5 },
		recoil = { vertical = 4.0, horizontal = 0.6, recovery = 6, adsMultiplier = 0.6 },
		adsFov = 50,
		scope = { fov = 22 },
		unlockLevel = 4,
		muzzleOffset = G.HR5.muzzle,
		sightOffset = G.HR5.sight,
		anchors = G.HR5.anchors,
		attachmentSlots = { "Muzzle", "Barrel", "Magazine" },
		attachmentUnlocks = ladder(SNIPER_LADDER, 3, 4),
		sounds = noSounds(),
		model = G.HR5.model,
	},
	GT8 = {
		id = "GT8",
		displayName = "GT-8 Gannet",
		description = "Lighter sniper rifle with a faster follow-up shot and quicker scope-in.",
		class = "Sniper",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 60,
		damage = { close = 105, far = 100, closeRange = 120, farRange = 350, maxRange = 1800 },
		headMultiplier = 1.5,
		limbMultiplier = 0.8,
		magSize = 8,
		reserveAmmo = 32,
		reloadTime = 2.8,
		reloadEmptyTime = 3.5,
		equipTime = 0.6,
		adsTime = 0.36,
		moveSpeedMultiplier = 0.92,
		adsMoveSpeedMultiplier = 0.42,
		spread = { hip = 7.0, ads = 0.03, movingMultiplier = 2.3 },
		recoil = { vertical = 3.2, horizontal = 0.5, recovery = 7, adsMultiplier = 0.6 },
		adsFov = 50,
		scope = { fov = 25 },
		unlockLevel = 16,
		muzzleOffset = G.GT8.muzzle,
		sightOffset = G.GT8.sight,
		anchors = G.GT8.anchors,
		attachmentSlots = { "Muzzle", "Barrel", "Magazine" },
		attachmentUnlocks = ladder(SNIPER_LADDER, 3, 4),
		sounds = noSounds(),
		model = G.GT8.model,
	},
	MO1 = {
		id = "MO1",
		displayName = "MO-1 Monolith",
		description = "Anti-materiel sniper rifle: the longest reach and the slowest everything else.",
		class = "Sniper",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 40,
		damage = { close = 130, far = 115, closeRange = 200, farRange = 500, maxRange = 2400 },
		headMultiplier = 1.5,
		limbMultiplier = 0.75,
		magSize = 4,
		reserveAmmo = 20,
		reloadTime = 3.6,
		reloadEmptyTime = 4.4,
		equipTime = 0.85,
		adsTime = 0.48,
		moveSpeedMultiplier = 0.86,
		adsMoveSpeedMultiplier = 0.35,
		spread = { hip = 9.0, ads = 0.01, movingMultiplier = 2.8 },
		recoil = { vertical = 5.0, horizontal = 0.8, recovery = 5, adsMultiplier = 0.6 },
		adsFov = 50,
		scope = { fov = 18 },
		unlockLevel = 38,
		muzzleOffset = G.MO1.muzzle,
		sightOffset = G.MO1.sight,
		anchors = G.MO1.anchors,
		attachmentSlots = { "Muzzle", "Barrel", "Magazine" },
		attachmentUnlocks = ladder(SNIPER_LADDER, 3, 4),
		sounds = noSounds(),
		model = G.MO1.model,
	},

	-- SHOTGUNS (damage is per pellet) -----------------------------------------------------------
	HG8 = {
		id = "HG8",
		displayName = "HG-8 Harrow",
		description = "Pump-action shotgun: one clean hit up close ends the fight.",
		class = "Shotgun",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 70,
		pellets = 8,
		pelletSpread = 5.5,
		damage = { close = 16, far = 5, closeRange = 12, farRange = 40, maxRange = 60 },
		headMultiplier = 1.2,
		limbMultiplier = 0.9,
		magSize = 6,
		reserveAmmo = 30,
		reloadTime = 3.2,
		reloadEmptyTime = 4.0,
		equipTime = 0.5,
		adsTime = 0.25,
		moveSpeedMultiplier = 0.96,
		adsMoveSpeedMultiplier = 0.65,
		spread = { hip = 2.5, ads = 0.6, movingMultiplier = 1.3 },
		recoil = { vertical = 3.5, horizontal = 0.6, recovery = 7, adsMultiplier = 0.8 },
		adsFov = 60,
		unlockLevel = 2,
		muzzleOffset = G.HG8.muzzle,
		sightOffset = G.HG8.sight,
		anchors = G.HG8.anchors,
		attachmentSlots = { "Optic", "Muzzle", "Barrel" },
		attachmentUnlocks = ladder({ "RedDot", "Choke", "StubBarrel", "HoloSight", "Suppressor", "LongBarrel" }, 2, 4),
		sounds = noSounds(),
		model = G.HG8.model,
	},
	RV6 = {
		id = "RV6",
		displayName = "RV-6 Riven",
		description = "Semi-automatic tube shotgun that fires as fast as you can pull the trigger.",
		class = "Shotgun",
		slot = "Primary",
		fireMode = "Semi",
		rpm = 200,
		pellets = 7,
		pelletSpread = 5,
		damage = { close = 15, far = 4, closeRange = 9, farRange = 35, maxRange = 55 },
		headMultiplier = 1.2,
		limbMultiplier = 0.9,
		magSize = 8,
		reserveAmmo = 32,
		reloadTime = 3.4,
		reloadEmptyTime = 4.2,
		equipTime = 0.5,
		adsTime = 0.25,
		moveSpeedMultiplier = 0.95,
		adsMoveSpeedMultiplier = 0.65,
		spread = { hip = 2.6, ads = 0.5, movingMultiplier = 1.3 },
		recoil = { vertical = 2.6, horizontal = 0.5, recovery = 8, adsMultiplier = 0.8 },
		adsFov = 60,
		unlockLevel = 12,
		muzzleOffset = G.RV6.muzzle,
		sightOffset = G.RV6.sight,
		anchors = G.RV6.anchors,
		attachmentSlots = { "Optic", "Muzzle", "Barrel" },
		attachmentUnlocks = ladder({ "RedDot", "Choke", "StubBarrel", "HoloSight", "Suppressor", "LongBarrel" }, 2, 4),
		sounds = noSounds(),
		model = G.RV6.model,
	},
	BL9 = {
		id = "BL9",
		displayName = "BL-9 Bellow",
		description = "Box-fed automatic shotgun that empties its small magazine in a heartbeat.",
		class = "Shotgun",
		slot = "Primary",
		fireMode = "Auto",
		rpm = 300,
		pellets = 6,
		pelletSpread = 6.5,
		damage = { close = 18, far = 4, closeRange = 10, farRange = 32, maxRange = 50 },
		headMultiplier = 1.2,
		limbMultiplier = 0.9,
		magSize = 8,
		reserveAmmo = 32,
		reloadTime = 2.8,
		reloadEmptyTime = 3.4,
		equipTime = 0.6,
		adsTime = 0.3,
		moveSpeedMultiplier = 0.93,
		adsMoveSpeedMultiplier = 0.6,
		spread = { hip = 3.0, ads = 0.7, movingMultiplier = 1.3 },
		recoil = { vertical = 2.0, horizontal = 0.7, recovery = 8, adsMultiplier = 0.8 },
		adsFov = 60,
		unlockLevel = 32,
		muzzleOffset = G.BL9.muzzle,
		sightOffset = G.BL9.sight,
		anchors = G.BL9.anchors,
		attachmentSlots = allSlots(),
		attachmentUnlocks = ladder({ "RedDot", "Choke", "AngledGrip", "QuickMag", "HoloSight", "StubBarrel", "Suppressor", "LongBarrel" }, 2, 3),
		sounds = noSounds(),
		model = G.BL9.model,
	},

	-- PISTOLS -----------------------------------------------------------------------------------
	P12 = {
		id = "P12",
		displayName = "P-12 Warden",
		description = "Service pistol. Fast to draw, three-shot kill up close, weak at range.",
		class = "Pistol",
		slot = "Secondary",
		fireMode = "Semi",
		rpm = 420,
		damage = { close = 36, far = 20, closeRange = 30, farRange = 90, maxRange = 400 },
		headMultiplier = 1.5,
		limbMultiplier = 0.9,
		magSize = 12,
		reserveAmmo = 48,
		reloadTime = 1.4,
		reloadEmptyTime = 1.7,
		equipTime = 0.3,
		adsTime = 0.16,
		moveSpeedMultiplier = 1.0,
		adsMoveSpeedMultiplier = 0.75,
		spread = { hip = 2.2, ads = 0.2, movingMultiplier = 1.3 },
		recoil = { vertical = 1.3, horizontal = 0.3, recovery = 12, adsMultiplier = 0.8 },
		adsFov = 62,
		unlockLevel = 1,
		muzzleOffset = G.P12.muzzle,
		sightOffset = G.P12.sight,
		anchors = G.P12.anchors,
		attachmentSlots = { "Optic", "Muzzle", "Barrel", "Magazine" },
		attachmentUnlocks = ladder(PISTOL_LADDER, 3, 3),
		sounds = noSounds(),
		model = G.P12.model,
	},
	FX3 = {
		id = "FX3",
		displayName = "FX-3 Ferret",
		description = "Lightweight high-capacity pistol with a snappy trigger and mild recoil.",
		class = "Pistol",
		slot = "Secondary",
		fireMode = "Semi",
		rpm = 500,
		damage = { close = 30, far = 20, closeRange = 25, farRange = 80, maxRange = 400 },
		headMultiplier = 1.5,
		limbMultiplier = 0.9,
		magSize = 15,
		reserveAmmo = 60,
		reloadTime = 1.3,
		reloadEmptyTime = 1.6,
		equipTime = 0.25,
		adsTime = 0.15,
		moveSpeedMultiplier = 1.0,
		adsMoveSpeedMultiplier = 0.78,
		spread = { hip = 2.0, ads = 0.25, movingMultiplier = 1.25 },
		recoil = { vertical = 1.0, horizontal = 0.35, recovery = 13, adsMultiplier = 0.8 },
		adsFov = 62,
		unlockLevel = 6,
		muzzleOffset = G.FX3.muzzle,
		sightOffset = G.FX3.sight,
		anchors = G.FX3.anchors,
		attachmentSlots = { "Optic", "Muzzle", "Barrel", "Magazine" },
		attachmentUnlocks = ladder(PISTOL_LADDER, 3, 3),
		sounds = noSounds(),
		model = G.FX3.model,
	},
	OG6 = {
		id = "OG6",
		displayName = "OG-6 Ogre",
		description = "Six-shot hand cannon with brutal recoil and rifle-like reach for a sidearm.",
		class = "Pistol",
		slot = "Secondary",
		fireMode = "Semi",
		rpm = 160,
		damage = { close = 48, far = 32, closeRange = 35, farRange = 110, maxRange = 500 },
		headMultiplier = 1.6,
		limbMultiplier = 0.9,
		magSize = 6,
		reserveAmmo = 30,
		reloadTime = 2.3,
		reloadEmptyTime = 2.6,
		equipTime = 0.4,
		adsTime = 0.2,
		moveSpeedMultiplier = 0.98,
		adsMoveSpeedMultiplier = 0.72,
		spread = { hip = 2.8, ads = 0.18, movingMultiplier = 1.4 },
		recoil = { vertical = 3.0, horizontal = 0.5, recovery = 9, adsMultiplier = 0.8 },
		adsFov = 62,
		unlockLevel = 24,
		muzzleOffset = G.OG6.muzzle,
		sightOffset = G.OG6.sight,
		anchors = G.OG6.anchors,
		attachmentSlots = { "Optic", "Muzzle", "Barrel" },
		attachmentUnlocks = ladder(without(PISTOL_LADDER, { "QuickMag", "ExtendedMag", "Suppressor" }), 4, 4),
		sounds = noSounds(),
		model = G.OG6.model,
	},
	SP3 = {
		id = "SP3",
		displayName = "SP-3 Sprite",
		description = "Fully automatic machine pistol that shreds at arm's length and sputters beyond it.",
		class = "MachinePistol",
		slot = "Secondary",
		fireMode = "Auto",
		rpm = 1100,
		damage = { close = 20, far = 12, closeRange = 12, farRange = 45, maxRange = 250 },
		headMultiplier = 1.3,
		limbMultiplier = 0.9,
		magSize = 20,
		reserveAmmo = 100,
		reloadTime = 1.6,
		reloadEmptyTime = 2.0,
		equipTime = 0.25,
		adsTime = 0.15,
		moveSpeedMultiplier = 1.0,
		adsMoveSpeedMultiplier = 0.75,
		spread = { hip = 2.6, ads = 0.4, movingMultiplier = 1.2 },
		recoil = { vertical = 0.45, horizontal = 0.45, recovery = 13, adsMultiplier = 0.85 },
		adsFov = 62,
		unlockLevel = 15,
		muzzleOffset = G.SP3.muzzle,
		sightOffset = G.SP3.sight,
		anchors = G.SP3.anchors,
		attachmentSlots = { "Optic", "Muzzle", "Barrel", "Magazine" },
		attachmentUnlocks = ladder(PISTOL_LADDER, 3, 3),
		sounds = noSounds(),
		model = G.SP3.model,
	},
}

return Weapons
