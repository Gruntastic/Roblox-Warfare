--!strict
-- Data-driven weapon attachments. Every attachment is earned deterministically by levelling the
-- weapon (see each weapon's `attachmentUnlocks`); none are sold or randomised.
-- All modifiers are multipliers (1 = unchanged); omitted fields mean unchanged.
local Weapons = require(script.Parent.Weapons)

export type Modifiers = {
	damage: number?, -- close and far damage
	range: number?, -- closeRange, farRange and maxRange
	rpm: number?,
	magSize: number?, -- rounded to the nearest round; reserve scales with it
	reload: number?, -- tactical and empty reload times
	adsTime: number?,
	equipTime: number?,
	moveSpeed: number?, -- hip-fire move speed multiplier
	adsMoveSpeed: number?,
	hipSpread: number?,
	adsSpread: number?,
	recoilVertical: number?,
	recoilHorizontal: number?,
}

export type AttachmentDef = {
	id: string,
	displayName: string,
	slot: Weapons.AttachmentSlot,
	description: string,
	classes: { Weapons.WeaponClass }, -- weapon classes that accept it
	modifiers: Modifiers,
	suppressed: boolean?, -- muzzle: no muzzle flash or tracer for other players, quieter
	muzzleExtend: number?, -- studs the muzzle point moves forward (barrels, muzzle devices)
	optic: { fov: number, sightHeight: number, reticle: "Dot" | "Holo" | "Chevron" }?, -- sightHeight: eye point above the optic anchor
	model: { Weapons.ModelPart }, -- parts relative to the slot's anchor on the weapon
}

local BLACK = Color3.fromRGB(28, 29, 31)
local GLASS = Color3.fromRGB(120, 170, 160)

local function part(name: string, size: Vector3, offset: CFrame, color: Color3?, shape: ("Block" | "Cylinder")?, material: Enum.Material?): Weapons.ModelPart
	return { name = name, shape = shape or "Block", size = size, offset = offset, color = color or BLACK, material = material or Enum.Material.Metal }
end

local CYL = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along -Z (the barrel axis)

local Attachments: { [string]: AttachmentDef } = {
	RedDot = {
		id = "RedDot",
		displayName = "Pinpoint Reflex",
		slot = "Optic",
		description = "Compact reflex sight with a clean red dot.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Shotgun", "Pistol", "MachinePistol" },
		modifiers = { adsTime = 1.03 },
		optic = { fov = 58, sightHeight = 0.11, reticle = "Dot" },
		model = {
			part("OpticBase", Vector3.new(0.12, 0.04, 0.22), CFrame.new(0, 0.02, 0)),
			part("OpticHood", Vector3.new(0.13, 0.12, 0.03), CFrame.new(0, 0.1, -0.09)),
			part("OpticGlass", Vector3.new(0.1, 0.09, 0.01), CFrame.new(0, 0.1, -0.075), GLASS, nil, Enum.Material.Glass),
		},
	},
	Suppressor = {
		id = "Suppressor",
		displayName = "Hush Can",
		slot = "Muzzle",
		description = "Hides your muzzle flash and tracers from enemies. Shorter effective range.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun", "Pistol", "MachinePistol" },
		modifiers = { range = 0.85, adsTime = 1.05 },
		suppressed = true,
		muzzleExtend = 0.6,
		model = {
			part("Suppressor", Vector3.new(0.6, 0.13, 0.13), CFrame.new(0, 0, -0.3) * CYL, BLACK, "Cylinder"),
		},
	},
	VerticalGrip = {
		id = "VerticalGrip",
		displayName = "Ridge Foregrip",
		slot = "Underbarrel",
		description = "Steadies vertical recoil at the cost of aim speed.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman" },
		modifiers = { recoilVertical = 0.85, adsTime = 1.07 },
		model = {
			part("Foregrip", Vector3.new(0.1, 0.32, 0.12), CFrame.new(0, -0.16, 0)),
		},
	},
	ExtendedMag = {
		id = "ExtendedMag",
		displayName = "Long Feed Mag",
		slot = "Magazine",
		description = "50% more rounds per magazine. Slower reloads and aim.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Pistol", "MachinePistol" },
		modifiers = { magSize = 1.5, reload = 1.15, adsTime = 1.05 },
		model = {
			part("Magazine", Vector3.new(0.14, 0.75, 0.22), CFrame.new(0, -0.12, 0) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(64, 62, 56), nil, Enum.Material.SmoothPlastic),
		},
	},
	LongBarrel = {
		id = "LongBarrel",
		displayName = "Reach Barrel",
		slot = "Barrel",
		description = "Extends damage range. Heavier to handle.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun" },
		modifiers = { range = 1.25, adsTime = 1.08, moveSpeed = 0.97 },
		muzzleExtend = 0.35,
		model = {
			part("BarrelExt", Vector3.new(0.35, 0.075, 0.075), CFrame.new(0, 0, -0.175) * CYL, Color3.fromRGB(46, 48, 52), "Cylinder"),
		},
	},
}

return Attachments
