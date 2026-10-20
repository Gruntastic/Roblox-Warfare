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

export type WeaponDef = {
	id: string,
	displayName: string,
	class: "AssaultRifle" | "SMG" | "LMG" | "Sniper" | "Marksman" | "Shotgun" | "Pistol",
	slot: "Primary" | "Secondary",
	fireMode: "Auto" | "Semi",
	rpm: number,
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
	adsFov: number,
	unlockLevel: number,
	muzzleOffset: CFrame, -- relative to grip origin
	sounds: { fire: string, reload: string, equip: string },
	model: { ModelPart },
}

local GUNMETAL = Color3.fromRGB(46, 48, 52)
local POLYMER = Color3.fromRGB(64, 62, 56)
local TAN = Color3.fromRGB(150, 128, 92)

local function part(name: string, size: Vector3, offset: CFrame, color: Color3?, shape: ("Block" | "Cylinder")?, material: Enum.Material?): ModelPart
	return {
		name = name,
		shape = shape or "Block",
		size = size,
		offset = offset,
		color = color or GUNMETAL,
		material = material or Enum.Material.Metal,
	}
end

local Weapons: { [string]: WeaponDef } = {
	-- Original mid-weight assault rifle. Reliable all-rounder with a 4-shot close-range kill.
	VK7 = {
		id = "VK7",
		displayName = "VK-7 Vanguard",
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
		muzzleOffset = CFrame.new(0, 0.12, -2.55),
		sounds = { fire = "", reload = "", equip = "" },
		model = {
			part("Receiver", Vector3.new(0.22, 0.32, 1.3), CFrame.new(0, 0.1, -0.55)),
			part("Handguard", Vector3.new(0.2, 0.24, 0.9), CFrame.new(0, 0.1, -1.6), TAN, nil, Enum.Material.SmoothPlastic),
			part("Barrel", Vector3.new(0.7, 0.07, 0.07), CFrame.new(0, 0.12, -2.25) * CFrame.Angles(0, math.rad(90), 0), GUNMETAL, "Cylinder"),
			part("Brake", Vector3.new(0.18, 0.11, 0.11), CFrame.new(0, 0.12, -2.5) * CFrame.Angles(0, math.rad(90), 0), GUNMETAL, "Cylinder"),
			part("Magazine", Vector3.new(0.14, 0.5, 0.22), CFrame.new(0, -0.27, -0.75) * CFrame.Angles(math.rad(-12), 0, 0), POLYMER, nil, Enum.Material.SmoothPlastic),
			part("Grip", Vector3.new(0.14, 0.38, 0.18), CFrame.new(0, -0.18, -0.05) * CFrame.Angles(math.rad(15), 0, 0), POLYMER, nil, Enum.Material.SmoothPlastic),
			part("Stock", Vector3.new(0.16, 0.3, 0.75), CFrame.new(0, 0.02, 0.45), TAN, nil, Enum.Material.SmoothPlastic),
			part("Rail", Vector3.new(0.1, 0.05, 0.9), CFrame.new(0, 0.29, -0.6)),
			part("RearSight", Vector3.new(0.08, 0.09, 0.08), CFrame.new(0, 0.35, -0.25)),
			part("FrontSight", Vector3.new(0.05, 0.12, 0.05), CFrame.new(0, 0.33, -1.95)),
		},
	},
	-- Original service pistol. Fast to draw, three-shot kill up close, weak at range.
	P12 = {
		id = "P12",
		displayName = "P-12 Warden",
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
		muzzleOffset = CFrame.new(0, 0.18, -0.85),
		sounds = { fire = "", reload = "", equip = "" },
		model = {
			part("Slide", Vector3.new(0.16, 0.18, 0.85), CFrame.new(0, 0.15, -0.38)),
			part("Frame", Vector3.new(0.15, 0.12, 0.7), CFrame.new(0, 0.02, -0.33), POLYMER, nil, Enum.Material.SmoothPlastic),
			part("Grip", Vector3.new(0.15, 0.45, 0.22), CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(14), 0, 0), POLYMER, nil, Enum.Material.SmoothPlastic),
			part("TriggerGuard", Vector3.new(0.05, 0.1, 0.22), CFrame.new(0, -0.08, -0.25)),
			part("FrontSight", Vector3.new(0.04, 0.05, 0.04), CFrame.new(0, 0.26, -0.75)),
			part("RearSight", Vector3.new(0.12, 0.05, 0.04), CFrame.new(0, 0.26, -0.02)),
		},
	},
}

return Weapons
