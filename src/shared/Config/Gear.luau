--!strict
-- Operator gear sets: the military kit every player wears (helmet, plate carrier, pouches, belt,
-- pack, gloves, knee pads) and the colours of the uniform under it. Gear is cosmetic only and is
-- the "Gear" cosmetic kind (Pure/CosmeticRules). Ownership:
--   * no `source`: owned from account level `level` (and forever once the player has prestiged)
--   * source "shop": bought with credits (Config/Store shop item)
--   * source "crate": dropped by the Gear Crate (Config/Store)
-- Team identity stays readable whatever the set: every operator wears a team-coloured armband and
-- helmet strobe (GearBuilder), and team uniforms use the team clothing templates in Config/Assets.

export type GearDef = {
	id: string,
	name: string,
	description: string,
	level: number, -- account level that unlocks it (ignored when `source` is set)
	source: string?, -- nil | "shop" | "crate"
	-- colours
	helmet: Color3,
	vest: Color3,
	pouches: Color3,
	webbing: Color3,
	shirt: Color3, -- uniform top (used when no clothing template is set)
	pants: Color3,
	gloves: Color3,
	boots: Color3,
	material: Enum.Material, -- vest / helmet surface
	-- silhouette
	nvg: boolean, -- night-vision mount and tubes on the helmet
	headset: boolean, -- ear cups and boom mic
	pack: string?, -- nil | "Radio" | "Assault"
	kneePads: boolean,
	faceWrap: Color3?, -- balaclava / shemagh colour, nil = bare face
}

local DEFAULT = "Ranger"

local sets: { GearDef } = {
	{
		id = "Ranger",
		name = "Ranger",
		description = "Standard issue: olive plate carrier, coyote helmet, comms headset.",
		level = 1,
		helmet = Color3.fromRGB(150, 124, 88),
		vest = Color3.fromRGB(78, 86, 52),
		pouches = Color3.fromRGB(92, 98, 62),
		webbing = Color3.fromRGB(54, 58, 38),
		shirt = Color3.fromRGB(96, 102, 74),
		pants = Color3.fromRGB(84, 88, 64),
		gloves = Color3.fromRGB(40, 40, 36),
		boots = Color3.fromRGB(58, 48, 36),
		material = Enum.Material.Fabric,
		nvg = false,
		headset = true,
		pack = nil,
		kneePads = true,
		faceWrap = nil,
	},
	{
		id = "Woodland",
		name = "Woodland Scout",
		description = "Green-on-green kit with a radio pack for long patrols.",
		level = 10,
		helmet = Color3.fromRGB(64, 80, 50),
		vest = Color3.fromRGB(58, 72, 44),
		pouches = Color3.fromRGB(70, 84, 52),
		webbing = Color3.fromRGB(40, 48, 32),
		shirt = Color3.fromRGB(70, 88, 56),
		pants = Color3.fromRGB(62, 74, 50),
		gloves = Color3.fromRGB(52, 56, 40),
		boots = Color3.fromRGB(44, 38, 30),
		material = Enum.Material.Fabric,
		nvg = false,
		headset = true,
		pack = "Radio",
		kneePads = true,
		faceWrap = Color3.fromRGB(56, 66, 44),
	},
	{
		id = "Urban",
		name = "Urban Assault",
		description = "Grey city kit with night vision and an assault pack.",
		level = 25,
		helmet = Color3.fromRGB(70, 74, 80),
		vest = Color3.fromRGB(58, 62, 68),
		pouches = Color3.fromRGB(74, 78, 86),
		webbing = Color3.fromRGB(36, 38, 42),
		shirt = Color3.fromRGB(92, 96, 104),
		pants = Color3.fromRGB(64, 68, 76),
		gloves = Color3.fromRGB(28, 28, 30),
		boots = Color3.fromRGB(30, 30, 32),
		material = Enum.Material.Fabric,
		nvg = true,
		headset = true,
		pack = "Assault",
		kneePads = true,
		faceWrap = nil,
	},
	{
		id = "DesertRecon",
		name = "Desert Recon",
		description = "Tan kit with a shemagh, built for open ground.",
		level = 1,
		source = "shop",
		helmet = Color3.fromRGB(196, 170, 124),
		vest = Color3.fromRGB(176, 150, 106),
		pouches = Color3.fromRGB(186, 160, 116),
		webbing = Color3.fromRGB(130, 108, 76),
		shirt = Color3.fromRGB(190, 168, 128),
		pants = Color3.fromRGB(168, 146, 108),
		gloves = Color3.fromRGB(150, 126, 90),
		boots = Color3.fromRGB(120, 96, 66),
		material = Enum.Material.Fabric,
		nvg = false,
		headset = true,
		pack = "Assault",
		kneePads = true,
		faceWrap = Color3.fromRGB(206, 190, 160),
	},
	{
		id = "Arctic",
		name = "Arctic Warfare",
		description = "White-over-grey cold weather kit.",
		level = 1,
		source = "crate",
		helmet = Color3.fromRGB(226, 230, 234),
		vest = Color3.fromRGB(200, 206, 212),
		pouches = Color3.fromRGB(214, 220, 226),
		webbing = Color3.fromRGB(120, 128, 138),
		shirt = Color3.fromRGB(222, 226, 232),
		pants = Color3.fromRGB(184, 190, 198),
		gloves = Color3.fromRGB(70, 74, 82),
		boots = Color3.fromRGB(60, 62, 68),
		material = Enum.Material.Fabric,
		nvg = false,
		headset = true,
		pack = "Assault",
		kneePads = true,
		faceWrap = Color3.fromRGB(236, 238, 240),
	},
	{
		id = "NightOps",
		name = "Night Ops",
		description = "Black kit, quad night vision, no shine.",
		level = 1,
		source = "crate",
		helmet = Color3.fromRGB(28, 30, 34),
		vest = Color3.fromRGB(24, 26, 28),
		pouches = Color3.fromRGB(34, 36, 40),
		webbing = Color3.fromRGB(18, 18, 20),
		shirt = Color3.fromRGB(36, 38, 42),
		pants = Color3.fromRGB(30, 32, 36),
		gloves = Color3.fromRGB(16, 16, 18),
		boots = Color3.fromRGB(16, 16, 18),
		material = Enum.Material.Fabric,
		nvg = true,
		headset = true,
		pack = "Radio",
		kneePads = true,
		faceWrap = Color3.fromRGB(22, 22, 24),
	},
	{
		id = "Jungle",
		name = "Jungle Raider",
		description = "Light kit in deep greens and brown, no knee pads.",
		level = 1,
		source = "crate",
		helmet = Color3.fromRGB(52, 70, 40),
		vest = Color3.fromRGB(86, 70, 46),
		pouches = Color3.fromRGB(60, 76, 44),
		webbing = Color3.fromRGB(46, 38, 28),
		shirt = Color3.fromRGB(60, 80, 46),
		pants = Color3.fromRGB(76, 64, 44),
		gloves = Color3.fromRGB(56, 46, 34),
		boots = Color3.fromRGB(46, 36, 26),
		material = Enum.Material.Fabric,
		nvg = false,
		headset = false,
		pack = "Radio",
		kneePads = false,
		faceWrap = Color3.fromRGB(70, 86, 52),
	},
	{
		id = "Highlander",
		name = "Highlander",
		description = "Slate and ranger-green kit with night vision.",
		level = 1,
		source = "crate",
		helmet = Color3.fromRGB(82, 96, 92),
		vest = Color3.fromRGB(70, 82, 78),
		pouches = Color3.fromRGB(88, 102, 96),
		webbing = Color3.fromRGB(44, 50, 48),
		shirt = Color3.fromRGB(96, 108, 102),
		pants = Color3.fromRGB(74, 84, 80),
		gloves = Color3.fromRGB(40, 42, 42),
		boots = Color3.fromRGB(42, 40, 38),
		material = Enum.Material.Fabric,
		nvg = true,
		headset = true,
		pack = nil,
		kneePads = true,
		faceWrap = nil,
	},
}

local Gear = {
	sets = sets,
	byId = {} :: { [string]: GearDef },
	Default = DEFAULT,
}
for _, g in sets do
	Gear.byId[g.id] = g
end

return Gear
