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
local POLYMER = Color3.fromRGB(64, 62, 56)
local STEEL = Color3.fromRGB(96, 99, 104)
local OLIVE = Color3.fromRGB(84, 90, 66)
local TAN = Color3.fromRGB(150, 128, 92)
local AMBER = Color3.fromRGB(176, 120, 60)

local function part(name: string, size: Vector3, offset: CFrame, color: Color3?, shape: ("Block" | "Cylinder")?, material: Enum.Material?): Weapons.ModelPart
	return { name = name, shape = shape or "Block", size = size, offset = offset, color = color or BLACK, material = material or Enum.Material.Metal }
end

local V3 = Vector3.new
local CF = CFrame.new
local CYL = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along -Z (the barrel axis)
local PLASTIC = Enum.Material.SmoothPlastic
local function tilt(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end

local ALL_GUNS: { Weapons.WeaponClass } = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun", "Pistol", "MachinePistol" }

-- Model conventions (see docs/CONTRACTS.md): optic/underbarrel/magazine parts are relative to their
-- anchor; barrel parts start at the muzzle anchor and extend along -Z; muzzle devices start at the
-- muzzle anchor moved forward by the barrel's muzzleExtend, and set muzzleExtend to their length.
-- Magazine anchors sit 0.25 studs below the top of the mag well.
local Attachments: { [string]: AttachmentDef } = {
	-- OPTICS --------------------------------------------------------------------------------------
	RedDot = {
		id = "RedDot",
		displayName = "Pinpoint Reflex",
		slot = "Optic",
		description = "Compact reflex sight with a clean red dot. Slightly tighter aim, slightly slower to raise.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Shotgun", "Pistol", "MachinePistol" },
		modifiers = { adsSpread = 0.92, adsTime = 1.03 },
		optic = { fov = 58, sightHeight = 0.11, reticle = "Dot" },
		model = {
			part("OpticBase", V3(0.12, 0.04, 0.22), CF(0, 0.02, 0)),
			part("OpticHood", V3(0.13, 0.12, 0.03), CF(0, 0.1, -0.09)),
			part("OpticGlass", V3(0.1, 0.09, 0.01), CF(0, 0.1, -0.075), GLASS, nil, Enum.Material.Glass),
		},
	},
	HoloSight = {
		id = "HoloSight",
		displayName = "Halo Holographic",
		slot = "Optic",
		description = "Wide-window holographic ring. Faster target pickup from the hip, heavier to aim.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Shotgun" },
		modifiers = { hipSpread = 0.93, adsSpread = 0.95, adsTime = 1.05 },
		optic = { fov = 56, sightHeight = 0.12, reticle = "Holo" },
		model = {
			part("OpticBase", V3(0.14, 0.04, 0.26), CF(0, 0.02, 0)),
			part("HoloBody", V3(0.14, 0.07, 0.12), CF(0, 0.075, 0.06)),
			part("HoloHood", V3(0.15, 0.15, 0.04), CF(0, 0.115, -0.1)),
			part("HoloRear", V3(0.15, 0.12, 0.03), CF(0, 0.12, 0.0)),
			part("OpticGlass", V3(0.12, 0.11, 0.01), CF(0, 0.12, -0.08), GLASS, nil, Enum.Material.Glass),
		},
	},
	ScoutScope = {
		id = "ScoutScope",
		displayName = "Scout 3x Optic",
		slot = "Optic",
		description = "Low-power 3x magnified optic for mid-range lanes. Much slower to aim and to move while aiming.",
		classes = { "AssaultRifle", "LMG", "Marksman" },
		modifiers = { adsSpread = 0.8, adsTime = 1.15, adsMoveSpeed = 0.9 },
		optic = { fov = 35, sightHeight = 0.14, reticle = "Chevron" },
		model = {
			part("OpticBase", V3(0.1, 0.04, 0.32), CF(0, 0.02, 0)),
			part("ScopeMountRear", V3(0.07, 0.08, 0.06), CF(0, 0.07, 0.1)),
			part("ScopeMountFront", V3(0.07, 0.08, 0.06), CF(0, 0.07, -0.1)),
			part("ScopeTube", V3(0.46, 0.1, 0.1), CF(0, 0.14, 0) * CYL, BLACK, "Cylinder"),
			part("ScopeObjective", V3(0.12, 0.14, 0.14), CF(0, 0.14, -0.26) * CYL, BLACK, "Cylinder"),
			part("ScopeEyepiece", V3(0.1, 0.13, 0.13), CF(0, 0.14, 0.24) * CYL, BLACK, "Cylinder"),
			part("ScopeLens", V3(0.01, 0.11, 0.11), CF(0, 0.14, -0.325) * CYL, GLASS, "Cylinder", Enum.Material.Glass),
		},
	},
	MicroDot = {
		id = "MicroDot",
		displayName = "Pocket Dot",
		slot = "Optic",
		description = "Tiny slide-mounted dot for sidearms and SMGs. Tighter aim, but a cramped window slows the draw.",
		classes = { "SMG", "Pistol", "MachinePistol" },
		modifiers = { adsSpread = 0.9, equipTime = 1.06 },
		optic = { fov = 60, sightHeight = 0.07, reticle = "Dot" },
		model = {
			part("OpticBase", V3(0.09, 0.03, 0.14), CF(0, 0.015, 0)),
			part("OpticHood", V3(0.1, 0.08, 0.02), CF(0, 0.06, -0.06)),
			part("OpticGlass", V3(0.08, 0.06, 0.01), CF(0, 0.065, -0.05), GLASS, nil, Enum.Material.Glass),
		},
	},

	-- MUZZLE --------------------------------------------------------------------------------------
	Suppressor = {
		id = "Suppressor",
		displayName = "Hush Can",
		slot = "Muzzle",
		description = "Hides your muzzle flash and tracers from enemies. Shorter effective range.",
		classes = ALL_GUNS,
		modifiers = { range = 0.85, adsTime = 1.05 },
		suppressed = true,
		muzzleExtend = 0.6,
		model = {
			part("Suppressor", V3(0.6, 0.13, 0.13), CF(0, 0, -0.3) * CYL, BLACK, "Cylinder"),
		},
	},
	Compensator = {
		id = "Compensator",
		displayName = "Kickstop Compensator",
		slot = "Muzzle",
		description = "Vents gas upward to tame vertical climb. Adds side-to-side kick and a bigger flash.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Pistol", "MachinePistol" },
		modifiers = { recoilVertical = 0.8, recoilHorizontal = 1.1, hipSpread = 1.05 },
		muzzleExtend = 0.16,
		model = {
			part("Compensator", V3(0.16, 0.1, 0.1), CF(0, 0, -0.08) * CYL, BLACK, "Cylinder"),
			part("CompPort", V3(0.06, 0.03, 0.1), CF(0, 0.05, -0.08), STEEL),
		},
	},
	FlashGuard = {
		id = "FlashGuard",
		displayName = "Prong Flash Guard",
		slot = "Muzzle",
		description = "Pronged flash guard that steadies horizontal sway. Slightly more muzzle climb.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "MachinePistol" },
		modifiers = { recoilHorizontal = 0.72, recoilVertical = 1.06 },
		muzzleExtend = 0.2,
		model = {
			part("FlashGuard", V3(0.2, 0.09, 0.09), CF(0, 0, -0.1) * CYL, BLACK, "Cylinder"),
			part("FlashProngs", V3(0.11, 0.11, 0.06), CF(0, 0, -0.17), BLACK),
		},
	},
	Choke = {
		id = "Choke",
		displayName = "Tightbore Choke",
		slot = "Muzzle",
		description = "Shotgun choke that keeps pellets lethal further out. Slower to aim and looser from the hip.",
		classes = { "Shotgun" },
		modifiers = { range = 1.3, adsTime = 1.06, hipSpread = 1.08 },
		muzzleExtend = 0.14,
		model = {
			part("Choke", V3(0.14, 0.12, 0.12), CF(0, 0, -0.07) * CYL, STEEL, "Cylinder"),
			part("ChokeRing", V3(0.03, 0.14, 0.14), CF(0, 0, -0.125) * CYL, BLACK, "Cylinder"),
		},
	},

	-- BARREL --------------------------------------------------------------------------------------
	LongBarrel = {
		id = "LongBarrel",
		displayName = "Reach Barrel",
		slot = "Barrel",
		description = "Extends damage range. Heavier to handle.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun" },
		modifiers = { range = 1.25, adsTime = 1.08, moveSpeed = 0.97 },
		muzzleExtend = 0.35,
		model = {
			part("BarrelExt", V3(0.35, 0.075, 0.075), CF(0, 0, -0.175) * CYL, Color3.fromRGB(46, 48, 52), "Cylinder"),
		},
	},
	StubBarrel = {
		id = "StubBarrel",
		displayName = "Stub Barrel",
		slot = "Barrel",
		description = "Cut-down barrel for close quarters. Faster aim and movement, shorter reach, more climb.",
		classes = { "AssaultRifle", "SMG", "LMG", "Shotgun" },
		modifiers = { range = 0.8, adsTime = 0.9, moveSpeed = 1.03, recoilVertical = 1.1 },
		muzzleExtend = 0.06,
		model = {
			part("StubCap", V3(0.06, 0.1, 0.1), CF(0, 0, -0.03) * CYL, BLACK, "Cylinder"),
		},
	},
	MatchBarrel = {
		id = "MatchBarrel",
		displayName = "Match Barrel",
		slot = "Barrel",
		description = "Precision sidearm barrel: more range and tighter aim, with snappier recoil and a slower draw.",
		classes = { "Pistol", "MachinePistol" },
		modifiers = { range = 1.2, adsSpread = 0.85, recoilVertical = 1.1, equipTime = 1.1 },
		muzzleExtend = 0.15,
		model = {
			part("MatchBarrel", V3(0.15, 0.07, 0.07), CF(0, 0, -0.075) * CYL, STEEL, "Cylinder"),
			part("MatchCrown", V3(0.03, 0.085, 0.085), CF(0, 0, -0.135) * CYL, BLACK, "Cylinder"),
		},
	},
	FlutedBarrel = {
		id = "FlutedBarrel",
		displayName = "Fluted Barrel",
		slot = "Barrel",
		description = "Lightened precision barrel: faster to aim and draw, but kicks harder and loses a little range.",
		classes = { "Marksman", "Sniper" },
		modifiers = { adsTime = 0.9, equipTime = 0.9, recoilVertical = 1.15, range = 0.92 },
		muzzleExtend = 0.2,
		model = {
			part("FlutedBarrel", V3(0.2, 0.075, 0.075), CF(0, 0, -0.1) * CYL, STEEL, "Cylinder"),
			part("FluteStrip", V3(0.08, 0.02, 0.16), CF(0, 0.035, -0.1), BLACK),
		},
	},

	-- UNDERBARREL ---------------------------------------------------------------------------------
	VerticalGrip = {
		id = "VerticalGrip",
		displayName = "Ridge Foregrip",
		slot = "Underbarrel",
		description = "Steadies vertical recoil at the cost of aim speed.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman" },
		modifiers = { recoilVertical = 0.85, adsTime = 1.07 },
		model = {
			part("Foregrip", V3(0.1, 0.32, 0.12), CF(0, -0.16, 0)),
		},
	},
	AngledGrip = {
		id = "AngledGrip",
		displayName = "Swept Grip",
		slot = "Underbarrel",
		description = "Angled handstop for fast aiming. Only a little recoil control, and wider side kick.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Shotgun" },
		modifiers = { adsTime = 0.92, recoilVertical = 0.95, recoilHorizontal = 1.05 },
		model = {
			part("AngledGrip", V3(0.1, 0.12, 0.3), CF(0, -0.05, 0.02) * tilt(-25), POLYMER, nil, PLASTIC),
		},
	},
	Brace = {
		id = "Brace",
		displayName = "Bracer Bipod",
		slot = "Underbarrel",
		description = "Heavy folding bipod for machine guns. Big recoil reduction, slow to aim and to move.",
		classes = { "LMG" },
		modifiers = { recoilVertical = 0.7, recoilHorizontal = 0.7, adsTime = 1.15, moveSpeed = 0.95, adsMoveSpeed = 0.85 },
		model = {
			part("BraceClamp", V3(0.12, 0.06, 0.12), CF(0, -0.03, 0)),
			part("BraceLegL", V3(0.035, 0.035, 0.5), CF(-0.05, -0.07, -0.25), OLIVE),
			part("BraceLegR", V3(0.035, 0.035, 0.5), CF(0.05, -0.07, -0.25), OLIVE),
		},
	},

	-- MAGAZINE (top of the mag sits 0.25 above the anchor) -----------------------------------------
	ExtendedMag = {
		id = "ExtendedMag",
		displayName = "Long Feed Mag",
		slot = "Magazine",
		description = "50% more rounds per magazine. Slower reloads and aim.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Pistol", "MachinePistol" },
		modifiers = { magSize = 1.5, reload = 1.15, adsTime = 1.05 },
		model = {
			part("Magazine", V3(0.14, 0.75, 0.22), CF(0, -0.12, 0) * tilt(12), POLYMER, nil, PLASTIC),
		},
	},
	QuickMag = {
		id = "QuickMag",
		displayName = "Snap Mag",
		slot = "Magazine",
		description = "Pull-tab magazine for much faster reloads. Holds slightly fewer rounds.",
		classes = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun", "Pistol", "MachinePistol" },
		modifiers = { reload = 0.75, magSize = 0.9 },
		model = {
			part("Magazine", V3(0.14, 0.46, 0.21), CF(0, 0.02, 0) * tilt(8), TAN, nil, PLASTIC),
			part("MagTab", V3(0.06, 0.06, 0.03), CF(0, -0.23, 0.04), AMBER, nil, PLASTIC),
		},
	},
	DrumMag = {
		id = "DrumMag",
		displayName = "Barrelhouse Drum",
		slot = "Magazine",
		description = "Double-capacity drum. Painfully slow to reload and weighs down aim and movement.",
		classes = { "AssaultRifle", "LMG" },
		modifiers = { magSize = 2.0, reload = 1.35, adsTime = 1.1, moveSpeed = 0.95 },
		model = {
			part("MagNeck", V3(0.12, 0.14, 0.18), CF(0, 0.18, 0), POLYMER, nil, PLASTIC),
			part("Magazine", V3(0.24, 0.56, 0.56), CF(0, -0.15, 0), POLYMER, "Cylinder", PLASTIC),
		},
	},
}

return Attachments
